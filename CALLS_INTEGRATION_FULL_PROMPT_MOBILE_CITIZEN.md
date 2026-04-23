# PROMPT D'INTÉGRATION COMPLÈTE — GESTION DES APPELS (App Citoyen + App Mobile Secouriste/Hôpital)

> **Public cible** : équipes mobiles (Flutter Citoyen, Flutter Secouriste, Flutter Hôpital).
> **Objectif** : aligner toutes les apps mobiles sur le contrat unifié de gestion des appels du dashboard PABX (centre d'appels Étoile Bleue / EBRDC).
> **Version** : v4 (claim_incoming_call v4 + propagation temps réel durcie).
> **Date** : 2026-04-23.

---

## 0. TL;DR (à lire en priorité)

1. Toute la signalisation d'appel transite par **Supabase Realtime** sur la table `call_history`. Le **PUSH FCM** est juste un réveil — il ne porte pas l'état canonique.
2. Le **canal Agora** = `channel_name` de `call_history`. Toujours utiliser ce nom exact pour `agora-token` et `RtcEngine.joinChannel`.
3. **Aucune app ne doit insérer un nouveau `call_history` si un `ringing` ou `active` du même canal existe déjà** (anti-doublon obligatoire).
4. Quand un appel passe à `completed`, `missed`, `failed`, ou `active` (pris par quelqu'un d'autre) : **arrêter immédiatement la sonnerie**, fermer la UI d'appel entrant, libérer le micro/caméra.
5. Pour décrocher un appel entrant (citoyen prenant un appel sortant de la centrale, secouriste prenant un broadcast interne, etc.), appeler le RPC **`claim_incoming_call`** (côté secouriste/centre, pas côté citoyen) et gérer les codes : `already_mine`, `taken_by_other`, `call_ended`.

---

## 1. Architecture globale des appels

```
                ┌─────────────────────────────────────────────────────┐
                │   SOURCE DE VÉRITÉ : Supabase Postgres + Realtime    │
                │   - call_history  (état canonique de chaque appel)   │
                │   - call_queue    (file d'attente côté centre)       │
                │   - incidents     (contexte SOS sous-jacent)         │
                └─────────────┬───────────────────────────────────────┘
                              │ Realtime (postgres_changes)
              ┌───────────────┼───────────────┐
              │               │               │
        ┌─────▼─────┐   ┌─────▼─────┐   ┌─────▼──────┐
        │ Dashboard │   │ App Mobile│   │ App Citoyen│
        │  PABX     │   │ Secouriste│   │  (Flutter) │
        │  (React)  │   │ / Hôpital │   │            │
        └─────┬─────┘   └─────┬─────┘   └─────┬──────┘
              │               │               │
              └───────► Agora RTC ◄────────────┘
                  (audio/vidéo via channel_name)
```

**Couches :**
- **Signalisation** : Supabase Realtime sur `call_history`.
- **Réveil** : FCM data-only push (déclenché par trigger Postgres `trg_call_push_notification`).
- **Média** : Agora RTC, channel = `call_history.channel_name`, token = edge function `agora-token`.

---

## 2. Sources de vérité

### 2.1 `call_history` — état canonique de chaque appel
| Colonne | Rôle |
|---|---|
| `id` (uuid) | identifiant unique de l'appel |
| `channel_name` (text) | **canal Agora** ; identifiant fonctionnel partagé entre tous les acteurs |
| `call_type` | `incoming` (citoyen → centre), `outgoing` (centre → citoyen/unité), `internal` (secouriste → centre), `field` (centre → unité) |
| `status` | `ringing`, `active`, `completed`, `missed`, `failed`, `abandoned` |
| `caller_name`, `caller_phone`, `caller_lat`, `caller_lng` | identité + position de l'appelant |
| `citizen_id` | uuid du citoyen (FK `users_directory`) si applicable |
| `operator_id` | opérateur centre ayant pris l'appel |
| `incident_id` | incident SOS lié (optionnel) |
| `agora_token`, `agora_uid` | token Agora pré-calculé (sinon appeler `agora-token`) |
| `has_video` | true si vidéo, false si audio seul |
| `started_at`, `answered_at`, `ended_at`, `duration_seconds` | horodatages |
| `ended_by` | identifiant de qui a raccroché (`citizen`, `operator`, `system_cleanup`, …) |
| `role` | rôle métier de l'appelant (`citoyen`, `secouriste`, `hopital`, `volontaire`, …) |

### 2.2 `call_queue` — file d'attente du centre (interne au dashboard)
Les apps mobiles **ne lisent ni n'écrivent jamais** dans `call_queue`. Cette table est interne au centre d'appels.

### 2.3 `incidents` — contexte SOS sous-jacent
| Colonne clé | Rôle |
|---|---|
| `id`, `reference` | identifiants ; `reference` = `channel_name` quand SOS |
| `status` | `new`, `pending`, `in_progress`, `dispatched`, `en_route`, `on_scene`, `at_hospital`, `mission_end`, `ended`, `resolved`, `archived`, `declasse` |
| `assigned_operator_id` | opérateur ayant pris l'incident |
| `citizen_id` | propriétaire de l'incident |
| `caller_realtime_lat/lng` | dernière position GPS connue |

---

## 3. États normalisés des appels (`call_history.status`)

| Statut | Sens fonctionnel |
|---|---|
| `ringing` | l'appel sonne ; pas encore décroché |
| `active` | un opérateur a décroché ; conversation en cours |
| `completed` | terminé proprement par l'un des participants |
| `missed` | jamais décroché (timeout, fermeture, raccroché par appelant) |
| `failed` | erreur réseau / Agora |
| `abandoned` | annulé avant prise (équivalent missed côté centre) |

---

## 4. Transitions autorisées

```
ringing  ──► active     (décroché par opérateur / unité)
ringing  ──► missed     (timeout, raccroché avant prise)
ringing  ──► failed     (erreur Agora / réseau)
active   ──► completed  (un participant raccroche)
active   ──► failed     (perte signalisation)
```

**Interdit :**
- `completed` → toute autre valeur
- `missed`/`failed` → `ringing` ou `active`

⚠️ Une fois sortie de `ringing`, une ligne **ne doit plus jamais y revenir**. Un nouveau cycle = un nouveau `call_history`.

---

## 5. Contrat temps réel (Supabase Realtime)

Chaque app s'abonne à `postgres_changes` sur `public.call_history` filtré par identité :

### App Citoyen
```dart
supabase.channel('citizen-calls-${citizenId}')
  .onPostgresChanges(
    event: PostgresChangeEvent.all,
    schema: 'public',
    table: 'call_history',
    filter: PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'citizen_id',
      value: citizenId,
    ),
    callback: handleCallEvent,
  )
  .subscribe();
```

### App Secouriste / Hôpital
S'abonner sur les appels où `operator_id = currentAuthUid` **ET** sur les broadcasts (`call_type = 'internal'` ou `call_type = 'field'` avec `incident_id` lié à l'unité).

### Règles côté mobile
- `INSERT` avec `status = 'ringing'` → **afficher la UI d'appel entrant + démarrer la sonnerie**.
- `UPDATE` vers `active` par un opérateur **autre que moi** → **arrêter sonnerie, fermer UI** (je n'ai plus rien à décrocher).
- `UPDATE` vers `completed` / `missed` / `failed` / `abandoned` → **arrêter sonnerie, fermer UI, libérer média**.
- `DELETE` sur la ligne (rare) → idem fermeture totale.

---

## 6. Contrat push FCM (data-only)

Le trigger Postgres `trg_call_push_notification` envoie automatiquement une notification FCM **data-only** à l'insertion d'un `call_history` `ringing`.

### Payload
```json
{
  "data": {
    "type": "incoming_call",
    "channel_name": "SOS-1776956812722",
    "call_id": "<uuid>",
    "call_type": "incoming",
    "caller_name": "Centre EBRDC",
    "caller_phone": "+243...",
    "has_video": "false",
    "incident_id": "<uuid|null>",
    "priority": "high"
  },
  "android": { "priority": "high" },
  "apns": { "headers": { "apns-priority": "10", "apns-push-type": "voip" } }
}
```

### Règles côté mobile
- **iOS** : utiliser **CallKit** (PushKit VoIP) pour réveiller l'app et afficher l'écran natif.
- **Android** : utiliser **ConnectionService** + service foreground pour afficher la notification en heads-up même app fermée.
- **Le push ne sert qu'à réveiller** : la vérité reste `call_history`. Au réveil, requeter immédiatement la ligne par `call_id` et écouter Realtime pour les changements.
- Si à l'ouverture la ligne est déjà `completed`/`missed`/`failed`/`active` → **annuler immédiatement la UI d'appel** (CallKit `endCall` / ConnectionService `setDisconnected`).

---

## 7. Règles anti-doublon

**JAMAIS d'INSERT `call_history` avec `status='ringing'` si une ligne `ringing` ou `active` existe déjà pour le même `channel_name`.**

Vérifier avant insert :
```sql
SELECT id, status FROM call_history
 WHERE channel_name = $1
   AND status IN ('ringing', 'active')
 ORDER BY created_at DESC LIMIT 1;
```
- Si présent et `ringing` → ne pas insérer ; réutiliser la ligne existante.
- Si présent et `active` → ne pas insérer ; l'appel est déjà décroché, ignorer.

Côté centre, il existe une garde de **10 secondes** dans les edge functions `call-rescuer`, `citizen-call-rescuer`, `rescuer-call-citizen` qui bloque tout doublon dans cette fenêtre.

---

## 8. Règles de prise d'appel

### 8.1 Côté centre (dashboard) — déjà implémenté
Appel du RPC :
```ts
await supabase.rpc("claim_incoming_call", { p_channel_name });
```

### 8.2 Côté secouriste mobile (broadcast interne / appel reçu de la centrale)
**Idem** : appeler `claim_incoming_call` AVANT de joindre Agora.

```dart
final claim = await supabase.rpc('claim_incoming_call',
  params: {'p_channel_name': channelName});
final result = claim as Map<String, dynamic>;

if (result['success'] == true) {
  if (result['already_mine'] == true) {
    // Reprise après reload — joindre Agora silencieusement
  }
  // → joindre Agora
} else {
  switch (result['error']) {
    case 'taken_by_other':
      showToast('Pris par ${result['taken_by_operator_name']}');
      closeIncomingUI();
      break;
    case 'call_ended':
      showToast('Cet appel est terminé');
      closeIncomingUI();
      break;
    default:
      showToast('Impossible de prendre cet appel');
      closeIncomingUI();
  }
}
```

### 8.3 Côté citoyen
Le citoyen **ne fait pas** de claim (il n'y a qu'un destinataire de son côté). Il :
1. reçoit la notification push,
2. lit `call_history` par `call_id`,
3. si `status = 'ringing'` → affiche CallKit/ConnectionService,
4. à l'acceptation : `UPDATE call_history SET status='active', answered_at=now()` **uniquement si `status = 'ringing'`** (clause idempotente),
5. joint Agora.

### 8.4 Codes de retour `claim_incoming_call` (v4)

| code | sens | action UI |
|---|---|---|
| `success: true, already_mine: false` | claim normal | continuer la prise d'appel |
| `success: true, already_mine: true` | l'appel est déjà à moi (reload, retry) | continuer **silencieusement** sans toast |
| `error: 'taken_by_other'` + `taken_by_operator_name` | un autre a pris | toast `Pris par X` + retirer de la file |
| `error: 'call_ended'` | terminé/abandonné | toast `Cet appel est terminé` + retirer de la file |
| `error: 'unauthenticated'` | session expirée | rediriger vers login |
| `error: 'operator_not_found'` | l'utilisateur n'est pas opérateur | toast d'erreur |

---

## 9. Disparition immédiate d'un appel pris ailleurs

**Règle absolue** : dès qu'une ligne `call_history` passe de `ringing` à un autre statut, **toutes les apps qui voyaient cet appel doivent fermer la UI d'appel entrant et arrêter la sonnerie en moins de 1 seconde**.

Implémentation mobile :
```dart
void onCallHistoryUpdate(PostgresChangePayload payload) {
  final newStatus = payload.newRecord['status'] as String;
  final channel = payload.newRecord['channel_name'] as String;

  if (newStatus != 'ringing') {
    // Stop ringtone
    Ringtone.stop();
    // End CallKit / ConnectionService
    CallKit.endCall(channel);
    // Close UI
    Navigator.popUntil(context, (r) => r.settings.name != '/incoming-call');
    // Free mic/camera if not the operator
    if (payload.newRecord['operator_id'] != currentUid) {
      Agora.leaveChannel();
    }
  }
}
```

---

## 10. Gestion des erreurs côté mobile (mapping unifié)

| Source | Erreur | Action UI |
|---|---|---|
| `claim_incoming_call` | `taken_by_other` | toast bref + fermer UI |
| `claim_incoming_call` | `call_ended` | toast bref + fermer UI |
| `claim_incoming_call` | `unauthenticated` | logout + redirect login |
| `agora-token` (edge fn) | 401 | refresh session + retry 1× |
| `agora-token` | 5xx | toast + retry exponentiel max 3× |
| Realtime déconnecté | — | reconnecter avec backoff exponentiel (1s → 30s max) |
| FCM token expiré | — | régénérer + UPDATE `users_directory.fcm_token` |

---

## 11. Comportement attendu — App Citoyen

1. **Au démarrage** : enregistrer le `fcm_token` dans `users_directory`.
2. **Souscrire** Realtime à `call_history` filtré par `citizen_id`.
3. **À la réception d'un push `incoming_call`** :
   - Réveiller l'app (CallKit / ConnectionService),
   - Charger `call_history` par `call_id`,
   - Si `ringing` → afficher écran d'appel entrant + sonnerie,
   - Si déjà `active`/`completed`/etc. → ne rien afficher.
4. **À l'acceptation** : passer `call_history.status = 'active'` (clause `WHERE status='ringing'`), demander permission micro/caméra, joindre Agora avec token de `agora-token`.
5. **Au raccroché** : `UPDATE call_history SET status='completed', ended_at=now(), ended_by='citizen', duration_seconds=…`.
6. **Sur `UPDATE` Realtime → status hors `ringing`** alors que je suis sur l'écran d'appel entrant : fermer immédiatement.

---

## 12. Comportement attendu — App Secouriste / Hôpital Mobile

1. Login via `agent-login` (PIN 6 chiffres).
2. Souscrire Realtime à `call_history` filtré par `operator_id = currentAuthUid` ET aux broadcasts ciblant l'unité (`call_type='internal'` ou `call_type='field'` avec `incident_id` ∈ mes dispatches actifs).
3. À la réception d'un `ringing` → push + sonnerie + UI.
4. **Avant d'accepter** : appeler `claim_incoming_call`. Gérer les 4 codes de retour (cf §8.4).
5. Si succès : récupérer token via `agora-token` puis joindre Agora.
6. Au raccroché : `UPDATE call_history SET status='completed', ended_at=now(), ended_by=role`.
7. Sur tout `UPDATE` qui sort de `ringing` sans que ce soit moi → fermer UI immédiatement.

---

## 13. Comportement attendu — Dashboard PABX (déjà en place)

- File reconstruite à partir de `call_queue` + fallback `incidents` + fallback `call_history` ringing.
- Filtre dur : un appel n'apparaît plus s'il est `completed`/`abandoned`, si l'incident lié est en statut terminal, ou s'il est claimé par un autre opérateur.
- À la prise : `claim_incoming_call` → arrêt sonnerie immédiat → optimistic remove de la file → join Agora.
- Sur `UPDATE` Realtime sortant de `ringing` : `markChannelTerminated` + arrêt sonnerie tous opérateurs.

---

## 14. Edge functions concernées

| Edge function | Rôle | À appeler depuis mobile ? |
|---|---|---|
| `agora-token` | Génère un token Agora pour un `channel_name` + `uid` | **Oui** (toujours, juste avant `joinChannel`) |
| `send-call-push` | Envoie un FCM data-only à un destinataire | Non (déclenché par trigger PG) |
| `call-rescuer` | Centre → secouriste : insère `call_history` + push | Non (dashboard uniquement) |
| `citizen-call-rescuer` | Citoyen → secouriste assigné : insère `call_history` + push | **Oui** (depuis app citoyen) |
| `rescuer-call-citizen` | Secouriste → citoyen de la mission : insère `call_history` + push | **Oui** (depuis app secouriste) |

### Contrat invocation
Toujours via le SDK Supabase :
```dart
final res = await supabase.functions.invoke(
  'agora-token',
  body: {'channelName': channel, 'uid': agoraUid, 'role': 'publisher'},
);
final token = res.data['token'] as String;
```

---

## 15. Synchro Agora / Realtime / Push — règles d'or

1. **Source de vérité = `call_history`**. Push et Agora sont des conséquences, jamais l'inverse.
2. **Le `channel_name` est immuable** sur toute la durée de l'appel. Ne jamais le réinventer côté mobile.
3. **Token Agora à générer juste avant `joinChannel`**, jamais en avance (durée 1h max).
4. **Toujours appeler `leaveChannel` + `release()` Agora** quand `call_history.status` sort de `active`.
5. **Réabonnement Realtime obligatoire** après chaque retour foreground (résume), avec backoff exponentiel.
6. **Une seule session active à la fois** par utilisateur : si un nouveau `ringing` arrive alors qu'un `active` existe pour moi, ignorer le nouveau ou afficher un badge "appel en attente" — ne jamais le décrocher en parallèle.

---

## 16. Cas limites & scénarios de reprise

| Scénario | Attendu |
|---|---|
| App citoyen tuée pendant `ringing` | Push réveille → UI s'affiche → si entre temps `completed`, refermer immédiatement. |
| Reload du dashboard avec `active` en cours | `claim_incoming_call` retourne `already_mine` → reprise silencieuse, ré-injection dans la UI. |
| Push reçu mais réseau coupé | Mettre la UI en attente avec spinner ; au retour réseau, fetch `call_history` + Realtime resume. |
| Crash Agora pendant `active` | `UPDATE call_history SET status='failed', ended_at=now(), ended_by='agora_crash'`. |
| Doublon `ringing` reçu (race FCM) | Vérifier en base avant INSERT ; ignorer le doublon. |
| Opérateur quitte sans raccrocher | Cron `cleanup_stale_queue_entries` ferme après 10 min (ringing) / 30 min (queue). |
| Incident résolu en parallèle | Ligne `call_history` passe `completed` via trigger ; mobile reçoit l'event → fermer UI. |

---

## 17. Checklist d'implémentation (par app)

### App Citoyen
- [ ] FCM enregistré + token sauvegardé dans `users_directory.fcm_token`
- [ ] Service VoIP (CallKit iOS / ConnectionService Android) opérationnel app fermée
- [ ] Realtime `call_history` filtré par `citizen_id`
- [ ] Anti-doublon : ne pas afficher 2× la même UI si push + realtime arrivent ensemble
- [ ] Fermeture UI immédiate si `status` sort de `ringing` sans que ce soit moi
- [ ] `agora-token` appelé juste avant `joinChannel`
- [ ] `UPDATE call_history` à l'acceptation et au raccroché (idempotent)
- [ ] Libération micro/caméra/Agora à la fermeture de l'écran d'appel

### App Secouriste / Hôpital
- [ ] Idem ci-dessus +
- [ ] `claim_incoming_call` AVANT joinChannel sur tout appel entrant
- [ ] Mapping des 4 codes de retour (`already_mine` silencieux, `taken_by_other` → toast nom, `call_ended` → toast, défaut → toast générique)
- [ ] Filtre des broadcasts : seulement si l'incident est dans mes dispatches actifs
- [ ] Pas de claim depuis l'app citoyen

---

## 18. Matrice de tests bout-en-bout

| # | Scénario | Préconditions | Attendu |
|---|---|---|---|
| 1 | Citoyen reçoit un appel entrant centre → décroche | App fermée | Push reçu, CallKit s'affiche, accept → Agora joint, audio bidir |
| 2 | Secouriste prend un broadcast interne | 2 secouristes en ligne | Le 1er à claimer obtient l'appel, le 2nd voit la UI se fermer instantanément |
| 3 | Centre prend un appel pendant qu'un autre opérateur tente aussi | 2 opérateurs cliquent simultanément | 1 succès, 1 toast `Pris par X` |
| 4 | Reload dashboard pendant un appel actif | Opérateur connecté avec call active | Reprise silencieuse via `already_mine` |
| 5 | Citoyen raccroche pendant que centre n'a pas décroché | Push envoyé | call_history → `missed`, sonnerie centre s'arrête immédiatement |
| 6 | Réseau coupé côté secouriste pendant `active` | Appel en cours | À reconnexion, status récupéré ; si déjà `completed` → fermer UI |
| 7 | Doublon FCM (push reçu 2×) | App ouverte + push background | Une seule UI d'appel affichée |
| 8 | Incident résolu par un autre opérateur pendant ringing | Appel SOS en attente | UI ferme + sonnerie stop sur tous les autres dashboards |
| 9 | Citoyen change de réseau pendant Agora | Appel actif | Agora gère reconnexion ; si échec > 30s, status `failed` |
| 10 | Cleanup automatique d'un ringing orphelin | App fermée + push raté | Après 10 min, status passe à `missed`, plus de fantôme |

---

## Annexes

### A. Schéma minimal `call_history` à manipuler côté mobile
```typescript
type CallHistoryRow = {
  id: string;
  channel_name: string;
  call_type: 'incoming' | 'outgoing' | 'internal' | 'field';
  status: 'ringing' | 'active' | 'completed' | 'missed' | 'failed' | 'abandoned';
  caller_name: string | null;
  caller_phone: string | null;
  caller_lat: number | null;
  caller_lng: number | null;
  citizen_id: string | null;
  operator_id: string | null;
  incident_id: string | null;
  has_video: boolean;
  agora_token: string | null;
  agora_uid: number | null;
  started_at: string;
  answered_at: string | null;
  ended_at: string | null;
  duration_seconds: number | null;
  ended_by: string | null;
  role: string | null;
  created_at: string;
};
```

### B. Référence rapide RPC `claim_incoming_call`
- **Signature** : `claim_incoming_call(p_channel_name text) → jsonb`
- **Auth** : `SECURITY DEFINER`, exige `auth.uid()`.
- **Idempotent** : oui (`already_mine: true`).
- **Réponse succès** : `{ success: true, already_mine: bool, channel_name, incident_id, call_id, queue_id }`.
- **Réponse erreur** : `{ success: false, error: string, taken_by_operator_name?, taken_by_operator_id? }`.

### C. Cron côté centre
- `cleanup_stale_queue_entries()` exécuté toutes les minutes via `pg_cron`.
- Ferme : queue ringing > 30 min, call_history ringing orphelin > 10 min, incidents in_progress orphelins > 30 min.

---

**Fin du prompt. Toute déviation par rapport à ce contrat doit être validée avec l'équipe backend du dashboard PABX avant implémentation.**
