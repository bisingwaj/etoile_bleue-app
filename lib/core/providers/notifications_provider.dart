import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/providers/user_provider.dart';

final notificationsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final userAsync = ref.watch(userProvider);

  if (userAsync.value == null) {
    return Stream.value([]);
  }

  final userId = userAsync.value!['auth_user_id'];
  if (userId == null) return Stream.value([]);

  final supabase = Supabase.instance.client;
  final controller = StreamController<List<Map<String, dynamic>>>();
  final items = <String, Map<String, dynamic>>{};

  Future<void> fetchInitial() async {
    try {
      final data = await supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(100);
      items.clear();
      for (final row in data) {
        items[row['id'] as String] = Map<String, dynamic>.from(row);
      }
      controller.add(items.values.toList());
    } catch (e) {
      controller.addError(e);
    }
  }

  fetchInitial();

  final channel = supabase
      .channel('notif-$userId-${DateTime.now().millisecondsSinceEpoch}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (payload) {
          final record = payload.newRecord;
          if (record.isNotEmpty) {
            final id = record['id'] as String?;
            if (id != null) {
              items[id] = Map<String, dynamic>.from(record);
            }
          } else if (payload.oldRecord.isNotEmpty) {
            final id = payload.oldRecord['id'] as String?;
            if (id != null) items.remove(id);
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

final unreadNotificationsCountProvider = Provider<int>((ref) {
  final notificationsAsync = ref.watch(notificationsProvider);

  return notificationsAsync.maybeWhen(
    data: (notifications) => notifications.where((n) => n['is_read'] != true).length,
    orElse: () => 0,
  );
});
