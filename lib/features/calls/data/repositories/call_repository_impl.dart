import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:etoile_bleue_mobile/features/calls/domain/repositories/call_repository.dart';
import 'package:etoile_bleue_mobile/core/network/agora_client.dart';
import 'package:flutter/foundation.dart';

/// ✅ CORRIGÉ: Utilise 'call_history' au lieu de 'calls'
class CallRepositoryImpl implements CallRepository {
  final AgoraClient _agoraClient;
  bool _isJoining = false;

  late final Stream<Map<String, dynamic>> _eventsStream;

  CallRepositoryImpl(this._agoraClient) {
    _eventsStream = _agoraClient.eventsStream;
  }

  @override
  Stream<Map<String, dynamic>> get agoraEventsStream => _eventsStream;

  @override
  Future<void> initializeEngine() async {
    try {
      await _agoraClient.initialize();
    } catch (e) {
      debugPrint('CallRepositoryImpl: Error initializing engine: $e');
      rethrow;
    }
  }

  @override
  Future<void> joinCall({
    required String channelId,
    required String role,
    required String uid,
  }) async {
    if (_isJoining) {
      throw Exception('CALL_ALREADY_IN_PROGRESS');
    }
    _isJoining = true;

    final needsCamera = role != 'Dispatcher';

    try {
      final permissionsGranted =
          await _requestPermissions(includeCamera: needsCamera);
      if (!permissionsGranted) {
        throw Exception('PERMISSIONS_DENIED');
      }

      await _agoraClient.dispose();
      await initializeEngine();

      final uidForAgora =
          Supabase.instance.client.auth.currentUser?.id ?? '';
      final intUid =
          uidForAgora.isNotEmpty ? _stableUidFromString(uidForAgora) : 0;

      // ✅ Récupérer le token Agora via l'Edge Function Supabase
      String token = '';
      try {
        final response = await Supabase.instance.client.functions.invoke(
          'agora-token',
          body: {
            'channelName': channelId,
            'uid': intUid,
            'role': role == 'Citizen' ? 'publisher' : 'subscriber',
          },
        );
        if (response.data != null && response.data['token'] != null) {
          token = response.data['token'];
          debugPrint('[CallRepo] ✅ Token Agora obtenu via Edge Function');
        }
      } catch (e) {
        debugPrint('[CallRepo] ⚠️ Impossible d\'obtenir le token Agora: $e');
        // Fallback: token vide (fonctionnera si App Certificate n'est pas requis)
      }

      await _agoraClient.joinChannel(
          token, channelId, intUid, videoEnabled: needsCamera);

      // ✅ CORRIGÉ: Sauvegarder dans 'call_history' au lieu de 'calls'
      try {
        await Supabase.instance.client
            .from('call_history')
            .update({'agora_token': token, 'agora_uid': intUid})
            .eq('channel_name', channelId);
      } catch (e) {
        debugPrint('[CallRepo] Token non sauvegardé: $e');
      }
    } catch (e) {
      debugPrint('CallRepositoryImpl: Error joining call: $e');
      rethrow;
    } finally {
      _isJoining = false;
    }
  }

  @override
  Future<void> leaveCall() async {
    await _agoraClient.leaveChannel();
  }

  @override
  Future<void> toggleAudio(bool isEnabled) async {
    await _agoraClient.muteLocalAudio(!isEnabled);
  }

  @override
  Future<void> toggleVideo(bool isEnabled) async {
    await _agoraClient.muteLocalVideo(!isEnabled);
  }

  @override
  Future<void> toggleSpeaker(bool isEnabled) async {
    await _agoraClient.setEnableSpeakerphone(isEnabled);
  }

  @override
  Future<void> switchCamera() async {
    await _agoraClient.switchCamera();
  }

  Future<bool> _requestPermissions({bool includeCamera = true}) async {
    final permissions = <Permission>[Permission.microphone];
    if (includeCamera) permissions.add(Permission.camera);

    final statusMap = await permissions.request();
    final micStatus = statusMap[Permission.microphone];

    if (micStatus != PermissionStatus.granted) {
      return false;
    }
    return true;
  }

  /// ✅ Hash MD5 déterministe pour UID Agora stable
  static int _stableUidFromString(String uid) {
    final bytes = utf8.encode(uid);
    final digest = md5.convert(bytes);
    final hash = digest.bytes
        .sublist(0, 4)
        .fold<int>(0, (prev, byte) => (prev << 8) | byte);
    return hash.abs() % 0x7FFFFFFF; // Entier positif 31 bits
  }
}
