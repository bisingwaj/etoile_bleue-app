# 📊 PABX Étoile Bleue — Schéma Base de Données

> **Version**: 5 avril 2026
> **Destination**: Équipe application citoyenne (Flutter / React Native)
> **Backend**: Supabase (PostgreSQL 15)

---

## 1. Vue d'ensemble

```text
┌─────────────────────────────────────────────────────────────────┐
│                        AUTHENTIFICATION                         │
│  auth.users (Supabase Auth) ──► users_directory (profil unifié) │
└───────────────┬─────────────────────────────────────────────────┘
                │ auth_user_id
    ┌───────────┴───────────┐
    │                       │
┌───▼────┐           ┌──────▼──────┐
│incidents│◄─────────►│ call_history │
│  (SOS)  │           │   (appels)  │
└───┬────┘           └──────┬──────┘
    │                       │
    ├──► dispatches ──► units
    ├──► sos_responses
    ├──► call_queue
    ├──► call_recordings
    └──► call_transcriptions

┌──────────────┐  ┌──────────────┐  ┌─────────────┐
│ signalements │  │health_struct.│  │ active_     │
│(dénonciations)│  │ (hôpitaux)  │  │ rescuers   │
└──────────────┘  └──────────────┘  └─────────────┘
```

---

## 2. Enums (types personnalisés)

| Enum | Valeurs |
|---|---|
| `user_role` | `citoyen`, `secouriste`, `call_center`, `hopital`, `volontaire`, `superviseur`, `admin` |
| `call_status` | `ringing`, `active`, `completed`, `missed`, `failed` |
| `call_type` | `incoming`, `outgoing`, `internal` |
| `incident_priority` | `critical`, `high`, `medium`, `low` |
| `incident_status` | `new`, `dispatched`, `in_progress`, `resolved`, `archived`, `pending`, `en_route`, `arrived`, `investigating`, `ended`, `en_route_hospital`, `arrived_hospital` |
| `unit_status` | `available`, `dispatched`, `en_route`, `on_scene`, `returning`, `offline` |

---

## 3. Tables

### 3.1 `users_directory` — Répertoire unifié des utilisateurs

> Source de vérité unique pour tous les profils (citoyens, secouristes, opérateurs, hôpitaux).

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `auth_user_id` | uuid | Oui | — | Lien vers `auth.users.id` |
| `first_name` | text | Non | — | Prénom |
| `last_name` | text | Non | — | Nom de famille |
| `email` | text | Oui | — | Email |
| `phone` | text | Oui | — | Téléphone (format +243...) |
| `role` | user_role | Non | `'citoyen'` | Rôle dans le système |
| `status` | text | Oui | — | Statut de présence (`online`, `offline`, `busy`) |
| `available` | boolean | Oui | — | Disponible pour prise d'appel |
| `is_on_call` | boolean | Oui | — | Actuellement en appel |
| `active_call_id` | text | Oui | — | ID de l'appel en cours |
| `photo_url` | text | Oui | — | URL photo de profil |
| `date_of_birth` | text | Oui | — | Date de naissance (YYYY-MM-DD) |
| `language` | text | Oui | — | Langue préférée |
| `address` | text | Oui | — | Adresse |
| `blood_type` | text | Oui | — | Groupe sanguin |
| `allergies` | text[] | Oui | — | Liste d'allergies |
| `medical_history` | text[] | Oui | — | Antécédents médicaux |
| `medications` | text[] | Oui | — | Médicaments en cours |
| `emergency_contact_name` | text | Oui | — | Nom contact d'urgence |
| `emergency_contact_phone` | text | Oui | — | Tél. contact d'urgence |
| `id_number` | text | Oui | — | Numéro pièce d'identité |
| `matricule` | text | Oui | — | Matricule professionnel |
| `grade` | text | Oui | — | Grade / titre |
| `specialization` | text | Oui | — | Spécialisation |
| `specialties` | text[] | Oui | — | Spécialités multiples |
| `zone` | text | Oui | — | Zone d'affectation |
| `assigned_unit_id` | uuid | Oui | — | FK → `units.id` |
| `vehicle_id` | text | Oui | — | Véhicule assigné |
| `agent_login_id` | text | Oui | — | Identifiant de connexion mobile |
| `pin_code` | text | Oui | — | Code PIN (6 chiffres, accès mobile) |
| `fcm_token` | text | Oui | — | Token Firebase pour push |
| `must_change_password` | boolean | Oui | — | Forcer changement de MDP |
| `credentials_sent` | boolean | Oui | — | Identifiants déjà envoyés |
| `call_count` | integer | Oui | — | Nombre d'appels traités |
| `last_call_at` | timestamptz | Oui | — | Dernier appel traité |
| `last_seen_at` | timestamptz | Oui | — | Dernier heartbeat |
| `notes` | text | Oui | — | Notes internes |
| `type` | text | Oui | — | Sous-type libre |
| `created_at` | timestamptz | Oui | `now()` | Date de création |
| `updated_at` | timestamptz | Oui | `now()` | Dernière modification |

**FK**: `assigned_unit_id` → `units.id`

---

### 3.2 `incidents` — Urgences SOS

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `reference` | text | Non | — | Référence unique (ex: `SOS-XXXX-XXXXX`) |
| `type` | text | Non | — | Type d'incident (`medical`, `accident`, etc.) |
| `title` | text | Non | — | Titre court |
| `description` | text | Oui | — | Description détaillée |
| `priority` | incident_priority | Non | `'medium'` | Niveau de priorité |
| `status` | incident_status | Non | `'new'` | Statut courant |
| `caller_name` | text | Oui | — | Nom de l'appelant |
| `caller_phone` | text | Oui | — | Téléphone de l'appelant |
| `citizen_id` | uuid | Oui | — | `auth.users.id` du citoyen |
| `assigned_operator_id` | uuid | Oui | — | Opérateur assigné |
| `location_lat` | double | Oui | — | Latitude GPS (fixée au SOS) |
| `location_lng` | double | Oui | — | Longitude GPS (fixée au SOS) |
| `location_address` | text | Oui | — | Adresse (auto-enrichie) |
| `commune` | text | Oui | — | Commune (auto-détectée) |
| `ville` | text | Oui | `'Kinshasa'` | Ville |
| `province` | text | Oui | `'Kinshasa'` | Province |
| `caller_realtime_lat` | double | Oui | — | Latitude temps réel |
| `caller_realtime_lng` | double | Oui | — | Longitude temps réel |
| `caller_realtime_updated_at` | timestamptz | Oui | — | Timestamp position temps réel |
| `media_urls` | text[] | Oui | `'{}'` | URLs des médias joints |
| `media_type` | text | Oui | `'photo'` | Type de média |
| `device_model` | text | Oui | — | Modèle appareil |
| `battery_level` | text | Oui | — | Niveau batterie |
| `network_state` | text | Oui | — | État réseau (wifi/4g/3g) |
| `recommended_facility` | text | Oui | — | Structure sanitaire recommandée |
| `recommended_actions` | text | Oui | — | Actions recommandées |
| `notes` | text | Oui | — | Notes opérateur |
| `incident_at` | timestamptz | Oui | — | Date/heure de l'incident |
| `ended_by` | text | Oui | — | Qui a clôturé |
| `resolved_at` | timestamptz | Oui | — | Date résolution |
| `archived_at` | timestamptz | Oui | — | Date archivage |
| `created_at` | timestamptz | Non | `now()` | Création |
| `updated_at` | timestamptz | Non | `now()` | Modification |

**FK**: `incident_id` référencé par `call_history`, `call_queue`, `dispatches`, `sos_responses`, `call_transcriptions`

---

### 3.3 `call_history` — Historique des appels

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `channel_name` | text | Non | — | Nom du canal Agora |
| `call_type` | call_type | Non | `'incoming'` | Type d'appel |
| `status` | call_status | Non | `'ringing'` | Statut courant |
| `caller_name` | text | Oui | — | Nom appelant |
| `caller_phone` | text | Oui | — | Tél. appelant |
| `citizen_id` | uuid | Oui | — | `auth.users.id` du citoyen |
| `operator_id` | uuid | Oui | — | Opérateur qui a pris l'appel |
| `incident_id` | uuid | Oui | — | FK → `incidents.id` |
| `has_video` | boolean | Oui | `false` | Appel vidéo ? |
| `agora_uid` | integer | Oui | — | UID Agora de l'opérateur |
| `agora_token` | text | Oui | — | Token Agora |
| `caller_lat` | double | Oui | — | Latitude appelant |
| `caller_lng` | double | Oui | — | Longitude appelant |
| `commune` | text | Oui | — | Commune |
| `ville` | text | Oui | `'Kinshasa'` | Ville |
| `province` | text | Oui | `'Kinshasa'` | Province |
| `role` | text | Oui | — | Rôle de l'appelant |
| `location` | jsonb | Oui | — | Données de localisation brutes |
| `triage_data` | jsonb | Oui | `'{}'` | Données de triage |
| `notes` | text | Oui | — | Notes |
| `started_at` | timestamptz | Non | `now()` | Début de l'appel |
| `answered_at` | timestamptz | Oui | — | Réponse opérateur |
| `ended_at` | timestamptz | Oui | — | Fin de l'appel |
| `ended_by` | text | Oui | — | Qui a raccroché |
| `duration_seconds` | integer | Oui | — | Durée en secondes |
| `created_at` | timestamptz | Non | `now()` | Création |

**FK**: `incident_id` → `incidents.id`
**Realtime**: Publication activée (`REPLICA IDENTITY FULL`)

---

### 3.4 `call_queue` — File d'attente

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `incident_id` | uuid | Oui | — | FK → `incidents.id` |
| `call_id` | uuid | Oui | — | FK → `call_history.id` |
| `channel_name` | text | Non | — | Canal Agora |
| `caller_name` | text | Oui | — | Nom appelant |
| `caller_phone` | text | Oui | — | Tél. appelant |
| `caller_lat` | double | Oui | — | Latitude |
| `caller_lng` | double | Oui | — | Longitude |
| `priority` | text | Non | `'medium'` | Priorité |
| `category` | text | Oui | `'general'` | Catégorie |
| `status` | text | Non | `'waiting'` | `waiting` / `assigned` / `answered` / `completed` / `abandoned` |
| `assigned_operator_id` | uuid | Oui | — | Opérateur assigné |
| `assigned_at` | timestamptz | Oui | — | Date assignation |
| `answered_at` | timestamptz | Oui | — | Date réponse |
| `completed_at` | timestamptz | Oui | — | Date clôture |
| `abandoned_at` | timestamptz | Oui | — | Date abandon |
| `estimated_wait_seconds` | integer | Oui | `0` | Attente estimée |
| `notes` | text | Oui | — | Notes |
| `created_at` | timestamptz | Non | `now()` | Création |

**FK**: `incident_id` → `incidents.id`, `call_id` → `call_history.id`

---

### 3.5 `call_recordings` — Enregistrements audio

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `call_id` | uuid | Non | — | FK → `call_history.id` |
| `incident_id` | uuid | Oui | — | FK vers incident |
| `channel_name` | text | Oui | — | Canal Agora |
| `file_url` | text | Non | — | URL du fichier |
| `file_type` | text | Non | `'audio'` | Type (`audio`/`video`) |
| `duration_seconds` | integer | Oui | — | Durée |
| `file_size_bytes` | bigint | Oui | — | Taille fichier |
| `agora_resource_id` | text | Oui | — | Resource ID Agora |
| `agora_sid` | text | Oui | — | Session ID Agora |
| `recorded_by` | uuid | Oui | — | Opérateur |
| `created_at` | timestamptz | Non | `now()` | Création |

---

### 3.6 `call_transcriptions` — Transcriptions

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `call_id` | text | Non | — | ID appel |
| `incident_id` | uuid | Oui | — | FK → `incidents.id` |
| `content` | text | Non | — | Texte transcrit |
| `speaker` | text | Non | `'unknown'` | Qui parle |
| `language` | text | Oui | `'auto'` | Langue détectée |
| `is_final` | boolean | Non | `true` | Segment final ? |
| `timestamp_ms` | bigint | Non | — | Timestamp en ms |
| `operator_id` | uuid | Oui | — | Opérateur |
| `operator_name` | text | Oui | — | Nom opérateur |
| `created_at` | timestamptz | Non | `now()` | Création |

---

### 3.7 `call_transfers` — Transferts d'appels

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `from_operator_id` | uuid | Non | — | Opérateur source |
| `to_operator_id` | uuid | Non | — | Opérateur cible |
| `call_id` | text | Oui | — | ID appel |
| `channel_name` | text | Oui | — | Canal Agora |
| `incident_id` | uuid | Oui | — | FK vers incident |
| `call_type` | text | Non | `'audio'` | `audio` / `video` |
| `status` | text | Non | `'pending'` | `pending` / `accepted` / `rejected` / `completed` |
| `context_data` | jsonb | Oui | `'{}'` | Contexte transféré |
| `transfer_notes` | text | Oui | — | Notes |
| `accepted_at` | timestamptz | Oui | — | Date acceptation |
| `rejected_at` | timestamptz | Oui | — | Date rejet |
| `created_at` | timestamptz | Non | `now()` | Création |

---

### 3.8 `call_rejections` — Rejets d'appels

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `call_id` | uuid | Non | — | ID appel |
| `operator_id` | uuid | Non | — | Opérateur qui rejette |
| `reason` | text | Non | `'manual'` | Raison du rejet |
| `rejected_at` | timestamptz | Non | `now()` | Date du rejet |

---

### 3.9 `operator_calls` — Appels inter-opérateurs

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `caller_profile_id` | uuid | Non | — | `users_directory.id` appelant |
| `callee_profile_id` | uuid | Non | — | `users_directory.id` appelé |
| `channel_name` | text | Non | — | Canal Agora |
| `call_type` | text | Non | `'audio'` | `audio` / `video` |
| `caller_name` | text | Oui | — | Nom appelant |
| `status` | text | Non | `'ringing'` | Statut |
| `started_at` | timestamptz | Non | `now()` | Début |
| `answered_at` | timestamptz | Oui | — | Réponse |
| `ended_at` | timestamptz | Oui | — | Fin |
| `created_at` | timestamptz | Non | `now()` | Création |

---

### 3.10 `sos_questions` — Questionnaire SOS

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `question_key` | text | Non | — | Identifiant unique |
| `question_text` | text | Non | — | Texte de la question |
| `question_type` | text | Non | `'single_choice'` | Type (`single_choice`, `text`, etc.) |
| `category` | text | Non | `'general'` | Catégorie |
| `template` | text | Non | `'default'` | Template SOS |
| `options` | jsonb | Oui | — | Options de réponse `[{label, weight}]` |
| `translations` | jsonb | Oui | — | Traductions |
| `display_order` | integer | Non | `0` | Ordre d'affichage |
| `is_active` | boolean | Non | `true` | Active ? |
| `is_required` | boolean | Non | `true` | Obligatoire ? |
| `parent_question_key` | text | Oui | — | Question parente |
| `show_if_answer` | jsonb | Oui | — | Affichage conditionnel |
| `created_at` | timestamptz | Non | `now()` | Création |
| `updated_at` | timestamptz | Non | `now()` | Modification |

---

### 3.11 `sos_responses` — Réponses SOS

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `incident_id` | uuid | Non | — | FK → `incidents.id` |
| `call_id` | uuid | Oui | — | FK → `call_history.id` |
| `citizen_id` | uuid | Oui | — | `auth.users.id` |
| `question_key` | text | Non | — | Clé de la question |
| `question_text` | text | Non | — | Texte de la question |
| `answer` | text | Oui | — | Réponse texte |
| `answers` | jsonb | Oui | — | Réponses multiples |
| `gravity_score` | integer | Oui | — | Score de gravité |
| `gravity_level` | text | Oui | — | Niveau (`critical`, `high`, `medium`) |
| `answered_at` | timestamptz | Oui | — | Date de réponse |
| `created_at` | timestamptz | Non | `now()` | Création |

---

### 3.12 `units` — Unités d'intervention

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `callsign` | text | Non | — | Indicatif radio (ex: `AMB-01`) |
| `type` | text | Non | — | Type (`ambulance`, `motard`, etc.) |
| `status` | unit_status | Non | `'available'` | Statut |
| `location_lat` | double | Oui | — | Latitude GPS |
| `location_lng` | double | Oui | — | Longitude GPS |
| `heading` | integer | Oui | — | Cap (degrés) |
| `battery` | integer | Oui | — | Batterie (%) |
| `network` | text | Oui | — | Réseau |
| `agent_name` | text | Oui | — | Agent principal |
| `personnel` | text[] | Oui | — | Équipage |
| `vehicle_type` | text | Oui | — | Type véhicule |
| `vehicle_plate` | text | Oui | — | Plaque |
| `tablet_id` | text | Oui | — | ID tablette |
| `app_version` | text | Oui | — | Version app mobile |
| `zone_id` | uuid | Oui | — | FK → `operational_zones.id` |
| `last_location_update` | timestamptz | Oui | — | Dernière MAJ position |
| `created_at` | timestamptz | Non | `now()` | Création |
| `updated_at` | timestamptz | Non | `now()` | Modification |

---

### 3.13 `dispatches` — Dispatches d'unités

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `incident_id` | uuid | Non | — | FK → `incidents.id` |
| `unit_id` | uuid | Non | — | FK → `units.id` |
| `rescuer_id` | uuid | Oui | — | ID du secouriste |
| `dispatched_by` | uuid | Oui | — | Opérateur ayant dispatché |
| `status` | text | Non | `'dispatched'` | Statut |
| `assigned_structure_id` | uuid | Oui | — | Structure sanitaire assignée |
| `assigned_structure_name` | text | Oui | — | Nom structure |
| `assigned_structure_type` | text | Oui | — | Type structure |
| `assigned_structure_lat` | double | Oui | — | Latitude structure |
| `assigned_structure_lng` | double | Oui | — | Longitude structure |
| `assigned_structure_phone` | text | Oui | — | Tél. structure |
| `assigned_structure_address` | text | Oui | — | Adresse structure |
| `notes` | text | Oui | — | Notes |
| `dispatched_at` | timestamptz | Non | `now()` | Date dispatch |
| `arrived_at` | timestamptz | Oui | — | Date arrivée |
| `completed_at` | timestamptz | Oui | — | Date fin |
| `created_at` | timestamptz | Non | `now()` | Création |
| `updated_at` | timestamptz | Non | `now()` | Modification |

---

### 3.14 `active_rescuers` — Positions GPS temps réel

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `user_id` | uuid | Non | — | `auth.users.id` du secouriste |
| `lat` | double | Non | — | Latitude |
| `lng` | double | Non | — | Longitude |
| `accuracy` | double | Oui | — | Précision GPS (mètres) |
| `heading` | double | Oui | — | Cap (degrés) |
| `speed` | double | Oui | — | Vitesse (m/s) |
| `battery` | integer | Oui | — | Batterie (%) |
| `status` | text | Oui | `'active'` | `active` / `en_intervention` / `offline` |
| `updated_at` | timestamptz | Non | `now()` | Dernière MAJ |

---

### 3.15 `health_structures` — Structures sanitaires

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `name` | text | Non | — | Nom courant |
| `official_name` | text | Oui | — | Nom officiel |
| `short_name` | text | Oui | — | Abréviation |
| `type` | text | Non | `'hopital'` | Type (`hopital`, `centre_sante`, `clinique`, etc.) |
| `address` | text | Non | — | Adresse |
| `phone` | text | Non | — | Téléphone |
| `email` | text | Oui | — | Email |
| `lat` | double | Oui | — | Latitude |
| `lng` | double | Oui | — | Longitude |
| `capacity` | integer | Oui | `0` | Capacité totale |
| `available_beds` | integer | Oui | `0` | Lits disponibles |
| `specialties` | text[] | Oui | `'{}'` | Spécialités |
| `equipment` | text[] | Oui | `'{}'` | Équipements |
| `operating_hours` | text | Oui | `'24h/24'` | Heures d'ouverture |
| `is_open` | boolean | Oui | `true` | Ouvert actuellement |
| `rating` | integer | Oui | — | Note (1-5) |
| `contact_person` | text | Oui | — | Personne de contact |
| `linked_user_id` | uuid | Oui | — | Utilisateur lié |
| `created_at` | timestamptz | Oui | `now()` | Création |
| `updated_at` | timestamptz | Oui | `now()` | Modification |

---

### 3.16 `signalements` — Dénonciations citoyennes

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `reference` | text | Non | — | Référence unique |
| `title` | text | Non | — | Titre |
| `description` | text | Oui | — | Description |
| `category` | text | Non | — | Catégorie (22 types) |
| `priority` | text | Non | `'medium'` | Priorité |
| `status` | text | Non | `'nouveau'` | `nouveau` / `en_cours` / `enquete` / `resolu` / `classe` / `transfere` |
| `is_anonymous` | boolean | Oui | — | Rapport anonyme |
| `citizen_name` | text | Oui | — | Nom du citoyen |
| `citizen_phone` | text | Oui | — | Tél. du citoyen |
| `commune` | text | Oui | — | Commune |
| `ville` | text | Non | `'Kinshasa'` | Ville |
| `province` | text | Non | `'Kinshasa'` | Province |
| `lat` | double | Oui | — | Latitude |
| `lng` | double | Oui | — | Longitude |
| `assigned_to` | text | Oui | — | Enquêteur assigné |
| `structure_id` | uuid | Oui | — | FK → `health_structures.id` |
| `structure_name` | text | Oui | — | Nom structure concernée |
| `created_at` | timestamptz | Oui | `now()` | Création |
| `updated_at` | timestamptz | Oui | `now()` | Modification |

---

### 3.17 `signalement_media` — Médias des signalements

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `signalement_id` | uuid | Non | — | FK → `signalements.id` |
| `url` | text | Non | — | URL du fichier |
| `filename` | text | Non | — | Nom du fichier |
| `type` | text | Non | `'image'` | `image` / `video` / `audio` |
| `thumbnail` | text | Oui | — | URL miniature |
| `duration` | integer | Oui | — | Durée (secondes) |
| `created_at` | timestamptz | Oui | `now()` | Création |

---

### 3.18 `signalement_notes` — Notes de suivi

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `signalement_id` | uuid | Non | — | FK → `signalements.id` |
| `author` | text | Non | — | Auteur |
| `text` | text | Non | — | Contenu |
| `created_at` | timestamptz | Oui | `now()` | Création |

---

### 3.19 `blocked_users` — Citoyens bloqués

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `citizen_id` | uuid | Non | — | `auth.users.id` du citoyen |
| `blocked_by` | uuid | Non | — | Opérateur |
| `reason` | text | Non | `''` | Raison |
| `duration_hours` | integer | Non | `168` | Durée (heures) |
| `expires_at` | timestamptz | Non | — | Expiration |
| `is_active` | boolean | Non | `true` | Actif |
| `incident_id` | uuid | Oui | — | Incident lié |
| `call_id` | uuid | Oui | — | Appel lié |
| `notes` | text | Oui | — | Notes |
| `blocked_at` | timestamptz | Non | `now()` | Date de blocage |
| `created_at` | timestamptz | Non | `now()` | Création |

---

### 3.20 `notifications` — Notifications push

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `user_id` | uuid | Non | — | Destinataire (`auth.users.id`) |
| `title` | text | Non | — | Titre |
| `message` | text | Non | — | Corps du message |
| `body` | text | Oui | — | Corps alternatif |
| `type` | text | Non | `'info'` | Type (`info`, `dispatch`, `alert`) |
| `reference_id` | uuid | Oui | — | ID entité liée |
| `is_read` | boolean | Non | `false` | Lu ? |
| `created_at` | timestamptz | Non | `now()` | Création |

---

### 3.21 `messages` — Messagerie opérateurs / unités

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `sender_id` | uuid | Non | — | `auth.users.id` expéditeur |
| `recipient_id` | text | Non | — | ID destinataire |
| `recipient_type` | text | Non | `'unit'` | Type (`unit`, `operator`) |
| `intervention_id` | text | Oui | — | ID intervention |
| `content` | text | Non | — | Contenu texte |
| `type` | text | Non | `'text'` | `text` / `audio` / `location` |
| `audio_url` | text | Oui | — | URL audio |
| `audio_duration` | integer | Oui | — | Durée audio |
| `read_at` | timestamptz | Oui | — | Date de lecture |
| `created_at` | timestamptz | Non | `now()` | Création |

---

### 3.22 `operational_zones` — Zones opérationnelles

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `name` | text | Non | — | Nom de la zone |
| `communes` | text[] | Non | `'{}'` | Communes couvertes |
| `color` | text | Oui | `'#3B82F6'` | Couleur (hex) |
| `description` | text | Oui | — | Description |
| `is_active` | boolean | Oui | `true` | Active |
| `created_at` | timestamptz | Oui | `now()` | Création |
| `updated_at` | timestamptz | Oui | `now()` | Modification |

---

### 3.23 `zone_units` — Affectation unités ↔ zones

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `zone_id` | uuid | Non | — | FK → `operational_zones.id` |
| `unit_id` | uuid | Non | — | FK → `units.id` |
| `assigned_at` | timestamptz | Oui | — | Date affectation |

---

### 3.24 `field_reports` — Rapports de terrain

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `user_id` | uuid | Non | — | `auth.users.id` du rapporteur |
| `unit_id` | uuid | Oui | — | FK → `units.id` |
| `category` | text | Non | — | Catégorie |
| `description` | text | Non | — | Description |
| `severity` | text | Non | `'low'` | Sévérité |
| `status` | text | Oui | `'new'` | Statut |
| `location_lat` | double | Oui | — | Latitude |
| `location_lng` | double | Oui | — | Longitude |
| `created_at` | timestamptz | Oui | `now()` | Création |
| `updated_at` | timestamptz | Oui | `now()` | Modification |

---

### 3.25 `commune_bounds` — Limites géographiques communes

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `commune_name` | text | Non | — | Nom de la commune |
| `min_lat` | double | Non | — | Latitude min (sud) |
| `max_lat` | double | Non | — | Latitude max (nord) |
| `min_lng` | double | Non | — | Longitude min (ouest) |
| `max_lng` | double | Non | — | Longitude max (est) |

---

### 3.26 `commune_health_data` — Données sanitaires par commune

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Clé primaire |
| `commune_name` | text | Non | — | Commune |
| `zone_sante_name` | text | Non | — | Zone de santé |
| `population` | integer | Non | `0` | Population |
| `nb_aires_sante` | integer | Non | `0` | Nombre d'aires de santé |
| `nb_ess` | integer | Non | `0` | Nombre d'ESS |
| `nb_villages_avenues` | integer | Non | `0` | Nombre villages/avenues |
| `created_at` | timestamptz | Oui | `now()` | Création |

---

## 4. Vues matérialisées (lecture seule)

| Vue | Description | Colonnes clés |
|---|---|---|
| `mv_incidents_by_commune` | Incidents agrégés par commune | `commune`, `type`, `priority`, `status`, `total`, `first_at`, `last_at` |
| `mv_daily_kpis` | KPIs journaliers | `day`, `total_incidents`, `resolved_count`, `critical_count`, `high_count`, `avg_resolution_seconds` |
| `mv_signalements_by_commune` | Signalements agrégés par commune | `commune`, `category`, `priority`, `status`, `total` |
| `mv_calls_by_commune` | Appels agrégés par commune | `commune`, `call_type`, `status`, `total`, `avg_duration_seconds` |

---

## 5. Fonctions SQL publiques

| Fonction | Arguments | Retour | Description |
|---|---|---|---|
| `get_user_role(p_auth_user_id)` | uuid | text | Retourne le rôle d'un utilisateur |
| `is_citizen_blocked(p_citizen_id)` | uuid | jsonb | Vérifie si un citoyen est bloqué |
| `auto_assign_queue()` | — | void | Attribution auto des appels en attente |
| `cleanup_stale_queue_entries()` | — | void | Nettoyage file d'attente expirée |
| `cleanup_stale_operators()` | — | void | Déconnexion opérateurs inactifs |
| `cleanup_expired_rate_limits()` | — | void | Purge rate limits expirés |
| `is_linked_structure(p_structure_id, p_user_id)` | uuid, uuid | boolean | Vérifie lien structure-utilisateur |
| `refresh_api_materialized_views()` | — | void | Rafraîchit les vues matérialisées |

---

## 6. Edge Functions (API endpoints)

Base URL: `https://<PROJECT_URL>/functions/v1/`

| Endpoint | Méthode | Auth | Description |
|---|---|---|---|
| `twilio-verify` | POST | Anon | Envoi/vérification OTP SMS |
| `complete-profile` | POST | JWT | Complétion profil citoyen |
| `update-phone` | POST | JWT | Mise à jour numéro téléphone |
| `agora-token` | POST | JWT | Génération token Agora RTC |
| `agora-recording` | POST | JWT | Gestion enregistrement cloud |
| `startCloudRecording` | POST | JWT | Démarrer enregistrement |
| `stopCloudRecording` | POST | JWT | Arrêter enregistrement |
| `rescuer-call-citizen` | POST | JWT | Appel urgentiste → citoyen |
| `create-user` | POST | JWT (admin) | Création utilisateur professionnel |
| `send-credentials` | POST | JWT (admin) | Envoi identifiants par email |
| `send-reset-password` | POST | JWT (admin) | Email reset mot de passe |
| `agent-login` | POST | Anon | Connexion mobile (login_id + PIN) |
| `send-call-push` | POST | JWT | Notification push appel entrant |
| `elevenlabs-scribe-token` | POST | JWT | Token transcription |
| `reverse-geocode` | POST | JWT | Géocodage inversé |
| `opencellid-proxy` | POST | JWT | Proxy antennes cellulaires |
| `dhis2-export` | POST | JWT (admin) | Export données DHIS2 |
| `dhis2-tracker-export` | POST | JWT (admin) | Export tracker DHIS2 |
| `api-gateway` | ALL | API Key | Passerelle API partenaires |

**Webhooks / Edge (ce dépôt)** — Les fonctions sous `supabase/functions/` ne dupliquent pas les lignes SOS :

| Fichier | Déclenché par | Effet sur `incidents` / `call_history` |
|---|---|---|
| `send-call-notification/index.ts` | Webhook sur **INSERT** `call_history` (`status = ringing`) | Aucun INSERT : envoi FCM uniquement ; ignore les canaux `SOS-*` / `CALLBACK-*` (appels citoyen → centrale). |
| `send-dispatch-notification/index.ts` | Webhook sur mise à jour **dispatches** | Aucun INSERT sur incidents/call_history. |

Les **triggers PostgreSQL** (ex. file `call_queue`, `on_call_history_status_change`, dédoublonnage incident) ne sont pas versionnés dans ce dépôt ; à contrôler dans le SQL Editor Supabase du projet.

---

## 7. Storage (Buckets)

| Bucket | Public | Usage |
|---|---|---|
| `avatars` | Oui | Photos de profil |
| `incidents` | Non | Médias liés aux incidents (auth requise) |

**URL fichier public**: `https://<PROJECT_URL>/storage/v1/object/public/avatars/<path>`
**URL fichier privé**: nécessite un `signedUrl` via le SDK

---

## 8. Realtime

Tables avec publication Realtime activée :

| Table | Identity | Usage |
|---|---|---|
| `call_history` | FULL | Signalisation appels entrants (filtre par `citizen_id`) |
| `incidents` | DEFAULT | Suivi statut SOS |
| `call_queue` | DEFAULT | File d'attente |
| `active_rescuers` | DEFAULT | Positions secouristes |
| `dispatches` | DEFAULT | Missions |
| `notifications` | DEFAULT | Notifications push |
| `messages` | DEFAULT | Messagerie |
| `operator_calls` | DEFAULT | Appels inter-opérateurs |

---

## 9. Politiques d'accès (RLS) — Résumé par rôle

### Citoyen (`citoyen`)

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `users_directory` | Propre profil | — | Propre profil | — |
| `incidents` | Propres incidents | Oui | — | — |
| `call_history` | Propres appels | Oui | Propres appels | — |
| `notifications` | Propres notifs | — | Propres notifs | — |
| `sos_responses` | Propres réponses | Oui | — | — |
| `signalement_media` | Tous | Oui | — | — |
| `health_structures` | Tous | — | — | — |
| `commune_bounds` | Tous (public) | — | — | — |

### Secouriste / Volontaire (`secouriste`, `volontaire`)

Accès citoyen + :

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `active_rescuers` | Tous | Oui | Propre position | Propre position |
| `incidents` | Tous (opérationnels) | Oui (secouriste) | Incidents assignés | — |
| `dispatches` | Tous | — | Propre unité | — |
| `field_reports` | Propres rapports | Oui | — | — |
| `messages` | Opérationnels | Oui | Propres messages | — |

### Opérateur / Admin / Superviseur (`call_center`, `admin`, `superviseur`)

Accès complet en lecture et écriture sur toutes les tables opérationnelles.

---

## 10. Relations (Foreign Keys)

```text
call_history.incident_id        → incidents.id
call_queue.incident_id          → incidents.id
call_queue.call_id              → call_history.id
call_recordings.call_id         → call_history.id
call_transcriptions.incident_id → incidents.id
sos_responses.incident_id       → incidents.id
sos_responses.call_id           → call_history.id
sos_questions_audit.question_id → sos_questions.id
dispatches.incident_id          → incidents.id
dispatches.unit_id              → units.id
units.zone_id                   → operational_zones.id
zone_units.zone_id              → operational_zones.id
zone_units.unit_id              → units.id
users_directory.assigned_unit_id→ units.id
field_reports.unit_id           → units.id
signalement_media.signalement_id→ signalements.id
signalement_notes.signalement_id→ signalements.id
signalements.structure_id      → health_structures.id
api_access_logs.api_key_id     → api_keys.id
api_access_logs.partner_id     → api_partners.id
api_key_scopes.api_key_id      → api_keys.id
api_keys.partner_id            → api_partners.id
```

---

## 11. SOS — « Deux entrées » sur le dashboard centrale

**Modèle attendu côté app citoyenne** : un SOS crée **une** ligne `incidents` et **une** ligne `call_history` liée (`incident_id`), canal Agora = `incidents.reference`.

**Pourquoi la centrale peut afficher deux lignes pour un seul SOS**

1. **Aggregation / UI** : une vue qui liste ou compte à la fois des **incidents** et des **lignes `call_history`** sans les fusionner par `incident_id` peut montrer **deux lignes** pour le **même** événement. Vérifier la requête ou l’API du dashboard (projet hors app mobile).
2. **Doublon réel dans `call_history`** : possible si un trigger ou un autre writer insère aussi un `call_history` après un `INSERT` sur `incidents` alors que le client en insère déjà un — à valider dans le SQL Supabase (voir § 6 ci‑dessus).
3. **Données test** : comparer `incident_id` / `channel_name` / horodatage — distinguer **deux lignes `call_history`** identiques vs **une ligne incident + une ligne appel**.

---

*Document généré le 5 avril 2026 — Projet PABX Étoile Bleue v3*
