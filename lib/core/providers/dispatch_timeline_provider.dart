import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provider pour la chronologie des actions terrain (soins, constantes, etc.)
final dispatchTimelineProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, incidentId) {
  final supabase = Supabase.instance.client;
  final controller = StreamController<List<Map<String, dynamic>>>();
  final items = <String, Map<String, dynamic>>{};

  Future<void> fetchInitial() async {
    try {
      final data = await supabase
          .from('dispatch_timeline')
          .select()
          .eq('incident_id', incidentId)
          .order('created_at', ascending: false);
      
      items.clear();
      for (final row in data) {
        items[row['id'] as String] = Map<String, dynamic>.from(row);
      }
      controller.add(items.values.toList());
    } catch (e) {
      debugPrint('[Timeline] Fetch error: $e');
      // If table doesn't exist yet, we just return empty list to avoid crashes
      controller.add([]);
    }
  }

  fetchInitial();

  final channel = supabase
      .channel('timeline-$incidentId-${DateTime.now().millisecondsSinceEpoch}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'dispatch_timeline',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'incident_id',
          value: incidentId,
        ),
        callback: (payload) {
          final record = payload.newRecord;
          if (record.isNotEmpty) {
            final id = record['id'] as String?;
            if (id != null) {
              items[id] = Map<String, dynamic>.from(record);
            }
          }
          final sorted = items.values.toList()
            ..sort((a, b) => (b['created_at'] as String? ?? '').compareTo(a['created_at'] as String? ?? ''));
          controller.add(sorted);
        },
      )
      .subscribe();

  ref.onDispose(() {
    channel.unsubscribe();
    controller.close();
  });

  return controller.stream;
});
