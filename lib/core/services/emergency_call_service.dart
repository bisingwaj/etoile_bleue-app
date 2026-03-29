/// emergency_call_service_v2.dart — Service d'appels SOS corrigé
/// IMPORTANT: Utilise channel_name de call_history pour garantir
/// le même canal Agora entre mobile et dashboard

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String agoraAppId = 'e2e0e5a6ef0d4ce3b2ab9efad48d62cf';

class EmergencyCallService {
  final SupabaseClient _supabase;
  RtcEngine? _engine;
  String? _currentChannelName;
  String? _currentCallId;
  bool _isMuted = false;
  bool _isVideoOn = false;
  bool _isSpeakerOn = true;

  // Callbacks pour l'UI
  void Function(bool joined)? onJoinChanged;
  void Function(int uid)? onRemoteUserJoined;
  void Function(int uid)? onRemoteUserLeft;
  void Function()? onCallEnded;

  EmergencyCallService(this._supabase);

  String get userId => _supabase.auth.currentUser?.id ?? '';

  /// Initie un appel SOS — crée l'incident + call_history et rejoint le canal Agora
  Future<String?> startSOSCall({
    required String callerName,
    required String callerPhone,
    double? lat,
    double? lng,
    String type = 'urgence_medicale',
    String description = '',
  }) async {
    await [Permission.microphone, Permission.camera].request();

    // 1. Créer l'incident
    final reference = 'SOS-${DateTime.now().millisecondsSinceEpoch}';
    final incidentRes = await _supabase.from('incidents').insert({
      'reference': reference,
      'type': type,
      'title': 'Appel SOS - $callerName',
      'description': description,
      'caller_name': callerName,
      'caller_phone': callerPhone,
      'location_lat': lat,
      'location_lng': lng,
      'priority': 'critical',
      'status': 'new',
      'citizen_id': userId,
    }).select('id').single();

    final incidentId = incidentRes['id'] as String;

    // 2. Créer l'entrée call_history avec channel_name = reference
    // ⚠️ CRITIQUE: Le dashboard utilise ce channel_name pour rejoindre le même canal Agora
    final channelName = reference;

    // 3. Obtenir le token Agora
    final tokenRes = await _supabase.functions.invoke('agora-token', body: {
      'channelName': channelName,
      'uid': 0,
      'role': 'publisher',
      'expireTime': 3600,
    });
    final token = tokenRes.data['token'] as String;

    // 4. Créer le call_history
    final callRes = await _supabase.from('call_history').insert({
      'channel_name': channelName,
      'caller_name': callerName,
      'caller_phone': callerPhone,
      'caller_lat': lat,
      'caller_lng': lng,
      'incident_id': incidentId,
      'citizen_id': userId,
      'call_type': 'incoming',
      'status': 'ringing',
      'agora_token': token,
    }).select('id').single();

    _currentCallId = callRes['id'] as String;
    _currentChannelName = channelName;

    // 5. Initialiser Agora et rejoindre le canal
    await _initAgoraEngine();
    await _engine!.joinChannel(
      token: token,
      channelId: channelName,
      uid: 0,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );

    return _currentCallId;
  }

  /// Initialise le moteur Agora RTC
  Future<void> _initAgoraEngine() async {
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(const RtcEngineContext(
      appId: agoraAppId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        onJoinChanged?.call(true);
        try { _engine?.setEnableSpeakerphone(true); } catch (_) {}
        if (_currentCallId != null) {
          _supabase.from('call_history').update({
            'status': 'active',
            'answered_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('id', _currentCallId!);
        }
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        onRemoteUserJoined?.call(remoteUid);
      },
      onUserOffline: (connection, remoteUid, reason) {
        onRemoteUserLeft?.call(remoteUid);
        // Si l'opérateur quitte, on termine l'appel
        if (reason == UserOfflineReasonType.userOfflineQuit) {
          hangUp();
        }
      },
      onConnectionLost: (connection) {
        // Reconnexion automatique gérée par Agora
      },
    ));

    await _engine!.enableAudio();
  }

  /// Mute/Unmute le micro
  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    await _engine?.muteLocalAudioStream(_isMuted);
  }

  /// Active/Désactive la vidéo
  Future<void> toggleVideo() async {
    _isVideoOn = !_isVideoOn;
    if (_isVideoOn) {
      await _engine?.enableVideo();
      await _engine?.startPreview();
    } else {
      await _engine?.stopPreview();
      await _engine?.disableVideo();
    }
  }

  /// Active/Désactive le haut-parleur
  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    await _engine?.setEnableSpeakerphone(_isSpeakerOn);
  }

  /// Raccrocher — met à jour call_history ET libère les ressources
  Future<void> hangUp() async {
    // ⚠️ CRITIQUE: Mettre à jour le statut dans la DB pour que le dashboard le détecte
    if (_currentCallId != null) {
      await _supabase.from('call_history').update({
        'status': 'completed',
        'ended_at': DateTime.now().toUtc().toIso8601String(),
        'ended_by': 'citizen',
      }).eq('id', _currentCallId!);
    }

    await _engine?.leaveChannel();
    await _engine?.release();
    _engine = null;
    _currentChannelName = null;
    _currentCallId = null;
    _isMuted = false;
    _isVideoOn = false;

    onJoinChanged?.call(false);
    onCallEnded?.call();
  }

  bool get isMuted => _isMuted;
  bool get isVideoOn => _isVideoOn;
  bool get isSpeakerOn => _isSpeakerOn;
  String? get currentChannelName => _currentChannelName;
  String? get currentCallId => _currentCallId;
  RtcEngine? get engine => _engine;

  /// Répondre à un appel entrant du dashboard
  Future<void> answerIncomingCall(String channelName, String callHistoryId) async {
    await [Permission.microphone, Permission.camera].request();

    _currentChannelName = channelName;
    _currentCallId = callHistoryId;

    final tokenRes = await _supabase.functions.invoke('agora-token', body: {
      'channelName': channelName,
      'uid': 0,
      'role': 'publisher',
      'expireTime': 3600,
    });
    final token = tokenRes.data['token'] as String;

    await _initAgoraEngine();
    await _engine!.joinChannel(
      token: token,
      channelId: channelName,
      uid: 0,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );

    await _supabase.from('call_history').update({
      'status': 'active',
      'answered_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', callHistoryId);
  }

  /// Rejeter un appel entrant du dashboard
  Future<void> rejectIncomingCall(String callHistoryId) async {
    await _supabase.from('call_history').update({
      'status': 'missed',
      'ended_at': DateTime.now().toUtc().toIso8601String(),
      'ended_by': 'citizen',
    }).eq('id', callHistoryId);
  }

  void dispose() {
    _engine?.release();
  }

  Future<void> endEmergencyCall() => hangUp();

  /// UI Backward compatibility
  Future<void> startEmergencyCall() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    
    // Obtenir infos user
    final userRes = await _supabase.from('users_directory').select('first_name, last_name, phone').eq('auth_user_id', userId).maybeSingle();
    final String name = userRes != null ? '${userRes['first_name']} ${userRes['last_name']}' : 'Anonyme';
    final String phone = userRes?['phone'] ?? '+243000000000';
    
    await startSOSCall(callerName: name, callerPhone: phone);
  }

  /// UI Backward compatibility
  Future<void> updateTriageData(String channelId, Map<String, dynamic> data) async {
    // Si la colonne n'existe pas ou pour simplifier, on peut juste logger ou stocker dans update
    // Par exemple, mettre à jour la description de l'incident :
    final callRes = await _supabase.from('call_history').select('incident_id').eq('channel_name', channelId).maybeSingle();
    if (callRes != null && callRes['incident_id'] != null) {
      final incidentId = callRes['incident_id'];
      await _supabase.from('incidents').update({
        'description': data.toString(), 
      }).eq('id', incidentId);
    }
  }
}

final isCallMinimizedProvider = StateProvider<bool>((ref) => false);

final emergencyCallServiceProvider = Provider<EmergencyCallService>((ref) {
  return EmergencyCallService(Supabase.instance.client);
});
