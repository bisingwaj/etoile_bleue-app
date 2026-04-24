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

String? toIso6393(String? localeOrPref) {
  if (localeOrPref == null) return null;
  final raw = localeOrPref.toLowerCase();
  // Préférences explicites de l'app
  if (raw == 'lingala' || raw.startsWith('ln')) return 'lin';
  if (raw == 'swahili' || raw.startsWith('sw')) return 'swa';
  if (raw == 'english' || raw.startsWith('en')) return 'eng';
  if (raw == 'francais' || raw == 'français' || raw.startsWith('fr')) return 'fra';
  return null;
}

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

    // 2. Créer l'incident (avec gestion des erreurs P0001 du backend)
    String incidentId;
    String channelName;

    try {
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

      incidentId = incidentRes['id'] as String;
      channelName = reference;
    } on PostgrestException catch (e) {
      if (e.code == 'P0001' && e.message.contains('in_progress')) {
        debugPrint('[EmergencyCall] Incident in_progress detected. Reusing existing incident...');
        final existing = await _supabase
            .from('incidents')
            .select('id, reference')
            .eq('citizen_id', userId)
            .eq('status', 'in_progress')
            .limit(1)
            .single();

        incidentId = existing['id'] as String;
        channelName = existing['reference'] as String;
      } else if (e.code == 'P0001' && (e.message.contains('just ended') || e.message.contains('Duplicate incident'))) {
        debugPrint('[EmergencyCall] Duplicate incident or just ended detected. Reusing existing call record...');
        
        final existing = await _supabase
          .from('call_history')
          .select('id, channel_name, agora_token')
          .eq('citizen_id', userId)
          .inFilter('status', ['ringing', 'active'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

        if (existing != null) {
          _currentCallId = existing['id'] as String;
          _currentChannelName = existing['channel_name'] as String;
          final token = existing['agora_token'] as String;
          
          // Join the existing channel
          await _initAgoraEngine();
          await _engine!.joinChannel(
            token: token,
            channelId: _currentChannelName!,
            uid: 0,
            options: const ChannelMediaOptions(
              clientRoleType: ClientRoleType.clientRoleBroadcaster,
              channelProfile: ChannelProfileType.channelProfileCommunication,
              publishMicrophoneTrack: true,
              autoSubscribeAudio: true,
            ),
          );
          
          return _currentCallId;
        }

        debugPrint('[EmergencyCall] No existing active call found to join. Waiting 3 seconds before retrying...');
        await Future.delayed(const Duration(seconds: 3));
        
        final reference = 'SOS-${DateTime.now().millisecondsSinceEpoch}';
        final retryRes = await _supabase.from('incidents').insert({
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

        incidentId = retryRes['id'] as String;
        channelName = reference;
      } else {
        rethrow;
      }
    }

    _currentIncidentId = incidentId;
    _currentChannelName = channelName;

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
    late final String callId;
    try {
      // ANTI-DOUBLON CHECK
      final existingCall = await _supabase.from('call_history')
          .select('id, status, agora_token')
          .eq('channel_name', channelName)
          .inFilter('status', ['ringing', 'active'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existingCall != null) {
        debugPrint('[EmergencyCall] Anti-doublon: Reusing existing call for $channelName');
        callId = existingCall['id'] as String;
      } else {
        // Language Hint Logic
        String? hint;
        try {
          final profileLang = await _supabase
              .from('profiles')
              .select('preferred_language')
              .eq('user_id', userId)
              .maybeSingle();
              
          hint = toIso6393(
            profileLang?['preferred_language'] as String?
            ?? Platform.localeName,
          );
        } catch (e) {
          debugPrint('[EmergencyCall] Language hint error: $e');
        }

        final callRes = await _supabase.from('call_history').insert({
          'channel_name': channelName,
          'caller_name': callerName,
          'caller_phone': callerPhone,
          'caller_lat': lat,
          'caller_lng': lng,
          'incident_id': incidentId,
          'citizen_id': userId,
          'call_type': 'audio', // Must be 'audio' per prompt
          'status': 'ringing',
          'caller_preferred_language': hint,
          'agora_token': token,
          'role': 'citoyen',    // Required by dashboard
          'has_video': false,   // Required
          'started_at': DateTime.now().toUtc().toIso8601String(),
        }).select('id').single();
        callId = callRes['id'] as String;
      }
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

    _currentCallId = callId;
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
        'call_type': 'audio',
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
        // ❌ POINT 2 : Ne JAMAIS écrire 'status': 'active' depuis le mobile.
        // Seul le dashboard transite via claim_incoming_call.
        if (_currentCallId != null) {
          try {
            await _supabase.from('call_history').update({
              'answered_at': DateTime.now().toUtc().toIso8601String(),
            }).eq('id', _currentCallId!).eq('status', 'ringing');
          } catch (e) {
            debugPrint('[Agora] Failed to update answered_at on remote join: $e');
          }
        }
        onRemoteUserJoined?.call(remoteUid);
      },
      onUserOffline: (connection, remoteUid, reason) {
        debugPrint('[Agora] onUserOffline: uid=$remoteUid, reason=$reason');
        onRemoteUserLeft?.call(remoteUid);
        if (reason == UserOfflineReasonType.userOfflineQuit) {
          hangUp(endedBy: 'remote');
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
  Future<void> hangUp({String endedBy = 'citizen'}) async {
    final user = _supabase.auth.currentUser;
    final callIdToEnd = _currentCallId;
    final channelName = _currentChannelName;
    
    try {
      if (user != null && channelName != null) {
        await _supabase.from('call_history').update({
          'status': 'completed',
          'ended_at': DateTime.now().toUtc().toIso8601String(),
          'ended_by': endedBy,
        }).eq('channel_name', channelName)
          .eq('citizen_id', user.id)
          .not('status', 'in', ['completed', 'missed', 'failed']); // ❌ Retrait de 'cancelled' (n'existe pas)
          
          
        debugPrint('[EmergencyCall] hangUp: DB status updated to completed');
      }
    } catch (e) {
      debugPrint('[EmergencyCall] hangUp DB update failed (best-effort): $e');
    } finally {
      // Nettoyage impératif des ressources
      await _engine?.leaveChannel();
      await _engine?.release();
      _engine = null;
      _currentChannelName = null;
      _currentCallId = null;
      _currentIncidentId = null;
      _isMuted = false;
      _isVideoOn = false;
      _isSpeakerOn = true;

      if (callIdToEnd != null) {
        CallKitService.endCall(callIdToEnd);
      }
      CallKitService.endAllCalls();
      _stopForegroundService();

      onJoinChanged?.call(false);
      onCallEnded?.call();
    }
  }

  bool get isMuted => _isMuted;
  bool get isVideoOn => _isVideoOn;
  bool get isSpeakerOn => _isSpeakerOn;
  String? get currentChannelName => _currentChannelName;
  String? get currentCallId => _currentCallId;
  String? get currentIncidentId => _currentIncidentId;
  RtcEngine? get engine => _engine;

  /// Récupérer les données complètes d'un appel entrant depuis call_history.
  /// Utilisé quand l'app est réveillée par FCM et que le Realtime n'est pas encore actif.
  Future<Map<String, dynamic>?> fetchIncomingCall(String callId) async {
    try {
      final response = await _supabase
          .from('call_history')
          .select()
          .eq('id', callId)
          .eq('status', 'ringing')
          .maybeSingle();
      debugPrint('[EmergencyCall] fetchIncomingCall($callId): ${response != null ? 'found' : 'not found'}');
      return response;
    } catch (e) {
      debugPrint('[EmergencyCall] fetchIncomingCall error: $e');
      return null;
    }
  }

  /// Répondre à un appel entrant de la Centrale ou d'un Urgentiste.
  ///
  /// Flux conforme au prompt :
  /// 1. Fetch call_history pour récupérer le agora_token pré-généré
  /// 2. Rejoindre le canal Agora avec ce token
  /// 3. UPDATE status: active + answered_at (par ID)
  Future<void> answerIncomingCall(String channelName, String callHistoryId) async {
    debugPrint('[AnswerCall] Starting: channel=$channelName, callId=$callHistoryId');

    debugPrint('[AnswerCall] Requesting permissions...');
    final perms = await [Permission.microphone, Permission.camera].request();
    debugPrint('[AnswerCall] Permissions: mic=${perms[Permission.microphone]}, cam=${perms[Permission.camera]}');

    _currentChannelName = channelName;
    _currentCallId = callHistoryId;

    // 1. Fetch le record call_history pour récupérer le token pré-généré + incident_id
    String? token;
    final callRecord = await fetchIncomingCall(callHistoryId);
    if (callRecord != null) {
      token = callRecord['agora_token'] as String?;
      _currentIncidentId = callRecord['incident_id'] as String?;
      debugPrint('[AnswerCall] Pre-generated token found: ${token != null ? '${token.length} chars' : 'null'}');
      debugPrint('[AnswerCall] Incident ID: $_currentIncidentId');
    }

    // ❌ POINT 2 : Ne JAMAIS écrire 'status': 'active' depuis le mobile.
    debugPrint('[AnswerCall] Reporting answer time to call_history...');
    try {
      final updateRes = await _supabase.from('call_history').update({
        'answered_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', callHistoryId).select('id');

      if (updateRes.isEmpty) {
        debugPrint('[AnswerCall] Call already taken or cancelled, aborting!');
        _currentChannelName = null;
        _currentCallId = null;
        _currentIncidentId = null;
        throw Exception('Cet appel n\'est plus disponible ou a déjà été pris.');
      }
    } catch (e) {
      _currentChannelName = null;
      _currentCallId = null;
      _currentIncidentId = null;
      rethrow;
    }

    // 3. Fallback : si pas de token pré-généré, en demander un nouveau
    if (token == null || token.isEmpty) {
      debugPrint('[AnswerCall] No pre-generated token, requesting new one from edge function...');
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
        _currentIncidentId = null;
        throw Exception('Impossible d\'obtenir le token Agora pour répondre à l\'appel.');
      }
      token = tokenData['token'].toString();
    }
    debugPrint('[AnswerCall] Token ready (${token.length} chars)');

    // 4. Initialiser Agora et rejoindre le canal
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
    debugPrint('[AnswerCall] Complete');
  }

  /// Rejeter un appel entrant du dashboard
  Future<void> rejectIncomingCall(String callHistoryId, {String? channelName}) async {
    final updateQuery = _supabase.from('call_history').update({
      'status': 'completed',
      'ended_at': DateTime.now().toUtc().toIso8601String(),
      'ended_by': 'citizen_rejected',
    });

    if (channelName != null) {
      await updateQuery.eq('channel_name', channelName).inFilter('status', ['ringing', 'active']);
    } else {
      await updateQuery.eq('id', callHistoryId);
    }

    CallKitService.endCall(callHistoryId);
  }

  /// Nettoyage des appels orphelins (après crash/kill) — version 2.0
  Future<void> recoverOrphanCalls() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      // 1. Sélectionner les appels orphelins (> 30s d'existence sans status terminal)
      final now = DateTime.now().toUtc();
      final threshold = now.subtract(const Duration(seconds: 30)).toIso8601String();
      
      final orphans = await _supabase
          .from('call_history')
          .select('id, channel_name')
          .eq('citizen_id', user.id)
          .inFilter('status', ['ringing', 'active'])
          .lt('updated_at', threshold);

      if (orphans.isNotEmpty) {
        for (final row in orphans as List) {
          await _supabase.from('call_history').update({
            'status': 'completed',
            'ended_at': now.toIso8601String(),
            'ended_by': 'citizen_recovery',
          }).eq('id', row['id']);
          debugPrint('[CallLifecycle] Recovered orphan call: ${row['channel_name']}');
        }
      }
    } catch (e) {
      debugPrint('[CallLifecycle] Recovery failed: $e');
    }
  }

  /// Alias pour compatibilité
  Future<void> checkAndCleanupOrphanCalls() => recoverOrphanCalls();

  /// Rappeler — initie un nouvel appel de rappel vers l'urgentiste
  /// qui avait précédemment appelé le patient (appel manqué ou terminé).
  /// Cible spécifiquement l'urgentiste via son operator_id.
  Future<String?> callbackCall({
    required String originalCallId,
  }) async {
    debugPrint('[EmergencyCall] Starting callback for original call: $originalCallId');

    await [Permission.microphone, Permission.camera].request();

    // 1. Récupérer les données de l'appel original
    final originalCall = await _supabase
        .from('call_history')
        .select()
        .eq('id', originalCallId)
        .maybeSingle();

    if (originalCall == null) {
      throw Exception('Appel original introuvable.');
    }

    final incidentId = originalCall['incident_id'] as String?;
    final callerName = originalCall['caller_name'] as String?;
    final operatorId = originalCall['operator_id'] as String?;
    final originalChannelName = originalCall['channel_name'] as String? ?? '';

    debugPrint('[EmergencyCall] Original call: caller=$callerName, operator=$operatorId, channel=$originalChannelName');

    // 2. Générer un nouveau canal pour le rappel
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final channelName = 'CALLBACK-${originalCallId.substring(0, 8)}-$timestamp';
    _currentChannelName = channelName;
    _currentIncidentId = incidentId;

    // 3. Obtenir un token Agora
    final tokenRes = await _supabase.functions.invoke('agora-token', body: {
      'channelName': channelName,
      'uid': 0,
      'role': 'publisher',
      'expireTime': 3600,
    });
    final tokenData = tokenRes.data;
    if (tokenData == null || tokenData['token'] == null) {
      _currentChannelName = null;
      _currentIncidentId = null;
      throw Exception('Impossible d\'obtenir le token Agora pour le rappel.');
    }
    final token = tokenData['token'].toString();

    // 4. Récupérer les infos du patient
    final userRes = await _supabase
        .from('users_directory')
        .select('first_name, last_name, phone')
        .eq('auth_user_id', userId)
        .maybeSingle();
    final String patientName = userRes != null
        ? '${userRes['first_name']} ${userRes['last_name']}'
        : 'Patient';
    final String patientPhone = userRes?['phone'] ?? '';

    // 5. Créer l'entrée call_history pour le rappel — avec operator_id pour cibler l'urgentiste
    // ANTI-DOUBLON CHECK
    final existingCall = await _supabase.from('call_history')
        .select('id, status, agora_token')
        .eq('channel_name', channelName)
        .inFilter('status', ['ringing', 'active'])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (existingCall != null) {
      debugPrint('[EmergencyCall] Anti-doublon: Reusing existing call for $channelName');
      _currentCallId = existingCall['id'] as String;
    } else {
      final insertData = <String, dynamic>{
        'channel_name': channelName,
        'caller_name': patientName,
        'caller_phone': patientPhone,
        'incident_id': incidentId,
        'citizen_id': userId,
        'call_type': 'audio',
        'status': 'ringing',
        'agora_token': token,
        'role': 'citoyen',
        'has_video': false,
      };

      // Conserver l'operator_id pour le routage vers l'urgentiste
      if (operatorId != null) {
        insertData['operator_id'] = operatorId;
      }

      final callRes = await _supabase.from('call_history')
          .insert(insertData)
          .select('id')
          .single();

      _currentCallId = callRes['id'] as String;
    }

    // 6. Initialiser Agora et rejoindre le canal
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

    // 7. UI native + foreground service
    CallKitService.startOutgoingCall(
      callId: _currentCallId!,
      callerName: callerName ?? 'Urgentiste',
    );
    _startForegroundService(channelName);

    // 8. Notifier l'urgentiste ciblé via FCM push
    //    On passe target_user_id = operator_id pour que l'edge function
    //    envoie le push au bon urgentiste, pas à la centrale.
    try {
      final pushBody = <String, dynamic>{
        'citizen_id': userId,
        'channel_name': channelName,
        'caller_name': patientName,
        'call_type': 'callback',
        'original_call_id': originalCallId,
        'call_history_id': _currentCallId,
      };

      // Cibler l'urgentiste spécifique via son operator_id
      if (operatorId != null) {
        pushBody['target_user_id'] = operatorId;
        debugPrint('[EmergencyCall] Callback targeting urgentiste: $operatorId');
      }

      await _supabase.functions.invoke('send-call-push', body: pushBody);
    } catch (e) {
      debugPrint('[EmergencyCall] send-call-push (callback) failed (non-fatal): $e');
    }

    debugPrint('[EmergencyCall] Callback call started: channel=$channelName, callId=$_currentCallId, targetOperator=$operatorId');
    return _currentCallId;
  }

  /// Met à jour le statut vidéo dans call_history pour la synchronisation dashboard
  Future<void> updateVideoStatus(String callId, bool hasVideo) async {
    try {
      await _supabase.from('call_history').update({
        'has_video': hasVideo,
      }).eq('id', callId);
    } catch (e) {
      debugPrint('[EmergencyCall] updateVideoStatus error: $e');
    }
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
