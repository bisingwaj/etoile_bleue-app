import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/services/cache_service.dart';

/// Fetches user profile with cache-first strategy, then listens for Realtime UPDATE events.
final userProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return Stream.value(null);

  final supabase = Supabase.instance.client;
  final controller = StreamController<Map<String, dynamic>?>();

  Future<void> fetchProfile() async {
    // Serve cache first for instant UI
    final cached = CacheService.getCachedProfile();
    if (cached != null) {
      controller.add(cached);
    }

    try {
      final rows = await supabase
          .from('users_directory')
          .select()
          .eq('auth_user_id', user.id)
          .limit(1);
      if (rows.isNotEmpty) {
        final profile = Map<String, dynamic>.from(rows.first);
        controller.add(profile);
        CacheService.cacheProfile(profile);
      } else {
        controller.add(null);
      }
    } catch (e) {
      if (cached == null) controller.addError(e);
      debugPrint('[UserProvider] Network error, serving cache: $e');
    }
  }

  fetchProfile();

  final channel = supabase
      .channel('user-profile-${user.id}-${DateTime.now().millisecondsSinceEpoch}')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'users_directory',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'auth_user_id',
          value: user.id,
        ),
        callback: (payload) {
          if (payload.newRecord.isNotEmpty) {
            final updated = Map<String, dynamic>.from(payload.newRecord);
            controller.add(updated);
            CacheService.cacheProfile(updated);
          }
        },
      )
      .subscribe();

  ref.onDispose(() {
    channel.unsubscribe();
    controller.close();
  });

  return controller.stream;
});
