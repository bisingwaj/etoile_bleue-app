# Annuaire Structures Sanitaires — Tri par proximité géographique

## Problème identifié

La table `health_structures` contient **1 726 structures**, mais Supabase ne retourne que **1 000 lignes max** par requête.  
Actuellement, le tri est alphabétique (`ORDER BY name`), ce qui exclut des structures proches de l'utilisateur si elles tombent au-delà de la 1 000ème ligne.

## Solution : Tri par distance géographique

L'application patient doit récupérer les structures triées par **proximité** à la position GPS de l'utilisateur connecté.

### Option 1 — Tri côté client (recommandé si < 2 000 structures)

Paginer pour récupérer **toutes** les structures, puis trier localement :

```dart
// 1. Récupérer toutes les structures (pagination)
List<Map<String, dynamic>> allStructures = [];
int pageSize = 1000;
int from = 0;
bool hasMore = true;

while (hasMore) {
  final response = await supabase
      .from('health_structures')
      .select('*')
      .eq('is_open', true)
      .range(from, from + pageSize - 1);

  if (response.isNotEmpty) {
    allStructures.addAll(List<Map<String, dynamic>>.from(response));
    from += pageSize;
    hasMore = response.length == pageSize;
  } else {
    hasMore = false;
  }
}

// 2. Trier par distance (formule Haversine simplifiée)
final userLat = currentPosition.latitude;
final userLng = currentPosition.longitude;

allStructures.sort((a, b) {
  final distA = _distanceSquared(userLat, userLng, a['lat'], a['lng']);
  final distB = _distanceSquared(userLat, userLng, b['lat'], b['lng']);
  return distA.compareTo(distB);
});

// Fonction utilitaire de distance approximative
double _distanceSquared(double lat1, double lng1, double? lat2, double? lng2) {
  if (lat2 == null || lng2 == null) return double.infinity;
  final dLat = lat2 - lat1;
  final dLng = (lng2 - lng1) * cos(lat1 * pi / 180);
  return dLat * dLat + dLng * dLng;
}
```

### Option 2 — Tri côté serveur (PostgreSQL, plus performant à grande échelle)

Créer une fonction RPC dans Supabase pour trier par distance :

```sql
-- Fonction RPC à créer via migration
CREATE OR REPLACE FUNCTION public.get_structures_near(
  p_lat double precision,
  p_lng double precision,
  p_limit integer DEFAULT 1000
)
RETURNS SETOF health_structures
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT *
  FROM public.health_structures
  WHERE is_open = true
    AND lat IS NOT NULL
    AND lng IS NOT NULL
  ORDER BY
    ((lat - p_lat) * (lat - p_lat)) +
    (((lng - p_lng) * cos(radians(p_lat))) * ((lng - p_lng) * cos(radians(p_lat))))
  ASC
  LIMIT p_limit;
$$;
```

Appel depuis Flutter :
```dart
final response = await supabase.rpc('get_structures_near', params: {
  'p_lat': currentPosition.latitude,
  'p_lng': currentPosition.longitude,
  'p_limit': 1000,
});
```

### Option 3 — Hybride (recommandé)

Utiliser l'Option 2 (RPC serveur) comme requête principale, et compléter avec les structures **sans coordonnées GPS** en requête secondaire.

## Changements côté Dashboard (déjà appliqués)

La requête du dashboard a été corrigée pour **paginer** et récupérer les 1 726+ structures (pas de limite à 1 000).

## Résumé des actions requises

| Composant | Action | Statut |
|-----------|--------|--------|
| Dashboard (web) | Pagination des structures | ✅ Fait |
| App Patient (Flutter) | Remplacer `.order('name')` par tri par proximité | ⬜ À faire |
| Base de données | (Optionnel) Créer la fonction RPC `get_structures_near` | ⬜ À faire |

## Notes techniques

- La table `health_structures` contient 6 types : `centre_sante` (980), `pharmacie` (358), `hopital` (205), `police` (107), `maternite` (71), `pompier` (5)
- **Toutes les catégories** doivent être incluses dans l'annuaire patient (pas seulement `hopital`)
- Les structures sans coordonnées GPS (`lat`/`lng` = NULL) doivent apparaître en fin de liste
