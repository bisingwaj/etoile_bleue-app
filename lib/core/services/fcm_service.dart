import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

/// Gestionnaire centralisé des notifications Push (Anciennement Firebase).
/// TODO: Migrer vers OneSignal ou intégration Native Supabase Edge Functions.
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

  /// Initialisation complète
  static Future<void> initialize() async {
    // 2. Configuration des notifications locales (Android)
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

    // 3. Créer le canal Android haute priorité
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
        
    debugPrint('[PUSH] Service stub initialisé avec succès.');
  }

  /// ── Notification locale tapée ─────────────────────────────────────────────
  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('[PUSH] Notification locale tapée: \${response.payload}');
    // Le payload contient le channelId — utilisé pour la navigation
  }

  /// ── Affichage de la notification d'appel entrant ──────────────────────────
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
