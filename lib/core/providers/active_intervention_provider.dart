import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Normalise le statut renvoyé par Postgres / le backend (casse, espaces, variantes).
String? _normalizeIncidentStatus(String? status) {
  if (status == null) return null;
  final s = status.trim().toLowerCase();
  if (s.isEmpty) return null;
  // Variantes observées côté prod / exports
  if (s == 'archive' || s.startsWith('archiv')) return 'archived';
  return s;
}

/// Seuls ces statuts `incidents.status` autorisent la bannière d’alerte citoyen.
/// Tout le reste (dont `archived`, `resolved`, `ended`, inconnu) → pas de popup.
const Set<String> _activeIncidentStatusesForBanner = {
  'new',
  'pending',
  'dispatched',
  'in_progress',
  'en_route',
  'arrived',
  'investigating',
  'en_route_hospital',
  'arrived_hospital',
};

bool _isActiveIncidentForBanner(String? status) {
  final n = _normalizeIncidentStatus(status);
  if (n == null) return false;
  return _activeIncidentStatusesForBanner.contains(n);
}

DateTime? _parseTimestamp(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

/// Clôture admin souvent portée par les dates même si `status` reste ambigu.
bool _isIncidentClosedByDates(dynamic archivedAt, dynamic resolvedAt) {
  return _parseTimestamp(archivedAt) != null || _parseTimestamp(resolvedAt) != null;
}

/// Phases dispatch terminées (mission close côté terrain).
bool _isTerminalDispatchStatus(String status) {
  return const {
    'completed',
    'cancelled',
    'returned',
  }.contains(status);
}

/// État de l'intervention active côté citoyen.
class ActiveInterventionState {
  final String? incidentId;
  /// Dernière valeur connue de [incidents.status] (temps réel + fetch).
  final String? incidentStatus;
  /// Si l’admin a renseigné une date de clôture (même sans `status` à jour).
  final DateTime? incidentArchivedAt;
  final DateTime? incidentResolvedAt;
  final String dispatchStatus; // 'processing', 'dispatched', 'en_route', …
  final String? rescuerName;

  const ActiveInterventionState({
    this.incidentId,
    this.incidentStatus,
    this.incidentArchivedAt,
    this.incidentResolvedAt,
    this.dispatchStatus = 'processing',
    this.rescuerName,
  });

  /// Visible seulement si le statut incident est explicitement « en cours » (liste blanche).
  /// Évite d’afficher une alerte pour un dossier déjà archivé / clos / inconnu.
  bool get isVisible {
    if (incidentId == null) return false;
    if (incidentArchivedAt != null || incidentResolvedAt != null) return false;
    if (!_isActiveIncidentForBanner(incidentStatus)) return false;
    if (_isTerminalDispatchStatus(dispatchStatus)) return false;
    return dispatchStatus == 'processing' ||
        dispatchStatus == 'dispatched' ||
        dispatchStatus == 'en_route' ||
        dispatchStatus == 'arrived';
  }

  ActiveInterventionState copyWith({
    String? incidentId,
    String? incidentStatus,
    DateTime? incidentArchivedAt,
    DateTime? incidentResolvedAt,
    String? dispatchStatus,
    String? rescuerName,
    bool clearIncident = false,
    bool clearIncidentStatus = false,
    bool clearClosureDates = false,
  }) {
    return ActiveInterventionState(
      incidentId: clearIncident ? null : (incidentId ?? this.incidentId),
      incidentStatus:
          clearIncident || clearIncidentStatus ? null : (incidentStatus ?? this.incidentStatus),
      incidentArchivedAt: clearIncident || clearClosureDates
          ? null
          : (incidentArchivedAt ?? this.incidentArchivedAt),
      incidentResolvedAt: clearIncident || clearClosureDates
          ? null
          : (incidentResolvedAt ?? this.incidentResolvedAt),
      dispatchStatus: dispatchStatus ?? this.dispatchStatus,
      rescuerName: rescuerName ?? this.rescuerName,
    );
  }
}

class ActiveInterventionNotifier extends StateNotifier<ActiveInterventionState> {
  RealtimeChannel? _dispatchChannel;
  RealtimeChannel? _incidentChannel;

  ActiveInterventionNotifier() : super(const ActiveInterventionState()) {
    // Au démarrage, chercher automatiquement les interventions actives
    refreshInterventionTracking();
  }

  /// Vérifie s'il y a un incident actif pour le citoyen connecté.
  Future<void> refreshInterventionTracking() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        debugPrint('[Intervention] No user logged in, skipping check');
        return;
      }

      debugPrint('[Intervention] Checking for active incident for user: ${user.id}');

      // Plusieurs lignes récentes : le filtre SQL seul peut rater la casse / l’enum. On valide en Dart.
      final rows = await Supabase.instance.client
          .from('incidents')
          .select('id, status, archived_at, resolved_at')
          .eq('citizen_id', user.id)
          .order('created_at', ascending: false)
          .limit(25);

      Map<String, dynamic>? picked;
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final st = map['status'] as String?;
        if (_isIncidentClosedByDates(map['archived_at'], map['resolved_at'])) {
          continue;
        }
        if (_isActiveIncidentForBanner(st)) {
          picked = map;
          break;
        }
      }

      if (picked != null) {
        final incidentId = picked['id'] as String;
        final incidentStatus = picked['status'] as String;
        debugPrint('[Intervention] Found active incident: $incidentId with status: $incidentStatus');
        startTracking(incidentId);
      } else {
        debugPrint('[Intervention] No active incident found in database');
        if (state.incidentId != null) {
          stopTracking();
        }
      }
    } catch (e) {
      debugPrint('[Intervention] Check active intervention failed: $e');
    }
  }

  /// Démarre le suivi d'une intervention.
  void startTracking(String incidentId) {
    if (state.incidentId == incidentId) {
      unawaited(_fetchIncidentAndDispatch(incidentId));
      return;
    }

    _dispatchChannel?.unsubscribe();
    _incidentChannel?.unsubscribe();

    debugPrint('[Intervention] Début du suivi pour incident=$incidentId');
    state = ActiveInterventionState(incidentId: incidentId);

    unawaited(_fetchIncidentAndDispatch(incidentId));
    _subscribeDispatchRealtime(incidentId);
    _subscribeIncidentRealtime(incidentId);
  }

  Future<void> _fetchIncidentAndDispatch(String incidentId) async {
    try {
      final incident = await Supabase.instance.client
          .from('incidents')
          .select('status, archived_at, resolved_at')
          .eq('id', incidentId)
          .maybeSingle();

      final incStatus = incident?['status'] as String?;
      final archAt = _parseTimestamp(incident?['archived_at']);
      final resAt = _parseTimestamp(incident?['resolved_at']);
      debugPrint(
        '[Intervention] Sync incident status: $incStatus archived_at=$archAt resolved_at=$resAt',
      );
      if (_isIncidentClosedByDates(incident?['archived_at'], incident?['resolved_at']) ||
          !_isActiveIncidentForBanner(incStatus)) {
        stopTracking();
        return;
      }
      state = ActiveInterventionState(
        incidentId: incidentId,
        incidentStatus: incStatus,
        incidentArchivedAt: archAt,
        incidentResolvedAt: resAt,
        dispatchStatus: state.dispatchStatus,
        rescuerName: state.rescuerName,
      );

      final dispatches = await Supabase.instance.client
          .from('dispatches')
          .select('status, rescuer_name')
          .eq('incident_id', incidentId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (dispatches != null) {
        final status = dispatches['status'] as String? ?? 'processing';
        final rescuerName = dispatches['rescuer_name'] as String?;
        debugPrint('[Intervention] Sync dispatch status: $status');
        state = state.copyWith(
          dispatchStatus: status,
          rescuerName: rescuerName,
        );
      }
    } catch (e) {
      debugPrint('[Intervention] Erreur fetch incident/dispatch: $e');
    }
  }

  void _subscribeDispatchRealtime(String incidentId) {
    _dispatchChannel = Supabase.instance.client
        .channel('dispatch-$incidentId-${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'dispatches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'incident_id',
            value: incidentId,
          ),
          callback: (payload) {
            final dispatch = payload.newRecord;
            final status = dispatch['status'] as String?;
            final rescuerName = dispatch['rescuer_name'] as String?;
            if (status != null) {
              debugPrint('[Intervention] Dispatch status update: $status');
              state = state.copyWith(
                dispatchStatus: status,
                rescuerName: rescuerName,
              );
            }
            unawaited(_fetchIncidentAndDispatch(incidentId));
          },
        )
        .subscribe();
  }

  void _subscribeIncidentRealtime(String incidentId) {
    _incidentChannel = Supabase.instance.client
        .channel('incident-$incidentId-${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'incidents',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: incidentId,
          ),
          callback: (payload) {
            debugPrint('[Intervention] Incident row updated (realtime), re-sync');
            unawaited(_fetchIncidentAndDispatch(incidentId));
          },
        )
        .subscribe();
  }

  void stopTracking() {
    _dispatchChannel?.unsubscribe();
    _dispatchChannel = null;
    _incidentChannel?.unsubscribe();
    _incidentChannel = null;
    state = const ActiveInterventionState();
  }

  @override
  void dispose() {
    _dispatchChannel?.unsubscribe();
    _incidentChannel?.unsubscribe();
    super.dispose();
  }
}

final activeInterventionProvider =
    StateNotifierProvider<ActiveInterventionNotifier, ActiveInterventionState>(
  (ref) => ActiveInterventionNotifier(),
);
