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
  'at_hospital',
  'transferring',
  'handover',
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
    'on_site',
    'on_side',
    'arrived',
  }.contains(status);
}

/// État de l'intervention active côté citoyen.
class ActiveInterventionState {
  final String? incidentId;
  /// Dernière valeur connue de [incidents.status] (temps réel + fetch).
  final String? incidentStatus;
  /// Si l'admin a renseigné une date de clôture (même sans `status` à jour).
  final DateTime? incidentArchivedAt;
  final DateTime? incidentResolvedAt;
  final String dispatchStatus; // 'processing', 'dispatched', 'en_route', …
  final String? rescuerName;
  final String? rescuerId;
  final String? unitId;
  final double? rescuerLat;
  final double? rescuerLng;

  // ── Tracking enrichi (données active_rescuers) ──
  final double? rescuerHeading;   // Cap en degrés 0-360
  final double? rescuerSpeed;     // Vitesse en m/s
  final double? rescuerAccuracy;  // Précision GPS en mètres
  final int? rescuerBattery;      // Batterie 0-100
  final String? rescuerGpsStatus; // 'active' / 'idle' / 'offline'
  final DateTime? rescuerUpdatedAt; // Dernier update reçu

  const ActiveInterventionState({
    this.incidentId,
    this.incidentStatus,
    this.incidentArchivedAt,
    this.incidentResolvedAt,
    this.dispatchStatus = 'processing',
    this.rescuerName,
    this.rescuerId,
    this.unitId,
    this.rescuerLat,
    this.rescuerLng,
    this.rescuerHeading,
    this.rescuerSpeed,
    this.rescuerAccuracy,
    this.rescuerBattery,
    this.rescuerGpsStatus,
    this.rescuerUpdatedAt,
  });

  // ── Getters d'état dégradé ──

  /// Position périmée (> 5 minutes sans mise à jour).
  bool get isRescuerStale {
    if (rescuerUpdatedAt == null) return false;
    return DateTime.now().toUtc().difference(rescuerUpdatedAt!.toUtc()).inMinutes >= 5;
  }

  /// Secouriste explicitement offline.
  bool get isRescuerOffline => rescuerGpsStatus == 'offline';

  /// Batterie faible (< 20%).
  bool get isLowBattery => rescuerBattery != null && rescuerBattery! < 20;

  /// Le marker doit être affiché en mode dégradé (grisé).
  bool get isRescuerDegraded => isRescuerStale || isRescuerOffline;

  /// Visible seulement si le statut incident est explicitement « en cours » (liste blanche).
  /// Évite d'afficher une alerte pour un dossier déjà archivé / clos / inconnu.
  bool get isVisible {
    if (incidentId == null) return false;
    if (incidentArchivedAt != null || incidentResolvedAt != null) return false;
    if (!_isActiveIncidentForBanner(incidentStatus)) return false;
    if (_isTerminalDispatchStatus(dispatchStatus)) return false;
    
    // Le tracking (et la bannière) ne commence QUE si l'urgentiste a accepté la mission.
    // 'processing' signifie que l'appel est en cours de traitement mais pas encore accepté.
    return dispatchStatus == 'dispatched' ||
        dispatchStatus == 'en_route' ||
        dispatchStatus == 'en_route_hospital' ||
        dispatchStatus == 'arrived_hospital' ||
        dispatchStatus == 'transferring' ||
        dispatchStatus == 'at_hospital';
  }

  bool get shouldShowRescuer {
    if (!isVisible) return false;
    // Le tracking sur la carte ne commence QUE quand le véhicule est "en route" (icône ambulance qui part).
    return dispatchStatus == 'en_route' ||
        dispatchStatus == 'en_route_hospital' ||
        dispatchStatus == 'transferring' ||
        dispatchStatus == 'at_hospital';
  }

  ActiveInterventionState copyWith({
    String? incidentId,
    String? incidentStatus,
    DateTime? incidentArchivedAt,
    DateTime? incidentResolvedAt,
    String? dispatchStatus,
    String? rescuerName,
    String? rescuerId,
    String? unitId,
    double? rescuerLat,
    double? rescuerLng,
    double? rescuerHeading,
    double? rescuerSpeed,
    double? rescuerAccuracy,
    int? rescuerBattery,
    String? rescuerGpsStatus,
    DateTime? rescuerUpdatedAt,
    bool clearIncident = false,
    bool clearIncidentStatus = false,
    bool clearClosureDates = false,
    bool clearRescuer = false,
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
      rescuerName: clearRescuer ? null : (rescuerName ?? this.rescuerName),
      rescuerId: clearRescuer ? null : (rescuerId ?? this.rescuerId),
      unitId: clearRescuer ? null : (unitId ?? this.unitId),
      rescuerLat: clearRescuer ? null : (rescuerLat ?? this.rescuerLat),
      rescuerLng: clearRescuer ? null : (rescuerLng ?? this.rescuerLng),
      rescuerHeading: clearRescuer ? null : (rescuerHeading ?? this.rescuerHeading),
      rescuerSpeed: clearRescuer ? null : (rescuerSpeed ?? this.rescuerSpeed),
      rescuerAccuracy: clearRescuer ? null : (rescuerAccuracy ?? this.rescuerAccuracy),
      rescuerBattery: clearRescuer ? null : (rescuerBattery ?? this.rescuerBattery),
      rescuerGpsStatus: clearRescuer ? null : (rescuerGpsStatus ?? this.rescuerGpsStatus),
      rescuerUpdatedAt: clearRescuer ? null : (rescuerUpdatedAt ?? this.rescuerUpdatedAt),
    );
  }
}

class ActiveInterventionNotifier extends StateNotifier<ActiveInterventionState> {
  RealtimeChannel? _dispatchChannel;
  RealtimeChannel? _incidentChannel;
  RealtimeChannel? _rescuerGpsChannel;

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

      // On récupère les incidents récents AVEC leur dispatch associé pour éviter le flash
      final rows = await Supabase.instance.client
          .from('incidents')
          .select('id, status, archived_at, resolved_at, dispatches(status, created_at)')
          .eq('citizen_id', user.id)
          .order('created_at', ascending: false)
          .limit(10);

      Map<String, dynamic>? picked;
      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        final st = map['status'] as String?;
        
        // Si clos par date, on ignore
        if (_isIncidentClosedByDates(map['archived_at'], map['resolved_at'])) {
          continue;
        }

        // Si le statut incident n'est pas "actif" pour la bannière, on ignore
        if (!_isActiveIncidentForBanner(st)) {
          continue;
        }

        // Vérifier le dispatch associé s'il existe
        final dispatchesList = map['dispatches'] as List?;
        if (dispatchesList != null && dispatchesList.isNotEmpty) {
          // Trier pour prendre le plus récent
          final sorted = List<Map<String, dynamic>>.from(dispatchesList);
          sorted.sort((a, b) {
            final da = a['created_at'] as String? ?? '';
            final db = b['created_at'] as String? ?? '';
            return db.compareTo(da);
          });
          
          final dStatus = sorted.first['status'] as String?;
          if (dStatus != null && _isTerminalDispatchStatus(dStatus)) {
            // Si le dispatch est déjà terminé/arrivé, on ne le "pick" pas comme actif
            continue;
          }
        }

        picked = map;
        break;
      }

      if (picked != null) {
        final incidentId = picked['id'] as String;
        debugPrint('[Intervention] Found active incident: $incidentId');
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
    _rescuerGpsChannel?.unsubscribe();

    debugPrint('[Intervention] Début du suivi pour incident=$incidentId');
    state = ActiveInterventionState(incidentId: incidentId);

    unawaited(_fetchIncidentAndDispatch(incidentId));
    _subscribeDispatchRealtime(incidentId);
    _subscribeIncidentRealtime(incidentId);
  }

  Future<void> _fetchIncidentAndDispatch(String incidentId) async {
    try {
      // 1. Fetch incident and dispatch in parallel for speed and to avoid state jumps
      final results = await Future.wait([
        Supabase.instance.client
            .from('incidents')
            .select('status, archived_at, resolved_at')
            .eq('id', incidentId)
            .maybeSingle(),
        Supabase.instance.client
            .from('dispatches')
            .select('status, rescuer_id, unit_id')
            .eq('incident_id', incidentId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle(),
      ]);

      final incident = results[0];
      final dispatch = results[1];

      final incStatus = incident?['status'] as String?;
      final archAt = _parseTimestamp(incident?['archived_at']);
      final resAt = _parseTimestamp(incident?['resolved_at']);

      debugPrint(
        '[Intervention] Sync incident status: $incStatus archived_at=$archAt resolved_at=$resAt',
      );

      // Validation finale de l'éligibilité à la bannière
      if (_isIncidentClosedByDates(incident?['archived_at'], incident?['resolved_at']) ||
          !_isActiveIncidentForBanner(incStatus)) {
        stopTracking();
        return;
      }

      String dStatus = 'processing';
      String? rescuerId;
      String? unitId;

      if (dispatch != null) {
        dStatus = dispatch['status'] as String? ?? 'processing';
        rescuerId = dispatch['rescuer_id'] as String?;
        unitId = dispatch['unit_id'] as String?;
        debugPrint('[Intervention] Sync dispatch: status=$dStatus, rescuerId=$rescuerId, unitId=$unitId');
      }

      // Si le dispatch est déjà arrivé/terminé, on ne doit pas afficher la bannière
      if (_isTerminalDispatchStatus(dStatus)) {
        debugPrint('[Intervention] Dispatch is terminal ($dStatus), stopping tracking');
        stopTracking();
        return;
      }

      // Mise à jour de l'état EN UNE SEULE FOIS pour éviter les flashs d'UI
      state = state.copyWith(
        incidentId: incidentId,
        incidentStatus: incStatus,
        incidentArchivedAt: archAt,
        incidentResolvedAt: resAt,
        dispatchStatus: dStatus,
        rescuerId: rescuerId,
        unitId: unitId,
      );

      // 3. Fetch rescuer/unit detail if we have an ID
      if (rescuerId != null) {
        _subscribeRescuerGpsRealtime(rescuerId);
        final pos = await Supabase.instance.client
            .from('active_rescuers')
            .select('lat, lng, heading, speed, accuracy, battery, status, updated_at')
            .eq('user_id', rescuerId)
            .maybeSingle();
        if (pos != null) {
          final lat = (pos['lat'] as num?)?.toDouble();
          final lng = (pos['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            state = state.copyWith(
              rescuerLat: lat,
              rescuerLng: lng,
              rescuerHeading: (pos['heading'] as num?)?.toDouble(),
              rescuerSpeed: (pos['speed'] as num?)?.toDouble(),
              rescuerAccuracy: (pos['accuracy'] as num?)?.toDouble(),
              rescuerBattery: (pos['battery'] as num?)?.toInt(),
              rescuerGpsStatus: pos['status'] as String?,
              rescuerUpdatedAt: _parseTimestamp(pos['updated_at']),
            );
          }
        }
      } else if (unitId != null) {
        _subscribeUnitGpsRealtime(unitId);
        final pos = await Supabase.instance.client
            .from('units')
            .select('location_lat, location_lng')
            .eq('id', unitId)
            .maybeSingle();
        if (pos != null) {
          final lat = (pos['location_lat'] as num?)?.toDouble();
          final lng = (pos['location_lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            state = state.copyWith(rescuerLat: lat, rescuerLng: lng);
          }
        }
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
            final rescuerId = dispatch['rescuer_id'] as String?;
            final unitId = dispatch['unit_id'] as String?;
            
            debugPrint('[Intervention] Dispatch update (realtime): status=$status, rescuerId=$rescuerId, unitId=$unitId');

            if (status != null) {
              state = state.copyWith(
                dispatchStatus: status,
                rescuerName: null,
                rescuerId: rescuerId,
                unitId: unitId,
              );
              if (rescuerId != null) {
                _subscribeRescuerGpsRealtime(rescuerId);
              } else if (unitId != null) {
                _subscribeUnitGpsRealtime(unitId);
              }
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

  void _subscribeRescuerGpsRealtime(String rescuerId) {
    if (_rescuerGpsChannel != null && _rescuerGpsChannel?.topic == 'rescuer-gps-$rescuerId') {
      return; // Already subscribed
    }
    _rescuerGpsChannel?.unsubscribe();

    debugPrint('[Intervention] Subscribing to rescuer GPS: $rescuerId');
    _rescuerGpsChannel = Supabase.instance.client
        .channel('rescuer-gps-$rescuerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'active_rescuers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: rescuerId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record.isNotEmpty) {
              final lat = (record['lat'] as num?)?.toDouble();
              final lng = (record['lng'] as num?)?.toDouble();
              debugPrint('[TRACKING_DEBUG] Rescuer position received: lat=$lat, lng=$lng, heading=${record['heading']}, speed=${record['speed']}');
              if (lat != null && lng != null) {
                state = state.copyWith(
                  rescuerLat: lat,
                  rescuerLng: lng,
                  rescuerHeading: (record['heading'] as num?)?.toDouble(),
                  rescuerSpeed: (record['speed'] as num?)?.toDouble(),
                  rescuerAccuracy: (record['accuracy'] as num?)?.toDouble(),
                  rescuerBattery: (record['battery'] as num?)?.toInt(),
                  rescuerGpsStatus: record['status'] as String?,
                  rescuerUpdatedAt: _parseTimestamp(record['updated_at']),
                );
              }
            }
          },
        )
        .subscribe();
  }

  void _subscribeUnitGpsRealtime(String unitId) {
    if (_rescuerGpsChannel != null && _rescuerGpsChannel?.topic == 'unit-gps-$unitId') {
      return; // Already subscribed
    }
    _rescuerGpsChannel?.unsubscribe();

    debugPrint('[Intervention] Fallback: Subscribing to unit GPS: $unitId');
    _rescuerGpsChannel = Supabase.instance.client
        .channel('unit-gps-$unitId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'units',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: unitId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record.isNotEmpty) {
              final lat = (record['location_lat'] as num?)?.toDouble();
              final lng = (record['location_lng'] as num?)?.toDouble();
              debugPrint('[TRACKING_DEBUG] Unit position received: lat=$lat, lng=$lng');
              if (lat != null && lng != null) {
                state = state.copyWith(
                  rescuerLat: lat,
                  rescuerLng: lng,
                );
              }
            }
          },
        )
        .subscribe();
  }

  void stopTracking() {
    debugPrint('[Intervention] stopTracking() called - clearing state and unsubscribing');
    _dispatchChannel?.unsubscribe();
    _dispatchChannel = null;
    _incidentChannel?.unsubscribe();
    _incidentChannel = null;
    _rescuerGpsChannel?.unsubscribe();
    _rescuerGpsChannel = null;
    state = const ActiveInterventionState();
  }

  @override
  void dispose() {
    _dispatchChannel?.unsubscribe();
    _incidentChannel?.unsubscribe();
    _rescuerGpsChannel?.unsubscribe();
    super.dispose();
  }
}

final activeInterventionProvider =
    StateNotifierProvider<ActiveInterventionNotifier, ActiveInterventionState>(
  (ref) => ActiveInterventionNotifier(),
);
