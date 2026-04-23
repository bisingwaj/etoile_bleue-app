# Notifications personnalisées (Dashboard → App citoyen)

## Vue d'ensemble

Le dashboard centre d'appels permet aux opérateurs (`call_center`, `admin`, `superviseur`) d'envoyer
depuis l'onglet **Notifications Citoyens** des messages personnalisés (info, alerte, système, formation)
soit à **un citoyen spécifique**, soit à **tous les citoyens** (broadcast).

Côté backend, ces envois passent par l'edge function **`send-citizen-notification`** qui :

1. Vérifie le JWT de l'opérateur et son rôle.
2. Insère un enregistrement dans la table `notifications` (affichage in-app).
3. Envoie un push FCM v1 vers le `fcm_token` enregistré dans `users_directory`.

L'app mobile doit donc :
- Enregistrer/rafraîchir le `fcm_token` du citoyen connecté.
- Recevoir les push **avec sonnerie**, **avec logo de l'app**, **persistants dans la barre de notifications**.
- Au tap, **deeplinker** vers l'écran « Notifications » de l'app.

---

## 1. Payload FCM reçu côté mobile

### Structure complète envoyée par l'edge function

```json
{
  "message": {
    "token": "<fcm_token_du_citoyen>",
    "data": {
      "type": "citizen_notification",
      "category": "info",          // info | alert | system | course
      "referenceId": "",
      "deeplink": "/notifications",
      "notificationTitle": "Mise à jour système",
      "notificationBody": "Une nouvelle version est disponible...",
      "timestamp": "1714000000000"
    },
    "android": {
      "priority": "high",
      "notification": {
        "title": "Mise à jour système",
        "body": "Une nouvelle version est disponible...",
        "channel_id": "general_updates",   // selon type
        "icon": "ic_notification",
        "click_action": "FLUTTER_NOTIFICATION_CLICK"
      }
    },
    "apns": {
      "headers": { "apns-priority": "10" },
      "payload": {
        "aps": {
          "alert": { "title": "...", "body": "..." },
          "sound": "default",
          "badge": 1,
          "content-available": 1
        }
      }
    }
  }
}
```

### Mapping `type` → `channel_id` Android

| Type        | Channel ID          | Usage                              |
|-------------|---------------------|------------------------------------|
| `info`      | `general_updates`   | Informations générales             |
| `alert`     | `health_alerts`     | Alertes sanitaires (importance HIGH) |
| `system`    | `system_updates`    | Mises à jour application           |
| `course`    | `training_updates`  | Nouvelles formations premiers secours |

---

## 2. Implémentation Android (Flutter)

### a. Déclarer les channels dans `MainActivity` ou via `flutter_local_notifications`

```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const channels = [
  AndroidNotificationChannel(
    'general_updates',
    'Informations générales',
    description: 'Notifications générales du service d\'urgence',
    importance: Importance.defaultImportance,
    playSound: true,
  ),
  AndroidNotificationChannel(
    'health_alerts',
    'Alertes sanitaires',
    description: 'Alertes santé importantes dans votre zone',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  ),
  AndroidNotificationChannel(
    'system_updates',
    'Mises à jour système',
    description: 'Notifications de mise à jour de l\'application',
    importance: Importance.defaultImportance,
  ),
  AndroidNotificationChannel(
    'training_updates',
    'Formations',
    description: 'Nouvelles formations aux premiers secours',
    importance: Importance.defaultImportance,
  ),
];

Future<void> registerChannels() async {
  final plugin = FlutterLocalNotificationsPlugin();
  for (final c in channels) {
    await plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(c);
  }
}
```

### b. Icône `ic_notification`

- Placer une icône **monochrome blanche transparente** dans `android/app/src/main/res/drawable-*dpi/ic_notification.png`.
- Taille recommandée : 24×24 dp (mdpi 24px, hdpi 36px, xhdpi 48px, xxhdpi 72px, xxxhdpi 96px).
- ⚠️ Sans cette icône, Android affiche un point gris générique au lieu du logo de l'app.

### c. AndroidManifest.xml

```xml
<application ...>
  <!-- Icône par défaut pour les notifications FCM -->
  <meta-data
    android:name="com.google.firebase.messaging.default_notification_icon"
    android:resource="@drawable/ic_notification" />
  <meta-data
    android:name="com.google.firebase.messaging.default_notification_color"
    android:resource="@color/notification_color" />
  <!-- Channel par défaut si non précisé -->
  <meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="general_updates" />
</application>
```

---

## 3. Implémentation iOS (Flutter)

### a. Capabilities Xcode

- ✅ Push Notifications
- ✅ Background Modes → Remote notifications + Background fetch

### b. APNs

Les `apns-priority: 10` + `sound: default` garantissent que la notification :
- Réveille l'écran verrouillé
- Joue le son par défaut
- Affiche le badge

### c. `AppDelegate.swift`

```swift
import UIKit
import Flutter
import Firebase
import FirebaseMessaging

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    UNUserNotificationCenter.current().delegate = self
    Messaging.messaging().delegate = self

    let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
    UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { _, _ in }
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

---

## 4. Enregistrement du `fcm_token`

Au démarrage de l'app (après login Twilio Verify), récupérer et persister le token :

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> registerFcmToken() async {
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);

  final token = await messaging.getToken();
  if (token == null) return;

  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return;

  await Supabase.instance.client
    .from('users_directory')
    .update({'fcm_token': token})
    .eq('auth_user_id', user.id);

  // Refresh on token rotation
  messaging.onTokenRefresh.listen((newToken) async {
    await Supabase.instance.client
      .from('users_directory')
      .update({'fcm_token': newToken})
      .eq('auth_user_id', user.id);
  });
}
```

---

## 5. Réception et deeplink

### a. Foreground (app ouverte)

```dart
FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
  final data = message.data;
  if (data['type'] == 'citizen_notification') {
    final title = data['notificationTitle'] ?? '';
    final body = data['notificationBody'] ?? '';
    final category = data['category'] ?? 'info';

    // Affichage local (Android/iOS) puisque iOS ne montre pas
    // automatiquement les notifs en foreground
    await FlutterLocalNotificationsPlugin().show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelForCategory(category),
          _channelLabelForCategory(category),
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_notification',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: data['deeplink'] ?? '/notifications',
    );
  }
});

String _channelForCategory(String c) => switch (c) {
  'alert' => 'health_alerts',
  'system' => 'system_updates',
  'course' => 'training_updates',
  _ => 'general_updates',
};
```

### b. Background / Terminated → tap

```dart
FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
  _handleNotificationTap(message.data);
});

// App lancée depuis une notification (terminated)
FirebaseMessaging.instance.getInitialMessage().then((message) {
  if (message != null) _handleNotificationTap(message.data);
});

void _handleNotificationTap(Map<String, dynamic> data) {
  final deeplink = data['deeplink'] ?? '/notifications';
  // GoRouter / Navigator
  navigatorKey.currentState?.pushNamed(deeplink);
}
```

### c. Background handler obligatoire

```dart
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Pour les data-only, créer une notification locale persistante
  // afin qu'elle apparaisse dans la barre des tâches.
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
  runApp(const MyApp());
}
```

---

## 6. Persistance dans la barre des tâches

Les notifications envoyées par `send-citizen-notification` contiennent un bloc
`notification` (Android) ce qui :
- Affiche automatiquement la notification même app fermée.
- Reste dans le shade jusqu'à tap ou swipe.
- Affiche le logo `ic_notification` + titre + message.

Côté code mobile : ne **pas** appeler `cancelAll()` ailleurs que sur action utilisateur.

---

## 7. Tests rapides

### Test depuis l'opérateur

1. Ouvrir le dashboard → onglet **Notifications Citoyens**.
2. Choisir « Citoyen spécifique » → rechercher par nom.
3. Sélectionner un citoyen ayant un `fcm_token` valide.
4. Saisir titre + message + type.
5. Cliquer **Envoyer la notification**.
6. Vérifier le toast : `(push livré)` confirme l'envoi FCM.

### Test côté app mobile

| Scénario             | Attendu                                                           |
|----------------------|-------------------------------------------------------------------|
| App au premier plan  | Notification locale affichée + son + écran qui scroll si dans /notifications |
| App en arrière-plan  | Notification dans la barre, sonnerie, logo correct                |
| App fermée           | Notification dans la barre, sonnerie, ouvre `/notifications` au tap |
| Pas de FCM token     | Toast dashboard : « pas de token push » (mais notif in-app insérée) |

---

## 8. Sécurité

- L'edge function vérifie obligatoirement le JWT et le rôle de l'opérateur.
- Les broadcasts vers tous les citoyens sont limités aux rôles `call_center`, `admin`, `superviseur`.
- Le payload n'expose aucun secret (uniquement titre, message, type, deeplink).
- Les tokens FCM invalides remontent dans `pushFailed` mais ne bloquent pas l'envoi global.

---

## 9. Endpoints

```
POST https://npucuhlvoalcbwdfedae.supabase.co/functions/v1/send-citizen-notification
Authorization: Bearer <operator_jwt>
Content-Type: application/json

{
  "target": "specific" | "all",
  "userId": "<auth_user_id>",   // requis si target=specific
  "title": "...",
  "message": "...",
  "type": "info" | "alert" | "system" | "course",
  "referenceId": "...",          // optionnel
  "deeplink": "/notifications"   // optionnel
}
```

**Réponse 200** :
```json
{
  "success": true,
  "recipients": 1542,
  "inAppInserted": 1542,
  "pushSent": 1289,
  "pushFailed": 12,
  "noToken": 241
}
```
