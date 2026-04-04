# PROMPT CURSOR — Alignement Mobile ↔ Dashboard

> Document de référence pour l'équipe mobile (Flutter/Cursor). Résume l'intégralité des implémentations côté dashboard et base de données pour garantir un alignement end-to-end.

---

## 1. Architecture Globale

- **Backend** : Supabase (PostgreSQL + Auth + Realtime + Storage + Edge Functions)
- **Dashboard** : React 18 + Vite + Tailwind CSS + TypeScript
- **Mobile** : Flutter (à aligner)
- **Communication temps réel** : Supabase Realtime (postgres_changes) + Agora RTC (appels audio/vidéo)
- **Authentification** : Supabase Auth (email/password, pas d'auto-confirm)

---

## 2. Schéma de la Base de Données

### 2.1 `sos_questions` — Questions du questionnaire SOS (dynamiques)

| Colonne | Type | Default | Description |
|---------|------|---------|-------------|
| id | uuid | gen_random_uuid() | PK |
| question_key | text | — | Identifiant unique de la question (ex: `urgency_type`) |
| question_text | text | — | Texte en français (source de vérité) |
| question_type | text | `single_choice` | Type de question |
| options | jsonb | `[]` | `[{"label": "Oui", "weight": 3}, {"label": "Non", "weight": 0}]` |
| display_order | integer | 0 | Ordre d'affichage |
| is_active | boolean | true | Question active |
| is_required | boolean | false | Question obligatoire |
| category | text | `triage` | Catégorie logique |
| template | text | `default` | Template d'urgence |
| parent_question_key | text | null | Question parente (cascade) |
| show_if_answer | jsonb | null | `["Oui"]` — afficher si la réponse parente est dans ce tableau |
| translations | jsonb | `{}` | Voir format ci-dessous |
| created_at | timestamptz | now() | — |
| updated_at | timestamptz | now() | — |

**Format `translations`** :
```json
{
  "en": { "text": "Is the person conscious?", "options": ["Yes", "No"] },
  "ln": { "text": "Moto azali na mayi?", "options": ["Iyo", "Te"] },
  "sw": { "text": "Mtu yuko na fahamu?", "options": ["Ndiyo", "Hapana"] },
  "ts": { "text": "Muntu udi ne meji?", "options": ["Eyowu", "To"] },
  "kg": { "text": "Muntu wena wawukidi?", "options": ["Inga", "Ve"] }
}
```

**IMPORTANT** : Les réponses sont TOUJOURS enregistrées en français (label du champ `options`), quel que soit la langue d'affichage. La correspondance se fait par index : `translations.ln.options[0]` → `options[0].label`.

### 2.2 `sos_responses` — Réponses au questionnaire

| Colonne | Type | Default | Description |
|---------|------|---------|-------------|
| id | uuid | gen_random_uuid() | PK |
| incident_id | uuid | null | FK → incidents.id |
| call_id | uuid | null | FK → call_history.id |
| citizen_id | uuid | null | ID du citoyen authentifié |
| question_key | text | — | Réf. vers sos_questions.question_key |
| question_text | text | — | Texte de la question au moment de la réponse |
| answer | text | null | Réponse en français (label de l'option) |
| answered_at | timestamptz | null | Horodatage de la réponse |
| gravity_score | integer | 0 | Score de gravité calculé (somme des poids) |
| gravity_level | text | `low` | `low` / `high` / `critical` |
| answers | jsonb | `{}` | Réponses consolidées (format mobile) |
| created_at | timestamptz | now() | — |

**Index unique** : `(incident_id, question_key) WHERE incident_id IS NOT NULL` — permet l'upsert.

**Stratégie d'écriture** :
- Le **mobile** écrit une ligne par réponse avec `question_key`, `answer`, `answered_at`
- Le mobile met aussi à jour `gravity_score` et `gravity_level` sur chaque ligne
- Le **dashboard** peut aussi écrire/modifier via upsert (l'opérateur répond à la place du citoyen)
- Le `gravity_score` = somme de tous les `weight` des options sélectionnées
- Le `gravity_level` : `critical` si score >= 7, `high` si >= 4, `low` sinon

### 2.3 `incidents` — Dossiers d'intervention

| Colonne | Type | Description |
|---------|------|-------------|
| id | uuid | PK |
| reference | text | Identifiant unique (= channel_name Agora) |
| type | text | Type d'urgence |
| title | text | Titre |
| status | enum | `new`, `pending`, `dispatched`, `en_route`, `arrived`, `investigating`, `in_progress`, `ended`, `resolved`, `archived` |
| priority | enum | `critical`, `high`, `medium`, `low` |
| citizen_id | uuid | ID du citoyen |
| caller_name, caller_phone | text | Info appelant |
| location_lat, location_lng | double | Position initiale |
| caller_realtime_lat, caller_realtime_lng | double | Position temps réel (mise à jour par le mobile) |
| caller_realtime_updated_at | timestamptz | Horodatage de la dernière position |
| device_model, battery_level, network_state | text | Télémétrie appareil |
| recommended_actions | text | Actions recommandées par l'opérateur |
| recommended_facility | text | Structure de santé recommandée |
| commune, ville, province | text | Localisation administrative |
| media_urls | text[] | URLs des médias joints |
| notes | text | Notes opérateur |

### 2.4 `call_history` — Historique des appels

| Colonne | Type | Description |
|---------|------|-------------|
| id | uuid | PK |
| channel_name | text | Nom du canal Agora (= incident.reference) |
| citizen_id | uuid | ID citoyen |
| call_type | enum | `incoming`, `outgoing`, `internal` |
| status | enum | `ringing`, `active`, `completed`, `missed`, `failed` |
| caller_name, caller_phone | text | — |
| caller_lat, caller_lng | double | — |
| started_at, answered_at, ended_at | timestamptz | — |
| triage_data | jsonb | Données de triage mobile |

**REPLICA IDENTITY FULL** activé pour filtrage Realtime par `citizen_id`.

### 2.5 `call_queue` — File d'attente

Créée automatiquement par trigger `on_incident_created()` quand un incident est créé avec status `new`.

### 2.6 `dispatches` — Unités dépêchées

| Colonne | Type | Description |
|---------|------|-------------|
| id | uuid | PK |
| incident_id | uuid | FK → incidents |
| unit_id | uuid | FK → units |
| rescuer_id | uuid | ID du secouriste individuel |
| status | text | `dispatched`, `en_route`, `arrived`, `completed` |
| dispatched_at, arrived_at, completed_at | timestamptz | — |

### 2.7 `notifications`

| Colonne | Type | Description |
|---------|------|-------------|
| id | uuid | PK |
| user_id | uuid | Destinataire |
| title, message | text | — |
| type | text | `info`, `sos`, `dispatch`, etc. |
| is_read | boolean | — |

**RLS** : Les citoyens ne voient que leurs propres notifications. Les opérateurs voient tout.

### 2.8 `users_directory` — Annuaire des utilisateurs

Contient tous les profils (citoyens, opérateurs, secouristes, etc.)

| Champs clés | Description |
|---|---|
| auth_user_id | Lien vers auth.users |
| role | `citoyen`, `secouriste`, `call_center`, `hopital`, `volontaire`, `superviseur`, `admin` |
| language | `fr`, `en`, `ln`, `sw`, `ts`, `kg` — défaut `fr` |
| fcm_token | Token Firebase pour push notifications |
| blood_type, allergies, medical_history, medications | Dossier médical |
| emergency_contact_name, emergency_contact_phone | Contact d'urgence |

---

## 3. Edge Functions Disponibles

### 3.1 `agora-token`
Génère un token Agora pour rejoindre un canal.
```
POST /agora-token
Body: { channelName: string, uid?: number, role?: "publisher"|"subscriber" }
Response: { token: string, uid: number }
```

### 3.2 `twilio-verify`
Vérification OTP par SMS.
```
POST /twilio-verify
Body: { phone: string, action: "send"|"verify", code?: string }
Response: { success: boolean, status?: string }
```

### 3.3 `complete-profile`
Complète le profil du citoyen après vérification OTP.
```
POST /complete-profile (JWT requis)
Body: { first_name, last_name, date_of_birth?, address?, blood_type?, allergies?, medical_history?, medications?, emergency_contact_name?, emergency_contact_phone?, language? }
Response: { success: true, user: {...} }
```

### 3.4 `update-phone`
Met à jour le numéro de téléphone d'un utilisateur authentifié.
```
POST /update-phone (JWT requis)
Body: { new_phone: string }
Response: { success: true }
```

### 3.5 `send-call-push`
Envoie une notification push FCM pour un appel entrant.
```
POST /send-call-push
Body: { citizen_id: string, channel_name: string, caller_name?: string, call_type?: string }
```

### 3.6 `send-reset-password`
Envoie un email de réinitialisation de mot de passe.

### 3.7 `create-user`
Crée un utilisateur (admin only).

---

## 4. Stratégie Realtime

### Tables avec Realtime activé :
- `call_history` — signaux d'appels entrants (filtrer par `citizen_id`)
- `incidents` — mises à jour de statut en temps réel
- `sos_responses` — synchronisation des réponses SOS entre mobile et dashboard
- `call_queue` — file d'attente
- `dispatches` — suivi des unités dépêchées
- `notifications` — notifications push in-app
- `units` — positions des unités
- `active_rescuers` — positions des secouristes
- `messages` — messagerie instantanée

### Bonnes pratiques :
- Utiliser des noms de canaux uniques : `channel-${Date.now()}-${random}`
- Pour données à faible fréquence, préférer l'invalidation manuelle du cache
- Toujours `removeChannel()` au démontage du composant

---

## 5. Flux SOS Complet (Mobile → Dashboard)

### 5.1 Citoyen déclenche un SOS
1. Mobile crée un `incident` avec `status: 'new'`, `citizen_id`, position GPS, télémétrie
2. Le trigger `on_incident_created()` vérifie le blocage, crée une entrée `call_queue`, auto-assigne un opérateur
3. Le trigger `deduplicate_incident()` empêche les doublons (30s)
4. Mobile appelle `agora-token` pour obtenir un token et rejoindre le canal
5. Mobile envoie `send-call-push` pour notifier l'opérateur assigné

### 5.2 Questionnaire SOS (pendant l'appel)
1. Mobile charge les questions depuis `sos_questions` (avec Realtime pour mises à jour)
2. Pour chaque réponse : upsert dans `sos_responses` avec `incident_id` + `question_key`
3. Après chaque réponse, recalculer `gravity_score` et `gravity_level`
4. Le dashboard voit les réponses en temps réel et peut les modifier

### 5.3 Dispatch
1. L'opérateur dispatche une unité → insert dans `dispatches`
2. Le secouriste reçoit la notification avec les données SOS (gravity_score, réponses, position)
3. Le secouriste met à jour sa position via `active_rescuers`

### 5.4 Fin d'appel
1. Le trigger `on_call_history_status_change()` met à jour `call_queue` et `incidents`
2. L'opérateur libéré reçoit le prochain appel en attente via `auto_assign_queue()`

---

## 6. Calcul du Score de Gravité

```dart
int calculateGravityScore(List<SOSResponse> responses, List<SOSQuestion> questions) {
  int total = 0;
  for (final response in responses) {
    if (response.answer == null) continue;
    final question = questions.firstWhereOrNull((q) => q.questionKey == response.questionKey);
    if (question == null) continue;
    final option = question.options.firstWhereOrNull((o) => o.label == response.answer);
    total += option?.weight ?? 0;
  }
  return total;
}

String getGravityLevel(int score) {
  if (score >= 7) return 'critical';
  if (score >= 4) return 'high';
  return 'low';
}
```

---

## 7. Gestion des Langues

**6 langues supportées** : `fr` (défaut), `en`, `ln` (Lingala), `sw` (Swahili), `ts` (Tshiluba), `kg` (Kikongo)

### Affichage d'une question :
```dart
String getQuestionText(SOSQuestion q, String lang) {
  if (lang == 'fr') return q.questionText;
  return q.translations[lang]?.text ?? q.questionText; // fallback FR
}

List<String> getOptionLabels(SOSQuestion q, String lang) {
  if (lang == 'fr') return q.options.map((o) => o.label).toList();
  final translated = q.translations[lang]?.options;
  if (translated != null && translated.length == q.options.length) return translated;
  return q.options.map((o) => o.label).toList(); // fallback FR
}
```

### Enregistrement de la réponse :
**TOUJOURS en français** (label de `options[index].label`), même si l'utilisateur voit la version traduite.

---

## 8. Points de Vérification End-to-End

- [ ] Le mobile peut lire `sos_questions` et recevoir les mises à jour Realtime
- [ ] Le mobile peut faire un upsert dans `sos_responses` avec `(incident_id, question_key)`
- [ ] Le `gravity_score` et `gravity_level` sont calculés et écrits à chaque réponse
- [ ] Les réponses sont enregistrées en français quel que soit la langue d'affichage
- [ ] La logique conditionnelle (`parent_question_key` + `show_if_answer`) fonctionne
- [ ] La position temps réel du citoyen met à jour `incidents.caller_realtime_lat/lng`
- [ ] La télémétrie appareil est envoyée dans `incidents` (device_model, battery_level, network_state)
- [ ] Le `triage_data` dans `call_history` est au format `{ category, isConscious, isBreathing, ... }`
- [ ] Les notifications push FCM fonctionnent pour les appels entrants
- [ ] L'Edge Function `update-phone` met à jour le numéro correctement
- [ ] Le citoyen ne peut voir que ses propres notifications (RLS)
- [ ] Le champ `language` de `users_directory` est mis à jour quand le citoyen change de langue
- [ ] Les médias (photos/vidéos) sont uploadés dans le bucket `incidents` de Storage

---

## 9. Tables avec Index Partiels (Performance)

```sql
idx_call_history_ringing      ON call_history(status) WHERE status = 'ringing'
idx_notifications_unread      ON notifications(user_id) WHERE is_read = false
idx_incidents_active          ON incidents(status) WHERE status NOT IN ('resolved','archived','ended')
idx_call_queue_waiting        ON call_queue(status, created_at) WHERE status = 'waiting'
idx_sos_responses_incident    ON sos_responses(incident_id, question_key) WHERE incident_id IS NOT NULL
```

---

## 10. Rate Limiting

La table `rate_limits` est disponible pour contrôler le débit des Edge Functions. Accessible uniquement par `service_role`.

| Colonne | Type | Description |
|---------|------|-------------|
| key | text | Identifiant de la limite (ex: `update-phone:{user_id}`) |
| count | integer | Nombre d'appels dans la fenêtre |
| window_start | timestamptz | Début de la fenêtre |
| expires_at | timestamptz | Expiration (défaut: +1 minute) |

---

*Document généré le 2026-03-31. Projet Lovable ID: 59cff7e3-cbf4-4772-934c-0d4470d461f9*
