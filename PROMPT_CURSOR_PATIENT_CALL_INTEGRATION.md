# Intégration Appels VoIP — Application Patient (Citoyen)

> Ce document décrit comment l'application Flutter du **patient/citoyen** doit recevoir et émettre des appels VoIP avec la centrale et les urgentistes.

---

## 1. Architecture globale

```
┌─────────────────┐         ┌──────────────────────┐         ┌─────────────────┐
│  Dashboard Web  │         │   Supabase Backend   │         │  App Patient    │
│  (Opérateur)    │────────▶│                      │◀────────│  (Flutter)      │
└─────────────────┘         │  - call_history      │         └─────────────────┘
                            │  - agora-token       │
┌─────────────────┐         │  - send-call-push    │
│  App Urgentiste │────────▶│  - rescuer-call-     │
│  (Flutter)      │         │    citizen            │
└─────────────────┘         └──────────────────────┘
```

### Deux flux d'appels impliquant le patient :

| Flux | Direction | Edge Function | Préfixe canal |
|------|-----------|---------------|---------------|
| **SOS** | Patient → Centrale | `agora-token` (token only) | `SOS-{incidentId}-{ts}` |
| **Appel entrant** | Centrale/Urgentiste → Patient | `call-rescuer` ou `rescuer-call-citizen` | `CENTRALE-{id}-{ts}` ou `RESCUER-{id}-{ts}` |

---

## 2. Constantes et configuration

```dart
// config/agora_config.dart
class AgoraConfig {
  static const String appId = "e2e0e5a6ef0d4ce3b2ab9efad48d62cf";
  
  // Edge Functions base URL
  static String get functionsUrl => '$supabaseUrl/functions/v1';
  
  // Endpoints
  static const String tokenEndpoint = '/agora-token';
}
```

---

## 3. Flux SOS — Patient appelle la Centrale

### 3.1 Séquence

```
Patient                    Supabase                    Dashboard
  │                           │                            │
  │─── POST /agora-token ────▶│                            │
  │◀── { token, appId } ─────│                            │
  │                           │                            │
  │─── INSERT call_history ──▶│                            │
  │    status: "ringing"      │── Realtime notification ──▶│
  │    call_type: "audio"     │                            │
  │    citizen_id: auth.uid   │                            │
  │                           │                            │
  │─── JOIN Agora channel ───▶│                            │
  │                           │     Opérateur décroche     │
  │                           │◀── UPDATE call_history ────│
  │                           │    status: "active"        │
  │◀────── Agora stream ─────────────────────────────────▶│
```

### 3.2 Obtenir un token Agora

```dart
Future<Map<String, dynamic>> getAgoraToken(String channelName) async {
  final response = await supabase.functions.invoke(
    'agora-token',
    body: {
      'channelName': channelName,
      'uid': 0,
      'role': 'publisher',
      'expireTime': 3600,
    },
  );

  if (response.status != 200) {
    throw Exception('Failed to get Agora token: ${response.data}');
  }

  return response.data;
  // Retourne: { token, appId, channelName, uid, expiresAt }
}
```

### 3.3 Créer l'appel SOS dans call_history

```dart
Future<Map<String, dynamic>> initiateSosCall({
  required String channelName,
  required String agoraToken,
  required int agoraUid,
  String? incidentId,
  String? callerName,
  String? callerPhone,
  double? lat,
  double? lng,
}) async {
  final userId = supabase.auth.currentUser!.id;

  final response = await supabase.from('call_history').insert({
    'channel_name': channelName,
    'call_type': 'audio',
    'status': 'ringing',
    'caller_name': callerName,
    'caller_phone': callerPhone,
    'citizen_id': userId,
    'incident_id': incidentId,
    'role': 'citoyen',
    'has_video': false,
    'agora_token': agoraToken,
    'agora_uid': agoraUid,
    'caller_lat': lat,
    'caller_lng': lng,
  }).select().single();

  return response;
}
```

### 3.4 Gestion de la résilience (doublon incident)

```dart
/// Si le serveur renvoie l'erreur P0001 "Duplicate incident",
/// le patient doit REJOINDRE le canal existant au lieu de recréer.
Future<void> handleSosCall() async {
  try {
    final incident = await createIncident(...);
    final channelName = 'SOS-${incident['id'].substring(0, 8)}-${DateTime.now().millisecondsSinceEpoch}';
    final tokenData = await getAgoraToken(channelName);
    await initiateSosCall(channelName: channelName, ...);
    await joinAgoraChannel(channelName, tokenData['token']);
  } catch (e) {
    if (e.toString().contains('Duplicate incident') || e.toString().contains('P0001')) {
      // Récupérer le canal existant en status 'ringing' ou 'active'
      final existing = await supabase
          .from('call_history')
          .select()
          .eq('citizen_id', supabase.auth.currentUser!.id)
          .inFilter('status', ['ringing', 'active'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        await joinAgoraChannel(existing['channel_name'], existing['agora_token']);
      }
    }
  }
}
```

---

## 4. Flux entrant — Recevoir un appel de la Centrale ou d'un Urgentiste

### 4.1 Séquence

```
Centrale/Urgentiste        Supabase                    Patient
  │                           │                            │
  │── POST /call-rescuer ────▶│                            │
  │   ou /rescuer-call-citizen│                            │
  │                           │                            │
  │                           │── INSERT call_history ────▶│ (Realtime)
  │                           │   status: "ringing"        │
  │                           │   citizen_id: patient_uid  │
  │                           │   channel_name: "CENTRALE-"│
  │                           │   agora_token: "..."       │
  │                           │                            │
  │                           │── FCM push notification ──▶│ (Réveil app)
  │                           │   type: "incoming_call"    │
  │                           │   channelName: "..."       │
  │                           │   callerName: "..."        │
  │                           │                            │
  │                           │                            │── Afficher UI appel
  │                           │                            │
  │                           │◀── UPDATE call_history ────│ (Répondre)
  │                           │    status: "active"        │
  │                           │    answered_at: now()      │
  │                           │                            │
  │◀────── Agora stream ──────────────────────────────────▶│
```

### 4.2 Écoute Realtime — Appels entrants

C'est le mécanisme **principal** pour détecter un appel entrant. L'app doit écouter les **INSERT** sur `call_history` filtrés par `citizen_id`.

```dart
// services/incoming_call_listener.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class IncomingCallListener {
  final SupabaseClient _supabase;
  RealtimeChannel? _channel;

  IncomingCallListener(this._supabase);

  /// Démarre l'écoute des appels entrants pour le citoyen connecté.
  /// Doit être appelé au démarrage de l'app (après login).
  void startListening({
    required void Function(Map<String, dynamic> callRecord) onIncomingCall,
  }) {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    _channel = _supabase
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
            final record = payload.newRecord;
            final status = record['status'] as String?;
            final channelName = record['channel_name'] as String? ?? '';

            // Ne réagir qu'aux appels "ringing" avec préfixe CENTRALE- ou RESCUER-
            if (status == 'ringing' &&
                (channelName.startsWith('CENTRALE-') ||
                 channelName.startsWith('RESCUER-'))) {
              onIncomingCall(record);
            }
          },
        )
        .subscribe();
  }

  void stopListening() {
    _channel?.unsubscribe();
    _channel = null;
  }
}
```

### 4.3 Réception FCM — Réveil en arrière-plan

La notification push FCM sert **uniquement** à réveiller l'app quand elle est en arrière-plan. Elle ne contient **pas** le token Agora pour des raisons de sécurité.

```dart
// services/fcm_handler.dart

import 'package:firebase_messaging/firebase_messaging.dart';

/// Handler FCM à enregistrer dans main.dart
Future<void> onBackgroundMessage(RemoteMessage message) async {
  final data = message.data;
  if (data['type'] == 'incoming_call') {
    // Réveiller l'app et afficher la sonnerie système
    // Les données complètes (token Agora) seront récupérées via Realtime
    // ou via un fetch direct sur call_history
    await _showCallNotification(
      callId: data['callId'] ?? '',
      channelName: data['channelName'] ?? '',
      callerName: data['callerName'] ?? 'Opérateur',
    );
  }
}

/// Payload FCM reçu :
/// {
///   "type": "incoming_call",
///   "callId": "uuid-du-call-history",
///   "channelName": "CENTRALE-xxxx-1234567890",
///   "callerName": "Dr. Kabila"
/// }
```

### 4.4 Récupérer les données complètes de l'appel (si réveil par push)

Quand l'app se réveille via FCM, le listener Realtime peut ne pas encore être actif. Il faut donc fetch les données directement :

```dart
Future<Map<String, dynamic>?> fetchIncomingCall(String callId) async {
  final response = await supabase
      .from('call_history')
      .select()
      .eq('id', callId)
      .eq('status', 'ringing')
      .maybeSingle();

  return response;
  // Contient : agora_token, channel_name, call_type, caller_name, has_video, etc.
}
```

### 4.5 Répondre à l'appel

```dart
Future<void> answerCall(String callId, String channelName, String agoraToken) async {
  // 1. Mettre à jour le statut en base
  await supabase.from('call_history').update({
    'status': 'active',
    'answered_at': DateTime.now().toUtc().toIso8601String(),
  }).eq('id', callId);

  // 2. Rejoindre le canal Agora avec le token fourni dans call_history
  await joinAgoraChannel(channelName, agoraToken);
}
```

### 4.6 Refuser l'appel

```dart
Future<void> rejectCall(String callId) async {
  await supabase.from('call_history').update({
    'status': 'missed',
    'ended_at': DateTime.now().toUtc().toIso8601String(),
    'ended_by': 'citizen_rejected',
  }).eq('id', callId);
}
```

### 4.7 Raccrocher

```dart
Future<void> hangUp(String callId) async {
  // 1. Quitter Agora
  await agoraEngine.leaveChannel();

  // 2. Mettre à jour call_history
  await supabase.from('call_history').update({
    'status': 'completed',
    'ended_at': DateTime.now().toUtc().toIso8601String(),
    'ended_by': 'citizen',
  }).eq('id', callId);
}
```

---

## 5. Rejoindre un canal Agora (commun aux deux flux)

```dart
// services/agora_service.dart

import 'package:agora_rtc_engine/agora_rtc_engine.dart';

class AgoraService {
  late RtcEngine _engine;

  Future<void> initialize() async {
    _engine = createAgoraRtcEngine();
    await _engine.initialize(RtcEngineContext(
      appId: AgoraConfig.appId,
    ));

    // Event handlers
    _engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        print('Joined channel: ${connection.channelId}');
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        print('Remote user joined: $remoteUid');
      },
      onUserOffline: (connection, remoteUid, reason) {
        print('Remote user left: $remoteUid, reason: $reason');
        // ⚠️ NE PAS recréer d'incident ici !
        // Simplement déclencher la fin de l'appel côté UI
      },
    ));
  }

  Future<void> joinChannel({
    required String channelName,
    required String token,
    bool enableVideo = false,
  }) async {
    await _engine.enableAudio();

    if (enableVideo) {
      await _engine.enableVideo();
      await _engine.startPreview();
    }

    await _engine.joinChannel(
      token: token,
      channelId: channelName,
      uid: 0,
      options: ChannelMediaOptions(
        autoSubscribeAudio: true,
        autoSubscribeVideo: enableVideo,
        publishMicrophoneTrack: true,
        publishCameraTrack: enableVideo,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  Future<void> leaveChannel() async {
    await _engine.leaveChannel();
  }

  Future<void> toggleVideo(bool enabled) async {
    if (enabled) {
      await _engine.enableVideo();
      await _engine.startPreview();
    } else {
      await _engine.stopPreview();
      await _engine.disableVideo();
    }
  }

  Future<void> toggleMute(bool muted) async {
    await _engine.muteLocalAudioStream(muted);
  }

  Future<void> dispose() async {
    await _engine.release();
  }
}
```

---

## 6. Enregistrement du FCM Token

L'app patient **doit** enregistrer son token FCM dans `users_directory` pour recevoir les notifications push de réveil.

```dart
Future<void> registerFcmToken() async {
  final fcmToken = await FirebaseMessaging.instance.getToken();
  if (fcmToken == null) return;

  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return;

  await supabase.from('users_directory').update({
    'fcm_token': fcmToken,
  }).eq('auth_user_id', userId);

  // Écouter les renouvellements de token
  FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
    await supabase.from('users_directory').update({
      'fcm_token': newToken,
    }).eq('auth_user_id', userId);
  });
}
```

---

## 7. Écoute des changements de statut pendant un appel actif

Pendant un appel, le patient doit écouter les **UPDATE** sur son `call_history` pour détecter si l'opérateur/urgentiste raccroche.

```dart
void listenCallStatus(String callId, {required VoidCallback onRemoteHangup}) {
  supabase
      .channel('call-status-$callId')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'call_history',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: callId,
        ),
        callback: (payload) {
          final newStatus = payload.newRecord['status'] as String?;
          if (newStatus == 'completed' || newStatus == 'missed' || newStatus == 'failed') {
            onRemoteHangup();
          }
        },
      )
      .subscribe();
}
```

---

## 8. Synchronisation vidéo (caméra du patient)

Le dashboard écoute le champ `has_video` pour savoir si le patient a activé sa caméra. L'app doit mettre à jour ce champ :

```dart
Future<void> updateVideoStatus(String callId, bool hasVideo) async {
  await supabase.from('call_history').update({
    'has_video': hasVideo,
  }).eq('id', callId);
}
```

---

## 9. Structure `call_history` — Colonnes clés

| Colonne | Type | Description |
|---------|------|-------------|
| `id` | uuid | ID unique de l'appel |
| `channel_name` | text | Nom du canal Agora (préfixé SOS-, CENTRALE-, RESCUER-) |
| `call_type` | enum | `audio` ou `video` |
| `status` | enum | `ringing` → `active` → `completed` / `missed` / `failed` |
| `caller_name` | text | Nom de l'appelant |
| `caller_phone` | text | Téléphone de l'appelant |
| `citizen_id` | uuid | **Auth user ID du citoyen** — clé de routage |
| `incident_id` | uuid | Référence à l'incident lié |
| `operator_id` | uuid | ID profil de l'opérateur/urgentiste |
| `has_video` | boolean | Caméra active ou non |
| `agora_token` | text | Token Agora pré-généré (pour appels entrants) |
| `agora_uid` | integer | UID Agora (généralement 0) |
| `answered_at` | timestamptz | Timestamp de décrochage (source de vérité pour durée) |
| `ended_at` | timestamptz | Timestamp de fin |
| `ended_by` | text | Qui a raccroché (`operator`, `citizen`, `citizen_rejected`, `system`, `timeout`) |
| `caller_lat` | double | Latitude GPS du patient |
| `caller_lng` | double | Longitude GPS du patient |

---

## 10. Checklist d'intégration

- [ ] **Config Agora** : App ID `e2e0e5a6ef0d4ce3b2ab9efad48d62cf`
- [ ] **Supabase client** : Initialisé avec URL + anon key
- [ ] **Auth** : Login via Twilio OTP (edge function `twilio-verify` + `complete-profile`)
- [ ] **FCM Token** : Enregistré dans `users_directory.fcm_token` au login
- [ ] **Realtime listener** : Écoute INSERT sur `call_history` filtré par `citizen_id`
- [ ] **FCM background handler** : Réveil app + affichage sonnerie native
- [ ] **Fetch call data** : Récupération `call_history` par ID si réveil par push
- [ ] **Answer flow** : UPDATE `status: active` + `answered_at` → join Agora
- [ ] **Reject flow** : UPDATE `status: missed` + `ended_by: citizen_rejected`
- [ ] **Hangup flow** : Leave Agora → UPDATE `status: completed` + `ended_at`
- [ ] **Status listener** : Écoute UPDATE sur `call_history.id` pendant appel actif
- [ ] **Video sync** : UPDATE `has_video` quand patient toggle caméra
- [ ] **Résilience SOS** : Gestion erreur P0001 (Duplicate incident) → rejoindre canal existant
- [ ] **Anti-doublon** : Ne PAS recréer d'incident sur `onUserOffline` Agora
- [ ] **Timeout** : Si aucun décrochage après 45s → UPDATE `status: missed`

---

## 11. Diagramme de statuts call_history

```
                    ┌──────────┐
                    │ ringing  │
                    └────┬─────┘
                         │
              ┌──────────┼──────────┐
              │          │          │
              ▼          ▼          ▼
         ┌────────┐ ┌────────┐ ┌────────┐
         │ active │ │ missed │ │ failed │
         └───┬────┘ └────────┘ └────────┘
             │
             ▼
       ┌───────────┐
       │ completed │
       └───────────┘
```

- `ringing` : Appel initié, en attente de réponse
- `active` : Appel en cours (stream Agora actif)
- `completed` : Appel terminé normalement
- `missed` : Non décroché (timeout 45s) ou refusé par le patient
- `failed` : Erreur technique (réseau, Agora, etc.)
