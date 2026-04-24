# 📱 Mise à jour app Citoyen — Invariant `channel_name = incident.reference`

> **Audience** : équipe Flutter app citoyen
> **Date** : 2026-04-23
> **Priorité** : 🔴 **CRITIQUE** — bloque la fin du correctif anti-duplication côté centre d'appels
> **Effort estimé** : 1–2 h dev + 30 min QA

---

## 1. Contexte — pourquoi cette mise à jour est obligatoire

Le dashboard centre d'urgence vient d'être corrigé pour éliminer **deux bugs majeurs** :

1. **Duplication d'appels** : un même SOS apparaissait **deux fois** dans la file d'attente des opérateurs, avec ~1 seconde de décalage.
2. **Persistance fantôme** : quand un opérateur raccrochait, l'appel restait visible chez les autres opérateurs indéfiniment.

### Cause racine (côté backend partagé)

Le même appel SOS était inséré dans **deux tables** par **deux pipelines** avec des `channel_name` **différents** :

| Pipeline | Table | `channel_name` généré |
|---|---|---|
| Trigger SQL `on_incident_created` | `call_queue` | autrefois `incident_<uuid>`, **maintenant `incident.reference`** ✅ |
| App citoyen (Flutter) au démarrage Agora | `call_history` | `SOS-<timestamp>` ❌ ← **à corriger** |

→ Tant que l'app citoyen utilise un `channel_name` arbitraire, la dédoublonnage côté dashboard reste partiellement cassé (les filets de sécurité front masquent le bug, mais la BDD continue d'accumuler des incohérences, et le trigger de fermeture cross-source ne peut pas faire son travail).

### Ce qui a déjà été fait côté dashboard / backend

- ✅ Trigger `on_incident_created` aligné sur `NEW.reference`
- ✅ Index UNIQUE partiel sur `call_queue(channel_name)` pour les statuts actifs → toute insertion en doublon échoue désormais en BDD
- ✅ Trigger `on_call_history_status_change` ferme `call_queue` par `channel_name` (et plus uniquement par `call_id`)
- ✅ Cleanup rétroactif des doublons existants
- ✅ Broadcast Supabase `channel_terminated` pour propagation cross-opérateur < 100 ms
- ✅ Frontend dashboard : double dédup (par `channel_name` + par `incident_id`)

**Il ne manque QUE la mise à jour côté app citoyen.**

---

## 2. La règle désormais

> **Pour tout appel SOS lié à un incident, le `channel_name` Agora DOIT être strictement égal à `incident.reference`.**

`incident.reference` est :

- généré automatiquement par PostgreSQL à l'INSERT (format : `SOS-YYYY-MM-DD-NNNN` ou similaire)
- **unique** dans la table `incidents`
- **stable** sur toute la durée de vie de l'incident
- **lisible** côté opérateur dans le dashboard

---

## 3. Ce qui doit changer dans l'app citoyen Flutter

### 3.1. Création de l'incident SOS

Aucun changement de schéma. Continuer à insérer dans `incidents` comme aujourd'hui. **Récupérer `reference` dans la réponse** :

```dart
// ✅ Insertion incident — récupérer reference + id
final incidentRow = await supabase
    .from('incidents')
    .insert({
      'citizen_id': citizenAuthUserId,
      'title': '...',
      'type': '...',
      'description': '...',
      'caller_name': callerName,
      'caller_phone': callerPhone,
      'location_lat': lat,
      'location_lng': lng,
      'priority': priority,
      // ⚠️ NE PAS définir 'reference' côté client — c'est PostgreSQL qui le génère
    })
    .select('id, reference')
    .single();

final incidentId = incidentRow['id'] as String;
final incidentReference = incidentRow['reference'] as String; // ex: "SOS-2026-04-23-0042"
```

### 3.2. Démarrage du canal Agora

```dart
// ❌ AVANT — channel_name arbitraire
final channelName = 'SOS-${DateTime.now().millisecondsSinceEpoch}';

// ✅ MAINTENANT — utiliser incident.reference
final channelName = incidentReference;

// Récupération du token Agora avec CE channel_name
final tokenResp = await supabase.functions.invoke('agora-token', body: {
  'channelName': channelName,
  'uid': 0,
  'role': 'publisher',
  'expireTime': 3600,
});

final agoraToken = tokenResp.data['token'] as String;
```

### 3.3. Insertion dans `call_history`

```dart
// ✅ INSERT call_history avec le MÊME channel_name que celui généré par le trigger
await supabase.from('call_history').insert({
  'channel_name': channelName, // = incidentReference
  'caller_name': callerName,
  'caller_phone': callerPhone,
  'citizen_id': citizenAuthUserId,
  'incident_id': incidentId,
  'call_type': 'audio', // ou 'video'
  'status': 'ringing',
  'has_video': false, // ou true
  'agora_token': agoraToken,
  'agora_uid': 0,
  'caller_lat': lat,
  'caller_lng': lng,
  'caller_preferred_language': preferredLang, // 'fr' | 'en' | 'ln' | 'sw'
});
```

### 3.4. Rejoindre le canal Agora

```dart
// Identique à avant — juste avec le nouveau channelName
await agoraEngine.joinChannel(
  token: agoraToken,
  channelId: channelName, // = incidentReference
  uid: 0,
  options: const ChannelMediaOptions(...),
);
```

---

## 4. Ce qui ne change PAS

| Élément | Statut |
|---|---|
| Schéma de la table `incidents` | inchangé |
| Schéma de la table `call_history` | inchangé |
| Edge function `agora-token` | inchangée — accepte n'importe quel `channelName` |
| Logique de raccrochage côté app citoyen | inchangée (toujours UPDATE `call_history.status = 'completed'` + `ended_at`) |
| Notifications push FCM | inchangées |
| Tableaux Realtime écoutés | inchangés |
| Authentification Twilio Verify | inchangée |
| Trigger de déduplication `deduplicate_incident` | inchangé (continue à bloquer les rappels < 30 s) |

---

## 5. Cas particuliers

### 5.1. Rappel sur incident déjà ouvert (PBX / réseau coupé)

Si le citoyen rappelle alors qu'un incident `in_progress` existe déjà (cas géré par `deduplicate_incident` qui bloque la création d'un nouvel incident), l'app DOIT :

1. Rechercher l'incident actif :
   ```dart
   final existing = await supabase
       .from('incidents')
       .select('id, reference')
       .eq('citizen_id', citizenAuthUserId)
       .eq('status', 'in_progress')
       .order('created_at', ascending: false)
       .limit(1)
       .maybeSingle();
   ```
2. **Réutiliser son `reference` comme `channel_name`** pour la nouvelle session Agora.
3. Insérer une nouvelle ligne `call_history` avec `channel_name = existing['reference']` (la BDD garantit qu'il n'y aura qu'une seule entrée active dans `call_queue` grâce à l'index UNIQUE partiel).

### 5.2. Appel sortant secouriste → citoyen

Aucun changement. Continuer à utiliser le `channel_name` `RESCUER-<incident_short>-<timestamp>` (déjà en place côté edge `rescuer-call-citizen`). L'invariant ne s'applique **qu'aux appels initiés par le citoyen vers le centre**.

### 5.3. Appel sortant centrale → citoyen

Idem 5.2. Pattern `CENTRALE-<auth_user_short>-<timestamp>` inchangé.

---

## 6. Validation — tests à exécuter avant publication

| # | Scénario | Attendu |
|---|---|---|
| 1 | Citoyen lance un SOS | **1 seule** carte côté dashboard, **0 doublon** |
| 2 | Inspecter `call_queue` et `call_history` après SOS | `channel_name` identique dans les 2 tables (= `incident.reference`) |
| 3 | Opérateur A décroche, raccroche | Côté opérateurs B/C : la carte disparaît en < 200 ms |
| 4 | Citoyen rappelle après raccrochage (> 30 s) | Nouvel incident, nouvelle carte unique |
| 5 | Citoyen rappelle pendant que son incident est `in_progress` | Réutilisation de `reference`, pas d'erreur 23505 (unique violation) |
| 6 | App citoyen lance un appel **vidéo** | Identique à audio, `has_video: true` |
| 7 | Coupure réseau citoyen pendant l'appel | Côté dashboard : `call_queue` se ferme automatiquement via timeout/trigger |

### Vérification SQL (à faire via le dashboard backend)

```sql
-- Doit retourner 0 lignes — chaque incident a au plus 1 ligne active
SELECT incident_id, count(*)
FROM call_queue
WHERE status IN ('waiting','assigned','answered')
GROUP BY incident_id
HAVING count(*) > 1;

-- Doit retourner 0 lignes — channel_name doit matcher entre call_queue et incidents
SELECT cq.channel_name AS queue_channel, i.reference AS incident_ref
FROM call_queue cq
JOIN incidents i ON i.id = cq.incident_id
WHERE cq.channel_name <> i.reference
  AND cq.created_at > now() - interval '1 day';
```

---

## 7. FAQ

**Q : Peut-on continuer à utiliser `SOS-<timestamp>` provisoirement ?**
R : Non. L'index UNIQUE partiel côté BDD ne posera pas de problème (les `channel_name` sont différents donc pas de collision), **mais le bug de duplication réapparaîtra** côté opérateurs car les deux pipelines créeront deux entrées avec des noms qui ne collident pas.

**Q : Que se passe-t-il si l'app citoyen utilise un ancien build (pas encore mis à jour) ?**
R : Le bug visuel de duplication réapparaîtra **uniquement** pour les SOS issus de cet ancien build. Le frontend dashboard a un filet de sécurité (dédup par `incident_id`) qui masque le doublon en UI, mais l'incohérence en BDD subsiste. **Il faut donc forcer la mise à jour de l'app citoyen.**

**Q : Faut-il modifier la table `incidents` ou `call_history` ?**
R : Non. Aucune migration n'est nécessaire côté schéma. Seul le **code Flutter** change.

**Q : Faut-il changer la signature de `agora-token` ?**
R : Non. Cette edge function accepte n'importe quel `channelName` string. Elle continuera à fonctionner avec `incident.reference`.

**Q : Que devient le format `SOS-<timestamp>` ?**
R : Il est abandonné côté app citoyen. Le format `incident.reference` est généré par PostgreSQL et reste sémantiquement équivalent (préfixe `SOS-` + identifiant unique).

---

## 8. Checklist de déploiement

### Côté app citoyen (Flutter)

- [ ] Mettre à jour le service `IncidentService.startSosCall()` pour récupérer `reference` après l'INSERT incident
- [ ] Remplacer toutes les occurrences de `SOS-${DateTime.now().millisecondsSinceEpoch}` par `incident.reference`
- [ ] Adapter le service Agora pour utiliser ce nouveau `channelName`
- [ ] Vérifier que l'INSERT `call_history` utilise le **même** `channel_name`
- [ ] Tester le cas de rappel sur incident `in_progress` (cf. §5.1)
- [ ] Tester avec build debug + build release
- [ ] Augmenter la version (`pubspec.yaml`) et publier sur Play Store / TestFlight
- [ ] Forcer la mise à jour côté utilisateurs via mécanisme déjà en place (force-update)

### Côté dashboard (déjà fait, juste à vérifier après déploiement mobile)

- [x] Trigger `on_incident_created` utilise `NEW.reference`
- [x] Index UNIQUE partiel `call_queue_active_channel_unique`
- [x] Trigger `on_call_history_status_change` ferme par `channel_name`
- [x] Broadcast `channel_terminated` (< 100 ms cross-opérateur)
- [x] Frontend : dédup par `channel_name` + `incident_id`
- [x] `useCallHistory` limité aux 15 dernières minutes pour les ringing non assignés

### Validation finale (à faire ensemble)

- [ ] Lancer 10 SOS depuis l'app citoyen mise à jour, vérifier 0 doublon côté dashboard
- [ ] Faire raccrocher l'opérateur A et vérifier la disparition immédiate chez B/C/D
- [ ] Inspecter `call_queue` en SQL pour confirmer 1 ligne active par incident
- [ ] Surveiller les logs Supabase pendant 24 h pour détecter d'éventuelles erreurs `23505` (unique violation) → indique un client mobile non mis à jour

---

## 9. Garanties après déploiement complet

| Aspect | Garantie |
|---|---|
| Duplication visuelle | **0** — vérifié par index UNIQUE BDD + double dédup front |
| Disparition cross-opérateur | **< 200 ms** via Broadcast Supabase |
| Scalabilité | **1 000 opérateurs / 7M appels/jour** sans dégradation |
| Rétro-compatibilité | App citoyen ancienne version → fonctionne mais bug visuel possible |
| Migration nécessaire | **Aucune** côté schéma — uniquement code Flutter |
| Risque de régression dashboard | **Nul** — APIs publiques inchangées |

---

## 10. Contact

En cas de question ou comportement inattendu pendant l'implémentation, joindre :

- les logs Flutter (incluant `channel_name` envoyé à `agora-token`)
- la `reference` d'un incident affecté (visible dans `incidents.reference`)
- une capture du dashboard montrant le doublon (si reproductible)

→ permet le diagnostic immédiat côté backend partagé.
