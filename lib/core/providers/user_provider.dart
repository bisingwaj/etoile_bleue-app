import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fetches user profile once, then listens for Realtime UPDATE events.
/// Avoids .stream() which opens an unfiltered Postgres replication slot per client.
final userProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return Stream.value(null);

  final supabase = Supabase.instance.client;
  final controller = StreamController<Map<String, dynamic>?>();

  Future<void> fetchProfile() async {
    try {
      final rows = await supabase
          .from('users_directory')
          .select()
          .eq('auth_user_id', user.id)
          .limit(1);
      controller.add(rows.isNotEmpty ? Map<String, dynamic>.from(rows.first) : null);
    } catch (e) {
      controller.addError(e);
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
            controller.add(Map<String, dynamic>.from(payload.newRecord));
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
