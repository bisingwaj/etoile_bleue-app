import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etoile_bleue_mobile/core/services/callkit_service.dart';
import 'package:etoile_bleue_mobile/core/router/app_router.dart';

@pragma('vm:entry-point')
Future<void> _handleBackgroundMessage(RemoteMessage message) async {
  // Réveil profond de l'application (Background / Killed)
  debugPrint('[PUSH-BG] ===== BACKGROUND MESSAGE RECEIVED =====');
  debugPrint('[PUSH-BG] messageId=${message.messageId}');
  debugPrint('[PUSH-BG] data=${message.data}');
  try {
    await Firebase.initializeApp();
    debugPrint('[PUSH-BG] Firebase initialized in background isolate');
  } catch (e) {
    debugPrint('[PUSH-BG] Firebase already initialized: $e');
  }
  await FcmService.processMessage(message);
  debugPrint('[PUSH-BG] ===== BACKGROUND PROCESSING DONE =====');
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

  static ProviderContainer? _container;

  /// Initialisation complète FCM et Local Notifications
  static Future<void> initialize(ProviderContainer container) async {
    _container = container;
    // 1. Demander les permissions Push (Obligatoire pour iOS, recommandé Android 13+)
    await FirebaseMessaging.instance.requestPermission();

    // 2. Écouteurs Firebase Messaging
    FirebaseMessaging.onMessage.listen(_handleFcmData);
    FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);

    // 3. Configuration des notifications locales
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
    
    // Check if the app was launched via a notification tap (Killed state)
    final NotificationAppLaunchDetails? launchDetails = 
        await _localNotifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _onNotificationTapped(launchDetails!.notificationResponse!);
    }

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
      debugPrint('[PUSH] FCM Token: ${token ?? "NULL"}');
      if (token != null) {
        await _updateTokenInDatabase(token);
        debugPrint('[PUSH] ✅ Token synced to database');
      } else {
        debugPrint('[PUSH] ⚠️ FCM token is null — push won\'t work');
      }
    } catch (e) {
      debugPrint('[PUSH] ❌ Erreur lors de la récupération du token: $e');
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
    final payload = response.payload;
    debugPrint('[PUSH] Notification locale tapée: $payload');
    
    if (payload != null && payload.startsWith('incident:')) {
      final incidentId = payload.replaceFirst('incident:', '');
      if (incidentId.isNotEmpty && _container != null) {
        debugPrint('[PUSH] Redirection vers l\'incident: $incidentId');
        // Use addPostFrameCallback to ensure the router is ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            _container!.read(appRouterProvider).push('/incident/$incidentId');
          } catch (e) {
            debugPrint('[PUSH] Erreur lors de la navigation: $e');
          }
        });
      }
    }
  }

  /// Réception quand l'app est au premier plan
  static Future<void> _handleFcmData(RemoteMessage message) async {
    debugPrint('[PUSH] Foreground message received: ${message.messageId}');
    await processMessage(message);
  }

  /// Traitement logique du payload recu par FCM
  static Future<void> processMessage(RemoteMessage message) async {
    final data = message.data;
    debugPrint('[PUSH] ===== FCM MESSAGE RECEIVED =====');
    debugPrint('[PUSH] Message ID: ${message.messageId}');
    debugPrint('[PUSH] Data keys: ${data.keys.toList()}');
    debugPrint('[PUSH] Full payload: $data');
    
    // Also check notification body for data (some backends send it there)
    if (message.notification != null) {
      debugPrint('[PUSH] Notification title: ${message.notification?.title}');
      debugPrint('[PUSH] Notification body: ${message.notification?.body}');
    }

    // Accept multiple type values from different backends
    final type = data['type'] ?? data['action'] ?? '';
    final isDispatchUpdate = type == 'dispatch_status_update' || 
                           type == 'dispatch' ||
                           data.containsKey('incidentId') || 
                           data.containsKey('incident_id');
    final isIncomingCall = type == 'incoming_call' || 
                           type == 'call' || 
                           type == 'voip_call' ||
                           type == 'incoming-call' ||
                           data.containsKey('callId') ||
                           data.containsKey('call_id') ||
                           data.containsKey('channel_name');
    
    if (isIncomingCall) {
      // Handle both camelCase and snake_case field names
      final callId = (data['callId'] ?? data['call_id'] ?? data['id'] ?? '') as String;
      final channelName = (data['channelName'] ?? data['channel_name'] ?? '') as String;
      final callerName = (data['callerName'] ?? data['caller_name'] ?? 'Centre d\'appels Étoile Bleue') as String;
      final hasVideo = data['hasVideo'] == 'true' || data['has_video'] == 'true';

      debugPrint('[PUSH] → Incoming call detected!');
      if (callId.isNotEmpty) {
        await CallKitService.showIncomingCall(
          callId: callId,
          callerName: callerName,
          hasVideo: hasVideo,
          extra: {'channelName': channelName},
        );
      }
    } else if (isDispatchUpdate) {
      final incidentId = (data['incidentId'] ?? data['incident_id'] ?? data['reference_id'] ?? '') as String;
      final status = (data['status'] ?? '') as String;
      
      debugPrint('[PUSH] → Dispatch status update: $status (incident=$incidentId)');
      
      // If we are in foreground and there's no system notification shown yet,
      // or if we want to ensure visual feedback, we show a local notification.
      if (incidentId.isNotEmpty) {
        String title = message.notification?.title ?? "Mise à jour d'intervention";
        String body = message.notification?.body ?? "Le statut de votre demande a changé.";
        
        await _localNotifications.show(
          incidentId.hashCode,
          title,
          body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _androidChannel.id,
              _androidChannel.name,
              channelDescription: _androidChannel.description,
              importance: Importance.max,
              priority: Priority.max,
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentSound: true,
              presentBadge: true,
            ),
          ),
          payload: 'incident:$incidentId',
        );
      }
    } else {
      debugPrint('[PUSH] ℹ️ Message type not recognized (type=$type). Ignoring.');
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
