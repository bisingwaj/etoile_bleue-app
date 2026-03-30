# Prompt d'intégration Mobile Flutter — Étoile Bleue

Ce document est le prompt complet à transmettre au développeur Flutter pour intégrer parfaitement toutes les fonctionnalités backend.

---

## Configuration Supabase

```
URL: https://npucuhlvoalcbwdfedae.supabase.co
Anon Key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5wdWN1aGx2b2FsY2J3ZGZlZGFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2NDQ3NzcsImV4cCI6MjA5MDIyMDc3N30.1XLmBbRpx3Q-raPvHDnLm3dLuQGRWFHaP-fXv9BbqQk
Agora App ID: e2e0e5a6ef0d4ce3b2ab9efad48d62cf
```

---

## 1. Authentification (SMS OTP via Twilio)

**Edge Function** : `twilio-verify`

### Étape 1 — Envoyer le code OTP
```
POST /functions/v1/twilio-verify
Headers: apikey: <anon_key>
Body: { "action": "send", "phone": "+243812345678" }
Response: { "success": true, "status": "pending" }
```

### Étape 2 — Vérifier le code et obtenir la session
```
POST /functions/v1/twilio-verify
Body: { "action": "verify", "phone": "+243812345678", "code": "123456", "fullName": "Jean Mutombo" }
Response:
{
  "success": true,
  "is_new_user": true,
  "session": {
    "access_token": "...",
    "refresh_token": "...",
    "expires_in": 3600,
    "expires_at": 1234567890,
    "token_type": "bearer"
  },
  "user": {
    "id": "<directory_uuid>",
    "auth_user_id": "<auth_uuid>",
    "phone": "+243812345678",
    "role": "citoyen",
    "first_name": "Jean",
    "last_name": "Mutombo",
    "date_of_birth": null
  }
}
```

Après réception, initialiser le client Supabase avec `access_token` et `refresh_token`. Stocker `auth_user_id` localement (SharedPreferences).

### Étape 3 — Compléter le profil (si `is_new_user: true`)
```
POST /functions/v1/complete-profile
Headers: Authorization: Bearer <access_token>, apikey: <anon_key>
Body: { "first_name": "Jean", "last_name": "Mutombo", "date_of_birth": "1990-05-15" }
Response: { "success": true, "user": { ... } }
```

---

## 2. Enregistrement du FCM Token (CRITIQUE)

À chaque démarrage de l'app et à chaque refresh du token FCM, mettre à jour la colonne `fcm_token` dans `users_directory` :

```dart
final fcmToken = await FirebaseMessaging.instance.getToken();
await supabase.from('users_directory')
    .update({'fcm_token': fcmToken})
    .eq('auth_user_id', currentAuthUserId);

// Écouter aussi les refresh
FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
  await supabase.from('users_directory')
      .update({'fcm_token': newToken})
      .eq('auth_user_id', currentAuthUserId);
});
```

---

## 3. Réception des appels entrants (Push FCM)

Le dashboard envoie une **data notification FCM silencieuse** quand un opérateur appelle un citoyen. Le payload reçu :

```json
{
  "type": "incoming_call",
  "callId": "<uuid>",
  "channelName": "sos_<timestamp>_<random>",
  "callerName": "Opérateur Étoile Bleue"
}
```

### Implémentation Flutter

```dart
// Intercepter en foreground ET background
FirebaseMessaging.onMessage.listen(_handleFcmData);
FirebaseMessaging.onBackgroundMessage(_handleBackgroundMessage);

Future<void> _handleFcmData(RemoteMessage message) async {
  final data = message.data;
  if (data['type'] == 'incoming_call') {
    final callId = data['callId'];
    final channelName = data['channelName'];
    final callerName = data['callerName'];
    // Déclencher l'interface CallKit / ConnectionService
    // Puis rejoindre le canal Agora si l'utilisateur décroche
  }
}
```

**IMPORTANT** : Configurer `android:priority="high"` dans le `AndroidManifest.xml` et utiliser `flutter_callkit_incoming` ou `connectycube_flutter_call_kit` pour afficher l'écran d'appel natif même écran verrouillé.

### Fallback Realtime (si le push échoue)

En complément, garder l'écoute Supabase Realtime sur `call_history` comme fallback quand l'app est au premier plan :

```dart
supabase.channel('incoming-calls')
  .onPostgresChanges(
    event: PostgresChangeEvent.insert,
    schema: 'public',
    table: 'call_history',
    filter: PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'citizen_id',
      value: currentAuthUserId,
    ),
    callback: (payload) {
      final row = payload.newRecord;
      if (row['call_type'] == 'outgoing' && row['status'] == 'ringing') {
        // Afficher l'écran d'appel entrant
      }
    },
  )
  .subscribe();
```

---

## 4. Appel SOS (citoyen vers dashboard)

### Étape 1 — Générer un token Agora
```
POST /functions/v1/agora-token
Headers: Authorization: Bearer <access_token>, apikey: <anon_key>
Body: { "channelName": "sos_<timestamp>_<random>", "uid": 0, "role": "publisher" }
Response: { "token": "...", "appId": "e2e0e5a6ef0d4ce3b2ab9efad48d62cf", "channelName": "...", "uid": 0 }
```

### Étape 2 — Créer l'incident
```dart
await supabase.from('incidents').insert({
  'reference': channelName,  // DOIT correspondre au channelName Agora
  'type': 'urgence_medicale', // ou 'accident', 'incendie', etc.
  'title': 'SOS - Jean Mutombo',
  'caller_name': 'Jean Mutombo',
  'caller_phone': '+243812345678',
  'citizen_id': currentAuthUserId,
  'location_lat': position.latitude,
  'location_lng': position.longitude,
  'caller_realtime_lat': position.latitude,
  'caller_realtime_lng': position.longitude,
  'priority': 'critical',
  'status': 'new',
  'description': jsonEncode({
    'category': 'urgence_medicale',
    'isConscious': true,
    'isConscious_at': DateTime.now().toIso8601String(),
    'isBreathing': true,
    'isBreathing_at': DateTime.now().toIso8601String(),
  }),
});
```

Le trigger SQL `on_incident_created` crée automatiquement une entrée dans `call_queue` et auto-assigne un opérateur.

### Étape 3 — Rejoindre le canal Agora
```dart
await agoraEngine.joinChannel(
  token: agoraToken,
  channelId: channelName,
  uid: 0,
  options: ChannelMediaOptions(
    channelProfile: ChannelProfileType.channelProfileCommunication,
    clientRoleType: ClientRoleType.clientRoleBroadcaster,
  ),
);
```

---

## 5. Mise à jour GPS temps réel (pendant l'appel)

Pendant un appel actif, envoyer la position GPS toutes les 5 secondes :

```dart
await supabase.from('incidents')
  .update({
    'caller_realtime_lat': position.latitude,
    'caller_realtime_lng': position.longitude,
    'caller_realtime_updated_at': DateTime.now().toIso8601String(),
  })
  .eq('reference', currentChannelName);
```

---

## 6. Réponses au questionnaire de triage (SOS Responses)

Quand le citoyen répond aux questions de triage sur l'app mobile :

```dart
await supabase.from('sos_responses').insert({
  'incident_id': incidentId,     // UUID de l'incident
  'question_key': 'isConscious', // Clé technique
  'question_text': 'La victime est-elle consciente ?',
  'answer': 'Oui',
  'answered_at': DateTime.now().toIso8601String(),
});
```

Aussi mettre à jour `incidents.description` avec le JSON structuré complet :

```dart
await supabase.from('incidents')
  .update({
    'description': jsonEncode({
      'category': 'urgence_medicale',
      'isConscious': true,
      'isConscious_at': DateTime.now().toIso8601String(),
      'isBreathing': false,
      'isBreathing_at': DateTime.now().toIso8601String(),
      'isBleeding': true,
      'isBleeding_at': DateTime.now().toIso8601String(),
    }),
  })
  .eq('id', incidentId);
```

---

## 7. Fin d'appel côté citoyen

Quand le citoyen raccroche :

```dart
// 1. Quitter le canal Agora
await agoraEngine.leaveChannel();

// 2. Mettre à jour call_history
await supabase.from('call_history')
  .update({
    'status': 'completed',
    'ended_at': DateTime.now().toIso8601String(),
    'ended_by': 'citizen',
  })
  .eq('channel_name', currentChannelName)
  .eq('status', 'active');

// 3. Mettre à jour l'incident
await supabase.from('incidents')
  .update({
    'status': 'in_progress',
    'ended_by': 'citizen',
  })
  .eq('reference', currentChannelName)
  .inFilter('status', ['new', 'in_progress']);
```

---

## 8. Table `users_directory` — Champs disponibles pour le profil citoyen

| Colonne | Type | Description |
|---------|------|-------------|
| `blood_type` | text | Groupe sanguin (A+, O-, etc.) |
| `allergies` | text[] | Liste des allergies |
| `medical_history` | text[] | Antécédents médicaux |
| `medications` | text[] | Médicaments en cours |
| `emergency_contact_name` | text | Nom du contact d'urgence |
| `emergency_contact_phone` | text | Téléphone du contact d'urgence |
| `date_of_birth` | date | Date de naissance |
| `address` | text | Adresse |
| `photo_url` | text | URL de la photo de profil |
| `fcm_token` | text | Token FCM pour les notifications push |

Tous ces champs sont mis à jour via un simple `UPDATE` sur `users_directory` filtré par `auth_user_id`.

---

## 9. Résumé des Edge Functions disponibles

| Fonction | Méthode | Auth requise | Usage |
|----------|---------|-------------|-------|
| `twilio-verify` | POST | Non (anon key) | Envoi/vérification OTP |
| `complete-profile` | POST | Oui (Bearer JWT) | Compléter le profil après inscription |
| `agora-token` | POST | Non (anon key) | Générer un token Agora pour rejoindre un canal |
| `send-call-push` | POST | Non (appelé par le dashboard uniquement) | Envoyer un push FCM — NE PAS appeler depuis le mobile |

---

## 10. Schéma des flux

```text
┌─────────────────────────────────────────────────────────────┐
│                    APPEL SOS (Mobile → Dashboard)           │
│                                                             │
│  Mobile                          Backend                    │
│  ──────                          ───────                    │
│  1. POST agora-token         →   Token Agora                │
│  2. INSERT incidents         →   Trigger: call_queue créé   │
│                                  + auto_assign_queue()      │
│  3. JOIN canal Agora         →   Opérateur voit l'appel     │
│  4. UPDATE GPS temps réel    →   Carte se met à jour        │
│  5. INSERT sos_responses     →   Triage visible en direct   │
│  6. LEAVE canal + UPDATE     →   Incident passe in_progress │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│              APPEL ENTRANT (Dashboard → Mobile)             │
│                                                             │
│  Dashboard                       Mobile                     │
│  ─────────                       ──────                     │
│  1. INSERT call_history      →   (Realtime fallback)        │
│  2. INVOKE send-call-push    →   FCM data message reçu      │
│                                  → CallKit / écran natif     │
│  3. Citoyen décroche         →   POST agora-token           │
│                                  → JOIN canal Agora          │
└─────────────────────────────────────────────────────────────┘
```
