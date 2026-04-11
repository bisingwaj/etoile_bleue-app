# PROMPT LOVABLE — Module Signalements & Plaintes

> **Version** : 1.0 — 4 avril 2026
> **Audience** : Dashboard Lovable (React / TypeScript)
> **Projet** : Étoile Bleue — Système national de surveillance sanitaire, RDC

---

## Préambule

Ce document est le **contrat technique complet** entre l'application mobile Flutter et le dashboard Lovable pour le module Signalements. Il décrit les tables, les politiques de sécurité, les contrats JSON, les flux Realtime et les fonctionnalités attendues côté dashboard.

**Règle cardinale** : les signalements sont un flux **asynchrone** totalement distinct des incidents SOS et des appels d'urgence. Ils ne passent **PAS** par la file d'attente (`call_queue`), n'ont **PAS** de canal Agora, et ne déclenchent **PAS** de dispatch opérateur. Le cycle de vie est :

```
Citoyen (mobile) → INSERT Supabase → Dashboard reçoit via Realtime → Opérateur traite → Citoyen notifié via Realtime
```

---

## Table des matières

1. [Schéma de données](#1-schéma-de-données)
2. [Politiques RLS](#2-politiques-rls)
3. [Storage](#3-storage)
4. [Catégories, priorités et statuts](#4-catégories-priorités-et-statuts)
5. [Contrats JSON](#5-contrats-json)
6. [Flux mobile → dashboard (Realtime)](#6-flux-mobile--dashboard-realtime)
7. [Fonctionnalités dashboard attendues](#7-fonctionnalités-dashboard-attendues)
8. [Règles métier critiques](#8-règles-métier-critiques)
9. [Optimisation et scalabilité](#9-optimisation-et-scalabilité)
10. [Checklist d'intégration dashboard](#10-checklist-dintégration-dashboard)

---

## 1. Schéma de données

### 1.1 Table `signalements`

Table principale. Une ligne par signalement citoyen.

```sql
CREATE TABLE IF NOT EXISTS signalements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reference TEXT NOT NULL,
  category TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  citizen_name TEXT,
  citizen_phone TEXT,
  is_anonymous BOOLEAN DEFAULT false,
  province TEXT NOT NULL DEFAULT 'Kinshasa',
  ville TEXT NOT NULL DEFAULT 'Kinshasa',
  commune TEXT,
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  structure_name TEXT,
  structure_id UUID REFERENCES health_structures(id) ON DELETE SET NULL,
  priority TEXT NOT NULL DEFAULT 'moyenne'
    CHECK (priority IN ('critique', 'haute', 'moyenne', 'basse')),
  status TEXT NOT NULL DEFAULT 'nouveau'
    CHECK (status IN ('nouveau', 'en_cours', 'enquete', 'resolu', 'classe', 'transfere')),
  assigned_to TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_signalements_created ON signalements (created_at DESC);
CREATE INDEX idx_signalements_citizen_phone ON signalements (citizen_phone);
CREATE INDEX idx_signalements_status ON signalements (status);
CREATE INDEX idx_signalements_category ON signalements (category);
CREATE INDEX idx_signalements_commune ON signalements (commune);
```

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Identifiant unique |
| `reference` | text | Non | — | Référence lisible. Format : `SIG-YYYYMMDD-NNNNN` (générée côté mobile) |
| `category` | text | Non | — | Code catégorie parmi les 22 définis (voir §4.1) |
| `title` | text | Non | — | Titre court du signalement (max 200 caractères) |
| `description` | text | Oui | — | Description détaillée (max 2000 caractères) |
| `citizen_name` | text | Oui | — | Nom complet du plaignant. **NULL si anonyme** |
| `citizen_phone` | text | Oui | — | Téléphone du plaignant (format `+243...`). **NULL si anonyme** |
| `is_anonymous` | boolean | Oui | `false` | Signalement anonyme |
| `province` | text | Non | `'Kinshasa'` | Province de l'incident |
| `ville` | text | Non | `'Kinshasa'` | Ville de l'incident |
| `commune` | text | Oui | — | Commune (renseignée par GPS ou manuellement) |
| `lat` | double precision | Oui | — | Latitude GPS WGS84 de l'incident |
| `lng` | double precision | Oui | — | Longitude GPS WGS84 de l'incident |
| `structure_name` | text | Oui | — | Nom de la structure sanitaire concernée |
| `structure_id` | uuid | Oui | — | FK vers `health_structures.id` (si sélectionnée dans l'app) |
| `priority` | text | Non | `'moyenne'` | `critique`, `haute`, `moyenne`, `basse` |
| `status` | text | Non | `'nouveau'` | Statut du workflow (voir §4.3) |
| `assigned_to` | text | Oui | — | Nom de l'enquêteur assigné (écrit par le dashboard) |
| `created_at` | timestamptz | Oui | `now()` | Date de création (immutable) |
| `updated_at` | timestamptz | Oui | `now()` | Dernière mise à jour (modifiée par le dashboard) |

### 1.2 Table `signalement_media`

Médias joints à un signalement. Une ligne par fichier (photo, vidéo ou audio).

```sql
CREATE TABLE IF NOT EXISTS signalement_media (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signalement_id UUID NOT NULL REFERENCES signalements(id) ON DELETE CASCADE,
  type TEXT NOT NULL DEFAULT 'image'
    CHECK (type IN ('image', 'video', 'audio')),
  url TEXT NOT NULL,
  thumbnail TEXT,
  duration INTEGER,
  filename TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_signalement_media_sig ON signalement_media (signalement_id);
```

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Identifiant unique |
| `signalement_id` | uuid | Non | — | FK vers `signalements.id` (CASCADE on delete) |
| `type` | text | Non | `'image'` | `image`, `video`, `audio` |
| `url` | text | Non | — | URL publique du fichier dans Storage |
| `thumbnail` | text | Oui | — | URL de la miniature (images et vidéos uniquement) |
| `duration` | integer | Oui | — | Durée en secondes (audio et vidéo uniquement) |
| `filename` | text | Non | — | Nom original du fichier |
| `created_at` | timestamptz | Oui | `now()` | Date d'upload |

### 1.3 Table `signalement_notes`

Notes de suivi ajoutées par les opérateurs. Le citoyen peut les lire mais pas en créer.

```sql
CREATE TABLE IF NOT EXISTS signalement_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  signalement_id UUID NOT NULL REFERENCES signalements(id) ON DELETE CASCADE,
  author TEXT NOT NULL,
  text TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_signalement_notes_sig ON signalement_notes (signalement_id);
```

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Identifiant unique |
| `signalement_id` | uuid | Non | — | FK vers `signalements.id` (CASCADE on delete) |
| `author` | text | Non | — | Nom de l'opérateur/enquêteur auteur de la note |
| `text` | text | Non | — | Contenu de la note |
| `created_at` | timestamptz | Oui | `now()` | Date de création |

---

## 2. Politiques RLS

Les rôles sont stockés dans `users_directory.role` et accessibles via `auth.jwt()->'user_metadata'->>'role'`.

### 2.1 Table `signalements`

| Action | `citoyen` | `call_center` | `admin` | `superviseur` | `hopital` | `secouriste` |
|---|---|---|---|---|---|---|
| SELECT | Ses propres (filtre `citizen_phone`) | Tous | Tous | Tous | Tous | Tous |
| INSERT | Oui | Oui | Oui | Oui | Non | Non |
| UPDATE | Non | Oui | Oui | Oui | Non | Non |
| DELETE | Non | Non | Non | Non | Non | Non |

```sql
-- SELECT : le citoyen ne voit que les siens, les autres rôles voient tout
CREATE POLICY signalements_select ON signalements FOR SELECT USING (
  CASE
    WHEN (auth.jwt()->'user_metadata'->>'role') IN ('call_center','admin','superviseur','hopital','secouriste')
    THEN true
    ELSE citizen_phone = (
      SELECT phone FROM users_directory WHERE auth_user_id = auth.uid() LIMIT 1
    )
  END
);

-- INSERT : citoyen, call_center, admin, superviseur
CREATE POLICY signalements_insert ON signalements FOR INSERT WITH CHECK (
  (auth.jwt()->'user_metadata'->>'role') IN ('citoyen','call_center','admin','superviseur')
);

-- UPDATE : opérateurs uniquement
CREATE POLICY signalements_update ON signalements FOR UPDATE USING (
  (auth.jwt()->'user_metadata'->>'role') IN ('call_center','admin','superviseur')
);

-- DELETE : interdit pour tous
-- Aucune policy DELETE créée
```

### 2.2 Table `signalement_media`

| Action | `citoyen` | `call_center` | `admin` | `superviseur` |
|---|---|---|---|---|
| SELECT | Tous | Tous | Tous | Tous |
| INSERT | Oui | Oui | Oui | Oui |
| UPDATE | Non | Non | Non | Non |
| DELETE | Non | Non | Non | Non |

```sql
CREATE POLICY signalement_media_select ON signalement_media FOR SELECT USING (true);

CREATE POLICY signalement_media_insert ON signalement_media FOR INSERT WITH CHECK (
  (auth.jwt()->'user_metadata'->>'role') IN ('citoyen','call_center','admin','superviseur')
);
```

### 2.3 Table `signalement_notes`

| Action | `citoyen` | `call_center` | `admin` | `superviseur` |
|---|---|---|---|---|
| SELECT | Tous | Tous | Tous | Tous |
| INSERT | Non | Oui | Oui | Oui |
| UPDATE | Non | Non | Non | Non |
| DELETE | Non | Non | Non | Non |

```sql
CREATE POLICY signalement_notes_select ON signalement_notes FOR SELECT USING (true);

CREATE POLICY signalement_notes_insert ON signalement_notes FOR INSERT WITH CHECK (
  (auth.jwt()->'user_metadata'->>'role') IN ('call_center','admin','superviseur')
);
```

---

## 3. Storage

### 3.1 Bucket

- **Nom** : `incidents` (bucket déjà existant, partagé avec les incidents SOS)
- **Public** : `true` (les URLs sont accessibles sans authentification)

### 3.2 Convention de chemins

Le mobile upload les fichiers dans le sous-dossier `signalements/` du bucket :

```
signalements/{signalement_id}/{type}_{timestamp}.{ext}
signalements/{signalement_id}/thumb_{type}_{timestamp}.jpg
```

Exemples concrets :
```
signalements/a1b2c3d4-e5f6-7890-abcd-ef1234567890/image_1712234567890.jpg
signalements/a1b2c3d4-e5f6-7890-abcd-ef1234567890/thumb_image_1712234567890.jpg
signalements/a1b2c3d4-e5f6-7890-abcd-ef1234567890/video_1712234567891.mp4
signalements/a1b2c3d4-e5f6-7890-abcd-ef1234567890/thumb_video_1712234567891.jpg
signalements/a1b2c3d4-e5f6-7890-abcd-ef1234567890/audio_1712234567892.m4a
```

### 3.3 Types MIME

| Type | Extension | Content-Type |
|---|---|---|
| Image | `.jpg` | `image/jpeg` |
| Vidéo | `.mp4` | `video/mp4` |
| Audio | `.m4a` | `audio/mp4` |
| Miniature | `.jpg` | `image/jpeg` |

### 3.4 Policies Storage

```sql
-- Lecture publique (bucket public)
CREATE POLICY storage_signalements_read ON storage.objects FOR SELECT USING (
  bucket_id = 'incidents' AND (storage.foldername(name))[1] = 'signalements'
);

-- Écriture : utilisateurs authentifiés avec rôle autorisé
CREATE POLICY storage_signalements_write ON storage.objects FOR INSERT WITH CHECK (
  bucket_id = 'incidents'
  AND (storage.foldername(name))[1] = 'signalements'
  AND auth.role() = 'authenticated'
);
```

### 3.5 Contraintes de taille (appliquées côté mobile)

| Type | Format compressé | Résolution max | Taille max unitaire |
|---|---|---|---|
| Photo | JPEG 75% | 1920x1080 | 2 MB |
| Vidéo | MP4 H.264 720p | 720p | 20 MB |
| Audio | AAC 64 kbps | — | 5 MB |
| Miniature | JPEG 50-60% | 300x300 | ~50 KB |

| Limite | Valeur |
|---|---|
| Photos max par signalement | 10 |
| Vidéos max par signalement | 3 |
| Audios max par signalement | 5 |
| Taille totale max | 50 MB |
| Durée vidéo max | 120 secondes (2 min) |
| Durée audio max | 300 secondes (5 min) |

---

## 4. Catégories, priorités et statuts

### 4.1 Catégories (22 codes)

Le mobile envoie le **code** dans le champ `category`. Le dashboard doit afficher le **libellé** correspondant.

| Code | Libellé |
|---|---|
| `corruption` | Corruption & Extorsion |
| `detournement_medicaments` | Détournement de médicaments |
| `maltraitance` | Maltraitance de patients |
| `surfacturation` | Surfacturation / Frais illicites |
| `personnel_fantome` | Personnel fantôme |
| `medicaments_perimes` | Vente de médicaments périmés |
| `faux_diplomes` | Faux diplômes / Exercice illégal |
| `insalubrite` | Insalubrité / Manquement hygiène |
| `violence_harcelement` | Violence & Harcèlement |
| `discrimination` | Discrimination |
| `negligence_medicale` | Négligence médicale |
| `trafic_organes` | Trafic de sang / organes |
| `racket_urgences` | Racket aux urgences |
| `detournement_aide` | Détournement d'aide humanitaire |
| `absence_injustifiee` | Absence injustifiée du personnel |
| `conditions_travail` | Conditions de travail inhumaines |
| `protocoles_sanitaires` | Non-respect protocoles sanitaires |
| `falsification_certificats` | Falsification de certificats |
| `rupture_stock` | Rupture volontaire de stock |
| `exploitation_stagiaires` | Exploitation de stagiaires |
| `abus_sexuels` | Abus sexuels en milieu hospitalier |
| `obstruction_enquetes` | Obstruction aux enquêtes |

### 4.2 Priorités

| Code | Libellé | Couleur HEX | Critère |
|---|---|---|---|
| `critique` | Critique | `#EF4444` (rouge) | Danger immédiat pour des vies |
| `haute` | Haute | `#F59E0B` (orange) | Impact grave, action rapide requise |
| `moyenne` | Moyenne | `#3B82F6` (bleu) | Standard, traitement normal |
| `basse` | Basse | `#6B7280` (gris) | Informationnel, pas urgent |

### 4.3 Statuts du workflow

```
nouveau ──→ en_cours ──→ enquete ──→ resolu
                    └──→ classe
                    └──→ transfere
```

| Code | Libellé | Description | Qui peut appliquer |
|---|---|---|---|
| `nouveau` | Nouveau | Vient d'être créé, non pris en charge | Mobile (auto à la création) |
| `en_cours` | En cours | Un opérateur examine le dossier | Dashboard (call_center, admin, superviseur) |
| `enquete` | En enquête | Investigation approfondie en cours | Dashboard (call_center, admin, superviseur) |
| `resolu` | Résolu | Mesures correctives appliquées | Dashboard (call_center, admin, superviseur) |
| `classe` | Classé | Classé sans suite (infondé, doublon...) | Dashboard (call_center, admin, superviseur) |
| `transfere` | Transféré | Transmis à une autre autorité | Dashboard (call_center, admin, superviseur) |

**Transitions autorisées** :
- `nouveau` → `en_cours`
- `en_cours` → `enquete`, `classe`, `transfere`
- `enquete` → `resolu`, `classe`, `transfere`
- `resolu`, `classe`, `transfere` → statuts terminaux (pas de retour arrière)

Toute modification de `status` doit aussi mettre à jour `updated_at = now()`.

---

## 5. Contrats JSON

### 5.1 INSERT `signalements` — Signalement nominatif

JSON exact envoyé par le mobile lors d'un INSERT :

```json
{
  "reference": "SIG-20260404-12345",
  "category": "corruption",
  "title": "Extorsion au service des urgences",
  "description": "Le personnel exige un paiement de 50$ avant toute prise en charge aux urgences du CHU.",
  "citizen_name": "Jean Mukendi",
  "citizen_phone": "+243812345678",
  "is_anonymous": false,
  "province": "Kinshasa",
  "ville": "Kinshasa",
  "commune": "Lemba",
  "lat": -4.3447,
  "lng": 15.3271,
  "structure_name": "Hôpital Général de Kinshasa",
  "structure_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "priority": "haute",
  "status": "nouveau"
}
```

### 5.2 INSERT `signalements` — Signalement anonyme

```json
{
  "reference": "SIG-20260404-67890",
  "category": "abus_sexuels",
  "title": "Harcèlement par un médecin-chef",
  "description": "Plusieurs stagiaires victimes de harcèlement sexuel au sein du service de chirurgie.",
  "citizen_name": null,
  "citizen_phone": null,
  "is_anonymous": true,
  "province": "Nord-Kivu",
  "ville": "Goma",
  "commune": null,
  "lat": -1.6585,
  "lng": 29.2208,
  "structure_name": "Centre Hospitalier de Goma",
  "structure_id": null,
  "priority": "critique",
  "status": "nouveau"
}
```

### 5.3 INSERT `signalement_media`

Une ligne par fichier joint. Envoyée après la création du signalement :

```json
{
  "signalement_id": "uuid-du-signalement",
  "type": "image",
  "url": "https://[SUPABASE_URL]/storage/v1/object/public/incidents/signalements/uuid/image_1712234567890.jpg",
  "thumbnail": "https://[SUPABASE_URL]/storage/v1/object/public/incidents/signalements/uuid/thumb_image_1712234567890.jpg",
  "duration": null,
  "filename": "preuve_extorsion.jpg"
}
```

```json
{
  "signalement_id": "uuid-du-signalement",
  "type": "video",
  "url": "https://[SUPABASE_URL]/storage/v1/object/public/incidents/signalements/uuid/video_1712234567891.mp4",
  "thumbnail": "https://[SUPABASE_URL]/storage/v1/object/public/incidents/signalements/uuid/thumb_video_1712234567891.jpg",
  "duration": 45,
  "filename": "video_temoignage.mp4"
}
```

```json
{
  "signalement_id": "uuid-du-signalement",
  "type": "audio",
  "url": "https://[SUPABASE_URL]/storage/v1/object/public/incidents/signalements/uuid/audio_1712234567892.m4a",
  "thumbnail": null,
  "duration": 120,
  "filename": "note_vocale.m4a"
}
```

### 5.4 INSERT `signalement_notes` (dashboard uniquement)

```json
{
  "signalement_id": "uuid-du-signalement",
  "author": "Opérateur Marie Kabongo",
  "text": "Contact établi avec la direction de l'hôpital. Enquête de terrain programmée pour le 10/04."
}
```

### 5.5 SELECT `signalements` — Réponse attendue par le mobile

Le mobile effectue un SELECT paginé (`ORDER BY created_at DESC, LIMIT 30`) filtré par `citizen_phone`. Chaque ligne retournée contient tous les champs de la table. Le mobile parse avec ce mapping Dart → JSON :

| Champ Dart | Clé JSON | Type |
|---|---|---|
| `id` | `id` | String (uuid) |
| `reference` | `reference` | String |
| `category` | `category` | String (code) |
| `title` | `title` | String |
| `description` | `description` | String? |
| `citizenName` | `citizen_name` | String? |
| `citizenPhone` | `citizen_phone` | String? |
| `isAnonymous` | `is_anonymous` | bool |
| `province` | `province` | String |
| `ville` | `ville` | String |
| `commune` | `commune` | String? |
| `lat` | `lat` | double? |
| `lng` | `lng` | double? |
| `structureName` | `structure_name` | String? |
| `structureId` | `structure_id` | String? (uuid) |
| `priority` | `priority` | String (code) |
| `status` | `status` | String (code) |
| `assignedTo` | `assigned_to` | String? |
| `createdAt` | `created_at` | String (ISO 8601) |
| `updatedAt` | `updated_at` | String? (ISO 8601) |

### 5.6 SELECT `signalement_media` — Réponse pour la page détail

Le mobile récupère les médias séparément : `SELECT * FROM signalement_media WHERE signalement_id = $id ORDER BY created_at`.

| Champ Dart | Clé JSON | Type |
|---|---|---|
| `id` | `id` | String (uuid) |
| `signalementId` | `signalement_id` | String (uuid) |
| `type` | `type` | String (`image`/`video`/`audio`) |
| `url` | `url` | String (URL publique) |
| `thumbnail` | `thumbnail` | String? (URL publique) |
| `duration` | `duration` | int? (secondes) |
| `filename` | `filename` | String |
| `createdAt` | `created_at` | String (ISO 8601) |

---

## 6. Flux mobile → dashboard (Realtime)

### 6.1 Direction mobile → dashboard (INSERT)

Le mobile INSERT dans `signalements` puis dans `signalement_media`. Le dashboard doit souscrire via Supabase Realtime pour recevoir les nouveaux signalements instantanément :

```typescript
// Dashboard : écouter les nouveaux signalements
const channel = supabase
  .channel('dashboard-signalements')
  .on('postgres_changes', {
    event: 'INSERT',
    schema: 'public',
    table: 'signalements',
  }, (payload) => {
    // Nouveau signalement reçu → rafraîchir la liste, incrémenter les compteurs
    console.log('Nouveau signalement:', payload.new);
    refreshSignalementsList();
    updateStats();
  })
  .subscribe();
```

### 6.2 Direction dashboard → mobile (UPDATE)

Quand un opérateur change le statut, assigne un enquêteur ou modifie un champ, le mobile est notifié. Le mobile écoute les UPDATE sur `signalements` filtrés par `citizen_phone` du citoyen :

```
Canal : my-signalements-{timestamp}
Event : postgres_changes (UPDATE uniquement)
Table : public.signalements
Filtre : citizen_phone = '{phone du citoyen}'
```

**Conséquence pour le dashboard** : toute modification de `status`, `assigned_to` ou `updated_at` dans la table `signalements` sera automatiquement poussée au mobile du citoyen. Le dashboard n'a rien de spécial à faire : il suffit de faire un UPDATE SQL standard.

```typescript
// Dashboard : mettre à jour le statut d'un signalement
const { error } = await supabase
  .from('signalements')
  .update({
    status: 'en_cours',
    assigned_to: 'Inspecteur Kabongo',
    updated_at: new Date().toISOString(),
  })
  .eq('id', signalementId);
```

### 6.3 Notes de suivi (INSERT)

Le mobile ne souscrit pas encore aux notes en temps réel, mais il les récupère à chaque ouverture de la page détail. Si une fonctionnalité de notification de note est souhaitée ultérieurement, le canal serait :

```
Canal : sig-notes-{signalement_id}
Event : postgres_changes (INSERT)
Table : public.signalement_notes
Filtre : signalement_id = '{id}'
```

### 6.4 Propagation sur le dashboard

Chaque INSERT depuis le mobile doit apparaître instantanément sur le dashboard dans :

- La **liste** du module Signalements
- La **carte Radar** (couche `signalements-layer`) si `lat` et `lng` sont renseignés
- Les **statistiques** (compteurs, graphiques par catégorie/province)
- La **vue matérialisée** `mv_signalements_by_commune` (après le prochain refresh pg_cron, toutes les 5 minutes)

---

## 7. Fonctionnalités dashboard attendues

### 7.1 Liste des signalements

Une vue tabulaire ou en cartes affichant tous les signalements, avec :

| Fonctionnalité | Détail |
|---|---|
| **Colonnes affichées** | Référence, titre, catégorie (libellé), priorité (badge couleur), statut (badge), commune, date, assigné à |
| **Tri** | Par date (défaut DESC), priorité, statut |
| **Filtres** | Par statut, catégorie, priorité, commune, province, plage de dates |
| **Recherche** | Recherche textuelle sur titre, description, référence |
| **Pagination** | 50-200 lignes par page |
| **Badge anonyme** | Afficher un badge "Anonyme" en jaune si `is_anonymous = true` |
| **Compteur** | Nombre total de signalements et ventilation par statut en haut de page |

### 7.2 Fiche détail d'un signalement

Une page ou un panneau latéral affichant toutes les informations d'un signalement :

**Section Informations principales :**
- Référence, titre, description complète
- Catégorie (libellé + code), priorité (badge couleur)
- Statut actuel (badge) avec bouton de changement de statut
- Date de création, dernière mise à jour
- Enquêteur assigné (modifiable)

**Section Plaignant :**
- Si `is_anonymous = false` : nom, téléphone, bouton "Appeler" (lance un appel sortant)
- Si `is_anonymous = true` : afficher **"Anonyme"** en badge jaune, masquer toute PII, **pas de bouton "Appeler"**

**Section Localisation :**
- Province, ville, commune
- Coordonnées GPS (lat/lng) si disponibles
- Mini-carte (pin sur les coordonnées)
- Structure concernée (nom + lien vers la fiche structure si `structure_id` existe)

**Section Médias (onglet dédié) :**
- Galerie d'images (clic pour agrandir en lightbox)
- Lecteur vidéo intégré (player HTML5)
- Lecteur audio intégré (player HTML5)
- Pour chaque média : nom du fichier, type, durée (si applicable), date d'upload

**Section Notes de suivi (timeline) :**
- Liste chronologique des notes existantes (`signalement_notes`)
- Formulaire pour ajouter une nouvelle note (auteur = nom de l'opérateur connecté)
- Chaque note affiche : auteur, texte, date

### 7.3 Actions opérateur

| Action | Détail |
|---|---|
| **Changer le statut** | Dropdown ou boutons avec les transitions autorisées (§4.3). UPDATE `status` + `updated_at` |
| **Assigner un enquêteur** | Champ texte ou dropdown d'utilisateurs. UPDATE `assigned_to` + `updated_at` |
| **Ajouter une note** | INSERT dans `signalement_notes` avec `author` = nom de l'opérateur connecté |
| **Voir les médias** | Ouvrir/télécharger les fichiers depuis le Storage |

### 7.4 Carte / Radar

Couche dédiée aux signalements sur la carte existante :

- Un marqueur par signalement ayant `lat` et `lng` non-null
- Couleur du marqueur selon la priorité (rouge=critique, orange=haute, bleu=moyenne, gris=basse)
- Popup au clic : référence, titre, catégorie, statut, date
- Clic sur le popup → navigation vers la fiche détail
- Filtrable par catégorie, statut, priorité, plage de dates

### 7.5 Statistiques

Widgets ou section dédiée affichant :

| Indicateur | Source |
|---|---|
| Total signalements | `COUNT(*)` sur `signalements` |
| Par statut | `GROUP BY status` avec badge couleur |
| Par catégorie | `GROUP BY category` (graphique en barres ou camembert) |
| Par priorité | `GROUP BY priority` avec couleurs |
| Par province/commune | `GROUP BY province` ou `commune` (carte choroplèthe ou tableau) |
| Évolution temporelle | `GROUP BY DATE(created_at)` (courbe) |
| Taux de résolution | `COUNT(status='resolu') / COUNT(*)` |
| Délai moyen de traitement | `AVG(updated_at - created_at) WHERE status = 'resolu'` |

La vue matérialisée `mv_signalements_by_commune` fournit des agrégations pré-calculées par commune, rafraîchie toutes les 5 minutes par pg_cron.

---

## 8. Règles métier critiques

### 8.1 Anonymat

**Quand `is_anonymous = true` :**

| Règle | Détail |
|---|---|
| `citizen_name` est **NULL** | Le mobile ne l'envoie pas |
| `citizen_phone` est **NULL** | Le mobile ne l'envoie pas |
| Dashboard affiche **"Anonyme"** | Badge jaune dans la fiche détail et la liste |
| **Pas de bouton "Appeler"** | Masquer toute action de contact avec le plaignant |
| **Pas d'exposition de PII** | Ne jamais tenter de retrouver l'auteur via logs, IP, etc. |
| `lat`/`lng` peuvent être renseignés | Ce sont les coordonnées de l'incident, pas du plaignant |

### 8.2 Déduplication

Le mobile implémente une déduplication avant INSERT : il vérifie si un signalement avec le même `title` existe dans les 30 dernières secondes (+ filtre `citizen_phone` si non-anonyme). Le dashboard ne devrait pas créer de doublons manuellement mais il n'a pas besoin d'implémenter cette logique côté serveur.

### 8.3 Référence

Le format de référence est `SIG-YYYYMMDD-NNNNN` (ex: `SIG-20260404-54321`). Il est généré côté mobile. Le dashboard ne doit **pas** modifier la référence d'un signalement existant. Si le dashboard crée des signalements manuellement (fonctionnalité optionnelle), il doit respecter le même format.

### 8.4 Immutabilité côté citoyen

Le citoyen ne peut **ni modifier, ni supprimer** ses signalements. Une fois soumis, le signalement est en lecture seule pour lui. Seuls les rôles `call_center`, `admin`, `superviseur` peuvent UPDATE les champs `status`, `assigned_to`, `updated_at`.

### 8.5 Intégrité des médias

Les médias sont insérés dans `signalement_media` après la création du signalement. Le mobile upload en best-effort (retry 3x avec backoff exponentiel). Si certains médias échouent, le signalement est quand même créé — le champ `signalement_media` peut avoir moins de lignes que le nombre de médias sélectionnés par le citoyen. Le dashboard doit simplement afficher ce qui est présent dans la table.

### 8.6 Structure sanitaire

Si le citoyen a sélectionné une structure dans l'app (via recherche autocomplete sur `health_structures`), les champs `structure_name` et `structure_id` sont renseignés. Le dashboard peut utiliser `structure_id` pour créer un lien vers la fiche de la structure. Si `structure_id` est NULL mais `structure_name` est renseigné, afficher simplement le nom en texte.

---

## 9. Optimisation et scalabilité

### 9.1 Index recommandés

```sql
-- Déjà créés avec les tables
CREATE INDEX idx_signalements_created ON signalements (created_at DESC);
CREATE INDEX idx_signalements_citizen_phone ON signalements (citizen_phone);
CREATE INDEX idx_signalements_status ON signalements (status);
CREATE INDEX idx_signalements_category ON signalements (category);
CREATE INDEX idx_signalements_commune ON signalements (commune);
CREATE INDEX idx_signalement_media_sig ON signalement_media (signalement_id);
CREATE INDEX idx_signalement_notes_sig ON signalement_notes (signalement_id);

-- Index partiels pour les requêtes fréquentes du dashboard
CREATE INDEX IF NOT EXISTS idx_signalements_active
  ON signalements (created_at DESC)
  WHERE status IN ('nouveau', 'en_cours', 'enquete');

CREATE INDEX IF NOT EXISTS idx_signalements_priority_critical
  ON signalements (created_at DESC)
  WHERE priority = 'critique' AND status NOT IN ('resolu', 'classe', 'transfere');
```

### 9.2 Vue matérialisée

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_signalements_by_commune AS
SELECT
  commune,
  province,
  category,
  status,
  priority,
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE status = 'nouveau') AS nouveau,
  COUNT(*) FILTER (WHERE status = 'en_cours') AS en_cours,
  COUNT(*) FILTER (WHERE status = 'enquete') AS enquete,
  COUNT(*) FILTER (WHERE status = 'resolu') AS resolu,
  COUNT(*) FILTER (WHERE status = 'classe') AS classe,
  COUNT(*) FILTER (WHERE status = 'transfere') AS transfere
FROM signalements
GROUP BY commune, province, category, status, priority;

-- Rafraîchissement automatique toutes les 5 minutes via pg_cron
SELECT cron.schedule(
  'refresh_mv_signalements',
  '*/5 * * * *',
  'REFRESH MATERIALIZED VIEW CONCURRENTLY mv_signalements_by_commune;'
);
```

### 9.3 Pagination

| Côté | Stratégie | Limite |
|---|---|---|
| Mobile | Pagination curseur sur `created_at` | 30 par page |
| Dashboard (liste) | Pagination offset ou curseur | 50-200 par page |
| Dashboard (stats) | Vue matérialisée | Agrégé |

### 9.4 Realtime

- Le Realtime Supabase est activé sur la table `signalements` via la publication `supabase_realtime`
- Chaque client ouvre 1 connexion WebSocket multiplexée
- Les noms de canaux doivent être **uniques** (suffixe timestamp) pour éviter les collisions entre opérateurs

```sql
-- Activer Realtime sur les tables signalements
ALTER PUBLICATION supabase_realtime ADD TABLE signalements;
ALTER PUBLICATION supabase_realtime ADD TABLE signalement_notes;
```

---

## 10. Checklist d'intégration dashboard

### Tables et données

- [ ] Créer la table `signalements` avec toutes les colonnes, contraintes et index
- [ ] Créer la table `signalement_media` avec FK et index
- [ ] Créer la table `signalement_notes` avec FK et index
- [ ] Appliquer toutes les politiques RLS (§2)
- [ ] Activer Realtime sur `signalements` et `signalement_notes`
- [ ] Créer la vue matérialisée `mv_signalements_by_commune`
- [ ] Configurer le pg_cron pour le refresh toutes les 5 minutes
- [ ] Vérifier que le bucket `incidents` existe et est public

### Interface

- [ ] Implémenter la page liste des signalements avec filtres et tri
- [ ] Implémenter la fiche détail avec toutes les sections (infos, plaignant, localisation, médias, notes)
- [ ] Implémenter le changement de statut (transitions autorisées §4.3)
- [ ] Implémenter l'assignation d'enquêteur
- [ ] Implémenter l'ajout de notes de suivi
- [ ] Afficher les médias : galerie images, player vidéo, player audio
- [ ] Gérer l'anonymat : badge "Anonyme", masquage PII, pas de bouton "Appeler"
- [ ] Ajouter les signalements sur la carte Radar (couche `signalements-layer`)
- [ ] Implémenter les statistiques (compteurs, graphiques)

### Realtime

- [ ] Souscrire aux INSERT sur `signalements` pour rafraîchir la liste en temps réel
- [ ] Vérifier que les UPDATE de statut déclenchent bien les notifications Realtime vers le mobile
- [ ] Souscrire aux INSERT sur `signalement_notes` pour rafraîchir le fil de notes

### Validation fonctionnelle

- [ ] Créer un signalement depuis le mobile → vérifier qu'il apparaît instantanément sur le dashboard
- [ ] Changer le statut depuis le dashboard → vérifier que le mobile reçoit la notification Realtime
- [ ] Tester les 22 catégories (codes et libellés)
- [ ] Tester les 4 niveaux de priorité (couleurs)
- [ ] Tester les 6 statuts et les transitions autorisées
- [ ] Tester un signalement anonyme → vérifier que PII est masquée
- [ ] Tester l'affichage des médias (images, vidéos, audios) depuis le Storage
- [ ] Vérifier l'affichage sur la carte Radar (pin avec coordonnées GPS)
- [ ] Vérifier les statistiques (vue matérialisée)
- [ ] Tester en conditions réseau dégradées (3G simulé) — le mobile gère le retry

---

*Document généré le 4 avril 2026 — Étoile Bleue RDC*
