// Modèles alignés sur l’Edge Function `get-patient-timeline` (voir PROMPT_CURSOR_PATIENT_FULL_TIMELINE.md).

class PatientTimelineIncident {
  final String id;
  final String? reference;
  final String? title;
  final String? type;
  final String? status;
  final String? priority;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  const PatientTimelineIncident({
    required this.id,
    this.reference,
    this.title,
    this.type,
    this.status,
    this.priority,
    this.createdAt,
    this.resolvedAt,
  });

  factory PatientTimelineIncident.fromJson(Map<String, dynamic> j) {
    return PatientTimelineIncident(
      id: j['id'] as String? ?? '',
      reference: j['reference'] as String?,
      title: j['title'] as String?,
      type: j['type'] as String?,
      status: j['status'] as String?,
      priority: j['priority'] as String?,
      createdAt: _parseDt(j['created_at']),
      resolvedAt: _parseDt(j['resolved_at']),
    );
  }

  static DateTime? _parseDt(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }
}

class TimelineEvent {
  final DateTime at;
  final String source;
  final String category;
  final String title;
  final String? description;
  final Map<String, dynamic> metadata;

  const TimelineEvent({
    required this.at,
    required this.source,
    required this.category,
    required this.title,
    this.description,
    this.metadata = const {},
  });

  factory TimelineEvent.fromJson(Map<String, dynamic> j) {
    final atStr = j['at']?.toString();
    return TimelineEvent(
      at: DateTime.tryParse(atStr ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      source: j['source'] as String? ?? 'systeme',
      category: j['category'] as String? ?? '',
      title: j['title'] as String? ?? '',
      description: j['description'] as String?,
      metadata: j['metadata'] is Map
          ? Map<String, dynamic>.from(j['metadata'] as Map)
          : <String, dynamic>{},
    );
  }

  bool get isHospital => source == 'hopital';
  bool get isField => source == 'terrain';
  bool get isCenter => source == 'centrale';

  Map<String, dynamic>? get vitalsFromMetadata {
    final v = metadata['vitals'];
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }
}

class PatientDispatchSummary {
  final String id;
  final String? status;
  final String? hospitalStatus;
  final String? structureName;
  final Map<String, dynamic>? hospitalData;

  const PatientDispatchSummary({
    required this.id,
    this.status,
    this.hospitalStatus,
    this.structureName,
    this.hospitalData,
  });

  factory PatientDispatchSummary.fromJson(Map<String, dynamic> j) {
    dynamic hd = j['hospital_data'];
    return PatientDispatchSummary(
      id: j['id'] as String? ?? '',
      status: j['status'] as String?,
      hospitalStatus: j['hospital_status'] as String?,
      structureName: j['structure_name'] as String?,
      hospitalData: hd is Map ? Map<String, dynamic>.from(hd) : null,
    );
  }
}

class HospitalReportSummary {
  final String id;
  final DateTime? sentAt;
  final String? summary;
  final Map<String, dynamic>? reportData;

  const HospitalReportSummary({
    required this.id,
    this.sentAt,
    this.summary,
    this.reportData,
  });

  factory HospitalReportSummary.fromJson(Map<String, dynamic> j) {
    dynamic rd = j['report_data'];
    return HospitalReportSummary(
      id: j['id'] as String? ?? '',
      sentAt: j['sent_at'] != null ? DateTime.tryParse(j['sent_at'].toString()) : null,
      summary: j['summary'] as String?,
      reportData: rd is Map ? Map<String, dynamic>.from(rd) : null,
    );
  }
}

class PatientTimelineResponse {
  final bool success;
  final PatientTimelineIncident? incident;
  final List<PatientDispatchSummary> dispatches;
  final List<TimelineEvent> events;
  final List<HospitalReportSummary> reports;

  const PatientTimelineResponse({
    required this.success,
    this.incident,
    this.dispatches = const [],
    this.events = const [],
    this.reports = const [],
  });

  factory PatientTimelineResponse.fromJson(Map<String, dynamic> j) {
    final disp = <PatientDispatchSummary>[];
    final rawD = j['dispatches'];
    if (rawD is List) {
      for (final e in rawD) {
        if (e is Map) disp.add(PatientDispatchSummary.fromJson(Map<String, dynamic>.from(e)));
      }
    }

    final evs = <TimelineEvent>[];
    final rawE = j['events'];
    if (rawE is List) {
      for (final e in rawE) {
        if (e is Map) evs.add(TimelineEvent.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    evs.sort((a, b) => a.at.compareTo(b.at));

    final reps = <HospitalReportSummary>[];
    final rawR = j['reports'];
    if (rawR is List) {
      for (final e in rawR) {
        if (e is Map) reps.add(HospitalReportSummary.fromJson(Map<String, dynamic>.from(e)));
      }
    }

    PatientTimelineIncident? inc;
    final rawI = j['incident'];
    if (rawI is Map) {
      inc = PatientTimelineIncident.fromJson(Map<String, dynamic>.from(rawI));
    }

    return PatientTimelineResponse(
      success: j['success'] == true,
      incident: inc,
      dispatches: disp,
      events: evs,
      reports: reps,
    );
  }
}
