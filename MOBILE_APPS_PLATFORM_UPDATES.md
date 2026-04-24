# Mises à jour plateforme — apps mobiles (Citoyen, Secouriste, Hôpital)

> **Audience** : équipes Flutter/mobile qui consomment le même backend Lovable Cloud que le dashboard web.
> **Objectif** : lister les changements backend récents qui impactent vos apps et les adaptations à prévoir.
> **Date** : 2026-04 — phase « performance haute charge » du dashboard.

---

## Contexte

Le dashboard centre d'urgence vient de subir plusieurs vagues d'optimisation pour tenir 7M appels/jour et 125k opérateurs concurrents. Ces changements sont **côté backend partagé** : RPC, RLS, triggers, buckets Storage, sécurité auth. Vous devez en tenir compte.

Bonne nouvelle : aucune migration SQL bloquante côté mobile. Les signatures publiques sont stables. Mais quelques détails d'intégration changent.

---

## 1. Buckets Storage devenus privés

Les buckets suivants ne sont **plus publics** :

- `avatars`
- `incident-media`
- `signalements`
- `incidents`
- `call-recordings`

### Ce qui ne marche plus

```dart
// ❌ Ne marche plus — renvoie 403 sur les nouveaux buckets privés
final url = supabase.storage.from('incident-media').getPublicUrl(path);
```

### Ce qu'il faut faire

```dart
// ✅ Générer une URL signée (TTL 1h recommandé pour l'affichage)
final signedUrl = await supabase.storage
    .from('incident-media')
    .createSignedUrl(path, 3600);
```

```ts
// TS / React Native
const { data, error } = await supabase.storage
  .from("incident-media")
  .createSignedUrl(path, 3600);
```

**Bonnes pratiques** :
- Cache l'URL signée jusqu'à expiration (≈55 min pour rester safe).
- Pour les avatars affichés en boucle, regroupe via `createSignedUrls(paths, 3600)`.
- Pour les uploads, rien ne change : `upload(path, file)` fonctionne toujours.

---

## 2. Sécurité auth : HIBP activé

L'API auth Supabase rejette désormais à l'inscription tout mot de passe présent dans Have-I-Been-Pwned. Le code d'erreur est `weak_password`.

### À afficher proprement

```dart
try {
  await supabase.auth.signUp(email: email, password: password);
} on AuthException catch (e) {
  if (e.code == 'weak_password') {
    showError(
      "Ce mot de passe a été divulgué dans une fuite de données publique. "
      "Choisissez-en un autre."
    );
    return;
  }
  rethrow;
}
```

**N'impacte pas** : le PIN à 6 chiffres des secouristes (flux `agent-login`) — il n'est pas un password Supabase Auth.

---

## 3. RPC `resolve_incident` (clôture atomique)

Si l'app mobile (typiquement secouriste à la fin d'une mission) clôture un incident, **utilise cette RPC** au lieu d'enchaîner plusieurs UPDATE. Elle ferme l'incident, libère l'unité, marque les dispatches `completed` et purge la file en une seule transaction.

### Signature

```ts
supabase.rpc("resolve_incident", {
  _incident_id: string,           // uuid
  _resolution: string,            // ex: "mission_end" | "no_dispatch" | "false_alarm"
  _notes: string | null,          // optionnel
})
// Retour : { success: boolean, error?: string }
```

### Exemple Dart

```dart
final res = await supabase.rpc('resolve_incident', params: {
  '_incident_id': incidentId,
  '_resolution': 'mission_end',
  '_notes': 'Patient acheminé à l\'hôpital X',
});
if (res['success'] != true) {
  // gérer res['error']
}
```

**Gate** : seuls les rôles `call_center`, `admin`, `superviseur`, `secouriste` (sur leur propre dispatch) sont autorisés. Si tu reçois `error: "unauthorized"`, c'est normal côté citoyen ou hôpital.

---

## 4. RPC `claim_incoming_call`

Signature inchangée. Côté serveur on log désormais via `RAISE LOG` les conflits de prise d'appel pour debug. Le format de retour est identique :

```ts
{
  success: boolean,
  error?: "taken_by_other" | "call_ended" | "operator_not_found" | "unauthenticated",
  already_mine?: boolean,
  taken_by_operator_name?: string,
}
```

Les apps mobiles citoyen/secouriste **ne devraient pas** appeler cette RPC — elle est réservée aux opérateurs du centre.

---

## 5. Trigger nouveau : libération automatique des unités

Le trigger `on_incident_closed_release_units` se déclenche désormais quand un incident passe en `resolved`, `archived`, `ended` ou `declasse`. Il :

1. Marque tous les dispatches associés en `status = 'completed'`.
2. Remet l'unité (`units`) en `available`.
3. Émet un broadcast Realtime sur la table `dispatches`.

### Ce que ça change pour l'app secouriste

- **Plus besoin** d'envoyer manuellement un `UPDATE dispatches SET status='completed'` à la fin de mission si tu appelles `resolve_incident`.
- Tu vas recevoir un événement Realtime `UPDATE` sur ton dispatch avec `status='completed'` automatiquement → ferme l'écran « Mission en cours » côté UI.
- Si ton app a une logique de dédoublonnement (« j'ai déjà marqué completed, ignore l'event »), c'est OK, l'event sera idempotent.

---

## 6. Recompute hospitaux : `trg_active_rescuer_recompute_hospitals`

Quand le secouriste bouge de **plus de 100 m**, le trigger recalcule automatiquement le top 5 hôpitaux pertinents pour chaque dispatch actif lié à son unité, et écrit le résultat dans `dispatches.suggested_hospitals` (JSONB).

### Ce que ça change

- **L'app secouriste n'a rien à calculer** côté client. Lit juste `suggested_hospitals` :

```dart
final dispatch = await supabase
  .from('dispatches')
  .select('id, suggested_hospitals, suggested_hospitals_computed_at')
  .eq('id', dispatchId)
  .single();

final hospitals = (dispatch['suggested_hospitals'] as List?) ?? [];
// chaque entrée : { id, name, address, lat, lng, distance_km, available_beds, ... }
```

- Souscris en Realtime au dispatch pour rafraîchir la liste sans rien recompter :

```dart
supabase.channel('dispatch-$dispatchId')
  .onPostgresChanges(
    event: PostgresChangeEvent.update,
    schema: 'public',
    table: 'dispatches',
    filter: PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'id',
      value: dispatchId,
    ),
    callback: (payload) => refreshSuggestedHospitals(payload.newRecord),
  )
  .subscribe();
```

---

## 7. RLS `health_structures` : champs admin protégés

Les fiches hôpital sont éditables (par l'app hôpital) **uniquement** sur la liste blanche suivante :

- `available_beds`, `capacity`, `is_open`
- `operating_hours`, `phone`, `email`
- `equipment`, `specialties`, `contact_person`
- `rating`

Toute tentative de modifier `name`, `official_name`, `address`, `lat`, `lng`, `type`, `linked_user_id` depuis un compte hôpital est rejetée par le trigger `protect_structure_admin_fields` avec un message FR explicite. Affiche-le tel quel à l'utilisateur.

---

## 8. Realtime côté mobile

Le dashboard web utilise désormais un **RealtimeHub multiplexé** (1 seul WebSocket par opérateur). **Cette optim n'existe pas côté Flutter** et ce n'est pas un problème : les apps mobiles ont beaucoup moins d'abonnements simultanés.

### Recommandations pragmatiques pour Flutter/mobile

- **1 channel par écran**, pas 1 par widget. Crée le channel dans `initState` de la page, dispose-le dans `dispose`.
- Utilise `filter` PostgreSQL côté serveur (`incident_id=eq.${id}`) plutôt que de tout recevoir et filtrer côté client → divise la bande passante par 100 sur les écrans live.
- Pas de panique à régler : ton volume reste très en-dessous de la limite Realtime (200 channels par client).

---

## 9. Latence appels : `resolve_incident` < 50 ms perçu

Le centre clôture désormais les incidents en quasi-instant. **Côté app citoyen** :

- Le statut `call_history.status = 'completed'` arrive très vite après que l'opérateur clique « Terminer ».
- Si ton UI affiche un loader « Appel en cours » qui dépend d'un poll, il sera obsolète quasi tout de suite.
- **Préfère un listener Realtime** sur `call_history` filtré par `citizen_id=eq.${authUid}` et clôture l'écran d'appel côté app dès que `status` change vers `completed`/`ended`/`cancelled`.

---

## 10. Métriques RPC : table `rpc_metrics`

Une nouvelle table d'observabilité existe :

- **SELECT** : réservé `admin` + `superviseur`. L'app mobile ne peut pas lire.
- **INSERT** : autorisé pour tout utilisateur authentifié.

Si tu veux mesurer la latence de tes propres appels critiques côté mobile, tu peux y insérer :

```dart
await supabase.from('rpc_metrics').insert({
  'rpc_name': 'mobile.create_signalement',
  'duration_ms': stopwatch.elapsedMilliseconds,
  'ok': true,
});
```

Optionnel — utile uniquement si tu cherches à tracer des perf mobile sans télémétrie tierce.

---

## Checklist QA mobile

Avant de releaser une nouvelle version :

- [ ] Toutes les images/medias de buckets affichées passent par `createSignedUrl`.
- [ ] Le formulaire d'inscription affiche un message FR clair sur l'erreur HIBP `weak_password`.
- [ ] L'écran « Mission en cours » de l'app secouriste se ferme automatiquement quand le dispatch passe en `completed` (déclenché par `resolve_incident` côté centre).
- [ ] L'écran « Hôpitaux suggérés » lit `dispatches.suggested_hospitals` et se rafraîchit en Realtime, **sans** recalcul client.
- [ ] L'app hôpital affiche tel quel le message d'erreur du trigger `protect_structure_admin_fields` si l'utilisateur tente d'éditer un champ admin.
- [ ] L'app citoyen ferme proprement l'écran d'appel sur `call_history.status` ∈ `{completed, ended, cancelled}` reçu en Realtime.
- [ ] Pas plus de 1 channel Realtime par écran actif.

---

## Contacts

Côté backend / dashboard : équipe Lovable Cloud.
Pour toute RPC manquante ou comportement bizarre, ouvrir un ticket avec le `rpc_name`, `request_id` (header de réponse) et l'horodatage UTC.
