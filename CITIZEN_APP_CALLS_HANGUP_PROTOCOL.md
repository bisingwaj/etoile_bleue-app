# 📞 CITIZEN APP — Protocole de raccrochage & cycle de vie des appels SOS

> **Pré-requis** : ce document complète `MOBILE_APPS_PLATFORM_UPDATES.md` (buckets, RLS, HIBP, structures) et `CITIZEN_APP_CHANNEL_NAME_INVARIANT.md` (invariant `channel_name`). Ne reprend QUE le cycle de vie des appels SOS post-refactor du centre d'appels.

---

## 1. Contexte & urgence

Avant le refactor : un raccrochage citoyen mal géré laissait l'appel **en `ringing` côté centre** pendant des minutes (parfois indéfiniment). Résultat : files d'attente fantômes, opérateurs qui décrochent dans le vide, KPIs faussés.

**Côté serveur, on a maintenant :**
- Trigger `on_call_history_status_change` qui ferme automatiquement la `call_queue` dès qu'une ligne `call_history` passe en statut terminal (`completed`, `missed`, `failed`, `ended`, `cancelled`).
- Cron 1 min `watchdog_close_stale_ringing` qui ferme tout `ringing > 5 min` ou `active` sans heartbeat depuis > 5 min.
- RPC admin `force_close_call(p_channel_name)` (utilisée côté dashboard, jamais côté mobile).
- **Important** : raccrocher **ne ferme PAS** l'incident. L'incident reste ouvert jusqu'à clôture par l'opérateur (RPC `resolve_incident`). Ne tentez plus de fermer l'incident côté citoyen.

**Côté app citoyen, vous devez :**
1. Toujours UPDATE `call_history.status` à terminal au raccrochage.
2. Écouter Realtime `call_history` pour fermer l'écran d'appel si l'opérateur raccroche.
3. (Recommandé) Pousser un heartbeat 15 s pendant un appel actif.
4. Survivre proprement aux crashs / kill app (filet de sécurité serveur garanti).

---

## 2. Hangup OBLIGATOIRE au raccrochage

Au moment où l'utilisateur tape "Raccrocher" (ou que l'appel se termine côté Agora) :

```dart
Future<void> hangupCall(String channelName) async {
  try {
    await Supabase.instance.client
      .from('call_history')
      .update({
        'status': 'completed',
        'ended_at': DateTime.now().toUtc().toIso8601String(),
        'ended_by': 'citizen',
      })
      .eq('channel_name', channelName)
      .neq('status', 'completed'); // idempotent
  } catch (e) {
    // best-effort — le watchdog serveur prendra le relais sous 30-60 s
    debugPrint('[CITIZEN] hangup update failed: $e');
  } finally {
    await agoraEngine.leaveChannel();
  }
}
```

**Règles** :
- `channel_name` doit correspondre EXACTEMENT à celui utilisé pour l'INSERT initial (cf. `CITIZEN_APP_CHANNEL_NAME_INVARIANT.md`).
- Pas besoin d'appeler la RPC `force_close_call` — réservée aux admins.
- **N'envoyez PAS** d'UPDATE sur `incidents`. Le citoyen n'a aucun droit de clôture (RLS).

### Statuts terminaux valides

| Statut       | Quand l'utiliser (côté citoyen)                                    |
|--------------|---------------------------------------------------------------------|
| `completed`  | Raccrochage normal après prise en charge.                           |
| `cancelled`  | Annulation avant que l'opérateur n'ait décroché (optionnel).        |
| `missed`     | ⚠ Réservé serveur — ne pas écrire depuis le citoyen.                |
| `failed`     | ⚠ Réservé serveur — ne pas écrire depuis le citoyen.                |
| `ended`      | ⚠ Legacy — ne plus utiliser, préférer `completed`.                  |

---

## 3. Listener Realtime — fermeture distante

Quand l'opérateur raccroche, l'écran d'appel citoyen doit se fermer **immédiatement**.

```dart
final channel = Supabase.instance.client
  .channel('citizen-call-watch-$channelName')
  .onPostgresChanges(
    event: PostgresChangeEvent.update,
    schema: 'public',
    table: 'call_history',
    filter: PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'channel_name',
      value: channelName,
    ),
    callback: (payload) {
      const terminal = ['completed', 'missed', 'failed', 'ended', 'cancelled'];
      final status = payload.newRecord['status'] as String?;
      if (status != null && terminal.contains(status)) {
        // Quitter Agora + fermer l'écran
        agoraEngine.leaveChannel();
        Navigator.of(context).pop();
        // Toast : "Appel terminé par l'opérateur" si endedBy != 'citizen'
      }
    },
  )
  .subscribe();

// À nettoyer dans dispose() : Supabase.instance.client.removeChannel(channel);
```

---

## 4. Crash / kill app — filet de sécurité

Si l'app meurt brutalement pendant l'appel :

| Cas                                          | Délai de fermeture côté centre                          |
|----------------------------------------------|----------------------------------------------------------|
| Hangup propre (UPDATE envoyé)                | < 100 ms (Realtime broadcast)                            |
| App killée pendant `ringing`                 | ≤ 5 min (watchdog cron 1 min, seuil `> 5 min`)           |
| App killée pendant `active` + heartbeat OFF  | ≤ 5 min (watchdog `updated_at < now() - 5 min`)          |
| App killée pendant `active` + heartbeat ON   | ≤ 5 min après dernier beat                               |

**Recommandations** :
- Sur Android, utilisez un **Foreground Service** (`flutter_foreground_task`) avec notification persistante pendant l'appel pour empêcher le kill par le système.
- Sur iOS, utilisez **CallKit** (équivalent natif robuste).
- Au prochain démarrage de l'app, vérifiez s'il y a un appel orphelin en `active`/`ringing` pour ce citoyen et fermez-le proprement (UPDATE → `completed`, `ended_by='citizen_recovery'`).

---

## 5. Heartbeat optionnel (recommandé)

Permet au serveur de détecter un appel zombie en < 5 min même si l'OS a tué l'app sans déclencher `dispose()`.

```dart
Timer? _heartbeat;

void startHeartbeat(String channelName) {
  _heartbeat?.cancel();
  _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) async {
    try {
      await Supabase.instance.client
        .from('call_history')
        .update({'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('channel_name', channelName)
        .eq('status', 'active');
    } catch (_) { /* best-effort */ }
  });
}

void stopHeartbeat() {
  _heartbeat?.cancel();
  _heartbeat = null;
}
```

Coût : 1 UPDATE / 15 s / appel actif. Négligeable.

---

## 6. Gestion d'erreurs

```dart
try {
  await hangupCall(channelName);
} on PostgrestException catch (e) {
  // 401/403 : session expirée → re-login silencieux puis retry une fois
  // 5xx     : laisser le watchdog serveur fermer
  Sentry.captureException(e);
}
```

**Ne JAMAIS bloquer la fermeture de l'UI sur le succès de l'UPDATE.** Le pire cas est une fermeture côté centre 30-60 s plus tard, jamais une UI bloquée.

---

## 7. Checklist QA

- [ ] **Raccrochage normal** : UPDATE envoyé, écran fermé, appel disparaît du dashboard en < 1 s.
- [ ] **Opérateur raccroche** : listener déclenché, écran citoyen fermé en < 1 s.
- [ ] **Kill app pendant ringing** : appel fermé côté centre en ≤ 5 min (cron).
- [ ] **Kill app pendant active + heartbeat ON** : appel fermé en ≤ 5 min.
- [ ] **Reprise après crash** : appel orphelin nettoyé au prochain login.

---

**Version** : 1.0 — post-refactor centre d'appels (Axe 0).
**Owner backend** : `useActiveCallController.ts` (heartbeat dashboard 15 s) + watchdog SQL.
