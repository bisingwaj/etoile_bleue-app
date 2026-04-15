import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provider that fetches recent incoming missed calls (centrale / rescuer → citoyen)
/// for **all** citizens — flux global. Le rappel n’est possible que pour les lignes
/// dont [citizen_id] est l’utilisateur connecté (voir UI).
///
/// Nécessite une politique RLS Supabase autorisant la lecture des lignes `call_history`
/// correspondantes pour les utilisateurs authentifiés (selon votre modèle de sécurité).
class MissedCallsNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  final String? _uid;

  MissedCallsNotifier(this._uid) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    if (_uid == null) {
      state = const AsyncValue.data([]);
      return;
    }
    try {
      final data = await Supabase.instance.client
          .from('call_history')
          .select()
          .inFilter('status', ['missed', 'completed', 'failed'])
          .order('created_at', ascending: false)
          .limit(100);

      final items = (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((call) {
            final channelName = call['channel_name'] as String? ?? '';
            return channelName.startsWith('CENTRALE-') ||
                channelName.startsWith('RESCUER-');
          })
          .toList();

      state = AsyncValue.data(items);
    } catch (e, st) {
      debugPrint('[MissedCalls] Error loading: $e');
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    await _load();
  }
}

final missedCallsProvider =
    StateNotifierProvider<MissedCallsNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  return MissedCallsNotifier(uid);
});
