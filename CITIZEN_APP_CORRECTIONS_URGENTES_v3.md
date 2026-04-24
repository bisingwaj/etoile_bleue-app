# 🚨 CITIZEN APP — Corrections urgentes v3 (post-audit dashboard 24/04/2026)

> **Audience** : équipe Flutter app citoyen.
> **Priorité** : P0 — à appliquer avant prochain release.
> **Référence longue** : `CITIZEN_APP_CALL_LIFECYCLE_SYNC.md` v3.0 et `CITIZEN_APP_CALLS_HANGUP_PROTOCOL.md` v3.
>
> Ce document est la **checklist condensée** des corrections à faire côté mobile pour s'aligner sur le contrat unifié du dashboard. Si vous appliquez ces 7 points, les sonneries fantômes disparaissent.

---

## ✅ Checklist des 7 corrections obligatoires

### 1. ❌ Supprimer tout usage des statuts `ended` / `cancelled` / `abandoned`

**Bug** : votre code écrit `status: 'ended'` ou `'cancelled'` dans `call_history`. Ces valeurs **n'existent pas** dans l'enum Postgres `call_status`. Vos UPDATE échouent en `22P02 invalid_input_value` silencieusement → l'appel reste `ringing` côté centre → sonnerie fantôme.

**Enum réel** (immuable) :
```
ringing | active | completed | missed | failed
```

**Action** :
```dart
// ❌ AVANT
.update({'status': 'ended'})
.update({'status': 'cancelled'})
.update({'status': 'abandoned'})

// ✅ APRÈS — un seul terminal autorisé côté citoyen
.update({'status': 'completed', 'ended_at': nowUtc, 'ended_by': 'citizen'})
```

`missed` et `failed` sont **réservés au watchdog serveur**. N'y touchez jamais.

---

### 2. ❌ Ne JAMAIS écrire `status: 'active'` depuis le mobile

**Bug** : certaines versions de l'app passaient `ringing → active` au moment du `joinChannel` Agora ou du heartbeat. **Interdit**.

**Règle** : seul le **dashboard** transite `ringing → active` via la RPC atomique `claim_incoming_call` (au moment où l'opérateur décroche). Le mobile **constate** la transition via Realtime et bascule l'UI.

**Action** :
```dart
// ❌ AVANT
await supabase.from('call_history').update({'status': 'active'}).eq('channel_name', ch);

// ✅ APRÈS — écouter Realtime et basculer l'UI quand le dashboard fait la transition
supabase.channel('call-$channelName')
  .onPostgresChanges(
    event: PostgresChangeEvent.update,
    schema: 'public',
    table: 'call_history',
    filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'channel_name', value: channelName),
    callback: (payload) {
      final newStatus = payload.newRecord['status'];
      if (newStatus == 'active') showInCallUI();
      if (['completed', 'missed', 'failed'].contains(newStatus)) closeCallScreen();
    },
  )
  .subscribe();
```

---

### 3. ✅ Remplacer `UPDATE updated_at` par la RPC `citizen_call_heartbeat`

**Bug** : votre heartbeat fait `UPDATE call_history SET updated_at = now()`. Cette colonne est gérée par trigger : votre UPDATE direct est rejeté par RLS dans 80 % des cas.

**Action — toutes les 10 s pendant `ringing` ET `active`** :
```dart
Timer.periodic(const Duration(seconds: 10), (_) async {
  try {
    await supabase.rpc('citizen_call_heartbeat', params: {'p_channel_name': channelName});
  } catch (e) {
    debugPrint('[heartbeat] failed: $e'); // best-effort
  }
});
```

⚠️ Le heartbeat **ne change PAS le statut**. Il prouve juste votre présence. Sans heartbeat, le watchdog serveur ferme l'appel en 60 s (ringing) ou 90 s (active).

---

### 4. ✅ Recovery orphelin obligatoire au boot de l'app

**Bug** : si l'app crashe pendant un appel, l'enregistrement reste `ringing` ou `active` côté serveur jusqu'au passage du watchdog (max 90 s). Pendant ce temps, l'utilisateur ne peut pas relancer un SOS (déduplication d'incident bloque).

**Action — au démarrage de l'app, après login** :
```dart
Future<void> recoverOrphanCalls() async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return;

  final orphans = await supabase
    .from('call_history')
    .select('id, channel_name, status, updated_at')
    .eq('citizen_id', userId)
    .inFilter('status', ['ringing', 'active'])
    .lt('updated_at', DateTime.now().toUtc().subtract(const Duration(seconds: 30)).toIso8601String());

  for (final orphan in orphans as List) {
    await supabase.from('call_history').update({
      'status': 'completed',
      'ended_at': DateTime.now().toUtc().toIso8601String(),
      'ended_by': 'citizen_recovery',
    }).eq('id', orphan['id']);
  }
}
```

---

### 5. ✅ Hangup idempotent (`.neq('status', 'completed')`)

**Bug** : si le serveur a déjà clôturé l'appel via watchdog, votre UPDATE `completed` rouvre une race condition.

**Action** :
```dart
await supabase.from('call_history').update({
  'status': 'completed',
  'ended_at': DateTime.now().toUtc().toIso8601String(),
  'ended_by': 'citizen',
})
.eq('channel_name', channelName)
.neq('status', 'completed'); // ✅ idempotent — n'écrase pas un état terminal serveur
```

Toujours faire l'UPDATE **AVANT** `agoraEngine.leaveChannel()` pour minimiser la fenêtre fantôme.

---

### 6. ✅ Listener Realtime — terminal = `{completed, missed, failed}` UNIQUEMENT

**Bug** : votre listener écoute encore `ended` ou `cancelled`. Ces statuts ne seront **jamais** émis. Votre écran d'appel ne se ferme pas quand l'opérateur raccroche.

**Action** :
```dart
const terminalStatuses = {'completed', 'missed', 'failed'};

if (terminalStatuses.contains(newStatus)) {
  closeCallScreen();
  await agoraEngine.leaveChannel();
}
```

---

### 7. ✅ Anti-doublon SOS — gérer l'erreur `P0001 Duplicate incident`

**Comportement serveur** : le trigger `trg_deduplicate_incident` bloque toute création d'un nouvel incident si un incident `ringing/active` existe déjà pour ce citoyen (fenêtre 5 min).

**Action — au lieu de retry, REJOIGNEZ le canal existant** :
```dart
try {
  await createIncidentAndCall();
} on PostgrestException catch (e) {
  if (e.code == 'P0001' || e.message.contains('Duplicate incident')) {
    final existing = await supabase
      .from('call_history')
      .select('channel_name, agora_token')
      .eq('citizen_id', userId)
      .inFilter('status', ['ringing', 'active'])
      .order('created_at', ascending: false)
      .limit(1)
      .maybeSingle();

    if (existing != null) {
      await joinAgoraChannel(existing['channel_name'], existing['agora_token']);
    }
  }
}
```

---

## 📊 Tableau récapitulatif des SLO

| Événement | Détection serveur | Action serveur |
|---|---|---|
| `ringing` sans heartbeat 10 s | 60 s | UPDATE → `missed` (`ended_by='watchdog_no_heartbeat'`) |
| `active` sans heartbeat 10 s | 90 s | UPDATE → `completed` (`ended_by='watchdog_no_heartbeat'`) |
| `call_queue` orpheline (sans `call_history` vivant) | 90 s | UPDATE → `abandoned` (côté **`call_queue`** uniquement) |
| Hangup propre citoyen | < 200 ms | Trigger ferme `call_queue` + Realtime broadcast au centre |

⚠️ Note : `abandoned` existe uniquement sur la table **`call_queue`**, **PAS** sur `call_history`. Ne pas confondre.

---

## 🧪 Tests manuels à exécuter avant release

1. **Hangup propre** : décrocher → raccrocher au bout de 5 s → vérifier que la fiche disparaît du centre en < 1 s.
2. **Kill app pendant ringing** : forcer kill app → vérifier que la sonnerie centre disparaît en ≤ 60 s.
3. **Kill app pendant active** : forcer kill app → vérifier que l'appel passe à `completed` en ≤ 90 s.
4. **Reload dashboard** : déclencher SOS → reload dashboard côté centre → vérifier que la sonnerie ne réapparaît PAS si raccrochée.
5. **Doublon SOS** : déclencher SOS, killer juste après → relancer SOS dans les 30 s → vérifier qu'on rejoint le canal existant (pas d'erreur).
6. **Heartbeat coupé** : couper le wifi pendant `ringing` → vérifier passage `missed` à 60 s côté serveur.

---

## 🆘 Support

Si un de ces 7 points ne fonctionne pas après implémentation, vérifier en priorité :
- Les logs `edge-functions` Supabase pour erreurs `22P02`.
- La query SQL : `SELECT id, status, ended_by, updated_at FROM call_history WHERE citizen_id = '...' ORDER BY created_at DESC LIMIT 5;`
- Le `ended_by` doit être `citizen` (hangup propre) ou `watchdog_no_heartbeat` (kill silencieux). Tout autre valeur = bug mobile.
