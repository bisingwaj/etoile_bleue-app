import 'dart:io' show Platform;
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etoile_bleue_mobile/core/services/callkit_service.dart';
import 'package:etoile_bleue_mobile/core/services/call_foreground_service.dart';
import 'package:etoile_bleue_mobile/core/services/telemetry_service.dart';

final String agoraAppId = dotenv.env['AGORA_APP_ID'] ?? 'e2e0e5a6ef0d4ce3b2ab9efad48d62cf';

class EmergencyCallService {
  final SupabaseClient _supabase;
  RtcEngine? _engine;
  String? _currentChannelName;
  String? _currentCallId;
  String? _currentIncidentId;
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

  /// Vérifie si le citoyen actuel est bloqué par la liste noire
  Future<Map<String, dynamic>> checkBlocked() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return {'blocked': false};
    
    try {
      final result = await _supabase.rpc('is_citizen_blocked', params: {
        'p_citizen_id': user.id,
      });
      if (result != null) {
        return Map<String, dynamic>.from(result as Map);
      }
    } catch (e) {
      debugPrint('[EmergencyCall] checkBlocked error: $e');
    }
    return {'blocked': false};
  }

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

    // 1. Récupérer la télémétrie de l'appareil
    final telemetry = await TelemetryService.getDeviceTelemetry();

    // 1b. Reverse geocoding — transformer lat/lng en adresse lisible
    String? locationAddress;
    if (lat != null && lng != null) {
      try {
        final placemarks = await geo.placemarkFromCoordinates(lat, lng)
            .timeout(const Duration(seconds: 3));
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = [
            p.name,
            [p.subThoroughfare, p.thoroughfare].where((s) => s != null && s.isNotEmpty).join(' '),
            p.subLocality,
            p.locality,
            if (p.subAdministrativeArea != null && p.subAdministrativeArea != p.locality)
              p.subAdministrativeArea,
            if (p.administrativeArea != null && p.administrativeArea != p.locality)
              p.administrativeArea,
          ].where((s) => s != null && s.isNotEmpty).cast<String>().toList();
          final unique = parts.toSet().toList();
          if (unique.isNotEmpty) {
            locationAddress = unique.join(', ');
          }
        }
        debugPrint('[EmergencyCall] Reverse geocoded: $locationAddress');
      } catch (e) {
        debugPrint('[EmergencyCall] Reverse geocoding failed (non-fatal): $e');
      }
    }

    // 2. Créer l'incident
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
      'location_address': locationAddress,
      'priority': 'critical',
      'status': 'new',
      'citizen_id': userId,
      'device_model': telemetry['device_model'],
      'battery_level': telemetry['battery_level'],
      'network_state': telemetry['network_state'],
    }).select('id').single();

    final incidentId = incidentRes['id'] as String;
    _currentIncidentId = incidentId;

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
    final tokenData = tokenRes.data;
    if (tokenData == null || tokenData['token'] == null) {
      debugPrint('[EmergencyCall] Agora token invalid — cleaning up orphan incident $incidentId');
      try {
        await _supabase.from('incidents').delete().eq('id', incidentId);
      } catch (e) {
        debugPrint('[EmergencyCall] Failed to delete orphan incident: $e');
      }
      _currentIncidentId = null;
      throw Exception('Impossible d\'obtenir le token Agora. Vérifiez votre connexion.');
    }
    final token = tokenData['token'].toString();

    // 4. Créer le call_history (compensate incident on failure)
    late final Map<String, dynamic> callRes;
    try {
      callRes = await _supabase.from('call_history').insert({
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
    } catch (e) {
      debugPrint('[EmergencyCall] call_history insert failed — cleaning orphan incident $incidentId');
      try {
        await _supabase.from('incidents').delete().eq('id', incidentId);
      } catch (delErr) {
        debugPrint('[EmergencyCall] Failed to delete orphan incident: $delErr');
      }
      _currentIncidentId = null;
      rethrow;
    }

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
        publishMicrophoneTrack: true,
        autoSubscribeAudio: true,
      ),
    );

    // 6. Report to native call UI & start foreground service
    CallKitService.startOutgoingCall(
      callId: _currentCallId!,
      callerName: callerName,
    );
    _startForegroundService(channelName);

    // 7. Notify the assigned operator via FCM push
    try {
      await _supabase.functions.invoke('send-call-push', body: {
        'citizen_id': userId,
        'channel_name': channelName,
        'caller_name': callerName,
        'call_type': 'incoming',
      });
    } catch (e) {
      debugPrint('[EmergencyCall] send-call-push failed (non-fatal): $e');
    }

    return _currentCallId;
  }

  /// Initialise le moteur Agora RTC
  Future<void> _initAgoraEngine() async {
    if (_engine != null) {
      debugPrint('[Agora] Releasing stale engine before re-init');
      try {
        await _engine!.leaveChannel();
      } catch (_) {}
      await _engine!.release();
      _engine = null;
    }

    debugPrint('[Agora] Creating RTC engine...');
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(
      appId: agoraAppId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));
    debugPrint('[Agora] Engine initialized');

    // On iOS, CallKit manages the audio session. Tell Agora to keep it
    // instead of resetting it, otherwise the audio will be silent.
    if (Platform.isIOS) {
      await _engine!.setParameters('{"che.audio.keep.audiosession": true}');
      debugPrint('[Agora] iOS: set keep.audiosession = true');
    }

    // --- AUDIO OPTIMISÉ POUR TRANSCRIPTION + APPELS ---
    // audioProfileDefault + audioScenarioChatroom : compatibilité Web Audio API
    // pour la transcription côté dashboard tout en gardant une bonne qualité vocale.
    await _engine!.setAudioProfile(
      profile: AudioProfileType.audioProfileDefault,
      scenario: AudioScenarioType.audioScenarioChatroom,
    );

    // On active une configuration vidéo dégradable (si la vidéo est allumée) : 
    // Maintien de l'audio et baisse de la qualité/framerate de la vidéo.
    await _engine!.setVideoEncoderConfiguration(
      const VideoEncoderConfiguration(
        dimensions: VideoDimensions(width: 480, height: 480), // Résolution moyenne pour économiser
        frameRate: 15, // FPS réduit 
        degradationPreference: DegradationPreference.maintainQuality,
      ),
    );
    // ---------------------------------------

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) async {
        debugPrint('[Agora] onJoinChannelSuccess: channel=${connection.channelId}, elapsed=$elapsed');
        onJoinChanged?.call(true);
        try { _engine?.setEnableSpeakerphone(true); } catch (_) {}
      },
      onUserJoined: (connection, remoteUid, elapsed) async {
        debugPrint('[Agora] onUserJoined: uid=$remoteUid');
        // Set answered_at only if status is still 'ringing' (SOS flow).
        // For incoming calls, answerIncomingCall() already wrote it.
        if (_currentCallId != null) {
          try {
            await _supabase.from('call_history').update({
              'status': 'active',
              'answered_at': DateTime.now().toUtc().toIso8601String(),
            }).eq('id', _currentCallId!).eq('status', 'ringing');
          } catch (e) {
            debugPrint('[Agora] Failed to update call_history on remote join: $e');
          }
        }
        onRemoteUserJoined?.call(remoteUid);
      },
      onUserOffline: (connection, remoteUid, reason) {
        debugPrint('[Agora] onUserOffline: uid=$remoteUid, reason=$reason');
        onRemoteUserLeft?.call(remoteUid);
        if (reason == UserOfflineReasonType.userOfflineQuit) {
          hangUp();
        }
      },
      onConnectionLost: (connection) {
        debugPrint('[Agora] onConnectionLost');
      },
      onError: (err, msg) {
        debugPrint('[Agora] ERROR: $err — $msg');
      },
    ));

    await _engine!.enableAudio();
    debugPrint('[Agora] Audio enabled');
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

  /// Bascule caméra avant/arrière
  Future<void> switchCamera() async {
    await _engine?.switchCamera();
  }

  /// Raccrocher — met à jour call_history ET libère les ressources
  Future<void> hangUp() async {
    final callIdToEnd = _currentCallId;

    if (callIdToEnd != null) {
      try {
        final now = DateTime.now().toUtc();
        
        // Fetch answered_at to calculate duration
        final callData = await _supabase
            .from('call_history')
            .select('answered_at')
            .eq('id', callIdToEnd)
            .maybeSingle();
            
        int? durationSeconds;
        if (callData != null && callData['answered_at'] != null) {
          final answeredAt = DateTime.parse(callData['answered_at']);
          durationSeconds = now.difference(answeredAt).inSeconds;
        }

        final updateData = <String, dynamic>{
          'status': 'completed',
          'ended_at': now.toIso8601String(),
          'ended_by': 'citizen_hangup',
        };
        
        if (durationSeconds != null && durationSeconds >= 0) {
          updateData['duration_seconds'] = durationSeconds;
        }

        await _supabase.from('call_history').update(updateData).eq('id', callIdToEnd);
      } catch (e) {
        debugPrint('[EmergencyCall] hangUp DB update failed (non-fatal): $e');
      }
    }

    await _engine?.leaveChannel();
    await _engine?.release();
    _engine = null;
    _currentChannelName = null;
    _currentCallId = null;
    _currentIncidentId = null;
    _isMuted = false;
    _isVideoOn = false;
    _isSpeakerOn = true;

    // End native call UI and stop foreground service
    if (callIdToEnd != null) {
      CallKitService.endCall(callIdToEnd);
    }
    CallKitService.endAllCalls();
    _stopForegroundService();

    onJoinChanged?.call(false);
    onCallEnded?.call();
  }

  bool get isMuted => _isMuted;
  bool get isVideoOn => _isVideoOn;
  bool get isSpeakerOn => _isSpeakerOn;
  String? get currentChannelName => _currentChannelName;
  String? get currentCallId => _currentCallId;
  String? get currentIncidentId => _currentIncidentId;
  RtcEngine? get engine => _engine;

  /// Répondre à un appel entrant du dashboard
  Future<void> answerIncomingCall(String channelName, String callHistoryId) async {
    debugPrint('[AnswerCall] Starting: channel=$channelName, callId=$callHistoryId');

    debugPrint('[AnswerCall] Requesting permissions...');
    final perms = await [Permission.microphone, Permission.camera].request();
    debugPrint('[AnswerCall] Permissions: mic=${perms[Permission.microphone]}, cam=${perms[Permission.camera]}');

    _currentChannelName = channelName;
    _currentCallId = callHistoryId;

    debugPrint('[AnswerCall] Fetching Agora token...');
    final tokenRes = await _supabase.functions.invoke('agora-token', body: {
      'channelName': channelName,
      'uid': 0,
      'role': 'publisher',
      'expireTime': 3600,
    });
    debugPrint('[AnswerCall] Token response status: ${tokenRes.status}');
    final tokenData = tokenRes.data;
    if (tokenData == null || tokenData['token'] == null) {
      debugPrint('[AnswerCall] Agora token invalid — clearing stale state');
      _currentChannelName = null;
      _currentCallId = null;
      throw Exception('Impossible d\'obtenir le token Agora pour répondre à l\'appel.');
    }
    final token = tokenData['token'].toString();
    debugPrint('[AnswerCall] Token received (${token.length} chars)');

    debugPrint('[AnswerCall] Initializing Agora engine...');
    await _initAgoraEngine();

    debugPrint('[AnswerCall] Joining channel $channelName...');
    await _engine!.joinChannel(
      token: token,
      channelId: channelName,
      uid: 0,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
        publishMicrophoneTrack: true,
        autoSubscribeAudio: true,
      ),
    );
    debugPrint('[AnswerCall] joinChannel call returned');

    _startForegroundService(channelName);

    debugPrint('[AnswerCall] Updating call_history to active...');
    await _supabase.from('call_history').update({
      'status': 'active',
      'answered_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', callHistoryId);
    debugPrint('[AnswerCall] Complete');
  }

  /// Rejeter un appel entrant du dashboard
  Future<void> rejectIncomingCall(String callHistoryId) async {
    await _supabase.from('call_history').update({
      'status': 'missed',
      'ended_at': DateTime.now().toUtc().toIso8601String(),
      'ended_by': 'citizen_rejected',
    }).eq('id', callHistoryId);

    CallKitService.endCall(callHistoryId);
  }

  void _startForegroundService(String channelName) {
    CallForegroundService.start(channelId: channelName, role: 'Citizen').catchError((e) {
      debugPrint('[EmergencyCallService] Foreground service start error: $e');
    });
  }

  void _stopForegroundService() {
    CallForegroundService.stop().catchError((e) {
      debugPrint('[EmergencyCallService] Foreground service stop error: $e');
    });
  }

  Future<void> dispose() async {
    try {
      await _engine?.leaveChannel();
    } catch (_) {}
    try {
      await _engine?.release();
    } catch (_) {}
    _engine = null;
  }

  Future<void> endEmergencyCall() => hangUp();

  /// UI Backward compatibility — accepts optional GPS coordinates
  Future<void> startEmergencyCall({double? lat, double? lng}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Utilisateur non authentifié. Veuillez vous reconnecter.');
    }
    
    final userRes = await _supabase.from('users_directory').select('first_name, last_name, phone').eq('auth_user_id', userId).maybeSingle();
    final String name = userRes != null ? '${userRes['first_name']} ${userRes['last_name']}' : 'Anonyme';
    final String phone = userRes?['phone'] ?? '+243000000000';
    
    await startSOSCall(callerName: name, callerPhone: phone, lat: lat, lng: lng);
  }

  Future<void> updateTriageData(String channelId, Map<String, dynamic> data) async {
    try {
      await _supabase.from('call_history').update({
        'triage_data': data,
      }).eq('channel_name', channelId);
    } catch (e) {
      debugPrint('[EmergencyCall] updateTriageData error: $e');
    }
  }
}

final isCallMinimizedProvider = StateProvider<bool>((ref) => false);

final emergencyCallServiceProvider = Provider<EmergencyCallService>((ref) {
  return EmergencyCallService(Supabase.instance.client);
});
