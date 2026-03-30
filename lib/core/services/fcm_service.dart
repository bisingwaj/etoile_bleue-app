import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/services/callkit_service.dart';

@pragma('vm:entry-point')
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  // Réveil profond de l'application (Background / Killed)
  await Firebase.initializeApp();
  debugPrint('[PUSH] Background message received: ${message.messageId}');
  await FcmService.processMessage(message);
}

/// Gestionnaire centralisé des notifications Push (Firebase FCM).
class FcmService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const _androidChannel = AndroidNotificationChannel(
    'sos_calls_channel',
    'Appels SOS',
    description: 'Notifications des appels d\'urgence SOS',
    importance: Importance.max,
    playSound: true,
  );

  /// Initialisation complète FCM et Local Notifications
  static Future<void> initialize() async {
    // 1. Demander les permissions Push (Obligatoire pour iOS, recommandé Android 13+)
    await FirebaseMessaging.instance.requestPermission();

    // 2. Écouteurs Firebase Messaging
    FirebaseMessaging.onMessage.listen(_handleFcmData);
    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);

    // 3. Configuration des notifications locales (Fallback)
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false, 
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // 4. Créer le canal Android haute priorité
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    // 5. Synchroniser le Token FCM
    await syncToken();

    // 6. S'abonner aux changements de Token
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _updateTokenInDatabase(newToken);
    });
        
    debugPrint('[PUSH] FcmService initialisé avec succès.');
  }

  /// Récupère le jeton actuel et l'envoie à Supabase
  static Future<void> syncToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _updateTokenInDatabase(token);
      }
    } catch (e) {
      debugPrint('[PUSH] Erreur lors de la récupération du token: $e');
    }
  }

  /// Met à jour la table users_directory avec le jeton FCM
  static Future<void> _updateTokenInDatabase(String token) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await Supabase.instance.client
            .from('users_directory')
            .update({'fcm_token': token})
            .eq('auth_user_id', user.id);
        debugPrint('[PUSH] Token FCM synchronisé pour ${user.id}');
      }
    } catch (e) {
      debugPrint('[PUSH] Echec synchro Supabase token FCM: $e');
    }
  }

  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('[PUSH] Notification locale tapée: \${response.payload}');
  }

  /// Réception quand l'app est au premier plan
  static Future<void> _handleFcmData(RemoteMessage message) async {
    debugPrint('[PUSH] Foreground message received: ${message.messageId}');
    await processMessage(message);
  }

  /// Traitement logique du payload recu par FCM
  static Future<void> processMessage(RemoteMessage message) async {
    final data = message.data;
    debugPrint('[PUSH] Payload Data: $data');

    if (data['type'] == 'incoming_call') {
      final callId = data['callId'] as String?;
      final channelName = data['channelName'] as String?;
      final callerName = data['callerName'] as String?;

      if (callId != null && callerName != null) {
        // Appelle explicitement CallKit pour réveiller le téléphone
        await CallKitService.showIncomingCall(
          callId: callId,
          callerName: callerName,
          hasVideo: false,
          extra: {'channelName': channelName},
        );
      }
    }
  }

  /// (Legacy fallback) Affichage de la notification d'appel entrant
  static Future<void> showIncomingCallNotification({
    required String channelId,
    required String callerName,
  }) async {
    await _localNotifications.show(
      channelId.hashCode,
      '🚨 Appel SOS entrant',
      '$callerName a besoin d\'aide',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true, // Ouvre l'écran quand le téléphone est verrouillé
          category: AndroidNotificationCategory.call,
          actions: [
            const AndroidNotificationAction('ACTION_ACCEPT', 'Décrocher',
                showsUserInterface: true),
            const AndroidNotificationAction('ACTION_DECLINE', 'Refuser',
                cancelNotification: true),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.critical,
        ),
      ),
      payload: channelId,
    );
  }
}
