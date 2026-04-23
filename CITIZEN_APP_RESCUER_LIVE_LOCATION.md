# Intégration — Géolocalisation temps réel de l'urgentiste (App citoyen)

> **Objectif** : afficher au citoyen, en temps réel, la position GPS du secouriste/urgentiste qui se déplace vers lui dès qu'un dispatch est créé pour son incident SOS.

---

## 1. Vue d'ensemble du flux

```
[Centre d'appels] ──crée dispatch──> [Table dispatches]
       │                                    │
       │                                    ├─ rescuer_id (auth_user_id du secouriste)
       │                                    └─ unit_id    (unité affectée)
       │
[App secouriste mobile] ──upsert position toutes les 5-10s──> [Table active_rescuers]
                                            │
                                            │ Realtime (postgres_changes)
                                            ▼
[App citoyen] ◄──── lit + écoute UNIQUEMENT le secouriste assigné à SON incident
```

**Sécurité** : une nouvelle politique RLS `citizen_select_assigned_rescuer_position` autorise le citoyen à lire `active_rescuers` **uniquement** pour le secouriste affecté à un dispatch actif (status ≠ `completed`/`cancelled`/`mission_end`) sur un incident dont il est le déclarant (`incidents.citizen_id = auth.uid()`).

Aucune autre position n'est visible. Aucun changement n'est requis côté backend pour le citoyen — la requête fonctionnera dès que la migration est déployée (déjà fait).

---

## 2. Schéma des tables impliquées

### `active_rescuers` (lecture seule pour le citoyen)
| Colonne       | Type      | Description                                  |
|---------------|-----------|----------------------------------------------|
| `id`          | uuid      | PK                                           |
| `user_id`     | uuid      | `auth_user_id` du secouriste                 |
| `lat`         | double    | Latitude GPS                                 |
| `lng`         | double    | Longitude GPS                                |
| `accuracy`    | double    | Précision en mètres (nullable)               |
| `heading`     | double    | Cap en degrés 0-360 (nullable)               |
| `speed`       | double    | Vitesse en m/s (nullable)                    |
| `battery`     | int       | Batterie 0-100 (nullable)                    |
| `status`      | text      | `active` / `idle` / `offline`                |
| `updated_at`  | timestamp | Dernière mise à jour                         |

### `dispatches` (lecture déjà autorisée via `citizen_select_own_dispatches`)
| Colonne                       | Description                                |
|-------------------------------|--------------------------------------------|
| `id`                          | PK dispatch                                |
| `incident_id`                 | FK vers `incidents.id`                     |
| `rescuer_id`                  | `auth_user_id` du secouriste (peut être null) |
| `unit_id`                     | FK vers `units.id` (peut être null)        |
| `status`                      | `dispatched`, `en_route`, `arrived`, etc.  |
| `assigned_structure_name`     | Nom de l'hôpital cible                     |
| `assigned_structure_lat/lng`  | Position de l'hôpital                      |

### `users_directory` (lookup secouriste via `unit_id`)
| Colonne              | Description                          |
|----------------------|--------------------------------------|
| `auth_user_id`       | UUID auth                            |
| `assigned_unit_id`   | Unité à laquelle l'agent est rattaché|
| `first_name`, `last_name` | Pour affichage UI               |

---

## 3. Étape 1 — Récupérer le `user_id` du secouriste assigné

Quand le citoyen consulte son incident actif, l'app doit déterminer **quel secouriste suivre** :

```dart
// Pseudo-code Flutter / TypeScript équivalent
final dispatch = await supabase
  .from('dispatches')
  .select('id, rescuer_id, unit_id, status, assigned_structure_name, assigned_structure_lat, assigned_structure_lng')
  .eq('incident_id', incidentId)
  .not('status', 'in', '(completed,cancelled,mission_end)')
  .order('created_at', ascending: false)
  .limit(1)
  .maybeSingle();

if (dispatch == null) return; // Aucun dispatch actif

String? rescuerAuthUserId = dispatch['rescuer_id'];

// Fallback : si rescuer_id est null, le résoudre via l'unité
if (rescuerAuthUserId == null && dispatch['unit_id'] != null) {
  final ud = await supabase
    .from('users_directory')
    .select('auth_user_id, first_name, last_name')
    .eq('assigned_unit_id', dispatch['unit_id'])
    .limit(1)
    .maybeSingle();
  rescuerAuthUserId = ud?['auth_user_id'];
}

if (rescuerAuthUserId == null) return; // Aucun secouriste résolvable
```

---

## 4. Étape 2 — Charger la position initiale

```dart
final position = await supabase
  .from('active_rescuers')
  .select('lat, lng, heading, speed, accuracy, battery, updated_at, status')
  .eq('user_id', rescuerAuthUserId)
  .order('updated_at', ascending: false)
  .limit(1)
  .maybeSingle();

if (position != null) {
  // Afficher le marker sur la carte
  showRescuerMarker(
    lat: position['lat'],
    lng: position['lng'],
    heading: position['heading'],
  );
}
```

> **Note de fraîcheur** : si `updated_at` date de plus de 5 minutes, considérer le secouriste comme "hors ligne" et afficher un état dégradé (icône grisée + message "Position non mise à jour depuis X min").

---

## 5. Étape 3 — S'abonner au Realtime

La table `active_rescuers` est déjà ajoutée à la publication `supabase_realtime`. Il suffit de souscrire :

```dart
final channel = supabase
  .channel('rescuer-tracking-$incidentId')
  .onPostgresChanges(
    event: PostgresChangeEvent.all, // INSERT + UPDATE + DELETE
    schema: 'public',
    table: 'active_rescuers',
    filter: PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'user_id',
      value: rescuerAuthUserId,
    ),
    callback: (payload) {
      if (payload.eventType == PostgresChangeEvent.delete) {
        hideRescuerMarker();
        return;
      }
      final row = payload.newRecord;
      updateRescuerMarker(
        lat: row['lat'],
        lng: row['lng'],
        heading: row['heading'],
        speed: row['speed'],
        updatedAt: row['updated_at'],
      );
    },
  )
  .subscribe();
```

**Cleanup obligatoire** au `dispose()` de l'écran :
```dart
await supabase.removeChannel(channel);
```

---

## 6. Étape 4 — Suivre les changements de dispatch

Le `rescuer_id` peut changer (réassignation par le centre d'appels) ou le dispatch peut passer en `completed`. Il faut donc s'abonner aussi à `dispatches` :

```dart
final dispatchChannel = supabase
  .channel('dispatch-tracking-$incidentId')
  .onPostgresChanges(
    event: PostgresChangeEvent.update,
    schema: 'public',
    table: 'dispatches',
    filter: PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'incident_id',
      value: incidentId,
    ),
    callback: (payload) async {
      final newRow = payload.newRecord;
      final newStatus = newRow['status'];
      final newRescuerId = newRow['rescuer_id'];

      if (['completed', 'cancelled', 'mission_end'].contains(newStatus)) {
        // Mission terminée : arrêter le tracking
        await supabase.removeChannel(channel);
        showMissionCompletedScreen();
      } else if (newRescuerId != null && newRescuerId != rescuerAuthUserId) {
        // Réassignation : recharger l'écran avec le nouveau secouriste
        await supabase.removeChannel(channel);
        rescuerAuthUserId = newRescuerId;
        await reloadTrackingFor(rescuerAuthUserId);
      }
    },
  )
  .subscribe();
```

---

## 7. Étape 5 — Affichage UX recommandé

### Carte
- **Marker citoyen** : icône fixe (point rouge) à `incidents.location_lat/lng`.
- **Marker secouriste** : icône ambulance/moto **rotatable** selon `heading`, animation linéaire entre deux positions (≈ 1 s).
- **Polyline** (optionnel) : trace Mapbox Directions API entre la position du secouriste et celle du citoyen, recalculée toutes les 30-60 s pour ne pas surcharger l'API.
- **Marker hôpital** : icône hôpital à `assigned_structure_lat/lng` si renseigné.

### Bandeau d'information
```
🚑 Secouriste en route
Distance : 2.4 km · ETA : ~6 min
Mise à jour : il y a 3 s
Statut : En route vers vous
```

### États dégradés
| Condition                                  | Comportement                                       |
|--------------------------------------------|----------------------------------------------------|
| `updated_at` > 5 min                       | Marker grisé + "Position non mise à jour"          |
| `status === 'offline'`                     | Marker grisé + "Secouriste hors ligne"             |
| `battery < 20`                             | Petit badge batterie faible sur le marker          |
| Dispatch passe à `arrived`                 | Marker fixe + bandeau "Le secouriste est arrivé"   |
| Dispatch passe à `completed`/`mission_end` | Fermer le tracking + écran de fin de mission       |

---

## 8. Étape 6 — Calcul ETA et distance (côté client)

Pour éviter un appel Mapbox à chaque update, calculer la distance à vol d'oiseau (Haversine) puis estimer l'ETA avec une vitesse moyenne urbaine (≈ 25 km/h) :

```dart
double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const R = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
      sin(dLng / 2) * sin(dLng / 2);
  return R * 2 * atan2(sqrt(a), sqrt(1 - a));
}

final distanceKm = haversineKm(rescuerLat, rescuerLng, citizenLat, citizenLng);
final etaMin = (distanceKm / 25 * 60).round(); // 25 km/h moyenne urbaine
```

Pour un calcul précis (routage réel), utiliser l'API Mapbox Directions avec un throttle de 30 s minimum entre deux appels.

---

## 9. Performance & bonnes pratiques

- **Un seul channel Realtime par écran** : ne PAS créer un channel par marker. Filtrer côté `filter: user_id=eq.<id>`.
- **Cleanup systématique** au `dispose()` pour éviter les fuites de connexions WebSocket.
- **Throttle d'animation** : limiter les rafraîchissements de marker à 1/seconde même si Realtime envoie plus vite.
- **Réseau dégradé** : afficher la dernière position connue + `updated_at` lisible ("il y a 12 s").
- **Battery saver** : si l'app citoyen passe en arrière-plan, désabonner le channel et réabonner au retour au premier plan.

---

## 10. Checklist d'intégration

- [ ] Lire le `dispatch` actif pour l'incident courant (`status NOT IN (completed, cancelled, mission_end)`)
- [ ] Résoudre `rescuerAuthUserId` via `rescuer_id` ou via `users_directory.assigned_unit_id`
- [ ] Charger la position initiale depuis `active_rescuers`
- [ ] S'abonner au Realtime sur `active_rescuers` avec filtre `user_id=eq.<rescuerAuthUserId>`
- [ ] S'abonner au Realtime sur `dispatches` avec filtre `incident_id=eq.<incidentId>` pour gérer réassignation/clôture
- [ ] Afficher le marker rotatif avec `heading`
- [ ] Calculer distance + ETA et afficher le bandeau
- [ ] Gérer les états dégradés (offline, position périmée, batterie faible)
- [ ] Cleanup des channels au `dispose()` et au passage en background
- [ ] Tester avec un compte citoyen réel (RLS doit bloquer toute autre position)

---

## 11. Test de la politique RLS

Pour vérifier que la politique fonctionne, depuis un client authentifié en tant que citoyen :

```sql
-- Doit retourner uniquement les positions des secouristes assignés à MES incidents actifs
SELECT user_id, lat, lng, updated_at
FROM active_rescuers;
```

Et tenter d'accéder à une autre position :
```sql
-- Doit retourner 0 lignes (RLS bloque)
SELECT * FROM active_rescuers WHERE user_id = '<un autre secouriste non assigné>';
```

---

## 12. Référence côté dashboard (déjà implémenté)

Le hook `src/hooks/useRescuerOriginForIncident.ts` du dashboard implémente exactement la même logique (résolution rescuer + Realtime). Il peut servir de référence canonique pour porter le comportement vers Flutter / l'app mobile citoyen.

---

**Backend prêt** ✅ — la migration RLS `citizen_select_assigned_rescuer_position` est déployée, Realtime est actif sur `active_rescuers`. L'app citoyen peut intégrer immédiatement.
