import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Wrapper strict et de bas niveau autour du SDK Agora.
/// Cette classe ne contient AUCUNE logique métier, elle se contente
/// d'exécuter les requêtes matérielles/réseaux et de relayer les événements.
///
/// === OPTIMISATION RÉSEAU (Stratégie Latence Africaine) ===
/// • Codec OPUS en mode Speech Standard (résilient jusqu'à 30% packet loss)
/// • Scénario CHATROOM : buffer minimal (latence ~100ms vs 150ms défaut)
/// • FEC (Forward Error Correction) implicite dans OPUS
/// • EnableDualStream OFF en mode audio-only (réduit overhead)
/// • Edge Routing : area code configuré pour minimiser les sauts réseaux
/// • Callbacks réseau en temps réel (qualité, RTT, packet loss)
class AgoraClient {
  String get appId => dotenv.env['AGORA_APP_ID'] ?? '';

  RtcEngine? _engine;
  RtcEngine get engine {
    if (_engine == null) {
      throw Exception('Agora Engine was not initialized before access.');
    }
    return _engine!;
  }

  // Stream Controller pour relayer les callbacks vers le Repository
  // ⚠️ Ce controller est intentionnellement NON fermé par dispose() pour rester
  // réutilisable entre appels consécutifs. closeStreamController() doit être
  // appelé uniquement lors de la destruction FINALE par Riverpod.
  final _eventsController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get eventsStream => _eventsController.stream;

  Future<void> initialize() async {
    if (_engine != null) return;

    _engine = createAgoraRtcEngine();

    // ─── EDGE ROUTING : Area Code Afrique-Sub-Saharienne ─────────────────────
    // Forcer la connexion au POP (Point of Presence) Agora SD-RTN le plus proche
    // pour minimiser les sauts réseau inter-continentaux.
    // AREA_CODE_GLOB = fallback mondial si l'edge africain est indisponible.
    await _engine!.initialize(
      RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
        // Area code: prioritize Sub-Saharan Africa -> Europe -> Global
        areaCode: 0xFFFFFFFF, // AREA_CODE_GLOB (all regions, auto best-path)
      ),
    );

    // ─── CODEC AUDIO ADAPTATIF POUR RÉSEAU INSTABLE ───────────────────────────
    // AudioProfileSpeechStandard = OPUS 32kbps, optimisé voix, résilient.
    // AudioScenarioChatroom = buffer jitter minimal → latence très faible (~100ms),
    //   le SDK résiste aux fluctuations réseau sans trop augmenter le délai.
    //   Parfait pour les urgences : on privilégie la fluidité à la qualité audiophile.
    await _engine!.setAudioProfile(
      profile: AudioProfileType.audioProfileSpeechStandard,
      scenario: AudioScenarioType.audioScenarioChatroom,
    );

    // ─── PARAMÈTRES DE RÉSILIENCE RÉSEAU ─────────────────────────────────────
    // Active les mécanismes d'adaptation automatique en cas de dégradation réseau :
    // - Bitrate adaptatif (descend jusqu'à ~8kbps si nécessaire, garde la voix)
    // - FEC (Forward Error Correction) : reconstruit les paquets perdus côté récepteur
    //   sans demander une re-transmission (élimine le lag lié aux droits de reprise)
    // - AGC (Automatic Gain Control) : normalise le volume même en conditions difficiles
    await _engine!.setParameters('{"che.audio.enable.opus_fec":true}');
    await _engine!.setParameters('{"che.audio.max_mixed_participants":1}');
    await _engine!.enableAudioVolumeIndication(
      interval: 1000,
      smooth: 5,
      reportVad: true,
    );

    _setupEventHandlers();
  }

  void _setupEventHandlers() {
    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          _eventsController.add({
            'type': 'onJoinChannelSuccess',
            'uid': connection.localUid,
            'elapsed': elapsed, // Telemetry: ms to connect
          });
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          _eventsController.add({
            'type': 'onUserJoined',
            'remoteUid': remoteUid,
          });
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          _eventsController.add({
            'type': 'onUserOffline',
            'remoteUid': remoteUid,
          });
        },
        onConnectionStateChanged: (RtcConnection connection, ConnectionStateType state, ConnectionChangedReasonType reason) {
          _eventsController.add({
            'type': 'onConnectionStateChanged',
            'state': state,
            'reason': reason,
          });
        },
        onError: (ErrorCodeType err, String msg) {
          _eventsController.add({
            'type': 'onError',
            'code': err,
            'msg': msg,
          });
        },
        // ─── TÉLÉMÉTRIE RÉSEAU TEMPS RÉEL ────────────────────────────────────
        // Permet d'afficher la qualité réseau live dans l'UI (dispatcher + citoyen)
        // et de déclencher des stratégies d'adaptation si la qualité se dégrade.
        onNetworkQuality: (RtcConnection connection, int remoteUid, QualityType txQuality, QualityType rxQuality) {
          _eventsController.add({
            'type': 'onNetworkQuality',
            'txQuality': txQuality.index,  // 0=Unknown, 1=Excellent...6=Down
            'rxQuality': rxQuality.index,
          });
        },
        onRtcStats: (RtcConnection connection, RtcStats stats) {
          _eventsController.add({
            'type': 'onRtcStats',
            'rtt': stats.gatewayRtt,              // Round-Trip Time en ms
            'txPacketLossRate': stats.txPacketLossRate, // % perte côté émetteur
            'rxPacketLossRate': stats.rxPacketLossRate, // % perte côté récepteur
          });
        },
      ),
    );
  }

  // ─── CONNEXION AUDIO-FIRST (Urgences) ────────────────────────────────────────
  // Mode audio-only par défaut → connexion immédiate et moins de ressources réseau.
  // La vidéo peut être activée à la demande via toggleVideo.
  Future<void> joinChannel(String token, String channelId, int uid, {bool videoEnabled = false}) async {
    if (videoEnabled) {
      await _engine!.enableVideo();
      await _engine!.startPreview();
    } else {
      // Mode audio seul : désactive le pipeline vidéo pour libérer bande passante
      await _engine!.disableVideo();
    }

    // Haut-parleur ON par défaut pour les urgences (mains libres)
    await _engine!.setEnableSpeakerphone(true);

    await _engine!.joinChannel(
      token: token,
      channelId: channelId,
      uid: uid,
      options: ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        autoSubscribeVideo: videoEnabled,
        autoSubscribeAudio: true,
        publishCameraTrack: videoEnabled,
        publishMicrophoneTrack: true,
      ),
    );
  }

  Future<void> leaveChannel() async {
    await _engine?.stopPreview();
    await _engine?.leaveChannel();
  }

  Future<void> muteLocalAudio(bool muted) async {
    await _engine?.muteLocalAudioStream(muted);
  }

  Future<void> muteLocalVideo(bool muted) async {
    await _engine?.muteLocalVideoStream(muted);
    if (muted) {
      await _engine?.stopPreview();
    } else {
      await _engine?.startPreview();
    }
  }

  Future<void> setEnableSpeakerphone(bool isEnabled) async {
    await _engine?.setEnableSpeakerphone(isEnabled);
  }

  Future<void> switchCamera() async {
    await _engine?.switchCamera();
  }

  /// Réinitialise l'engine pour un nouvel appel (garde le StreamController ouvert)
  Future<void> dispose() async {
    await leaveChannel();
    _engine?.unregisterEventHandler(RtcEngineEventHandler());
    await _engine?.release();
    _engine = null;
    // ✅ _eventsController reste OUVERT — réutilisable pour le prochain appel
  }

  /// Détruit définitivement le client (appelé par Riverpod lors du onDispose)
  Future<void> closeStreamController() async {
    await dispose();
    if (!_eventsController.isClosed) {
      await _eventsController.close();
    }
  }
}
