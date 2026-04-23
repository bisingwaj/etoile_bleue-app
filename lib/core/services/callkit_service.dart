import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart' hide NotificationVisibility;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service CallKit — Native call UI on iOS (CallKit) and Android (notification).
///
/// On Android: bypasses CallKit's native full-screen activity entirely.
/// Instead uses a local notification + FlutterForegroundTask.launchApp()
/// so the custom Flutter UI (Dynamic Island) takes over.
///
/// On iOS: uses CallKit as required by Apple.
class CallKitService {
  static StreamSubscription? _eventSubscription;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _localNotificationsInitialized = false;

  /// Initialize local notifications for Android incoming call alerts
  static Future<void> _ensureLocalNotificationsInit() async {
    if (_localNotificationsInitialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        // Tapping the notification brings the app to foreground
        debugPrint('[CallKit] Notification tapped, launching app');
        FlutterForegroundTask.launchApp();
      },
    );
    _localNotificationsInitialized = true;
  }

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

  /// Show incoming call UI.
  /// - Uses native CallKit/SystemUI for both platforms (background/locked state).
  static Future<void> showIncomingCall({
    required String callId,
    required String callerName,
    bool hasVideo = false,
    Map<String, dynamic>? extra,
  }) async {
    try {
      final params = CallKitParams(
        id: callId,
        nameCaller: 'Étoile Bleue',
        appName: 'Étoile Bleue',
        handle: 'Service d\'urgence',
        type: hasVideo ? 1 : 0,
        duration: 45000,
        textAccept: 'Décrocher',
        textDecline: 'Refuser',
        missedCallNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: 'Appel d\'urgence manqué',
          callbackText: 'Rappeler',
        ),
        callingNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: false,
          subtitle: 'Appel en cours...',
        ),
        extra: extra ?? <String, dynamic>{},
        headers: <String, dynamic>{'platform': 'flutter'},
        android: const AndroidParams(
          isCustomNotification: false,
          isShowLogo: true,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0955fa',
          backgroundUrl: 'assets/test.png',
          actionColor: '#4CAF50',
          textColor: '#ffffff',
          incomingCallNotificationChannelName: 'Appels entrants',
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
      debugPrint('[CallKit] Native incoming call UI displayed');
    } catch (e) {
      debugPrint('[CallKit] Error showIncomingCall: $e');
    }
  }

  /// Dismiss the incoming call notification on Android
  static Future<void> dismissIncomingNotification() async {
    if (Platform.isAndroid) {
      await _localNotifications.cancel(42);
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
        nameCaller: 'Étoile Bleue',
        handle: 'Service d\'urgence',
        type: hasVideo ? 1 : 0,
        extra: <String, dynamic>{},
        ios: const IOSParams(handleType: 'generic'),
      );
      await FlutterCallkitIncoming.startCall(params);
    } catch (e) {
      debugPrint('[CallKit] Error startOutgoingCall: $e');
    }
  }

  static Future<void> endCall(String callId) async {
    try {
      await FlutterCallkitIncoming.endCall(callId);
      // Also dismiss our local notification on Android
      if (Platform.isAndroid) {
        await _localNotifications.cancel(42);
      }
    } catch (e) {
      debugPrint('[CallKit] Error endCall: $e');
    }
  }

  static Future<void> endAllCalls() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
      if (Platform.isAndroid) {
        await _localNotifications.cancel(42);
      }
    } catch (e) {
      debugPrint('[CallKit] Error endAllCalls: $e');
    }
  }

  static void listenToCallEvents({
    required Future<void> Function(String callId, Map<String, dynamic> extra) onAccepted,
    required void Function(String callId) onDeclined,
    required void Function(String callId) onEnded,
    required void Function(String callId) onTimeout,
    void Function(String callId, Map<String, dynamic> extra)? onIncoming,
  }) {
    _eventSubscription?.cancel();
    _eventSubscription = FlutterCallkitIncoming.onEvent.listen((event) async {
      debugPrint('[CallKit] Event: ${event?.event}');
      final body = event?.body ?? {};
      final callId = body['id']?.toString() ?? '';
      final extra = (body['extra'] as Map<String, dynamic>?) ?? {};

      switch (event?.event) {
        case Event.actionCallIncoming:
          // On Android this won't fire since we don't use CallKit UI
          // On iOS this fires when the native CallKit screen appears
          if (callId.isNotEmpty) onIncoming?.call(callId, extra);
          break;
        case Event.actionCallStart:
          break;
        case Event.actionCallAccept:
          if (callId.isNotEmpty) await onAccepted(callId, extra);
          break;
        case Event.actionCallDecline:
          if (callId.isNotEmpty) onDeclined(callId);
          break;
        case Event.actionCallEnded:
          if (callId.isNotEmpty) onEnded(callId);
          break;
        case Event.actionCallTimeout:
          if (callId.isNotEmpty) onTimeout(callId);
          break;
        default:
          break;
      }
    });
  }
}
