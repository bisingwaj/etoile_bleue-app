# 📱 Application Citoyen — Intégration des notifications push (FCM)

> **Objectif** : recevoir sur le téléphone du citoyen, **même app fermée ou téléphone verrouillé**, toutes les notifications envoyées depuis le dashboard (appels entrants de l'opérateur, changements de statut d'intervention, mises à jour hôpital). Les notifications doivent **sonner**, **rester dans la barre des notifications avec le logo** et **ouvrir l'écran approprié** au tap.

---

## 1. État côté backend (déjà opérationnel ✅)

L'infrastructure dashboard envoie **automatiquement** des notifications push FCM v1 dans les cas suivants :

| Déclencheur | Edge Function | Quand | Type FCM |
|---|---|---|---|
| Opérateur appelle le citoyen | `send-call-push` | INSERT sur `call_history` (call_type ≠ internal) | **data-only** (VoIP iOS, high-priority Android) |
| Statut intervention change | `send-dispatch-push` | UPDATE de `dispatches.status` | data + notification |
| Statut hôpital change | `send-patient-hospital-push` | UPDATE `dispatches.hospital_data.status` | data + notification |

Les triggers PostgreSQL (`trg_call_push_notification`, `notify_citizen_dispatch_status`, `notify_patient_hospital_status`) appellent les edge functions automatiquement. **Aucune action côté dashboard n'est requise.**

### Récupération du token FCM
Toutes les fonctions cherchent le token via :
```sql
SELECT fcm_token FROM users_directory WHERE auth_user_id = <citizen_id>
```
→ **L'app mobile DOIT enregistrer son token FCM dans `users_directory.fcm_token` pour le user authentifié.**

---

## 2. Payloads envoyés par le backend

### 2.1 Appel entrant (VoIP) — `send-call-push`
**Data-only** (pas de bloc `notification` au top level → garantit que le handler background est toujours invoqué).

```json
{
  "data": {
    "type": "incoming_call",
    "callId": "<uuid>",
    "channelName": "<agora_channel>",
    "callerName": "Opérateur EBRDC",
    "callType": "audio | video",
    "hasVideo": "true | false",
    "notificationTitle": "Appel vidéo entrant",
    "notificationBody": "Opérateur EBRDC vous appelle",
    "timestamp": "<ms>"
  },
  "android": { "priority": "high", "ttl": "0s" },
  "apns": {
    "headers": {
      "apns-priority": "10",
      "apns-push-type": "voip",
      "apns-topic": "<projectId>.voip"
    },
    "payload": { "aps": { "content-available": 1, "sound": "ringtone.caf" } }
  }
}
```

### 2.2 Changement de statut intervention — `send-dispatch-push`
```json
{
  "notification": { "title": "🚑 Secours en route", "body": "..." },
  "data": {
    "type": "dispatch_status",
    "dispatchId": "<uuid>",
    "incidentId": "<uuid>",
    "status": "dispatched | en_route | on_scene | en_route_hospital | arrived_hospital | mission_end | completed",
    "click_action": "FLUTTER_NOTIFICATION_CLICK"
  },
  "android": { "priority": "high", "notification": { "channel_id": "dispatch_updates" } }
}
```

### 2.3 Statut hôpital — `send-patient-hospital-push`
```json
{
  "notification": { "title": "🏥 Pris en charge", "body": "..." },
  "data": {
    "type": "hospital_status",
    "incidentId": "<uuid>",
    "dispatchId": "<uuid>",
    "hospitalStatus": "admis | triage | prise_en_charge | monitoring | termine"
  }
}
```

---

## 3. À implémenter côté app citoyen (Flutter)

### 3.1 Dépendances `pubspec.yaml`
```yaml
dependencies:
  firebase_core: ^3.6.0
  firebase_messaging: ^15.1.3
  flutter_local_notifications: ^17.2.3
  flutter_callkit_incoming: ^2.5.2   # iOS CallKit + Android full-screen ringing UI
  permission_handler: ^11.3.1
```

### 3.2 Permissions

**Android `AndroidManifest.xml`** :
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT"/>
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_PHONE_CALL"/>
```

**iOS `Info.plist`** :
```xml
<key>UIBackgroundModes</key>
<array>
  <string>voip</string>
  <string>remote-notification</string>
  <string>audio</string>
</array>
```

### 3.3 Channels Android (à créer au démarrage)

```dart
const callChannel = AndroidNotificationChannel(
  'incoming_calls',
  'Appels entrants',
  importance: Importance.max,
  sound: RawResourceAndroidNotificationSound('ringtone'), // android/app/src/main/res/raw/ringtone.mp3
  playSound: true,
  enableVibration: true,
  enableLights: true,
);

const dispatchChannel = AndroidNotificationChannel(
  'dispatch_updates',
  'Mises à jour intervention',
  importance: Importance.high,
  playSound: true,
);

const hospitalChannel = AndroidNotificationChannel(
  'hospital_updates',
  'Statut hôpital',
  importance: Importance.high,
);

await FlutterLocalNotificationsPlugin()
  .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
  ?.createNotificationChannel(callChannel);
// idem pour les autres
```

### 3.4 Enregistrement du token FCM dans Supabase

**Critique** : sans cette étape, le citoyen ne reçoit RIEN.

```dart
Future<void> registerFcmToken() async {
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);

  final token = await messaging.getToken();
  if (token == null) return;

  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return;

  await Supabase.instance.client
    .from('users_directory')
    .update({'fcm_token': token})
    .eq('auth_user_id', userId);

  // Refresh automatique
  messaging.onTokenRefresh.listen((newToken) async {
    await Supabase.instance.client
      .from('users_directory')
      .update({'fcm_token': newToken})
      .eq('auth_user_id', userId);
  });
}
```

À appeler **après chaque login réussi** et au démarrage si déjà connecté.

### 3.5 Background handler (point d'entrée critique)

```dart
// main.dart — TOP LEVEL function (obligatoire)
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final data = message.data;
  final type = data['type'];

  if (type == 'incoming_call') {
    // → Affiche CallKit (iOS) / full-screen ringing (Android)
    await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams(
      id: data['callId'],
      nameCaller: data['callerName'] ?? 'Opérateur',
      handle: data['channelName'],
      type: data['hasVideo'] == 'true' ? 1 : 0,
      duration: 45000,
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0F172A',
        actionColor: '#3B82F6',
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
      ),
    ));
  } else if (type == 'dispatch_status' || type == 'hospital_status') {
    // → Affiche notification système avec logo + titre
    await _showLocalNotification(message);
  }
}

void main() async {
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
  runApp(const CitizenApp());
}
```

### 3.6 Affichage des notifications (foreground + background)

```dart
Future<void> _showLocalNotification(RemoteMessage message) async {
  final data = message.data;
  final isCallType = data['type'] == 'incoming_call';
  final channelId = data['type'] == 'hospital_status' ? 'hospital_updates' : 'dispatch_updates';

  final title = message.notification?.title ?? data['notificationTitle'] ?? 'EBRDC';
  final body = message.notification?.body ?? data['notificationBody'] ?? '';

  await FlutterLocalNotificationsPlugin().show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelId == 'hospital_updates' ? 'Statut hôpital' : 'Interventions',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',           // ← logo de l'app
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        styleInformation: BigTextStyleInformation(body),
        color: const Color(0xFF3B82F6),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
    payload: jsonEncode(data), // → utilisé au tap pour la navigation
  );
}
```

### 3.7 Navigation au tap (deep linking)

```dart
// Au démarrage de l'app, après runApp
Future<void> setupNotificationTaps(GlobalKey<NavigatorState> navKey) async {
  // Cas 1 : app ouverte au tap sur notif
  FirebaseMessaging.onMessageOpenedApp.listen((msg) => _routeFromData(msg.data, navKey));

  // Cas 2 : app lancée DEPUIS une notif (état terminated)
  final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMsg != null) _routeFromData(initialMsg.data, navKey);

  // Cas 3 : tap sur notif locale (foreground)
  FlutterLocalNotificationsPlugin().initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
    onDidReceiveNotificationResponse: (resp) {
      if (resp.payload != null) {
        _routeFromData(jsonDecode(resp.payload!) as Map<String, dynamic>, navKey);
      }
    },
  );

  // Cas 4 : tap sur CallKit (Accept/Decline)
  FlutterCallkitIncoming.onEvent.listen((event) {
    if (event?.event == Event.actionCallAccept) {
      navKey.currentState?.pushNamed('/call', arguments: event!.body);
    } else if (event?.event == Event.actionCallDecline) {
      // Optionnel : notifier le backend
    }
  });
}

void _routeFromData(Map<String, dynamic> data, GlobalKey<NavigatorState> navKey) {
  switch (data['type']) {
    case 'incoming_call':
      navKey.currentState?.pushNamed('/call', arguments: data);
      break;
    case 'dispatch_status':
      navKey.currentState?.pushNamed('/intervention', arguments: {'incidentId': data['incidentId']});
      break;
    case 'hospital_status':
      navKey.currentState?.pushNamed('/hospital-status', arguments: {'incidentId': data['incidentId']});
      break;
    default:
      navKey.currentState?.pushNamed('/notifications');
  }
}
```

### 3.8 Foreground listener (app ouverte)

```dart
FirebaseMessaging.onMessage.listen((message) {
  if (message.data['type'] == 'incoming_call') {
    // Toujours afficher CallKit même en foreground
    _firebaseBackgroundHandler(message);
  } else {
    _showLocalNotification(message);
  }
});
```

---

## 4. Ressources requises côté app

| Asset | Emplacement Android | Emplacement iOS |
|---|---|---|
| Logo notification (mono petit) | `android/app/src/main/res/drawable/ic_notification.png` (24dp blanc) | inclus dans `AppIcon.appiconset` |
| Logo grand format | `@mipmap/ic_launcher` (déjà existant) | idem |
| Sonnerie d'appel | `android/app/src/main/res/raw/ringtone.mp3` | `ios/Runner/ringtone.caf` |

> ⚠️ Sans `ic_notification.png` mono blanc, Android affiche un carré gris à la place du logo. À fournir impérativement.

---

## 5. Configuration Firebase

L'app doit utiliser le **même `FIREBASE_PROJECT_ID`** que celui configuré côté backend (déjà présent dans les secrets Lovable Cloud). Récupérer auprès de l'équipe backend :
- `google-services.json` (Android)
- `GoogleService-Info.plist` (iOS)

Pour iOS VoIP, il faut **activer le push VoIP** dans Apple Developer + uploader le certificat APNs sur Firebase Console (Project Settings → Cloud Messaging → APNs Authentication Key).

---

## 6. Checklist de validation

- [ ] App enregistre `fcm_token` dans `users_directory` après login
- [ ] Logo blanc mono `ic_notification.png` ajouté
- [ ] 3 channels Android créés (`incoming_calls`, `dispatch_updates`, `hospital_updates`)
- [ ] `UIBackgroundModes` iOS contient `voip` + `remote-notification`
- [ ] Permission POST_NOTIFICATIONS demandée (Android 13+)
- [ ] Background handler décoré `@pragma('vm:entry-point')`
- [ ] CallKit/CallKeep affiche un écran d'appel plein écran
- [ ] Notifications restent visibles dans la barre tant que non touchées
- [ ] Tap sur notif ouvre l'écran correct (call / intervention / hospital)
- [ ] Test : opérateur appelle citoyen → téléphone sonne **app fermée**
- [ ] Test : opérateur change statut dispatch → notif arrive **téléphone verrouillé**

---

## 7. Tests recommandés

```dart
// Bouton de debug pour tester l'enregistrement du token
final token = await FirebaseMessaging.instance.getToken();
print('FCM Token: $token');

// Vérifier la persistance
final row = await Supabase.instance.client
  .from('users_directory')
  .select('fcm_token')
  .eq('auth_user_id', userId)
  .single();
print('Token in DB: ${row['fcm_token']}');
```

Côté dashboard, demander à un opérateur de lancer un appel : la notification doit arriver en **moins de 3 secondes** sur tous les appareils où le citoyen est connecté.

---

**Backend prêt à 100 %. Aucune modification dashboard requise. L'intégralité du travail restant est mobile.**
