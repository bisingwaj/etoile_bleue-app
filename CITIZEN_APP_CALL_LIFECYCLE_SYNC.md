# 📞 CITIZEN APP — Cycle de vie des appels SOS (sync v2 dashboard)

> **Audience** : équipe Flutter de l'application citoyen.
> **Statut** : remplace les sections « Hangup » et « Heartbeat » de `CITIZEN_APP_CALLS_HANGUP_PROTOCOL.md` v1.
> **Date** : 2026-04 — phase « zéro appel zombie ».
> **Owner backend** : centre d'appels (dashboard React).

---

## 0. TL;DR — ce qui change pour vous

| Avant | Maintenant |
|---|---|
| `UPDATE call_history SET updated_at=now()` direct | **RPC `citizen_call_heartbeat(p_channel_name)`** |
| Watchdog serveur : 5 minutes | **Watchdog : 60 s (ringing) / 90 s (active)** |
| Heartbeat optionnel (15 s) | **Heartbeat obligatoire (10 s)** dès `ringing` |
| Aucun nettoyage au démarrage | **Recovery orphelin** au boot/login |
| Fermeture distante facultative | **Listener Realtime obligatoire** |

Si vous ne faites qu'**une seule chose** : remplacez vos UPDATE de heartbeat par la RPC `citizen_call_heartbeat`. C'est ce qui empêche la sonnerie fantôme côté centre.

---

## 1. Contexte & changements backend

Le centre d'appels souffrait de 3 bugs liés au cycle de vie des appels SOS :

1. **Sonnerie fantôme au reload** du dashboard (appels morts qui re-sonnent).
2. **Appel qui reste dans la file** ≥ 5 min après raccrochage silencieux (kill app citoyen).
3. **Heartbeat citoyen inopérant** : la colonne `call_history.updated_at` n'existait pas, vos UPDATE échouaient en `PGRST204` silencieusement.

Le backend a été corrigé :

- ✅ Colonne `call_history.updated_at` ajoutée + trigger `BEFORE UPDATE` pour auto-incrément.
- ✅ Index partiel `(updated_at) WHERE status IN ('ringing','active')` pour watchdog rapide.
- ✅ RPC `citizen_call_heartbeat(p_channel_name text)` — `SECURITY DEFINER`, RLS-safe, idempotent.
- ✅ Watchdog `pg_cron` 1 min :
  - `ringing` sans heartbeat > **60 s** → `missed`, `ended_by='watchdog_no_heartbeat'`.
  - `active` sans heartbeat > **90 s** → `completed`, `ended_by='watchdog_no_heartbeat'`.
- ✅ Trigger `on_call_history_status_change` ferme automatiquement la `call_queue` correspondante (Realtime broadcast < 1 s vers le centre).

**Vous n'avez rien à migrer en SQL.** Mais vous devez **adapter votre code Dart**.

---

## 2. Contrat d'appel SOS — séquence obligatoire

```text
┌─────────────────────────────────────────────────────────────┐
│ 1. Citoyen tape "SOS"                                       │
│                                                             │
│ 2. INSERT incidents → récupérer incident.reference          │
│    (cf. CITIZEN_APP_CHANNEL_NAME_INVARIANT.md)              │
│                                                             │
│ 3. INSERT call_history {                                    │
│      channel_name: incident.reference,                      │
│      incident_id, citizen_id: auth.uid(),                   │
│      status: 'ringing',                                     │
│      call_type: 'incoming'                                  │
│    }                                                        │
│                                                             │
│ 4. ▶ START heartbeat 10 s : rpc(citizen_call_heartbeat)     │
│                                                             │
│ 5. ▶ START listener Realtime (filter channel_name=eq.X)     │
│                                                             │
│ 6. ▶ START Foreground Service (Android) / CallKit (iOS)     │
│                                                             │
│ 7. agoraEngine.joinChannel(token, channelName)              │
│                                                             │
│ ─── Opérateur décroche ──── status='active' (Realtime) ──── │
│                                                             │
│ 8. Heartbeat continue (10 s)                                │
│                                                             │
│ ─── Citoyen raccroche ──────                                │
│                                                             │
│ 9. UPDATE call_history SET                                  │
│      status='completed', ended_by='citizen',                │
│      ended_at=now()                                         │
│    WHERE channel_name=X AND citizen_id=auth.uid()           │
│      AND status NOT IN ('completed','missed','failed','cancelled') │
│                                                             │
│ 10. agoraEngine.leaveChannel()                              │
│                                                             │
│ 11. Stop heartbeat, stop Foreground Service, removeChannel  │
└─────────────────────────────────────────────────────────────┘
```

⚠ **Ordre critique** : UPDATE **AVANT** `leaveChannel()`. Si `leaveChannel()` plante, le serveur est déjà au courant.

---

## 3. Code Flutter prêt à coller

### 3.1 Service singleton `CallLifecycleService`

```dart
import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CallLifecycleService {
  CallLifecycleService._();
  static final instance = CallLifecycleService._();

  Timer? _heartbeat;
  RealtimeChannel? _watchChannel;
  String? _activeChannelName;
  String? _activeCallHistoryId;
  VoidCallback? _onRemoteHangup;

  SupabaseClient get _sb => Supabase.instance.client;

  /// Démarre un appel SOS. Appelle ceci APRÈS création de l'incident
  /// et obtention du token Agora, AVANT joinChannel.
  Future<void> startCall({
    required String channelName,        // = incident.reference
    required String incidentId,
    required VoidCallback onRemoteHangup,
  }) async {
    _activeChannelName = channelName;
    _onRemoteHangup = onRemoteHangup;

    // 1) INSERT call_history
    final inserted = await _sb.from('call_history').insert({
      'channel_name': channelName,
      'incident_id': incidentId,
      'citizen_id': _sb.auth.currentUser?.id,
      'status': 'ringing',
      'call_type': 'incoming',
      'started_at': DateTime.now().toUtc().toIso8601String(),
    }).select('id').single();
    _activeCallHistoryId = inserted['id'] as String;

    // 2) Heartbeat 10 s
    _startHeartbeat();

    // 3) Listener fermeture distante
    _startWatchListener(channelName);
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) async {
      final ch = _activeChannelName;
      if (ch == null) return;
      try {
        await _sb.rpc(
          'citizen_call_heartbeat',
          params: {'p_channel_name': ch},
        );
      } on PostgrestException catch (e) {
        // 401/403 → tentative de refresh, puis 1 retry
        if (e.code == '401' || e.code == '403') {
          try {
            await _sb.auth.refreshSession();
            await _sb.rpc('citizen_call_heartbeat',
                params: {'p_channel_name': ch});
          } catch (_) {/* watchdog filet de sécurité */}
        }
        debugPrint('[CallLifecycle] heartbeat failed: ${e.code} ${e.message}');
      } catch (e) {
        debugPrint('[CallLifecycle] heartbeat error: $e');
      }
    });
  }

  void _startWatchListener(String channelName) {
    _watchChannel?.unsubscribe();
    _watchChannel = _sb
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
            const terminal = {
              'completed', 'missed', 'failed', 'ended', 'cancelled'
            };
            final status = payload.newRecord['status'] as String?;
            final endedBy = payload.newRecord['ended_by'] as String?;
            if (status != null && terminal.contains(status)) {
              debugPrint('[CallLifecycle] remote close: $status by $endedBy');
              if (endedBy != 'citizen') {
                _onRemoteHangup?.call();
              }
              _cleanup();
            }
          },
        )
        .subscribe();
  }

  /// Raccrochage volontaire du citoyen.
  Future<void> hangup({required RtcEngine engine}) async {
    final ch = _activeChannelName;
    if (ch != null) {
      try {
        await _sb
            .from('call_history')
            .update({
              'status': 'completed',
              'ended_at': DateTime.now().toUtc().toIso8601String(),
              'ended_by': 'citizen',
            })
            .eq('channel_name', ch)
            .eq('citizen_id', _sb.auth.currentUser!.id)
            .not('status', 'in', '(completed,missed,failed,cancelled)');
      } catch (e) {
        debugPrint('[CallLifecycle] hangup update failed: $e');
        // best-effort — watchdog ferme sous 60-90 s
      }
    }
    try {
      await engine.leaveChannel();
    } catch (_) {}
    _cleanup();
  }

  void _cleanup() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _watchChannel?.unsubscribe();
    _watchChannel = null;
    _activeChannelName = null;
    _activeCallHistoryId = null;
    _onRemoteHangup = null;
  }

  /// À appeler au démarrage de l'app + au login.
  /// Ferme tout appel orphelin du citoyen courant.
  Future<void> recoverOrphanCalls() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      // Sélectionne d'abord (PostgREST ne supporte pas update+limit)
      final orphans = await _sb
          .from('call_history')
          .select('id, channel_name, started_at')
          .eq('citizen_id', uid)
          .inFilter('status', ['ringing', 'active'])
          .lt('started_at',
              DateTime.now()
                  .toUtc()
                  .subtract(const Duration(seconds: 30))
                  .toIso8601String());

      for (final row in orphans as List) {
        await _sb.from('call_history').update({
          'status': 'completed',
          'ended_at': DateTime.now().toUtc().toIso8601String(),
          'ended_by': 'citizen_recovery',
        }).eq('id', row['id']);
        debugPrint('[CallLifecycle] recovered orphan ${row['channel_name']}');
      }
    } catch (e) {
      debugPrint('[CallLifecycle] recovery failed: $e');
    }
  }
}
```

### 3.2 Intégration dans l'écran d'appel

```dart
@override
void initState() {
  super.initState();
  CallLifecycleService.instance.startCall(
    channelName: widget.channelName,        // = incident.reference
    incidentId: widget.incidentId,
    onRemoteHangup: () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Appel terminé par l'opérateur")),
      );
      Navigator.of(context).pop();
    },
  );
}

Future<void> _onTapHangup() async {
  await CallLifecycleService.instance.hangup(engine: agoraEngine);
  if (mounted) Navigator.of(context).pop();
}

@override
void dispose() {
  CallLifecycleService.instance.hangup(engine: agoraEngine);
  super.dispose();
}
```

### 3.3 Recovery au boot + au login

```dart
// main.dart, après initialisation Supabase
await CallLifecycleService.instance.recoverOrphanCalls();

// Après chaque signIn réussi
Supabase.instance.client.auth.onAuthStateChange.listen((data) {
  if (data.event == AuthChangeEvent.signedIn) {
    CallLifecycleService.instance.recoverOrphanCalls();
  }
});
```

---

## 4. Cas limites & SLO

| Scénario | Action mobile | Délai max côté centre |
|---|---|---|
| Raccrochage propre | UPDATE + leaveChannel | **< 1 s** |
| Kill app pendant `ringing` | rien (heartbeat off) | **≤ 60 s** (watchdog) |
| Kill app pendant `active` | rien | **≤ 90 s** (watchdog) |
| Réseau perdu < 30 s | reprise heartbeat auto | < 1 s après reprise |
| Reload dashboard, appel mort | (transparent) | aucune sonnerie |
| Opérateur raccroche | listener → snackbar + pop | **< 1 s** |
| Crash app + relance | `recoverOrphanCalls()` au boot | < 5 s après relance |

---

## 5. Plateformes natives

### Android — Foreground Service obligatoire pendant un appel

Sans Foreground Service, Android tue l'app dès que l'écran s'éteint → heartbeat off → watchdog → appel coupé brutalement.

```yaml
dependencies:
  flutter_foreground_task: ^6.0.0
```

```dart
// Au début de startCall() :
await FlutterForegroundTask.startService(
  notificationTitle: 'Appel SOS en cours',
  notificationText: 'N\'éteignez pas l\'écran',
  serviceTypes: [ForegroundServiceTypes.mediaPlayback,
                 ForegroundServiceTypes.microphone],
);

// Au cleanup :
await FlutterForegroundTask.stopService();
```

`AndroidManifest.xml` :
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

### iOS — CallKit + AVAudioSession

```dart
// Avant joinChannel
await AVAudioSession().setCategory(
  AVAudioSessionCategory.playAndRecord,
  options: [AVAudioSessionCategoryOptions.allowBluetooth,
            AVAudioSessionCategoryOptions.defaultToSpeaker],
);
```

Configurer un `CXProvider` CallKit en mode `voIP` pour empêcher iOS de killer l'app pendant un appel actif.

`Info.plist` :
```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
  <string>voip</string>
</array>
```

### Batterie / wakelock

`wakelock_plus` activé pendant l'appel, **désactivé** dans `_cleanup()` :
```dart
await WakelockPlus.enable();   // début appel
await WakelockPlus.disable();  // fin appel
```

---

## 6. Gestion d'erreurs

| Erreur | Réaction |
|---|---|
| `PostgrestException` 401/403 sur RPC | `auth.refreshSession()` + 1 retry, puis abandon silencieux |
| `PostgrestException` 5xx | ignorer (watchdog filet de sécurité) |
| `SocketException` | ignorer (le timer 10 s reprendra) |
| Échec INSERT initial `call_history` | **bloquant** : ne pas démarrer l'appel, afficher erreur user |
| Échec UPDATE hangup | **non bloquant** : fermer l'UI quand même |

**Règle d'or** : ne **JAMAIS** bloquer la fermeture d'UI sur le succès d'un appel réseau. Le pire cas est une fermeture côté centre 60-90 s plus tard, jamais une UI bloquée.

---

## 7. Checklist QA livrable

À cocher avant de releaser la nouvelle version :

- [ ] **Raccrochage normal** → disparition centre < 1 s.
- [ ] **Kill app pendant `ringing`** → disparition centre ≤ 60 s.
- [ ] **Kill app pendant `active`** → disparition centre ≤ 90 s.
- [ ] **Heartbeat visible** toutes 10 s dans les logs Postgres (filtrer `citizen_call_heartbeat`).
- [ ] **Reload dashboard** pendant un appel mort → **aucune resonnerie**.
- [ ] **Opérateur raccroche** → écran citoyen fermé < 1 s + snackbar « Appel terminé par l'opérateur ».
- [ ] **Recovery au login** → aucun `ringing`/`active` orphelin restant pour ce citoyen.
- [ ] **Foreground Service Android** visible (notification persistante) pendant tout appel.
- [ ] **Listener Realtime** correctement `unsubscribe`d dans `dispose()`.

---

## 8. Migration depuis l'existant

### À supprimer impérativement

```dart
// ❌ Échouait silencieusement (PGRST204) — la colonne n'existait pas
await supabase.from('call_history')
  .update({'updated_at': DateTime.now().toUtc().toIso8601String()})
  .eq('channel_name', channelName)
  .eq('status', 'active');
```

### À remplacer par

```dart
// ✅ RPC dédiée, RLS-safe, idempotente
await supabase.rpc(
  'citizen_call_heartbeat',
  params: {'p_channel_name': channelName},
);
```

### Documentation à mettre à jour

`CITIZEN_APP_CALLS_HANGUP_PROTOCOL.md` v1 → ajouter en tête :
> ⚠ Sections 5 (Heartbeat) et 4 (filet de sécurité) **remplacées** par `CITIZEN_APP_CALL_LIFECYCLE_SYNC.md`.

---

## 9. Référence rapide RPC

### Signature

```sql
public.citizen_call_heartbeat(p_channel_name text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
```

### Comportement

- Met à jour `call_history.updated_at = now()` pour la ligne `(channel_name = p_channel_name AND citizen_id = auth.uid() AND status IN ('ringing','active'))`.
- **Idempotent** : ne fait rien si l'appel est déjà terminé (pas d'erreur).
- **RLS-safe** : `SECURITY DEFINER`, mais filtre interne par `auth.uid()` → un citoyen ne peut heartbeat que ses propres appels.
- **Coût** : 1 UPDATE indexé / 10 s / appel actif. Négligeable (< 0,1 ms serveur).

### Codes d'erreur

| Code | Cause | Action mobile |
|---|---|---|
| `200` (void) | OK ou no-op | continuer |
| `401` | session expirée | `refreshSession` + retry |
| `403` | `auth.uid()` ≠ `citizen_id` | abandonner (pas votre appel) |
| `5xx` | serveur down | ignorer, watchdog prendra le relais |

---

## 10. Schéma cycle complet (ASCII)

```
       CITOYEN                   BACKEND                  CENTRE
          │                         │                        │
          │── INSERT call_history ──►│                        │
          │                         │── trigger queue ──────►│
          │                         │                        │ (sonne)
          │── rpc heartbeat (10s) ─►│                        │
          │── rpc heartbeat (10s) ─►│                        │
          │                         │◄── claim_call ─────────│ (décroche)
          │                         │── UPDATE active ──────►│
          │── rpc heartbeat (10s) ─►│                        │
          │                         │                        │
          │── UPDATE completed ────►│                        │
          │                         │── trigger close ──────►│ (disparaît)
          │   leaveChannel()        │                        │
          │   stopForeground()      │                        │
          ▼                         │                        ▼

   Si KILL pendant ringing/active :
          ✗                         │ watchdog 60/90s ──────►│ (disparaît)
                                    │                        ▼
```

---

**Version** : 2.0 — sync dashboard avril 2026.
**Référence backend** : RPC `citizen_call_heartbeat`, watchdog `pg_cron` 1 min, trigger `on_call_history_status_change`.
**Contact** : équipe backend Lovable Cloud pour toute RPC manquante / latence anormale (joindre `request_id` + horodatage UTC).
