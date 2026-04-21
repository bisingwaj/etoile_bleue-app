import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/patient_timeline_models.dart';

class PatientTimelineRepository {
  final SupabaseClient _db;

  PatientTimelineRepository({SupabaseClient? db}) : _db = db ?? Supabase.instance.client;

  /// Appelle l’Edge Function `get-patient-timeline` (JWT session requis).
  Future<PatientTimelineResponse?> fetchTimeline(String incidentId) async {
    try {
      final res = await _db.functions.invoke(
        'get-patient-timeline',
        body: {'incident_id': incidentId},
      );

      if (res.status != 200) {
        debugPrint('[PatientTimeline] HTTP ${res.status}: ${res.data}');
        return null;
      }

      final data = res.data;
      if (data is! Map) {
        debugPrint('[PatientTimeline] unexpected body: $data');
        return null;
      }

      return PatientTimelineResponse.fromJson(Map<String, dynamic>.from(data));
    } catch (e, st) {
      debugPrint('[PatientTimeline] fetchTimeline error: $e\n$st');
      return null;
    }
  }
}

final patientTimelineRepositoryProvider = Provider<PatientTimelineRepository>((ref) {
  return PatientTimelineRepository();
});
