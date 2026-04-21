import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/patient_timeline_repository.dart';
import '../models/patient_timeline_models.dart';

/// Timeline complète patient (centrale / terrain / hôpital) pour un incident.
final patientTimelineProvider =
    FutureProvider.family<PatientTimelineResponse?, String>((ref, incidentId) async {
  final repo = ref.watch(patientTimelineRepositoryProvider);
  return repo.fetchTimeline(incidentId);
});
