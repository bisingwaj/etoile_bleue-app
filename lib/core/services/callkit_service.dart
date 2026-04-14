import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Service CallKit — Native call UI on iOS (CallKit) and Android (full-screen notification).
/// Works when the app is in foreground or recently minimized.
class CallKitService {
  static StreamSubscription? _eventSubscription;

  /// Demande les permissions nécessaires pour Android 13/14+
  static Future<void> requestPermissions() async {
    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        "rationaleMessagePermission":
            "L'autorisation de notification est requise pour recevoir les appels d'urgence.",
        "postNotificationMessageRequired":
            "L'autorisation de notification est requise pour recevoir les appels d'urgence.",
      });
      debugPrint('[CallKit] Permissions requested successfully');
    } catch (e) {
      debugPrint('[CallKit] Error requesting permissions: $e');
    }
  }

  /// Show native incoming call screen
  static Future<void> showIncomingCall({
    required String callId,
    required String callerName,
    bool hasVideo = false,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final params = CallKitParams(
        id: callId,
        nameCaller: callerName,
        appName: 'Étoile Bleue',
        handle: 'SOS Urgence',
        type: hasVideo ? 1 : 0,
        textAccept: 'Décrocher',
        textDecline: 'Refuser',
        missedCallNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: 'Appel SOS manqué',
          callbackText: 'Rappeler',
        ),
        callingNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: false,
          subtitle: 'Appel en cours...',
        ),
        duration: 45000,
        extra: extra ?? <String, dynamic>{},
        headers: <String, dynamic>{'platform': 'flutter'},
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          isShowFullLockedScreen: true,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0D1421',
          actionColor: '#4CAF50',
          textColor: '#FFFFFF',
          incomingCallNotificationChannelName: 'Appels SOS',
          missedCallNotificationChannelName: 'Appels manqués',
          isShowCallID: false,
        ),
        ios: const IOSParams(
          iconName: 'AppIcon',
          handleType: 'generic',
          supportsVideo: true,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'default',
          audioSessionActive: true,
          audioSessionPreferredSampleRate: 44100.0,
          audioSessionPreferredIOBufferDuration: 0.005,
          supportsDTMF: false,
          supportsHolding: true,
          supportsGrouping: false,
          supportsUngrouping: false,
          ringtonePath: 'system_ringtone_default',
        ),
      );

      await FlutterCallkitIncoming.showCallkitIncoming(params);
      debugPrint('[CallKit] Incoming call displayed for $callerName (id: $callId)');
    } catch (e) {
      debugPrint('[CallKit] Error showIncomingCall: $e');
    }
  }

  /// Report an active outgoing call to the system (green pill on iOS)
  static Future<void> startOutgoingCall({
    required String callId,
    required String callerName,
    bool hasVideo = false,
  }) async {
    try {
      final params = CallKitParams(
        id: callId,
        nameCaller: callerName,
        appName: 'Étoile Bleue',
        handle: 'SOS Urgence',
        type: hasVideo ? 1 : 0,
        extra: <String, dynamic>{},
        headers: <String, dynamic>{'platform': 'flutter'},
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          backgroundColor: '#0D1421',
          actionColor: '#4CAF50',
          textColor: '#FFFFFF',
          incomingCallNotificationChannelName: 'Appels SOS',
          isShowCallID: false,
        ),
        ios: const IOSParams(
          iconName: 'AppIcon',
          handleType: 'generic',
          supportsVideo: true,
          maximumCallGroups: 1,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'default',
          audioSessionActive: true,
          audioSessionPreferredSampleRate: 44100.0,
          audioSessionPreferredIOBufferDuration: 0.005,
        ),
      );

      await FlutterCallkitIncoming.startCall(params);
      debugPrint('[CallKit] Outgoing call started for $callerName (id: $callId)');
    } catch (e) {
      debugPrint('[CallKit] Error startOutgoingCall: $e');
    }
  }

  /// End a specific call
  static Future<void> endCall(String callId) async {
    try {
      await FlutterCallkitIncoming.endCall(callId);
      debugPrint('[CallKit] Call ended: $callId');
    } catch (e) {
      debugPrint('[CallKit] Error endCall: $e');
    }
  }

  /// End all active calls
  static Future<void> endAllCalls() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
      debugPrint('[CallKit] All calls ended.');
    } catch (e) {
      debugPrint('[CallKit] Error endAllCalls: $e');
    }
  }

  /// Listen to native CallKit events (accept, decline, end).
  /// The [onAccepted] callback receives the call ID and extra payload from the event body.
  static void listenToCallEvents({
    void Function(String callId, Map<String, dynamic> extra)? onAccepted,
    void Function(String callId)? onDeclined,
    void Function(String callId)? onEnded,
    void Function(String callId)? onTimeout,
  }) {
    _eventSubscription?.cancel();
    _eventSubscription = FlutterCallkitIncoming.onEvent.listen((event) {
      if (event == null) return;
      final callId = _extractCallId(event);
      debugPrint('[CallKit] Event: ${event.event} (callId: $callId)');

      switch (event.event) {
        case Event.actionCallAccept:
          if (callId != null) {
            final body = event.body as Map<dynamic, dynamic>? ?? {};
            final extraMap = body['extra'] as Map<dynamic, dynamic>? ?? {};
            final extraPayload = extraMap.map((key, value) => MapEntry(key.toString(), value));
            onAccepted?.call(callId, extraPayload);
          }
          break;
        case Event.actionCallDecline:
          if (callId != null) onDeclined?.call(callId);
          break;
        case Event.actionCallEnded:
          if (callId != null) onEnded?.call(callId);
          break;
        case Event.actionCallTimeout:
          if (callId != null) onTimeout?.call(callId);
          break;
        default:
          break;
      }
    });
  }

  static String? _extractCallId(CallEvent event) {
    try {
      final body = event.body as Map<dynamic, dynamic>?;
      return body?['id'] as String?;
    } catch (_) {
      return null;
    }
  }

  static void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }
}
