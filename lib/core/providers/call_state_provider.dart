import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:etoile_bleue_mobile/core/services/emergency_call_service.dart';
import 'package:etoile_bleue_mobile/core/services/call_sound_service.dart';
import 'package:etoile_bleue_mobile/core/services/cloud_recording_service.dart';
import 'package:etoile_bleue_mobile/core/services/location_service.dart';

enum ActiveCallStatus {
  idle,
  connecting,
  ringing,
  active,
  ended,
  incomingRinging,
  onHold,
  blocked,
}

class ActiveCallState {
  final ActiveCallStatus status;
  final bool isMuted;
  final bool isVideoOn;
  final bool isSpeakerOn;
  final bool isRecording;
  final String? channelName;
  final String? callHistoryId;
  final String? incidentId;
  final String? callerName;
  final int? remoteUid;
  final String? blockedExpiresAt;
  final String? blockedReason;
  final bool isSosCall;
  final DateTime? activeSince;

  const ActiveCallState({
    this.status = ActiveCallStatus.idle,
    this.isMuted = false,
    this.isVideoOn = false,
    this.isSpeakerOn = true,
    this.isRecording = false,
    this.channelName,
    this.callHistoryId,
    this.incidentId,
    this.callerName,
    this.remoteUid,
    this.blockedExpiresAt,
    this.blockedReason,
    this.isSosCall = false,
    this.activeSince,
  });

  ActiveCallState copyWith({
    ActiveCallStatus? status,
    bool? isMuted,
    bool? isVideoOn,
    bool? isSpeakerOn,
    bool? isRecording,
    String? channelName,
    String? callHistoryId,
    String? incidentId,
    String? callerName,
    int? remoteUid,
    bool clearRemoteUid = false,
    bool clearChannelName = false,
    bool clearCallHistoryId = false,
    bool clearIncidentId = false,
    bool clearCallerName = false,
    String? blockedExpiresAt,
    String? blockedReason,
    bool? isSosCall,
    DateTime? activeSince,
    bool clearActiveSince = false,
  }) {
    return ActiveCallState(
      status: status ?? this.status,
      isMuted: isMuted ?? this.isMuted,
      isVideoOn: isVideoOn ?? this.isVideoOn,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isRecording: isRecording ?? this.isRecording,
      channelName: clearChannelName ? null : (channelName ?? this.channelName),
      callHistoryId: clearCallHistoryId ? null : (callHistoryId ?? this.callHistoryId),
      incidentId: clearIncidentId ? null : (incidentId ?? this.incidentId),
      callerName: clearCallerName ? null : (callerName ?? this.callerName),
      remoteUid: clearRemoteUid ? null : (remoteUid ?? this.remoteUid),
      blockedExpiresAt: blockedExpiresAt ?? this.blockedExpiresAt,
      blockedReason: blockedReason ?? this.blockedReason,
      isSosCall: isSosCall ?? this.isSosCall,
      activeSince: clearActiveSince ? null : (activeSince ?? this.activeSince),
    );
  }

  bool get isInCall =>
      status == ActiveCallStatus.connecting ||
      status == ActiveCallStatus.ringing ||
      status == ActiveCallStatus.active ||
      status == ActiveCallStatus.onHold ||
      status == ActiveCallStatus.incomingRinging;

  /// Whether the call involves the central dispatch (SOS or incoming from central).
  bool get isCentraleCall =>
      isSosCall ||
      channelName?.startsWith('SOS-') == true ||
      channelName?.startsWith('CENTRALE-') == true;
}

class CallStateNotifier extends StateNotifier<ActiveCallState> {
  final EmergencyCallService _service;
  final CloudRecordingService _recording;
  final LocationService _location;
  final CallSoundService _sounds = CallSoundService();
  Timer? _endedResetTimer;
  Timer? _heartbeatTimer;
  RealtimeChannel? _callStatusChannel;

  bool _sosStartInFlight = false;
  String? _lastEndedCallId;
  DateTime? _lastEndedAt;

  CallStateNotifier(this._service, this._recording, this._location) : super(const ActiveCallState()) {
    _wireCallbacks();
  }

  void _wireCallbacks() {
    _service.onJoinChanged = (joined) {
      if (joined) {
        state = state.copyWith(status: ActiveCallStatus.ringing);
        _sounds.startRingback();
      }
    };

    _service.onRemoteUserJoined = (uid) {
      _sounds.stopRingback();
      _sounds.playConnected();
      state = state.copyWith(
        status: ActiveCallStatus.active,
        remoteUid: uid,
        activeSince: DateTime.now(),
      );
      if (state.channelName != null) {
        _startHeartbeat(state.channelName!);
      }
      _tryStartRecording();
    };

    _service.onRemoteUserLeft = (uid) {
      state = state.copyWith(
        status: ActiveCallStatus.onHold,
        clearRemoteUid: true,
      );
    };

    _service.onCallEnded = () {
      _sounds.stopRingback();
      _sounds.playEnded();
      _stopCallStatusListener();
      _stopHeartbeat();
      _tryStopRecording();
      _location.stopCitizenTracking();
      _endedResetTimer?.cancel();
      state = const ActiveCallState(status: ActiveCallStatus.ended);
      _endedResetTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          state = const ActiveCallState();
        }
      });
    };
  }

  Future<void> startSosCall({double? lat, double? lng}) async {
    if (_sosStartInFlight) {
      debugPrint('[CallState] startSosCall ignored: SOS start already in flight');
      return;
    }
    if (state.isInCall || state.status == ActiveCallStatus.connecting) {
      debugPrint('[CallState] startSosCall ignored: already in call or connecting');
      return;
    }
    _sosStartInFlight = true;
    try {
      // Enable wakelock to prevent screen off during emergency call
      WakelockPlus.enable();

      _endedResetTimer?.cancel();
      state = state.copyWith(
        status: ActiveCallStatus.connecting,
        isSosCall: true,
      );

      // 1. Check blacklist status
      try {
        final blockStatus = await _service.checkBlocked();
        if (blockStatus['blocked'] == true) {
          debugPrint('[CallState] User is blocked. Not starting SOS.');
          state = ActiveCallState(
            status: ActiveCallStatus.blocked,
            blockedExpiresAt: blockStatus['expires_at'] as String?,
            blockedReason: blockStatus['reason'] as String?,
          );
          return;
        }
      } catch (e) {
        debugPrint('[CallState] Blocked check failed, continuing... $e');
      }

      try {
        await _service.startEmergencyCall(lat: lat, lng: lng);
        state = state.copyWith(
          channelName: _service.currentChannelName,
          incidentId: _service.currentIncidentId,
          callHistoryId: _service.currentCallId,
        );
        if (_service.currentChannelName != null) {
          _listenForCallStatusChanges(_service.currentChannelName!);
          _startHeartbeat(_service.currentChannelName!);
          _location.startCitizenTracking(_service.currentChannelName!);
        }
      } catch (e) {
        state = const ActiveCallState(status: ActiveCallStatus.ended);
        rethrow;
      }
    } finally {
      _sosStartInFlight = false;
    }
  }

  Timer? _incomingTimeoutTimer;

  void setIncomingCall({
    required String channelName,
    required String callHistoryId,
    required String callerName,
  }) {
    // 🛡️ GHOST CALL GUARD (Silence)
    final now = DateTime.now();
    if (callHistoryId == _lastEndedCallId && _lastEndedAt != null) {
      final diff = now.difference(_lastEndedAt!).inSeconds;
      if (diff < 10) {
        debugPrint('[CallState] 🛡️ Ignoring ghost call (same ID $callHistoryId, ended ${diff}s ago)');
        return;
      }
    }
    
    if (_lastEndedAt != null && now.difference(_lastEndedAt!).inSeconds < 3) {
      debugPrint('[CallState] 🛡️ Ignoring ghost call (cooldown period after hangup)');
      return;
    }

    // 🛡️ BUSY GUARD (Auto-reject)
    if (state.isInCall || state.status == ActiveCallStatus.connecting) {
      // Don't reject if it's the SAME call we are already handling (duplicate event)
      if (state.callHistoryId == callHistoryId) {
        debugPrint('[CallState] setIncomingCall: duplicate event for current call $callHistoryId — ignoring');
        return;
      }

      debugPrint('[CallState] setIncomingCall busy: already in call/connecting — auto-rejecting new call $callHistoryId');
      _service.rejectIncomingCall(callHistoryId).catchError((e) {
        debugPrint('[CallState] Auto-reject failed: $e');
      });
      return;
    }

    _endedResetTimer?.cancel();
    _incomingTimeoutTimer?.cancel();
    
    state = ActiveCallState(
      status: ActiveCallStatus.incomingRinging,
      channelName: channelName,
      callHistoryId: callHistoryId,
      callerName: callerName,
    );

    // Start manual ringtone if in foreground (since we skip CallKit there)
    _sounds.startRingtone();
    
    // §4.0: Heartbeat obligatoire dès ringing (même entrant)
    _startHeartbeat(channelName);

    // 45s timeout for auto-rejecting incoming call
    _incomingTimeoutTimer = Timer(const Duration(seconds: 45), () {
      if (mounted && state.status == ActiveCallStatus.incomingRinging) {
        debugPrint('[CallState] Incoming call timed out after 45s. Auto-rejecting.');
        rejectIncomingCall();
      }
    });
  }

  void clearIncomingCall() {
    final callId = state.callHistoryId;
    if (callId != null) {
      _lastEndedCallId = callId;
      _lastEndedAt = DateTime.now();
    }

    _incomingTimeoutTimer?.cancel();
    _sounds.stopRingtone();
    _cleanup();
    state = const ActiveCallState();
  }

  Future<void> answerIncomingCall() async {
    _incomingTimeoutTimer?.cancel();
    _sounds.stopRingtone();
    if (state.channelName == null || state.callHistoryId == null) {
      debugPrint('[CallState] answerIncomingCall aborted: channelName=${state.channelName}, callHistoryId=${state.callHistoryId}');
      return;
    }
    _endedResetTimer?.cancel();
    debugPrint('[CallState] answerIncomingCall: transitioning to connecting');
    state = state.copyWith(status: ActiveCallStatus.connecting);
    
    // Enable wakelock
    WakelockPlus.enable();
    
    try {
      await _service.answerIncomingCall(
        state.channelName!,
        state.callHistoryId!,
      );
      
      // Sync incident_id recovered from call_history fetch
      if (_service.currentIncidentId != null) {
        state = state.copyWith(incidentId: _service.currentIncidentId);
      }
      
      if (state.channelName != null) {
        _listenForCallStatusChanges(state.channelName!);
        _startHeartbeat(state.channelName!);
        _location.startCitizenTracking(state.channelName!);
      }
      
      debugPrint('[CallState] answerIncomingCall: service call succeeded');
    } catch (e, stack) {
      debugPrint('[CallState] answerIncomingCall FAILED: $e\n$stack');
      state = const ActiveCallState(status: ActiveCallStatus.ended);
      rethrow;
    }
  }

  Future<void> rejectIncomingCall() async {
    _incomingTimeoutTimer?.cancel();
    _sounds.stopRingtone();
    final callId = state.callHistoryId;
    if (callId == null) return;
    
    // Save for ghost guard
    _lastEndedCallId = callId;
    _lastEndedAt = DateTime.now();

    await _service.rejectIncomingCall(callId, channelName: state.channelName);
    _cleanup();
    state = const ActiveCallState();
  }

  Future<void> hangUp({String endedBy = 'citizen'}) async {
    final callId = state.callHistoryId;
    
    // Save for ghost guard
    if (callId != null) {
      _lastEndedCallId = callId;
      _lastEndedAt = DateTime.now();
    }

    _location.stopCitizenTracking();
    await _tryStopRecording();
    try {
      await _service.hangUp();
    } catch (e) {
      debugPrint('[CallState] hangUp service error: $e');
    }
    
    final wasActive = state.status != ActiveCallStatus.ended && state.status != ActiveCallStatus.idle;
    _cleanup();
    
    if (mounted && wasActive) {
      state = const ActiveCallState(status: ActiveCallStatus.ended);
      _endedResetTimer?.cancel();
      _endedResetTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) state = const ActiveCallState();
      });
    }
  }

  // ─── Heartbeat ─────────────────────────────────────────────────────────────

  void _startHeartbeat(String channelName) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        await Supabase.instance.client.rpc(
          'citizen_call_heartbeat',
          params: {'p_channel_name': channelName},
        );
      } on PostgrestException catch (e) {
        // 401/403 → tentative de refresh, puis le watchdog serveur prendra le relais si ça échoue
        if (e.code == '401' || e.code == '403') {
          try {
            await Supabase.instance.client.auth.refreshSession();
          } catch (_) {}
        }
        debugPrint('[CallLifecycle] heartbeat failed: ${e.code} ${e.message}');
      } catch (e) {
        debugPrint('[CallLifecycle] heartbeat error: $e');
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _cleanup() {
    _stopHeartbeat();
    _stopCallStatusListener();
    _sounds.stopRingback();
    _sounds.stopRingtone();
    _incomingTimeoutTimer?.cancel();
    _incomingTimeoutTimer = null;
    
    // Disable wakelock
    WakelockPlus.disable();
  }

  // ─── Cloud Recording helpers ──────────────────────────────────────────────

  Future<void> _tryStartRecording() async {
    final channel = state.channelName;
    if (channel == null) return;
    try {
      final started = await _recording.startRecording(channelId: channel);
      if (started && mounted) {
        state = state.copyWith(isRecording: true);
        debugPrint('[CallState] Cloud recording started');
      }
    } catch (e) {
      debugPrint('[CallState] Cloud recording start failed (non-fatal): $e');
    }
  }

  Future<void> _tryStopRecording() async {
    if (!_recording.isRecording) return;
    try {
      await _recording.stopRecording();
      if (mounted) state = state.copyWith(isRecording: false);
      debugPrint('[CallState] Cloud recording stopped');
    } catch (e) {
      debugPrint('[CallState] Cloud recording stop failed (non-fatal): $e');
    }
  }

  // ─── Call status Realtime listener ─────────────────────────────────────────

  void _listenForCallStatusChanges(String channelName) {
    _stopCallStatusListener();
    _callStatusChannel = Supabase.instance.client
        .channel('citizen-call-watch-$channelName')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'call_history',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'channel_name',
            value: channelName,
          ),
          callback: (payload) {
            const terminal = ['completed', 'missed', 'failed'];
            final newStatus = payload.newRecord['status'] as String?;
            if (newStatus != null && terminal.contains(newStatus)) {
              final endedBy = payload.newRecord['ended_by'] as String?;
              // Only hang up if the remote side triggered the status change
              if (endedBy != null && !endedBy.startsWith('citizen')) {
                debugPrint('[CallLifecycle] Call $newStatus by remote ($endedBy) — hanging up');
                hangUp();
              }
            }
          },
        )
        .subscribe();
  }

  void _stopCallStatusListener() {
    _callStatusChannel?.unsubscribe();
    _callStatusChannel = null;
  }

  Future<void> toggleMute() async {
    await _service.toggleMute();
    state = state.copyWith(isMuted: _service.isMuted);
  }

  Future<void> toggleVideo() async {
    await _service.toggleVideo();
    state = state.copyWith(isVideoOn: _service.isVideoOn);
    // Sync has_video status to call_history for dashboard awareness
    final callId = state.callHistoryId;
    if (callId != null) {
      _service.updateVideoStatus(callId, _service.isVideoOn);
    }
  }

  Future<void> toggleSpeaker() async {
    await _service.toggleSpeaker();
    state = state.copyWith(isSpeakerOn: _service.isSpeakerOn);
  }

  Future<void> switchCamera() async {
    await _service.switchCamera();
  }

  /// Rappeler un appel manqué ou terminé
  Future<void> startCallbackCall(String originalCallId) async {
    if (state.isInCall || state.status == ActiveCallStatus.connecting) {
      debugPrint('[CallState] startCallbackCall ignored: already in call or connecting');
      return;
    }
    _endedResetTimer?.cancel();
    state = state.copyWith(status: ActiveCallStatus.connecting);

    try {
      await _service.callbackCall(originalCallId: originalCallId);
      state = state.copyWith(
        channelName: _service.currentChannelName,
        incidentId: _service.currentIncidentId,
        callHistoryId: _service.currentCallId,
      );
      if (_service.currentChannelName != null) {
        _listenForCallStatusChanges(_service.currentChannelName!);
        _startHeartbeat(_service.currentChannelName!);
        _location.startCitizenTracking(_service.currentChannelName!);
      }
    } catch (e) {
      state = const ActiveCallState(status: ActiveCallStatus.ended);
      rethrow;
    }
  }
  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}

final callStateProvider =
    StateNotifierProvider<CallStateNotifier, ActiveCallState>((ref) {
  final service = ref.watch(emergencyCallServiceProvider);
  final recording = ref.watch(cloudRecordingServiceProvider);
  final location = ref.watch(locationServiceProvider);
  return CallStateNotifier(service, recording, location);
});
