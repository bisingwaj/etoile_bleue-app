import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  RealtimeChannel? _callStatusChannel;

  /// Évite deux lancements SOS concurrents avant que l’état ne passe à `connecting`.
  bool _sosStartInFlight = false;

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
        if (_service.currentCallId != null) {
          _listenForCallStatusChanges(_service.currentCallId!);
        }
        if (_service.currentChannelName != null) {
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
    String? callerName,
  }) {
    if (state.isInCall || state.status == ActiveCallStatus.connecting) {
      debugPrint('[CallState] setIncomingCall rejected: already in call/connecting — auto-rejecting');
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

    // 45s timeout for auto-rejecting incoming call
    _incomingTimeoutTimer = Timer(const Duration(seconds: 45), () {
      if (mounted && state.status == ActiveCallStatus.incomingRinging) {
        debugPrint('[CallState] Incoming call timed out after 45s. Auto-rejecting.');
        rejectIncomingCall();
      }
    });
  }

  void clearIncomingCall() {
    if (state.status == ActiveCallStatus.incomingRinging) {
      _incomingTimeoutTimer?.cancel();
      _sounds.stopRingtone();
      state = const ActiveCallState();
    }
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
    try {
      await _service.answerIncomingCall(
        state.channelName!,
        state.callHistoryId!,
      );
      
      // Sync incident_id recovered from call_history fetch
      if (_service.currentIncidentId != null) {
        state = state.copyWith(incidentId: _service.currentIncidentId);
      }
      
      _listenForCallStatusChanges(state.callHistoryId!);
      
      // Start GPS tracking for citizen during active call
      if (state.channelName != null) {
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
    if (state.callHistoryId == null) return;
    await _service.rejectIncomingCall(state.callHistoryId!, channelName: state.channelName);
    state = const ActiveCallState();
  }

  Future<void> hangUp() async {
    _sounds.stopRingback();
    _stopCallStatusListener();
    await _tryStopRecording();
    _location.stopCitizenTracking();
    try {
      await _service.hangUp();
    } catch (e) {
      debugPrint('[CallState] hangUp service error: $e');
    }
    if (mounted && state.status != ActiveCallStatus.ended && state.status != ActiveCallStatus.idle) {
      state = const ActiveCallState(status: ActiveCallStatus.ended);
      _endedResetTimer?.cancel();
      _endedResetTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) state = const ActiveCallState();
      });
    }
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

  void _listenForCallStatusChanges(String callHistoryId) {
    _stopCallStatusListener();
    _callStatusChannel = Supabase.instance.client
        .channel('call-status-$callHistoryId-${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'call_history',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: callHistoryId,
          ),
          callback: (payload) {
            final newStatus = payload.newRecord['status'] as String?;
            if (newStatus == 'abandoned') {
              debugPrint('[CallState] Call marked abandoned by server — hanging up');
              hangUp();
            } else if (newStatus == 'completed' || newStatus == 'missed' || newStatus == 'failed') {
              final endedBy = payload.newRecord['ended_by'] as String?;
              // Only hang up if the remote side triggered the status change
              if (endedBy != null && endedBy != 'citizen_hangup' && endedBy != 'citizen_rejected') {
                debugPrint('[CallState] Call $newStatus by remote ($endedBy) — hanging up');
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
      if (_service.currentCallId != null) {
        _listenForCallStatusChanges(_service.currentCallId!);
      }
      if (_service.currentChannelName != null) {
        _location.startCitizenTracking(_service.currentChannelName!);
      }
    } catch (e) {
      state = const ActiveCallState(status: ActiveCallStatus.ended);
      rethrow;
    }
  }
}

final callStateProvider =
    StateNotifierProvider<CallStateNotifier, ActiveCallState>((ref) {
  final service = ref.watch(emergencyCallServiceProvider);
  final recording = ref.watch(cloudRecordingServiceProvider);
  final location = ref.watch(locationServiceProvider);
  return CallStateNotifier(service, recording, location);
});
