import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/providers/user_provider.dart';
import 'package:etoile_bleue_mobile/core/services/cache_service.dart';

final notificationsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final userAsync = ref.watch(userProvider.select((s) => s.valueOrNull?['auth_user_id']));

  if (userAsync == null) {
    return Stream.value([]);
  }

  final userId = userAsync as String;
  final supabase = Supabase.instance.client;
  final controller = StreamController<List<Map<String, dynamic>>>();
  final items = <String, Map<String, dynamic>>{};

  Future<void> fetchInitial() async {
    // Serve cache first
    final cached = CacheService.getCachedNotifications();
    if (cached != null && cached.isNotEmpty) {
      for (final row in cached) {
        items[row['id'] as String] = row;
      }
      controller.add(cached);
    }

    try {
      final data = await supabase
          .from('notifications')
          .select('id, user_id, title, body, type, is_read, reference_id, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(100);
      items.clear();
      for (final row in data) {
        items[row['id'] as String] = Map<String, dynamic>.from(row);
      }
      final list = items.values.toList();
      controller.add(list);
      CacheService.cacheNotifications(list);
    } catch (e) {
      if (cached == null || cached.isEmpty) controller.addError(e);
      debugPrint('[Notifications] Network error, serving cache: $e');
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
          CacheService.cacheNotifications(sorted);
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
