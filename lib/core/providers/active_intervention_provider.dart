import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// État de l'intervention active côté citoyen.
class ActiveInterventionState {
  final String? incidentId;
  final String dispatchStatus; // 'processing', 'dispatched', 'en_route', 'arrived', 'completed'
  final String? rescuerName;

  const ActiveInterventionState({
    this.incidentId,
    this.dispatchStatus = 'processing',
    this.rescuerName,
  });

  /// Visible tant que l'équipe n'est pas sur place (arrived) ou terminé.
  bool get isVisible =>
      incidentId != null &&
      dispatchStatus != 'arrived' &&
      dispatchStatus != 'completed';

  ActiveInterventionState copyWith({
    String? incidentId,
    String? dispatchStatus,
    String? rescuerName,
    bool clearIncident = false,
  }) {
    return ActiveInterventionState(
      incidentId: clearIncident ? null : (incidentId ?? this.incidentId),
      dispatchStatus: dispatchStatus ?? this.dispatchStatus,
      rescuerName: rescuerName ?? this.rescuerName,
    );
  }
}

class ActiveInterventionNotifier extends StateNotifier<ActiveInterventionState> {
  RealtimeChannel? _dispatchChannel;

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

      // Chercher le dernier incident actif du citoyen (non terminé)
      final incident = await Supabase.instance.client
          .from('incidents')
          .select('id, status')
          .eq('citizen_id', user.id)
          .inFilter('status', ['new', 'pending', 'dispatched', 'en_route'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (incident != null) {
        final incidentId = incident['id'] as String;
        final incidentStatus = incident['status'] as String;
        debugPrint('[Intervention] Found active incident: $incidentId with status: $incidentStatus');
        startTracking(incidentId);
      } else {
        debugPrint('[Intervention] No active incident found in database');
      }
    } catch (e) {
      debugPrint('[Intervention] Check active intervention failed: $e');
    }
  }

  /// Démarre le suivi d'une intervention.
  void startTracking(String incidentId) {
    if (state.incidentId == incidentId) return;
    _dispatchChannel?.unsubscribe();

    debugPrint('[Intervention] Début du suivi pour incident=$incidentId');
    state = ActiveInterventionState(incidentId: incidentId);

    // Vérifier s'il y a déjà un dispatch existant
    _fetchInitialStatus(incidentId);

    // S'abonner aux changements en temps réel
    _dispatchChannel = Supabase.instance.client
        .channel('intervention-$incidentId-${DateTime.now().millisecondsSinceEpoch}')
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
          },
        )
        .subscribe();
  }

  Future<void> _fetchInitialStatus(String incidentId) async {
    try {
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
        debugPrint('[Intervention] Initial dispatch status: $status');
        state = state.copyWith(
          dispatchStatus: status,
          rescuerName: rescuerName,
        );
      }
    } catch (e) {
      debugPrint('[Intervention] Erreur fetch initial status: $e');
    }
  }

  void stopTracking() {
    _dispatchChannel?.unsubscribe();
    _dispatchChannel = null;
    state = const ActiveInterventionState();
  }

  @override
  void dispose() {
    _dispatchChannel?.unsubscribe();
    super.dispose();
  }
}

final activeInterventionProvider =
    StateNotifierProvider<ActiveInterventionNotifier, ActiveInterventionState>(
  (ref) => ActiveInterventionNotifier(),
);
