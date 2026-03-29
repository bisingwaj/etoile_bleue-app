import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// Service CallKit — Affiche l'écran d'appel natif iOS (et Android)
/// pour les appels entrants reçus même lorsque l'app est en arrière-plan.
class CallKitService {
  /// Afficher un écran d'appel entrant (utilisé par le Secouriste qui reçoit un SOS)
  static Future<void> showIncomingCall({
    required String callId,
    required String callerName,
    bool hasVideo = true,
  }) async {
    try {
      final params = CallKitParams(
        id: callId,
        nameCaller: callerName,
        appName: 'Étoile Bleue',
        avatar: 'https://i.pravatar.cc/100',
        handle: 'SOS',
        type: hasVideo ? 1 : 0, // 0=audio, 1=vidéo
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
        duration: 45000, // 45s de sonnerie
        extra: <String, dynamic>{'channelId': callId},
        headers: <String, dynamic>{'platform': 'flutter'},
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0D1421',
          backgroundUrl: null,
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
          supportsHolding: false,
          supportsGrouping: false,
          supportsUngrouping: false,
          ringtonePath: 'system_ringtone_default',
        ),
      );

      await FlutterCallkitIncoming.showCallkitIncoming(params);
      debugPrint('[CallKit] Écran d\'appel affiché pour $callerName (id: $callId)');
    } catch (e) {
      debugPrint('[CallKit] Erreur showIncomingCall: $e');
    }
  }

  /// Terminer un appel CallKit (appeler quand raccroché côté Agora)
  static Future<void> endCall(String callId) async {
    try {
      await FlutterCallkitIncoming.endCall(callId);
      debugPrint('[CallKit] Appel terminé: $callId');
    } catch (e) {
      debugPrint('[CallKit] Erreur endCall: $e');
    }
  }

  /// Terminer tous les appels en cours (utile en cas de désync)
  static Future<void> endAllCalls() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
      debugPrint('[CallKit] Tous les appels terminés.');
    } catch (e) {
      debugPrint('[CallKit] Erreur endAllCalls: $e');
    }
  }

  /// Écouter les actions utilisateur (décrocher, raccrocher, refuser)
  static void listenToCallEvents({
    VoidCallback? onAnswered,
    VoidCallback? onDeclined,
    VoidCallback? onEnded,
  }) {
    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event == null) return;
      debugPrint('[CallKit] Événement: ${event.event}');
      switch (event.event) {
        case Event.actionCallAccept:
          onAnswered?.call();
          break;
        case Event.actionCallDecline:
          onDeclined?.call();
          break;
        case Event.actionCallEnded:
          onEnded?.call();
          break;
        default:
          break;
      }
    });
  }
}
