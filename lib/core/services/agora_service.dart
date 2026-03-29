import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';

class AgoraService {
  late RtcEngine _engine;
  bool _isInitialized = false;

  RtcEngine get engine => _engine;

  Future<void> initialize(String appId, RtcEngineEventHandler handler) async {
    if (_isInitialized) return;

    // Check permissions
    await [Permission.microphone, Permission.camera].request();

    _engine = createAgoraRtcEngine();
    
    await _engine.initialize(
      RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );

    _engine.registerEventHandler(handler);

    await _engine.enableVideo();
    await _engine.startPreview();
    
    _isInitialized = true;
  }

  Future<void> joinChannel({
    required String token,
    required String channelId,
    required int uid,
    bool isVideoEnabled = true,
  }) async {
    if (!_isInitialized) throw Exception('AgoraService not initialized');

    if (isVideoEnabled) {
      await _engine.enableVideo();
    } else {
      await _engine.disableVideo();
    }

    await _engine.joinChannel(
      token: token,
      channelId: channelId,
      uid: uid,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  Future<void> leaveChannel() async {
    if (!_isInitialized) return;
    await _engine.leaveChannel();
  }

  Future<void> toggleVideo(bool enabled) async {
    if (!_isInitialized) return;
    if (enabled) {
      await _engine.enableVideo();
    } else {
      await _engine.disableVideo();
    }
  }

  Future<void> toggleAudio(bool enabled) async {
    if (!_isInitialized) return;
    await _engine.muteLocalAudioStream(!enabled);
  }

  Future<void> switchCamera() async {
    if (!_isInitialized) return;
    await _engine.switchCamera();
  }

  Future<void> dispose() async {
    if (!_isInitialized) return;
    await _engine.leaveChannel();
    await _engine.release();
    _isInitialized = false;
  }
}
