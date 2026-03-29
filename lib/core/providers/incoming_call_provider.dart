import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/core/services/callkit_service.dart';

/// Sets up a Supabase Realtime subscription on `call_history` to detect
/// when the dashboard initiates an outgoing call to this citizen.
///
/// The dashboard inserts a row with:
///   call_type = 'outgoing', citizen_id = <this_user>, status = 'ringing'
///
/// We detect that INSERT, show the native CallKit UI, and transition
/// the callStateProvider to incomingRinging.
///
/// NOT autoDispose — the subscription must stay alive for the entire session.
final incomingCallListenerProvider = Provider<void>((ref) {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) {
    debugPrint('[IncomingCall] No authenticated user, skipping Realtime subscription');
    return;
  }

  debugPrint('[IncomingCall] Setting up Realtime subscription for citizen_id=$userId');

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
          debugPrint('[IncomingCall] Realtime event received: ${payload.newRecord}');
          final record = payload.newRecord;
          final callType = record['call_type'] as String?;
          final status = record['status'] as String?;

          if (callType == 'outgoing' && status == 'ringing') {
            final channelName = record['channel_name'] as String?;
            final callId = record['id'] as String?;
            final callerName = record['caller_name'] as String?;
            final name = callerName ?? 'Opérateur';

            if (channelName != null && callId != null) {
              debugPrint('[IncomingCall] Incoming call detected: channel=$channelName, caller=$name');

              ref.read(callStateProvider.notifier).setIncomingCall(
                channelName: channelName,
                callHistoryId: callId,
                callerName: name,
              );

              CallKitService.showIncomingCall(
                callId: callId,
                callerName: name,
                hasVideo: false,
              );
            }
          }
        },
      )
      .subscribe((status, error) {
        debugPrint('[IncomingCall] Realtime channel status: $status (error: $error)');
      });

  ref.onDispose(() {
    debugPrint('[IncomingCall] Disposing Realtime subscription');
    channel.unsubscribe();
  });
});
