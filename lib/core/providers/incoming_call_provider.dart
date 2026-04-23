import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/core/services/callkit_service.dart';
import 'package:etoile_bleue_mobile/features/auth/providers/auth_provider.dart';

/// Sets up a Supabase Realtime subscription on `call_history` to detect
/// when the dashboard initiates an outgoing call to this citizen.
///
/// Watches authProvider so the subscription is recreated after login/logout.
final incomingCallListenerProvider = Provider<void>((ref) {
  // Watch auth state so this provider rebuilds on login/logout
  final authState = ref.watch(authProvider);
  
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null || !authState.isAuthenticated) {
    debugPrint('[IncomingCall] No authenticated user, skipping Realtime subscription');
    return;
  }

  debugPrint('[IncomingCall] Setting up Realtime subscription for citizen_id=$userId');

  RealtimeChannel? channel;
  Timer? retryTimer;

  void subscribe() {
    channel?.unsubscribe();
    channel = Supabase.instance.client
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
            final status = record['status'] as String?;

            if (status == 'ringing') {
              final currentState = ref.read(callStateProvider);
              if (currentState.isInCall || currentState.status == ActiveCallStatus.incomingRinging) {
                debugPrint('[IncomingCall] Call already being handled, ignoring Realtime ringing');
                return;
              }
              final channelName = record['channel_name'] as String?;
              final callId = record['id'] as String?;
              final callerName = record['caller_name'] as String?;
              final name = callerName ?? 'Centre d\'appels Etoile Bleue';

              // Ignore calls initiated by the patient (SOS or CALLBACK)
              if (channelName != null &&
                  (channelName.startsWith('SOS-') || channelName.startsWith('CALLBACK-'))) {
                debugPrint('[IncomingCall] Ignoring own outgoing call: $channelName');
                return;
              }

              if (channelName != null && callId != null) {
                debugPrint('[IncomingCall] Incoming call detected: channel=$channelName, caller=$name');
                HapticFeedback.heavyImpact();

                // Always update Flutter state
                ref.read(callStateProvider.notifier).setIncomingCall(
                  channelName: channelName,
                  callHistoryId: callId,
                  callerName: 'Étoile Bleue',
                );

                final hasVideo = record['has_video'] == true;

                // ONLY trigger native CallKit if we are NOT in the foreground
                // (If in foreground, the Dynamic Island handles it seamlessly)
                final lifecycle = WidgetsBinding.instance.lifecycleState;
                final isForeground = lifecycle == AppLifecycleState.resumed;

                if (!isForeground) {
                  debugPrint('[IncomingCall] App is in BACKGROUND, triggering native CallKit');
                  CallKitService.showIncomingCall(
                    callId: callId,
                    callerName: 'Étoile Bleue',
                    hasVideo: hasVideo,
                    extra: {'channelName': channelName},
                  );
                } else {
                  debugPrint('[IncomingCall] App is in FOREGROUND, skipping native CallKit (using Dynamic Island)');
                }
              }
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'call_history',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'citizen_id',
            value: userId,
          ),
          callback: (payload) {
            debugPrint('[IncomingCall] Realtime UPDATE event received: ${payload.newRecord}');
            final record = payload.newRecord;
            final status = record['status'] as String?;
            final callId = record['id'] as String?;

            if (status == 'completed' || status == 'missed' || status == 'failed' || status == 'abandoned') {
              final currentState = ref.read(callStateProvider);
              if (currentState.status == ActiveCallStatus.incomingRinging && currentState.callHistoryId == callId) {
                debugPrint('[IncomingCall] Remote operator cancelled the call. Closing incoming UI.');
                ref.read(callStateProvider.notifier).clearIncomingCall();
                if (callId != null) {
                  CallKitService.endCall(callId);
                }
              }
            }
          },
        )
        .subscribe((status, error) {
          debugPrint('[IncomingCall] Realtime channel status: $status (error: $error)');

          // Re-subscribe automatically on JWT expiry or channel error
          if (status == RealtimeSubscribeStatus.channelError) {
            final errMsg = error?.toString() ?? '';
            debugPrint('[IncomingCall] Channel error detected: $errMsg');
            retryTimer?.cancel();
            retryTimer = Timer(const Duration(seconds: 3), () async {
              debugPrint('[IncomingCall] Attempting session refresh + re-subscribe...');
              try {
                await Supabase.instance.client.auth.refreshSession();
                debugPrint('[IncomingCall] Session refreshed, re-subscribing...');
              } catch (e) {
                debugPrint('[IncomingCall] Session refresh failed: $e');
              }
              subscribe();
            });
          }
        });
  }

  final observer = _LifecycleObserver(onResumed: () {
    debugPrint('[IncomingCall] App resumed, refreshing Realtime subscription...');
    // Slight backoff on resume to avoid socket race conditions
    retryTimer?.cancel();
    retryTimer = Timer(const Duration(milliseconds: 500), () {
      subscribe();
    });
  });

  WidgetsBinding.instance.addObserver(observer);
  subscribe();

  ref.onDispose(() {
    debugPrint('[IncomingCall] Disposing Realtime subscription');
    WidgetsBinding.instance.removeObserver(observer);
    retryTimer?.cancel();
    channel?.unsubscribe();
  });
});

class _LifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResumed;

  _LifecycleObserver({required this.onResumed});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumed();
    }
  }
}
