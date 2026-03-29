import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';

/// Sets up a Supabase Realtime subscription on `call_history` to detect
/// when the dashboard initiates an outgoing call to this citizen.
///
/// The dashboard inserts a row with:
///   call_type = 'outgoing', citizen_id = <this_user>, status = 'ringing'
///
/// We detect that INSERT and transition the callStateProvider to incomingRinging.
final incomingCallListenerProvider = Provider.autoDispose<void>((ref) {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return;

  final channel = Supabase.instance.client
      .channel('incoming-calls-$userId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'call_history',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'citizen_id',
          value: userId,
        ),
        callback: (payload) {
          final record = payload.newRecord;
          final callType = record['call_type'] as String?;
          final status = record['status'] as String?;

          if (callType == 'outgoing' && status == 'ringing') {
            final channelName = record['channel_name'] as String?;
            final callId = record['id'] as String?;
            final callerName = record['caller_name'] as String?;

            if (channelName != null && callId != null) {
              debugPrint('[IncomingCall] Detected incoming call: channel=$channelName');
              ref.read(callStateProvider.notifier).setIncomingCall(
                channelName: channelName,
                callHistoryId: callId,
                callerName: callerName ?? 'Opérateur',
              );
            }
          }
        },
      )
      .subscribe();

  ref.onDispose(() {
    channel.unsubscribe();
  });
});
