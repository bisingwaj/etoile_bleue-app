import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/signalement_models.dart';

class SignalementRepository {
  final SupabaseClient _db;

  SignalementRepository({SupabaseClient? db})
      : _db = db ?? Supabase.instance.client;

  /// Même bucket que les médias SOS ; les fichiers signalement utilisent le préfixe
  /// de chemin `signalements/{signalement_id}/...` (voir SIGNALEMENTS_MOBILE_GUIDE.md).
  static const String _storageBucketSignalementMedia = 'incidents';

  String? get _uid => _db.auth.currentUser?.id;

  // ─── REFERENCE ──────────────────────────────────────────────────────────────

  String generateReference() {
    final now = DateTime.now();
    final date = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final rand = (now.millisecondsSinceEpoch % 100000).toString().padLeft(5, '0');
    return 'SIG-$date-$rand';
  }

  // ─── PROFIL CITOYEN ─────────────────────────────────────────────────────────

  Future<({String? name, String? phone})> getCitizenProfile() async {
    return _getCitizenProfile();
  }

  Future<({String? name, String? phone})> _getCitizenProfile() async {
    if (_uid == null) return (name: null, phone: null);
    try {
      final profile = await _db
          .from('users_directory')
          .select('first_name, last_name, phone')
          .eq('auth_user_id', _uid!)
          .maybeSingle();
      if (profile != null) {
        final name = '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'.trim();
        return (name: name.isNotEmpty ? name : null, phone: profile['phone'] as String?);
      }
    } catch (e) {
      debugPrint('[Signalement] Profil citoyen non trouvé: $e');
    }
    return (name: null, phone: null);
  }

  // ─── DEDUPLICATION ──────────────────────────────────────────────────────────

  Future<bool> isDuplicate(String title, {bool isAnonymous = false}) async {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 30)).toUtc().toIso8601String();
    try {
      var query = _db
          .from('signalements')
          .select('id')
          .eq('title', title)
          .gte('created_at', cutoff);

      if (!isAnonymous) {
        final profile = await _getCitizenProfile();
        if (profile.phone != null) {
          query = query.eq('citizen_phone', profile.phone!);
        }
      }

      final result = await query.limit(1);
      return (result as List).isNotEmpty;
    } catch (e) {
      debugPrint('[Signalement] Dedup check error: $e');
      return false;
    }
  }

  // ─── INSERT SIGNALEMENT ─────────────────────────────────────────────────────

  Future<String> createSignalement({
    required String title,
    required String category,
    required String description,
    required String province,
    required String ville,
    String? commune,
    double? lat,
    double? lng,
    String? structureName,
    String? structureId,
    String priority = 'moyenne',
    bool isAnonymous = false,
  }) async {
    if (_uid == null) throw Exception('Non authentifié');

    final profile = await _getCitizenProfile();

    final data = <String, dynamic>{
      'p_reference': generateReference(),
      'p_category': category,
      'p_title': title,
      'p_description': description,
      'p_citizen_name': isAnonymous ? null : profile.name,
      'p_citizen_phone': isAnonymous ? null : profile.phone,
      'p_is_anonymous': isAnonymous,
      'p_province': province,
      'p_ville': ville,
      'p_commune': commune,
      'p_lat': lat,
      'p_lng': lng,
      'p_structure_name': structureName,
      'p_structure_id': structureId,
      'p_priority': priority,
    };

    final response = await _db.rpc('create_signalement', params: data);
    
    // Si la RPC renvoie un Map, extraire l'id
    // S'il renvoie directement la chaine, parser.
    final id = response['id'] as String;
    debugPrint('[Signalement] Créé via RPC: $id (ref: ${response['reference']})');
    return id;
  }

  // ─── INSERT MEDIA ROW ───────────────────────────────────────────────────────

  Future<void> insertMediaRow({
    required String signalementId,
    required String type,
    required String url,
    String? thumbnail,
    int? duration,
    required String filename,
  }) async {
    await _db.from('signalement_media').insert({
      'signalement_id': signalementId,
      'type': type,
      'url': url,
      'thumbnail': thumbnail,
      'duration': duration,
      'filename': filename,
    });
    debugPrint('[Signalement] Média enregistré: $type ($filename)');
  }

  // ─── UPLOAD STORAGE ─────────────────────────────────────────────────────────

  Future<String> uploadBytes({
    required String storagePath,
    required Uint8List bytes,
    required String contentType,
    int maxRetries = 3,
  }) async {
    int attempt = 0;
    while (true) {
      try {
        await _db.storage.from(_storageBucketSignalementMedia).uploadBinary(
              storagePath,
              bytes,
              fileOptions: FileOptions(contentType: contentType, upsert: true),
            );
        final url = await _db.storage.from(_storageBucketSignalementMedia).createSignedUrl(storagePath, 604800);
        debugPrint('[Signalement] Upload OK: $storagePath');
        return url;
      } catch (e) {
        attempt++;
        if (attempt >= maxRetries) {
          debugPrint('[Signalement] Upload ECHEC après $maxRetries tentatives: $storagePath — $e');
          rethrow;
        }
        debugPrint('[Signalement] Upload retry $attempt/$maxRetries: $storagePath');
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
  }

  // ─── LIST PAGINATED ─────────────────────────────────────────────────────────

  Future<List<Signalement>> listMySignalements({String? cursor, int limit = 30}) async {
    if (_uid == null) return [];

    var filter = _db
        .from('signalements')
        .select('id, reference, category, title, is_anonymous, priority, status, commune, created_at, updated_at')
        .eq('submitted_by_auth_user_id', _uid!);

    if (cursor != null) {
      filter = filter.lt('created_at', cursor);
    }

    final rows = await filter
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).map((r) => Signalement.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  // ─── DETAIL ─────────────────────────────────────────────────────────────────

  Future<Signalement?> getSignalement(String id) async {
    final row = await _db.from('signalements')
        .select('id, reference, category, title, description, citizen_name, citizen_phone, is_anonymous, province, ville, commune, lat, lng, structure_name, structure_id, priority, status, assigned_to, created_at, updated_at')
        .eq('id', id).maybeSingle();
    if (row == null) return null;

    final mediaRows = await _db
        .from('signalement_media')
        .select('id, signalement_id, type, url, thumbnail, duration, filename, created_at')
        .eq('signalement_id', id)
        .order('created_at');
    final media = (mediaRows as List)
        .map((m) => SignalementMediaItem.fromMap(Map<String, dynamic>.from(m)))
        .toList();

    return Signalement.fromMap(Map<String, dynamic>.from(row), media: media);
  }

  // ─── SEARCH STRUCTURES ──────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> searchStructures(String query) async {
    if (query.length < 2) return [];
    try {
      final result = await _db
          .from('health_structures')
          .select('id, name, type, address, lat, lng')
          .ilike('name', '%$query%')
          .limit(20);
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      debugPrint('[Signalement] Recherche structures erreur: $e');
      return [];
    }
  }
}

final signalementRepositoryProvider = Provider<SignalementRepository>((ref) {
  return SignalementRepository();
});
