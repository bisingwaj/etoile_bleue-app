import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etoile_bleue_mobile/core/services/emergency_call_service.dart';

enum ActiveCallStatus {
  idle,
  connecting,
  ringing,
  active,
  ended,
  incomingRinging,
}

class ActiveCallState {
  final ActiveCallStatus status;
  final bool isMuted;
  final bool isVideoOn;
  final bool isSpeakerOn;
  final String? channelName;
  final String? callHistoryId;
  final String? incidentId;
  final String? callerName;
  final int? remoteUid;

  const ActiveCallState({
    this.status = ActiveCallStatus.idle,
    this.isMuted = false,
    this.isVideoOn = false,
    this.isSpeakerOn = true,
    this.channelName,
    this.callHistoryId,
    this.incidentId,
    this.callerName,
    this.remoteUid,
  });

  ActiveCallState copyWith({
    ActiveCallStatus? status,
    bool? isMuted,
    bool? isVideoOn,
    bool? isSpeakerOn,
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
  }) {
    return ActiveCallState(
      status: status ?? this.status,
      isMuted: isMuted ?? this.isMuted,
      isVideoOn: isVideoOn ?? this.isVideoOn,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      channelName: clearChannelName ? null : (channelName ?? this.channelName),
      callHistoryId: clearCallHistoryId ? null : (callHistoryId ?? this.callHistoryId),
      incidentId: clearIncidentId ? null : (incidentId ?? this.incidentId),
      callerName: clearCallerName ? null : (callerName ?? this.callerName),
      remoteUid: clearRemoteUid ? null : (remoteUid ?? this.remoteUid),
    );
  }

  bool get isInCall =>
      status == ActiveCallStatus.connecting ||
      status == ActiveCallStatus.ringing ||
      status == ActiveCallStatus.active;
}

class CallStateNotifier extends StateNotifier<ActiveCallState> {
  final EmergencyCallService _service;

  CallStateNotifier(this._service) : super(const ActiveCallState()) {
    _wireCallbacks();
  }

  void _wireCallbacks() {
    _service.onJoinChanged = (joined) {
      if (joined) {
        state = state.copyWith(status: ActiveCallStatus.ringing);
      }
    };

    _service.onRemoteUserJoined = (uid) {
      state = state.copyWith(
        status: ActiveCallStatus.active,
        remoteUid: uid,
      );
    };

    _service.onRemoteUserLeft = (uid) {
      state = state.copyWith(
        status: ActiveCallStatus.ringing,
        clearRemoteUid: true,
      );
    };

    _service.onCallEnded = () {
      state = const ActiveCallState(status: ActiveCallStatus.ended);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          state = const ActiveCallState();
        }
      });
    };
  }

  Future<void> startSosCall() async {
    state = state.copyWith(status: ActiveCallStatus.connecting);
    try {
      await _service.startEmergencyCall();
      state = state.copyWith(
        channelName: _service.currentChannelName,
      );
    } catch (e) {
      state = const ActiveCallState(status: ActiveCallStatus.ended);
      rethrow;
    }
  }

  void setIncomingCall({
    required String channelName,
    required String callHistoryId,
    String? callerName,
  }) {
    state = ActiveCallState(
      status: ActiveCallStatus.incomingRinging,
      channelName: channelName,
      callHistoryId: callHistoryId,
      callerName: callerName,
    );
  }

  Future<void> answerIncomingCall() async {
    if (state.channelName == null || state.callHistoryId == null) return;
    state = state.copyWith(status: ActiveCallStatus.connecting);
    try {
      await _service.answerIncomingCall(
        state.channelName!,
        state.callHistoryId!,
      );
    } catch (e) {
      state = const ActiveCallState(status: ActiveCallStatus.ended);
      rethrow;
    }
  }

  Future<void> rejectIncomingCall() async {
    if (state.callHistoryId == null) return;
    await _service.rejectIncomingCall(state.callHistoryId!);
    state = const ActiveCallState();
  }

  Future<void> hangUp() async {
    await _service.hangUp();
  }

  Future<void> toggleMute() async {
    await _service.toggleMute();
    state = state.copyWith(isMuted: _service.isMuted);
  }

  Future<void> toggleVideo() async {
    await _service.toggleVideo();
    state = state.copyWith(isVideoOn: _service.isVideoOn);
  }

  Future<void> toggleSpeaker() async {
    await _service.toggleSpeaker();
    state = state.copyWith(isSpeakerOn: _service.isSpeakerOn);
  }
}

final callStateProvider =
    StateNotifierProvider<CallStateNotifier, ActiveCallState>((ref) {
  final service = ref.watch(emergencyCallServiceProvider);
  return CallStateNotifier(service);
});
