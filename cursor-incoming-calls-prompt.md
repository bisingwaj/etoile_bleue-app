# Prompt Cursor : Réception des appels entrants du Centre d'Appels sur l'application mobile Flutter

## Contexte

Le Centre d'Appels (dashboard web) peut émettre des appels sortants vers les citoyens et les secouristes via Supabase + Agora RTC. Côté web, tout est fonctionnel : l'opérateur clique "Appeler", une ligne `call_history` est insérée avec `call_type: 'outgoing'` et `status: 'ringing'`, et l'opérateur rejoint le canal Agora.

**Le problème** : l'application mobile n'écoute pas (ou mal) les signaux d'appels entrants provenant du centre d'appels. L'appel reste "en attente de connexion" côté web parce que personne ne rejoint le canal Agora côté mobile.

---

## Architecture de signalisation (déjà en place côté backend)

### Flux d'un appel sortant (Dashboard → Mobile) :

1. **Dashboard** insère dans `call_history` :
   ```sql
   INSERT INTO call_history (
     channel_name, caller_name, caller_phone, call_type, status,
     citizen_id, operator_id, has_video
   ) VALUES (
     'CALL-{operatorId_8chars}-{timestamp}',  -- canal Agora unique
     'Opérateur Jean',                         -- nom de l'opérateur
     NULL,                                     -- pas de téléphone
     'outgoing',                               -- type sortant (= entrant pour le mobile)
     'ringing',                                -- statut initial
     '{citizen_auth_user_id}',                 -- UUID Auth du citoyen ciblé
     '{operator_profile_id}',                  -- profil opérateur
     false                                     -- audio ou vidéo
   );
   ```

2. **Mobile** doit écouter les insertions dans `call_history` où :
   - `citizen_id` = UUID Auth de l'utilisateur connecté
   - `status` = `'ringing'`
   - `call_type` = `'outgoing'` (sortant du centre = entrant pour le mobile)

3. **Mobile** affiche l'écran d'appel entrant (type CallKit/ConnectionService)

4. Si l'utilisateur **accepte** :
   - Update `call_history` : `status = 'active'`, `answered_at = now()`
   - Rejoindre le canal Agora avec le `channel_name` de l'enregistrement
   - Générer un token Agora via l'Edge Function `agora-token`

5. Si l'utilisateur **refuse** :
   - Update `call_history` : `status = 'missed'`, `ended_at = now()`, `ended_by = 'citizen_rejected'`

6. Si l'utilisateur **raccroche** après avoir décroché :
   - Update `call_history` : `status = 'completed'`, `ended_at = now()`, `ended_by = 'citizen_hangup'`, `duration_seconds = diff(answered_at, now())`

---

## Implémentation Flutter requise

### 1. Service d'écoute Realtime (`incoming_call_listener.dart`)

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

class IncomingCallListener {
  final SupabaseClient _supabase;
  RealtimeChannel? _channel;
  Function(Map<String, dynamic> callData)? onIncomingCall;

  IncomingCallListener(this._supabase);

  void startListening() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // IMPORTANT: La table call_history a REPLICA IDENTITY FULL
    // ce qui permet le filtrage serveur par citizen_id
    _channel = _supabase
        .channel('incoming-calls-${DateTime.now().millisecondsSinceEpoch}')
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
            final newRecord = payload.newRecord;
            // Vérifier que c'est bien un appel entrant pour nous
            if (newRecord['status'] == 'ringing' &&
                newRecord['call_type'] == 'outgoing') {
              onIncomingCall?.call(newRecord);
            }
          },
        )
        .subscribe();
  }

  void stopListening() {
    if (_channel != null) {
      _supabase.removeChannel(_channel!);
      _channel = null;
    }
  }
}
```

### 2. Surveiller aussi les UPDATES (raccrochage distant)

```dart
// Dans le même channel, ajouter un listener UPDATE pour détecter
// quand l'opérateur raccroche (status passe à 'completed' ou 'missed')
_channel = _supabase
    .channel('call-status-${DateTime.now().millisecondsSinceEpoch}')
    .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'call_history',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'citizen_id',
        value: userId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        final status = newRecord['status'];
        if (status == 'completed' || status == 'missed' || status == 'failed') {
          // L'opérateur a raccroché → fermer l'écran d'appel
          onCallEnded?.call(newRecord);
        }
      },
    )
    .subscribe();
```

### 3. Écran d'appel entrant (`incoming_call_screen.dart`)

Design attendu : écran plein format type WhatsApp/Telegram avec :

```
┌─────────────────────────────┐
│                             │
│     🏥 Centre d'Appels      │
│     Étoile Bleue            │
│                             │
│     Opérateur: Jean Doe     │
│                             │
│     Appel audio entrant     │
│     ── ou ──                │
│     Appel vidéo entrant     │
│                             │
│                             │
│   [🔴 Refuser]  [🟢 Accepter] │
│                             │
└─────────────────────────────┘
```

**Éléments critiques** :
- Animation de pulsation sur le bouton vert
- Sonnerie (utiliser le pattern ringtone natif ou un son personnalisé)
- Vibration continue tant que l'écran est affiché
- Le `caller_name` de l'enregistrement `call_history` contient le nom de l'opérateur
- Afficher si c'est un appel audio ou vidéo (`has_video`)
- **Timeout** : si pas de réponse après 45 secondes, auto-refuser

### 4. Accepter l'appel

```dart
Future<void> acceptCall(Map<String, dynamic> callData) async {
  final callId = callData['id'];
  final channelName = callData['channel_name'];
  final hasVideo = callData['has_video'] ?? false;

  // 1. Mettre à jour le statut dans call_history
  await _supabase
      .from('call_history')
      .update({
        'status': 'active',
        'answered_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', callId);

  // 2. Générer un token Agora
  final tokenResponse = await _supabase.functions.invoke(
    'agora-token',
    body: {
      'channelName': channelName,
      'role': 'publisher',  // IMPORTANT: publisher pour audio bidirectionnel
    },
  );
  final token = tokenResponse.data['token'];
  final uid = tokenResponse.data['uid'];

  // 3. Rejoindre le canal Agora
  await agoraEngine.joinChannel(
    token: token,
    channelId: channelName,
    uid: uid,
    options: ChannelMediaOptions(
      clientRoleType: ClientRoleType.clientRoleBroadcaster,
      channelProfile: ChannelProfileType.channelProfileCommunication,
      autoSubscribeAudio: true,
      autoSubscribeVideo: hasVideo,
      publishMicrophoneTrack: true,
      publishCameraTrack: hasVideo,
    ),
  );

  // 4. Naviguer vers l'écran d'appel actif
  Navigator.pushReplacement(context, MaterialPageRoute(
    builder: (_) => ActiveCallScreen(
      callId: callId,
      channelName: channelName,
      callerName: callData['caller_name'] ?? 'Centre d\'Appels',
      hasVideo: hasVideo,
    ),
  ));
}
```

### 5. Refuser l'appel

```dart
Future<void> rejectCall(Map<String, dynamic> callData) async {
  await _supabase
      .from('call_history')
      .update({
        'status': 'missed',
        'ended_at': DateTime.now().toUtc().toIso8601String(),
        'ended_by': 'citizen_rejected',
      })
      .eq('id', callData['id']);
}
```

### 6. Raccrocher (après avoir décroché)

```dart
Future<void> hangUp(String callId, String answeredAt) async {
  final now = DateTime.now().toUtc();
  final answered = DateTime.parse(answeredAt);
  final duration = now.difference(answered).inSeconds;

  await _supabase
      .from('call_history')
      .update({
        'status': 'completed',
        'ended_at': now.toIso8601String(),
        'ended_by': 'citizen_hangup',
        'duration_seconds': duration,
      })
      .eq('id', callId);

  // Quitter le canal Agora
  await agoraEngine.leaveChannel();
}
```

### 7. Intégration dans le lifecycle de l'app

```dart
// Dans main.dart ou le provider principal
class AppState extends ChangeNotifier {
  late IncomingCallListener _callListener;

  void initCallListener() {
    _callListener = IncomingCallListener(Supabase.instance.client);
    _callListener.onIncomingCall = (callData) {
      // Afficher l'écran d'appel entrant
      // Si l'app est en arrière-plan, utiliser les notifications push
      // comme signal de réveil (voir send-call-push Edge Function)
      _showIncomingCallScreen(callData);
    };
    _callListener.startListening();
  }

  @override
  void dispose() {
    _callListener.stopListening();
    super.dispose();
  }
}
```

### 8. Notifications Push (complément pour app en arrière-plan)

L'Edge Function `send-call-push` envoie déjà un push FCM lors de l'insertion dans `call_history`. Le payload contient :

```json
{
  "data": {
    "type": "incoming_call",
    "callId": "uuid-de-l-appel",
    "channelName": "CALL-abc12345-1234567890",
    "callerName": "Opérateur Jean",
    "hasVideo": "false"
  }
}
```

**Action requise côté Flutter** :
- Le `FirebaseMessagingService` doit intercepter ce data message
- Afficher une notification haute priorité (heads-up) ou déclencher CallKit/ConnectionService
- Au tap sur la notification → ouvrir l'écran d'appel entrant avec les données du payload
- Si l'app est au premier plan, le Realtime listener suffira (pas besoin du push)

---

## Checklist de vérification

- [ ] Le `citizen_id` dans `call_history` correspond bien à `auth.users.id` (UUID Auth), PAS à `users_directory.id`
- [ ] Le Realtime écoute les INSERT avec filtre `citizen_id = currentUser.id`
- [ ] Le mobile met à jour `call_history.status` à `'active'` quand l'utilisateur décroche
- [ ] Le mobile rejoint le canal Agora en mode `clientRoleBroadcaster` (pas subscriber)
- [ ] Le token Agora est généré via l'Edge Function `agora-token` avec `role: 'publisher'`
- [ ] Le mobile détecte quand l'opérateur raccroche (UPDATE status → completed/missed)
- [ ] Le FCM data message déclenche CallKit/ConnectionService en arrière-plan
- [ ] Timeout de 45s si pas de réponse → auto-refuser
- [ ] L'écran d'appel affiche le nom de l'opérateur (`caller_name`)
- [ ] Le son de sonnerie et la vibration fonctionnent

---

## Tables et fonctions Supabase concernées

| Élément | Usage |
|---------|-------|
| `call_history` | Source de vérité pour la signalisation (INSERT = sonnerie, UPDATE = état) |
| `call_history.citizen_id` | Filtre Realtime pour cibler le bon utilisateur mobile |
| `call_history.channel_name` | Nom du canal Agora à rejoindre |
| `call_history.call_type` | `'outgoing'` = émis par le centre (entrant pour le mobile) |
| `call_history.has_video` | Détermine si c'est audio ou vidéo |
| Edge Function `agora-token` | Génération du token RTC pour rejoindre le canal |
| Edge Function `send-call-push` | Push FCM pour réveiller l'app en arrière-plan |

---

## Constantes Supabase

```dart
// Ces valeurs sont déjà dans votre configuration
const supabaseUrl = 'https://npucuhlvoalcbwdfedae.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
const agoraAppId = 'e2e0e5a6ef0d4ce3b2ab9efad48d62cf';
```

---

## Rôles concernés

Ce système de réception d'appels s'applique à **TOUS les rôles** de l'application mobile :

| Rôle | Peut recevoir des appels du centre ? |
|------|--------------------------------------|
| `citoyen` | ✅ Oui — rappels, suivi d'incidents |
| `secouriste` | ✅ Oui — coordination terrain |
| `volontaire` | ✅ Oui — mobilisation |
| `hopital` | ✅ Oui — coordination transferts patients |

Le filtrage se fait uniquement par `citizen_id` (qui est en réalité l'`auth_user_id` de n'importe quel utilisateur, pas seulement les citoyens). Le nom du champ est historique.

---

## Erreurs courantes à éviter

1. **Ne PAS utiliser `users_directory.id` comme `citizen_id`** — utiliser `auth.users.id` (le UUID d'authentification)
2. **Ne PAS rejoindre le canal Agora en mode `subscriber`** — utiliser `broadcaster` sinon l'audio ne passera pas dans les deux sens
3. **Ne PAS créer un nouveau canal Agora** — utiliser le `channel_name` existant de `call_history`
4. **Ne PAS oublier de mettre à jour `call_history`** avant de rejoindre Agora — le dashboard surveille le statut pour savoir que l'appel a été accepté
5. **Ne PAS ignorer le push FCM** — le Realtime ne fonctionne que si l'app est au premier plan avec une connexion WebSocket active
