import 'dart:math' show cos, pi;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Récupération paginée de toutes les structures ouvertes, puis tri par proximité côté client
/// (voir [PATIENT_APP_STRUCTURES_PROXIMITY.md]). Le filtre rayon km ne modifie pas cette requête.
class HealthStructuresRepository {
  HealthStructuresRepository({SupabaseClient? client})
      : _db = client ?? Supabase.instance.client;

  final SupabaseClient _db;

  static const int _pageSize = 1000;

  /// Colonnes nécessaires à l’affichage annuaire.
  static const String _select =
      'id, name, official_name, type, address, phone, lat, lng, specialties, linked_user_id, is_open';

  /// Récupère toutes les lignes `is_open = true` par pagination (évite la limite 1000 de Supabase).
  Future<List<Map<String, dynamic>>> fetchAllOpenStructures() async {
    final all = <Map<String, dynamic>>[];
    var from = 0;
    while (true) {
      final response = await _db
          .from('health_structures')
          .select(_select)
          .eq('is_open', true)
          .range(from, from + _pageSize - 1);

      final batch = List<Map<String, dynamic>>.from(response);
      if (batch.isEmpty) break;
      all.addAll(batch);
      if (batch.length < _pageSize) break;
      from += _pageSize;
    }
    return all;
  }

  /// Tri par distance approximative (même logique que le doc : coordonnées nulles en dernier).
  void sortByProximity(
    List<Map<String, dynamic>> rows, {
    required double userLat,
    required double userLng,
  }) {
    rows.sort((a, b) {
      final la = _parseDouble(a['lat']);
      final lnA = _parseDouble(a['lng']);
      final lb = _parseDouble(b['lat']);
      final lnB = _parseDouble(b['lng']);

      final hasA = la != null && lnA != null;
      final hasB = lb != null && lnB != null;
      if (hasA && !hasB) return -1;
      if (!hasA && hasB) return 1;
      if (!hasA && !hasB) {
        final na = '${a['name'] ?? ''}';
        final nb = '${b['name'] ?? ''}';
        return na.compareTo(nb);
      }

      final distA = _distanceSquared(userLat, userLng, la!, lnA!);
      final distB = _distanceSquared(userLat, userLng, lb!, lnB!);
      return distA.compareTo(distB);
    });
  }

  static double _distanceSquared(double lat1, double lng1, double lat2, double lng2) {
    final dLat = lat2 - lat1;
    final dLng = (lng2 - lng1) * cos(lat1 * pi / 180);
    return dLat * dLat + dLng * dLng;
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
