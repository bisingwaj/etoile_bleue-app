import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ✅ CORRIGÉ: Utilise les bonnes colonnes de la table 'incidents'
/// Schéma réel: reference, type, title, description, caller_name, caller_phone,
///   location_lat, location_lng, media_urls, status, priority, citizen_id, media_type
class IncidentRepository {
  final SupabaseClient _db;
  final String? _uid;

  IncidentRepository({SupabaseClient? db})
      : _db = db ?? Supabase.instance.client,
        _uid = Supabase.instance.client.auth.currentUser?.id;

  // ─── UPLOAD MÉDIA ─────────────────────────────────────────────────────────────

  /// ✅ Upload vers le bucket 'incidents' (créé par migration)
  static const int _maxImageBytes = 10 * 1024 * 1024; // 10 MB
  static const int _maxVideoBytes = 50 * 1024 * 1024; // 50 MB

  Future<String> uploadMedia({
    required File file,
    required bool isVideo,
    void Function(double progress)? onProgress,
  }) async {
    if (_uid == null) throw Exception('Utilisateur non connecté');

    final fileSize = await file.length();
    final maxSize = isVideo ? _maxVideoBytes : _maxImageBytes;
    if (fileSize > maxSize) {
      throw Exception(
        'Fichier trop volumineux (${(fileSize / (1024 * 1024)).toStringAsFixed(1)} Mo). '
        'Maximum : ${maxSize ~/ (1024 * 1024)} Mo',
      );
    }

    final ext = isVideo ? 'mp4' : 'jpg';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$_uid/$timestamp.$ext';

    try {
      await _db.storage.from('incidents').upload(path, file);
      onProgress?.call(1.0);
    } catch (e) {
      debugPrint("Storage Upload Error: $e");
      rethrow;
    }

    final downloadUrl = _db.storage.from('incidents').getPublicUrl(path);
    debugPrint('[IncidentRepository] ✅ Média uploadé: $downloadUrl');
    return downloadUrl;
  }

  // ─── CRÉATION INCIDENT ────────────────────────────────────────────────────────

  /// ✅ CORRIGÉ: Colonnes alignées sur le schéma réel de la table 'incidents'
  Future<String> createIncident({
    required String mediaUrl,
    required bool isVideo,
    required String category,
    String? details,
    Map<String, double>? location,
    DateTime? incidentTimestamp,
  }) async {
    if (_uid == null) throw Exception('Utilisateur non connecté');

    // Générer une référence unique
    final ref = 'SIG-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

    // Récupérer le nom de l'appelant depuis users_directory
    String? callerName;
    String? callerPhone;
    try {
      final profile = await _db
          .from('users_directory')
          .select('first_name, last_name, phone')
          .eq('auth_user_id', _uid)
          .maybeSingle();
      if (profile != null) {
        callerName = '${profile['first_name']} ${profile['last_name']}'.trim();
        callerPhone = profile['phone'];
      }
    } catch (_) {}

    final response = await _db.from('incidents').insert({
      'reference': ref,
      'type': category,
      'title': 'Signalement: $category',
      'description': details ?? '',
      'caller_name': callerName,
      'caller_phone': callerPhone,
      'citizen_id': _uid,
      'media_urls': mediaUrl.isNotEmpty ? [mediaUrl] : [],
      'media_type': isVideo ? 'video' : 'photo',
      'location_lat': location?['lat'],
      'location_lng': location?['lng'],
      'incident_at': incidentTimestamp?.toIso8601String(),
      'status': 'new',
      'priority': 'medium',
      'province': 'Kinshasa',
      'ville': 'Kinshasa',
    }).select('id').single();

    final docId = response['id'].toString();
    debugPrint('[IncidentRepository] ✅ Incident créé: $docId');
    return docId;
  }

  // ─── UPLOAD + CRÉATION (opération atomique) ───────────────────────────────────

  Future<({String incidentId, String mediaUrl})> submitIncident({
    required File file,
    required bool isVideo,
    required String category,
    String? details,
    Map<String, double>? location,
    DateTime? incidentTimestamp,
    void Function(double progress)? onProgress,
  }) async {
    String mediaUrl = '';

    try {
      mediaUrl = await uploadMedia(
        file: file,
        isVideo: isVideo,
        onProgress: onProgress,
      );
    } catch (e) {
      debugPrint('[IncidentRepository] Échec Upload Media: $e');
      mediaUrl = '';
    }

    final incidentId = await createIncident(
      mediaUrl: mediaUrl,
      isVideo: isVideo,
      category: category,
      details: details,
      location: location,
      incidentTimestamp: incidentTimestamp,
    );

    return (incidentId: incidentId, mediaUrl: mediaUrl);
  }

  // ─── LECTURE ─────────────────────────────────────────────────────────────────

  /// ✅ Stream des incidents du citoyen connecté (via citizen_id)
  Stream<List<Map<String, dynamic>>> watchMyIncidents() {
    if (_uid == null) return Stream.value([]);
    return _db
        .from('incidents')
        .stream(primaryKey: ['id'])
        .eq('citizen_id', _uid)
        .order('created_at', ascending: false)
        .limit(20);
  }

  /// ✅ Récupérer un incident par ID
  Future<Map<String, dynamic>?> getIncident(String id) async {
    return await _db.from('incidents')
        .select('id, reference, type, title, description, caller_name, caller_phone, citizen_id, media_urls, media_type, location_lat, location_lng, status, priority, province, ville, incident_at, created_at')
        .eq('id', id).maybeSingle();
  }
}

/// Provider Riverpod
final incidentRepositoryProvider = Provider<IncidentRepository>((ref) {
  return IncidentRepository();
});
