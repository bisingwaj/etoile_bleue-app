import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Service Flutter pour démarrer et arrêter l'enregistrement audio Agora Cloud Recording.
///
/// ─── Edge Cases couverts ──────────────────────────────────────────────────────
/// ✅ EC-1 : Double startRecording() — guard _isStarting empêche un double acquire
/// ✅ EC-2 : Erreur dans stopRecording() — session réinitialisée dans le finally
/// ✅ EC-3 : maxIdleTime Agora (30s sans participant) — détecté via watchRecordingStatus()
/// ✅ EC-4 : Token optionnel — l'Edge Function génère son propre token si absent
/// ✅ EC-5 : stopRecording() si recording jamais démarré — guard explicite + log
/// ✅ EC-6 : App tuée / crash pendant recording — onCallEnded Cloud Function arrête Agora via stop
class CloudRecordingService {
  final SupabaseClient _supabase;

  String? _resourceId;
  String? _sid;
  String? _currentChannelId;
  bool _isStarting = false; // EC-1 : Guard anti-double acquire

  CloudRecordingService({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  /// Démarre l'enregistrement audio pour un appel SOS.
  ///
  /// Retourne true si l'enregistrement a démarré avec succès.
  /// Le token est optionnel : l'Edge Function génère le sien si absent.
  Future<bool> startRecording({
    required String channelId,
    String? token,
  }) async {
    if (_isStarting || _sid != null) {
      debugPrint('[CloudRecordingService] Enregistrement déjà en cours ou en démarrage.');
      return false;
    }
    _isStarting = true;

    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) {
      _isStarting = false;
      return false;
    }

    try {
      final body = <String, dynamic>{
        'channelId': channelId,
        'uid': uid,
      };
      if (token != null && token.isNotEmpty) {
        body['token'] = token;
      }

      final result = await _supabase.functions.invoke(
        'startCloudRecording',
        body: body,
      );

      final data = result.data as Map<String, dynamic>?;
      _resourceId = data?['resourceId'] as String?;
      _sid = data?['sid'] as String?;
      _currentChannelId = channelId;

      final success = _resourceId != null && _sid != null;
      debugPrint('[CloudRecordingService] ${success ? "Démarré" : "Échec"} — sid=$_sid');
      return success;
    } catch (e) {
      debugPrint('[CloudRecordingService] Erreur démarrage: $e');
      // EC-2 : Nettoyage même en cas d'erreur
      _resourceId = null;
      _sid = null;
      _currentChannelId = null;
      return false;
    } finally {
      _isStarting = false; // EC-1 : Toujours libérer le guard
    }
  }

  /// Arrête l'enregistrement en cours et retourne l'URL du fichier audio.
  Future<String?> stopRecording() async {
    // EC-5 : Guard explicite si pas d'enregistrement actif
    if (_sid == null || _resourceId == null || _currentChannelId == null) {
      debugPrint('[CloudRecordingService] Pas d\'enregistrement actif à arrêter.');
      return null;
    }

    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return null;

    // Sauvegarder les valeurs localement avant le try (EC-2 : finally réinitialise)
    final channelId = _currentChannelId!;
    final resourceId = _resourceId!;
    final sid = _sid!;

    try {
      final result = await _supabase.functions.invoke(
        'stopCloudRecording',
        body: {
          'channelId': channelId,
          'uid': uid,
          'resourceId': resourceId,
          'sid': sid,
        },
      );

      final data = result.data as Map<String, dynamic>?;
      final recordingUrl = data?['recordingUrl'] as String?;
      debugPrint('[CloudRecordingService] ✅ Arrêté — url=$recordingUrl');
      return recordingUrl;
    } catch (e) {
      debugPrint('[CloudRecordingService] Erreur arrêt: $e');
      return null;
    } finally {
      // EC-2 : Toujours réinitialiser, succès OU échec
      _resourceId = null;
      _sid = null;
      _currentChannelId = null;
    }
  }

  /// Stream du statut de l'enregistrement — détecte EC-3 (maxIdleTime Agora).
  ///
  /// Si recording.status passe à "stopped" sans action Flutter (canal vide 30s),
  /// l'UI peut afficher un badge "Enregistrement interrompu".
  Stream<Map<String, dynamic>?> watchRecordingStatus(String channelId) {
    return _supabase
        .from('calls')
        .stream(primaryKey: ['id'])
        .eq('id', channelId)
        .map((docs) => docs.isNotEmpty ? docs.first['recording'] as Map<String, dynamic>? : null);
  }

  bool get isRecording => _sid != null && !_isStarting;
}

/// Provider Riverpod du service d'enregistrement
final cloudRecordingServiceProvider = Provider<CloudRecordingService>((ref) {
  return CloudRecordingService();
});
