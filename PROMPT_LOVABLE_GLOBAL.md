# PROMPT GLOBAL POUR LOVABLE — Synchronisation Backend & Dashboard

Ce document rassemble **toutes** les spécifications côté base de données (Supabase), Edge Functions, Realtime, Storage et tableau de bord (Dashboard Lovable) pour assurer la compatibilité complète avec l'application mobile Étoile Bleue après toutes les mises à jour.

---

## 1. SCHÉMA COMPLET DE LA BASE DE DONNÉES

### 1.1 Table `call_history` — Flux d'appels (CRITIQUE)

C'est la table centrale du système d'appels. L'application mobile écoute les INSERT via Supabase Realtime pour détecter les appels entrants du dashboard.

```sql
CREATE TABLE IF NOT EXISTS call_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  channel_name TEXT NOT NULL,
  caller_name TEXT,
  caller_phone TEXT,
  caller_lat DOUBLE PRECISION,
  caller_lng DOUBLE PRECISION,
  incident_id UUID REFERENCES incidents(id) ON DELETE SET NULL,
  citizen_id UUID NOT NULL REFERENCES auth.users(id),
  call_type TEXT NOT NULL CHECK (call_type IN ('incoming', 'outgoing', 'internal')),
  status TEXT NOT NULL DEFAULT 'ringing' CHECK (status IN ('ringing', 'active', 'completed', 'missed', 'failed', 'abandoned')),
  agora_token TEXT,
  agora_uid INTEGER,
  triage_data JSONB,
  started_at TIMESTAMPTZ,
  answered_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  ended_by TEXT CHECK (ended_by IN ('citizen', 'operator', 'citizen_hangup', 'citizen_rejected')),
  duration_seconds INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_call_history_citizen ON call_history(citizen_id);
CREATE INDEX idx_call_history_channel ON call_history(channel_name);
CREATE INDEX idx_call_history_incident ON call_history(incident_id);
```

| Colonne | Type | Description |
|---------|------|-------------|
| `channel_name` | text | Nom du canal Agora (unique par appel) = `incident.reference` |
| `call_type` | text | `'incoming'` = citoyen SOS vers dashboard, `'outgoing'` = dashboard vers citoyen, `'internal'` = inter-opérateurs |
| `status` | text | `'ringing'` → `'active'` → `'completed'` ou `'missed'` ou `'failed'` ou `'abandoned'` |
| `triage_data` | jsonb | Données de triage écrites par le mobile (`{"category": "Accident", ...}`) |
| `agora_token` | text | Token RTC généré par l'Edge Function `agora-token` |
| `answered_at` | timestamptz | Horodatage du décrochage — voir note sémantique ci-dessous |
| `ended_by` | text | `'citizen'`, `'citizen_hangup'`, `'citizen_rejected'`, ou `'operator'` |
| `duration_seconds` | integer | Durée réelle de conversation (calculée par le mobile : `ended_at - answered_at`) |

**Contrat critique pour les appels dashboard → citoyen :**

Pour qu'un citoyen reçoive un appel, le dashboard doit insérer une ligne avec :
```sql
INSERT INTO call_history (channel_name, caller_name, citizen_id, call_type, status, agora_token)
VALUES ('<nom_canal_agora>', '<nom_operateur>', '<uuid_citoyen>', 'outgoing', 'ringing', '<token>');
```

Le mobile détecte cet INSERT via Realtime (canal `incoming-calls-$userId`, filtre `citizen_id = auth.uid()`, événement INSERT) et affiche l'interface CallKit native.

---

### 1.2 Table `incidents` — Incidents et télémétrie

```sql
CREATE TABLE IF NOT EXISTS incidents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  reference TEXT,
  type TEXT,
  title TEXT,
  description TEXT,
  caller_name TEXT,
  caller_phone TEXT,
  location_lat DOUBLE PRECISION,
  location_lng DOUBLE PRECISION,
  caller_realtime_lat DOUBLE PRECISION,
  caller_realtime_lng DOUBLE PRECISION,
  caller_realtime_updated_at TIMESTAMPTZ,
  location_address TEXT,
  priority TEXT DEFAULT 'high',
  status TEXT NOT NULL DEFAULT 'new',
  citizen_id UUID REFERENCES auth.users(id),
  media_urls TEXT[],
  media_type TEXT,
  incident_at TIMESTAMPTZ,
  province TEXT,
  ville TEXT,
  ended_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Télémétrie appareil (envoyée par le mobile au moment du SOS)
  device_model TEXT,
  battery_level TEXT,
  network_state TEXT,
  -- Recommandations temps réel (écrites par le dashboard)
  recommended_actions TEXT,
  recommended_facility TEXT
);

CREATE INDEX idx_incidents_citizen ON incidents(citizen_id);
CREATE INDEX idx_incidents_status ON incidents(status);
CREATE INDEX idx_incidents_created ON incidents(created_at DESC);
```

| Colonne | Écrit par | Description |
|---------|-----------|-------------|
| `device_model` | Mobile | Ex: "TECNO Spark 10", "iPhone 13" |
| `battery_level` | Mobile | Ex: "85%" — Afficher en rouge si < 20% |
| `network_state` | Mobile | Ex: "WiFi", "Mobile", "None" — Afficher en orange si "None" |
| `recommended_actions` | Dashboard | Consignes de premiers secours pour le citoyen |
| `recommended_facility` | Dashboard | Hôpital/clinique vers lequel orienter le patient |
| `caller_realtime_lat/lng` | Mobile | Position GPS mise à jour en temps réel pendant l'incident |
| `caller_realtime_updated_at` | Mobile | Horodatage de la dernière mise à jour de position GPS |
| `media_urls` | Mobile | URLs des photos/vidéos depuis le bucket Storage `incidents` |

**Statuts gérés par le mobile pour la timeline :**

| Statut | Groupe | Description |
|--------|--------|-------------|
| `new` | En attente | Incident vient d'être créé |
| `pending` | En attente | En attente de prise en charge |
| `dispatched` | En cours | Unité assignée (timeline step 1) |
| `en_route` | En cours | Unité en route (timeline step 2) |
| `arrived` | En cours | Unité sur place (timeline step 3) |
| `investigating` | En cours | Intervention en cours |
| `ended` | Terminé | Incident clos |
| `resolved` | Terminé | Incident résolu |
| `archived` | Terminé | Archivé |

Le dashboard doit permettre de changer le statut d'un incident. Chaque changement est reçu en temps réel par le mobile via Realtime.

---

### 1.3 Table `dispatches` — Assignation d'unités

L'app mobile s'abonne en Realtime à cette table pour mettre à jour la timeline de suivi (en route, sur place, etc.).

```sql
CREATE TABLE IF NOT EXISTS dispatches (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  rescuer_id UUID REFERENCES auth.users(id),
  status TEXT NOT NULL DEFAULT 'dispatched' CHECK (status IN ('dispatched', 'en_route', 'arrived', 'completed')),
  assigned_at TIMESTAMPTZ,
  departed_at TIMESTAMPTZ,
  arrived_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_dispatches_incident ON dispatches(incident_id);
```

| Statut dispatch | Effet sur le mobile |
|-----------------|---------------------|
| `dispatched` | Timeline → "Assigné" |
| `en_route` | Timeline → "En route" |
| `arrived` | Timeline → "Sur place" |
| `completed` | Timeline → "Terminé" |

---

### 1.4 Table `users_directory` — Profils utilisateurs

```sql
CREATE TABLE IF NOT EXISTS users_directory (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  auth_user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  first_name TEXT,
  last_name TEXT,
  phone TEXT,
  status TEXT DEFAULT 'offline' CHECK (status IN ('online', 'offline')),
  last_seen_at TIMESTAMPTZ,
  fcm_token TEXT,
  blood_type TEXT,
  allergies TEXT,
  medical_history TEXT,
  medications TEXT,
  emergency_contact_name TEXT,
  emergency_contact_phone TEXT,
  photo_url TEXT,
  address TEXT,
  language TEXT,
  date_of_birth TEXT,
  available BOOLEAN DEFAULT false,
  specialization TEXT,
  zone TEXT,
  vehicle_id TEXT,
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_directory_auth ON users_directory(auth_user_id);
```

**Comportement mobile :**
- À la connexion : `UPDATE users_directory SET status = 'online', last_seen_at = now() WHERE auth_user_id = <uid>`
- À la déconnexion : `UPDATE users_directory SET status = 'offline' WHERE auth_user_id = <uid>`
- Le `fcm_token` est mis à jour automatiquement par le service FCM du mobile

---

### 1.5 Table `notifications` — Centre de notifications

```sql
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'info' CHECK (type IN ('info', 'alert', 'system', 'course')),
  is_read BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_notifications_created ON notifications(created_at DESC);
```

Le mobile stream cette table en Realtime et affiche un badge sur l'icône cloche. Quand l'utilisateur ouvre la page Notifications, toutes les notifications non lues sont marquées `is_read = true`.

---

### 1.6 Table `messages` — Messagerie opérateur-citoyen

```sql
CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sender_id UUID NOT NULL REFERENCES auth.users(id),
  recipient_id UUID NOT NULL REFERENCES auth.users(id),
  recipient_type TEXT DEFAULT 'operator',
  content TEXT,
  type TEXT NOT NULL DEFAULT 'text' CHECK (type IN ('text', 'audio')),
  audio_url TEXT,
  audio_duration INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_messages_sender ON messages(sender_id);
CREATE INDEX idx_messages_recipient ON messages(recipient_id);
CREATE INDEX idx_messages_created ON messages(created_at);
```

Le mobile écoute les INSERT en Realtime sur le canal `messages-$recipientId` et affiche les nouveaux messages dans l'interface de chat.

---

### 1.7 Table `active_rescuers` — Positions GPS des secouristes

```sql
CREATE TABLE IF NOT EXISTS active_rescuers (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  lat DOUBLE PRECISION NOT NULL,
  lng DOUBLE PRECISION NOT NULL,
  accuracy DOUBLE PRECISION,
  heading DOUBLE PRECISION,
  speed DOUBLE PRECISION,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

> **Note technique :** L'app mobile a deux fichiers qui accèdent à cette table — `location_service.dart` utilise la colonne `uid` et `rescuer_gps_provider.dart` utilise `user_id`. La colonne primaire dans le schéma doit être `user_id`. Si une colonne `uid` existe en héritage, ajouter un alias ou la renommer.

---

### 1.8 Table `calls` (LEGACY — module SOS vocal désactivé)

```sql
CREATE TABLE IF NOT EXISTS calls (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  citizen_id UUID REFERENCES auth.users(id),
  rescuer_id UUID REFERENCES auth.users(id),
  status TEXT DEFAULT 'pending',
  call_type TEXT,
  type TEXT,
  location JSONB,
  recording JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Cette table est utilisée uniquement par le module SOS vocal (désactivé) et le cloud recording (lecture du champ `recording`). Ne pas supprimer mais ne pas y ajouter de nouvelles fonctionnalités.

---

### 1.9 Table `call_transcriptions` — Transcriptions temps réel

Le dashboard écrit les transcriptions audio (opérateur + appelant) dans cette table pendant un appel actif. Le mobile peut s'y abonner en Realtime pour afficher la transcription en direct.

```sql
CREATE TABLE IF NOT EXISTS call_transcriptions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  call_id TEXT NOT NULL,
  speaker TEXT NOT NULL CHECK (speaker IN ('operator', 'caller')),
  content TEXT NOT NULL,
  language TEXT DEFAULT 'fra',
  operator_id UUID REFERENCES auth.users(id),
  operator_name TEXT,
  incident_id UUID REFERENCES incidents(id),
  is_final BOOLEAN NOT NULL DEFAULT false,
  timestamp_ms BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_transcriptions_call ON call_transcriptions(call_id);
CREATE INDEX idx_transcriptions_incident ON call_transcriptions(incident_id);
```

| Colonne | Type | Description |
|---------|------|-------------|
| `call_id` | text | = `channel_name` Agora (même que `call_history.channel_name`) |
| `speaker` | text | `'operator'` ou `'caller'` — identifie la source audio |
| `content` | text | Texte transcrit par le STT du dashboard |
| `language` | text | Code ISO 639-3 de la langue détectée (`'fra'`, `'eng'`, `'swa'`) |
| `is_final` | boolean | `false` = transcription partielle (en cours), `true` = segment final |
| `timestamp_ms` | bigint | Horodatage en millisecondes depuis le début de l'appel |

**RLS :**
```sql
ALTER TABLE call_transcriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Citizens read transcriptions for own calls"
  ON call_transcriptions FOR SELECT TO authenticated
  USING (call_id IN (SELECT channel_name FROM call_history WHERE citizen_id = auth.uid()));

CREATE POLICY "Service role full access transcriptions"
  ON call_transcriptions FOR ALL TO service_role
  USING (true) WITH CHECK (true);
```

**Publication Realtime :**
```sql
ALTER PUBLICATION supabase_realtime ADD TABLE call_transcriptions;
```

---

### 1.10 Fonction SQL `cleanup_stale_queue_entries()` — Nettoyage automatique

Cette fonction marque les appels en `waiting` ou `assigned` depuis plus de 5 minutes comme `abandoned`. Elle doit être appelée périodiquement (toutes les 30 secondes côté dashboard, ou via un cron Supabase).

```sql
CREATE OR REPLACE FUNCTION cleanup_stale_queue_entries()
RETURNS void AS $$
BEGIN
  UPDATE call_history
  SET status = 'abandoned',
      ended_at = now()
  WHERE status IN ('ringing')
    AND created_at < now() - INTERVAL '5 minutes';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

Le mobile gère le statut `abandoned` : un listener Realtime sur `call_history` UPDATE détecte le changement et déclenche automatiquement un `hangUp()`.

---

### 1.11 Table `call_queue` — File d'attente des appels (Dashboard)

Le dashboard utilise cette table pour distribuer les appels entrants aux opérateurs disponibles. Un trigger SQL insère automatiquement une entrée quand un incident est créé. Le mobile n'interagit pas directement avec cette table.

```sql
CREATE TABLE IF NOT EXISTS call_queue (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  incident_id UUID NOT NULL REFERENCES incidents(id) ON DELETE CASCADE,
  citizen_id UUID NOT NULL REFERENCES auth.users(id),
  operator_id UUID REFERENCES auth.users(id),
  channel_name TEXT NOT NULL,
  caller_name TEXT,
  caller_phone TEXT,
  priority TEXT DEFAULT 'high',
  status TEXT NOT NULL DEFAULT 'waiting' CHECK (status IN ('waiting', 'assigned', 'active', 'completed', 'abandoned')),
  assigned_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_call_queue_status ON call_queue(status);
CREATE INDEX idx_call_queue_operator ON call_queue(operator_id);
CREATE INDEX idx_call_queue_created ON call_queue(created_at);
```

**Trigger automatique à la création d'un incident :**

```sql
CREATE OR REPLACE FUNCTION on_incident_created()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO call_queue (incident_id, citizen_id, channel_name, caller_name, caller_phone, priority)
  VALUES (NEW.id, NEW.citizen_id, NEW.reference, NEW.caller_name, NEW.caller_phone, NEW.priority);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_incident_created
  AFTER INSERT ON incidents
  FOR EACH ROW
  EXECUTE FUNCTION on_incident_created();
```

**Fonction d'assignation automatique :**

```sql
CREATE OR REPLACE FUNCTION auto_assign_queue()
RETURNS void AS $$
BEGIN
  UPDATE call_queue
  SET operator_id = (
    SELECT ud.auth_user_id
    FROM users_directory ud
    WHERE ud.available = true
      AND ud.status = 'online'
      AND (SELECT COUNT(*) FROM call_queue cq WHERE cq.operator_id = ud.auth_user_id AND cq.status IN ('assigned', 'active')) < 5
    ORDER BY ud.last_seen_at ASC
    LIMIT 1
  ),
  status = 'assigned',
  assigned_at = now()
  WHERE status = 'waiting'
    AND operator_id IS NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

La fonction `cleanup_stale_queue_entries()` (section 1.10) doit aussi nettoyer cette table :

```sql
-- Ajouter au corps de cleanup_stale_queue_entries() :
UPDATE call_queue
SET status = 'abandoned'
WHERE status IN ('waiting', 'assigned')
  AND created_at < now() - INTERVAL '5 minutes';
```

**RLS :**
```sql
ALTER TABLE call_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access call_queue"
  ON call_queue FOR ALL TO service_role
  USING (true) WITH CHECK (true);

CREATE POLICY "Operators read assigned queue"
  ON call_queue FOR SELECT TO authenticated
  USING (operator_id = auth.uid() OR status = 'waiting');
```

**Publication Realtime :**
```sql
ALTER PUBLICATION supabase_realtime ADD TABLE call_queue;
```

---

### 1.12 Table `call_recordings` — Enregistrements audio des appels

Stocke les métadonnées et URLs des enregistrements cloud Agora. L'Edge Function `stopCloudRecording` crée une entrée après l'arrêt de l'enregistrement.

```sql
CREATE TABLE IF NOT EXISTS call_recordings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  call_history_id UUID REFERENCES call_history(id) ON DELETE SET NULL,
  incident_id UUID REFERENCES incidents(id) ON DELETE SET NULL,
  channel_name TEXT NOT NULL,
  file_url TEXT NOT NULL,
  duration_seconds INTEGER,
  file_size_bytes BIGINT,
  recorded_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_call_recordings_channel ON call_recordings(channel_name);
CREATE INDEX idx_call_recordings_incident ON call_recordings(incident_id);
```

| Colonne | Description |
|---------|-------------|
| `file_url` | URL publique ou signée du fichier dans le bucket `incidents` |
| `duration_seconds` | Durée de l'enregistrement (calculée par l'Edge Function) |
| `recorded_by` | UUID de l'opérateur ou du système qui a lancé l'enregistrement |

**RLS :**
```sql
ALTER TABLE call_recordings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Citizens read own recordings"
  ON call_recordings FOR SELECT TO authenticated
  USING (
    call_history_id IN (SELECT id FROM call_history WHERE citizen_id = auth.uid())
    OR incident_id IN (SELECT id FROM incidents WHERE citizen_id = auth.uid())
  );

CREATE POLICY "Service role full access recordings"
  ON call_recordings FOR ALL TO service_role
  USING (true) WITH CHECK (true);
```

### 1.13 Table `blocked_users` — Liste noire des citoyens

```sql
CREATE TABLE public.blocked_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  citizen_id uuid NOT NULL,        -- auth.users.id du citoyen bloqué
  blocked_by uuid NOT NULL,        -- ID de l'opérateur qui a bloqué
  reason text NOT NULL DEFAULT '',
  duration_hours integer NOT NULL DEFAULT 168,
  blocked_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  call_id uuid,
  incident_id uuid,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);
```

### 1.14 Fonction RPC `is_citizen_blocked`

```sql
CREATE OR REPLACE FUNCTION is_citizen_blocked(p_citizen_id uuid)
RETURNS jsonb AS $$
DECLARE
  v_block RECORD;
BEGIN
  SELECT * INTO v_block
  FROM blocked_users
  WHERE citizen_id = p_citizen_id
    AND is_active = true
    AND expires_at > now()
  ORDER BY expires_at DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'blocked', true,
      'expires_at', v_block.expires_at,
      'reason', v_block.reason,
      'blocked_at', v_block.blocked_at
    );
  ELSE
    RETURN jsonb_build_object('blocked', false);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

Le mobile appelle `supabase.rpc('is_citizen_blocked', params: {'p_citizen_id': userId})` AVANT chaque appel SOS. Le trigger `on_incident_created` vérifie aussi côté serveur comme filet de sécurité.

---

### 1.15 Table `sos_questions` — Questionnaire dynamique de triage

Les questions SOS sont gérées dynamiquement depuis la base de données. Le mobile les télécharge au démarrage, les cache localement (SharedPreferences), et s'abonne en Realtime pour recevoir les mises à jour instantanément.

```sql
CREATE TABLE IF NOT EXISTS sos_questions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  question_key TEXT UNIQUE NOT NULL,
  question_text TEXT NOT NULL,
  question_type TEXT NOT NULL DEFAULT 'single_choice'
    CHECK (question_type IN ('single_choice', 'boolean', 'multiple_choice', 'free_text')),
  options JSONB NOT NULL DEFAULT '[]'::jsonb,
  display_order INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  is_required BOOLEAN NOT NULL DEFAULT false,
  category TEXT NOT NULL DEFAULT 'triage',
  template TEXT NOT NULL DEFAULT 'default',
  parent_question_key TEXT,
  show_if_answer JSONB,
  translations JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_sos_questions_active ON sos_questions(is_active, display_order);
CREATE INDEX idx_sos_questions_template ON sos_questions(template);
```

| Colonne | Type | Description |
|---------|------|-------------|
| `question_key` | text | Identifiant unique lisible (ex: `category`, `isConscious`) |
| `question_type` | text | `single_choice`, `boolean`, `multiple_choice`, `free_text` |
| `options` | jsonb | Tableau d'objets `{"label": "Malaise", "weight": 2}` — le poids sert au calcul de gravité |
| `display_order` | integer | Ordre d'affichage (0, 1, 2...) |
| `template` | text | Nom du template de questionnaire (ex: `default`, `pediatric`, `cardiac`) |
| `parent_question_key` | text | Si renseigné, la question ne s'affiche que si la question parent a été répondue |
| `show_if_answer` | jsonb | Tableau de valeurs attendues pour la question parent (ex: `["Accident", "Agressions"]`) |
| `translations` | jsonb | Objet `{"en": {"text": "...", "options": [...]}, "sw": {...}}` pour les traductions |

**Format de `options` :**
```json
[
  {"label": "Malaise", "weight": 2},
  {"label": "Accident", "weight": 3},
  {"label": "Agressions", "weight": 3},
  {"label": "Incendie", "weight": 3},
  {"label": "Autre", "weight": 1}
]
```

**Logique conditionnelle :**
- Si `parent_question_key = 'category'` et `show_if_answer = '["Accident"]'`, la question ne s'affiche que si l'utilisateur a répondu "Accident" à la question `category`
- Si `parent_question_key` est `NULL`, la question s'affiche toujours (question racine)

**Calcul du score de gravité :**
- Le mobile additionne les `weight` de chaque réponse sélectionnée
- Score ≥ 7 → `critical` (rouge), Score ≥ 4 → `high` (orange), Score < 4 → `low` (vert)
- Le score et le niveau sont envoyés dans `sos_responses`

---

### 1.16 Table `sos_responses` — Réponses au questionnaire SOS

Stocke les réponses du citoyen au questionnaire de triage. **Un row par question** (pas un row consolidé). Le mobile fait un upsert à chaque réponse.

```sql
CREATE TABLE IF NOT EXISTS sos_responses (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  incident_id UUID REFERENCES incidents(id) ON DELETE CASCADE,
  call_id UUID REFERENCES call_history(id) ON DELETE SET NULL,
  citizen_id UUID REFERENCES auth.users(id),
  question_key TEXT NOT NULL,
  question_text TEXT,
  answer TEXT,
  answered_at TIMESTAMPTZ,
  gravity_score INTEGER NOT NULL DEFAULT 0,
  gravity_level TEXT NOT NULL DEFAULT 'low'
    CHECK (gravity_level IN ('low', 'high', 'critical')),
  answers JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_sos_responses_upsert
  ON sos_responses(incident_id, question_key)
  WHERE incident_id IS NOT NULL;
CREATE INDEX idx_sos_responses_incident ON sos_responses(incident_id);
CREATE INDEX idx_sos_responses_citizen ON sos_responses(citizen_id);
```

| Colonne | Type | Description |
|---------|------|-------------|
| `question_key` | text | Référence vers `sos_questions.question_key` |
| `question_text` | text | Texte de la question au moment de la réponse |
| `answer` | text | Réponse en français (label de l'option choisie) |
| `answered_at` | timestamptz | Horodatage de la réponse |
| `gravity_score` | integer | Score de gravité cumulé (somme des poids de toutes les réponses) |
| `gravity_level` | text | `low`, `high`, ou `critical` — déduit du score |
| `call_id` | uuid | FK → `call_history.id` (pour lier la réponse à l'appel) |
| `answers` | jsonb | Copie de la réponse au format `{"questionKey": "answer"}` |

**Stratégie d'écriture mobile (per-question upsert) :**
1. À chaque réponse, le mobile fait un `UPSERT` sur `(incident_id, question_key)`
2. Le `gravity_score` et `gravity_level` sont recalculés et écrits sur chaque ligne
3. Le dashboard voit les réponses apparaître en temps réel via Realtime (INSERT/UPDATE)
4. Le dashboard peut aussi écrire/modifier via upsert (l'opérateur répond à la place du citoyen)
5. Les réponses sont **toujours enregistrées en français** (label de `options[index].label`), quelle que soit la langue d'affichage

---

## 2. EDGE FUNCTIONS

### 2.1 `agora-token` — Génération de tokens Agora RTC

Utilisée par le mobile et le dashboard pour rejoindre un canal audio/vidéo.

```
POST /functions/v1/agora-token
Body: {
  "channelName": "sos-abc123",
  "uid": 0,
  "role": "publisher",     // "publisher" ou "subscriber"
  "expireTime": 3600       // durée en secondes
}
Response: {
  "token": "006abc...xyz"
}
```

### 2.2 `twilio-verify` — Vérification OTP par SMS

Utilisée pour l'authentification par numéro de téléphone.

```
POST /functions/v1/twilio-verify
// Envoi du code :
Body: { "action": "send", "phone": "+243810000000" }
// Vérification du code :
Body: { "action": "verify", "phone": "+243810000000", "code": "123456" }
```

### 2.3 `complete-profile` — Finalisation du profil

Appelée après la saisie du profil lors de l'inscription. L'Edge Function doit accepter et écrire tous les champs optionnels dans `users_directory`.

```
POST /functions/v1/complete-profile
Body: {
  "full_name": "David Kabila",
  "first_name": "David",
  "last_name": "Kabila",
  "language": "Français",                    // optionnel
  "date_of_birth": "1990-01-01",             // optionnel — format YYYY-MM-DD
  "emergency_contact_name": "Marie Kabila",  // optionnel
  "emergency_contact_phone": "+243810000001" // optionnel
}
```

> **Note :** Les champs `emergency_contact_name` et `emergency_contact_phone` sont stockés dans `users_directory` et affichés sur le dashboard dans la fiche citoyen (voir section 8.D). Le mobile peut aussi les écrire via un UPDATE direct sur `users_directory` depuis l'écran Profil.

### 2.4 `startCloudRecording` — Démarrage enregistrement Agora

```
POST /functions/v1/startCloudRecording
Body: {
  "channelId": "sos-abc123",
  "uid": "<auth_user_id UUID>",    // UUID Supabase du citoyen — l'Edge Function doit
                                    // convertir en UID numérique Agora (ex: 0) en interne
  "token": "006abc...xyz"           // optionnel — l'Edge Function peut générer son propre token
}
Response: {
  "resourceId": "res-xxx",
  "sid": "sid-yyy"
}
```

> **Note technique :** L'API REST Agora Cloud Recording attend un UID numérique (ex: `0`). L'Edge Function reçoit le UUID auth de l'utilisateur et doit le convertir ou utiliser un UID fixe (ex: `0`) pour le bot d'enregistrement.

### 2.5 `stopCloudRecording` — Arrêt enregistrement

```
POST /functions/v1/stopCloudRecording
Body: {
  "channelId": "sos-abc123",
  "uid": "<auth_user_id UUID>",
  "resourceId": "res-xxx",
  "sid": "sid-yyy"
}
Response: {
  "recordingUrl": "https://storage.supabase.co/.../recording.mp4"
}
```

Le mobile lit la clé `recordingUrl` dans la réponse. Les fichiers audio sont stockés dans le bucket Storage `incidents` et référencés dans la table `call_recordings`.

### 2.6 `send-call-push` — Notification push FCM pour appels entrants

Appelée par le mobile immédiatement après la création de l'incident et de l'entrée `call_history`. Envoie une notification FCM à tous les opérateurs actifs pour signaler un nouvel appel entrant.

```
POST /functions/v1/send-call-push
Headers: Authorization: Bearer <JWT>
Body: {
  "citizen_id": "uuid-xxx",
  "channel_name": "SOS-1234567890",
  "caller_name": "David Kabila",
  "call_type": "incoming"
}
Response: { "sent": true, "recipients": 3 }
```

**Logique interne :**
1. Récupère les opérateurs actifs depuis `users_directory` (rôle `operator`, `is_available = true`)
2. Pour chaque opérateur ayant un `fcm_token`, envoie une notification FCM via Firebase Admin SDK
3. Le payload FCM contient `channel_name`, `caller_name`, `call_type` pour que le dashboard puisse identifier l'appel
4. Non bloquant pour le mobile — si la fonction échoue, l'appel SOS continue normalement

### 2.7 `update-phone` — Mise à jour du numéro de téléphone

```
POST /functions/v1/update-phone
Headers: Authorization: Bearer <JWT>
Body: { "new_phone": "+243810000001" }
Réponse succès: { "success": true }
```

**Logique interne :**
1. Vérifie que l'utilisateur est authentifié (`context.auth.uid`)
2. Met à jour `auth.users.phone` via **Supabase Admin API** (`supabaseAdmin.auth.admin.updateUserById(uid, { phone: newPhone })`)
3. Met à jour `users_directory.phone` via `UPDATE users_directory SET phone = newPhone, updated_at = now() WHERE auth_user_id = uid`
4. Insère une notification de confirmation : `INSERT INTO notifications (user_id, title, message, type) VALUES (uid, 'Numéro mis à jour', 'Votre numéro de téléphone a été changé en ' || newPhone, 'system')`
5. Le mobile appelle cette fonction APRÈS la vérification OTP Twilio réussie

**Variables d'environnement requises :** `SUPABASE_SERVICE_ROLE_KEY` (pour l'Admin API)

---

## 3. REALTIME — Publications Supabase

### 3.1 Tables à inclure dans la publication

```sql
ALTER PUBLICATION supabase_realtime ADD TABLE call_history;
ALTER PUBLICATION supabase_realtime ADD TABLE incidents;
ALTER PUBLICATION supabase_realtime ADD TABLE dispatches;
ALTER PUBLICATION supabase_realtime ADD TABLE messages;
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE active_rescuers;
ALTER PUBLICATION supabase_realtime ADD TABLE call_transcriptions;
ALTER PUBLICATION supabase_realtime ADD TABLE call_queue;
ALTER PUBLICATION supabase_realtime ADD TABLE sos_questions;
ALTER PUBLICATION supabase_realtime ADD TABLE sos_responses;
```

### 3.2 Canaux Realtime écoutés par le mobile

| Canal | Table | Événement | Filtre | Usage |
|-------|-------|-----------|--------|-------|
| `incoming-calls-$userId` | `call_history` | INSERT | `citizen_id = userId` | Détection appels entrants du dashboard |
| `call-status-$callId-$ts` | `call_history` | UPDATE | `id = callHistoryId` | Détection d'un appel marqué `abandoned` par le serveur |
| `public:incidents:$incidentId` | `incidents` | UPDATE / ALL | `id = incidentId` | Mise à jour du statut de l'incident actif |
| `incident-reco-$incidentId` | `incidents` | UPDATE | `id = incidentId` | Réception des recommandations en temps réel |
| `dispatches-$incidentId` | `dispatches` | ALL | `incident_id = incidentId` | Progression de la timeline (assigné, en route, sur place, terminé) |
| `transcriptions-$channelName-$ts` | `call_transcriptions` | INSERT | `call_id = channelName` | Transcription audio en direct pendant l'appel |
| `messages-$recipientId` | `messages` | INSERT | Filtrage Dart côté client | Nouveaux messages dans le chat |
| `sos-questions-$ts` | `sos_questions` | ALL | Aucun | Mise à jour des questions de triage en temps réel |

### 3.3 Streams Realtime (Postgres Changes Streams)

| Table | Filtre | Usage |
|-------|--------|-------|
| `incidents` | `citizen_id = uid` | Historique des incidents du citoyen |
| `notifications` | `user_id = uid` | Centre de notifications (badge + liste) |
| `users_directory` | `auth_user_id = uid` | Profil utilisateur en temps réel |
| `active_rescuers` | Toutes les lignes | Carte des secouristes |

---

## 4. STORAGE

### Bucket `incidents`

```sql
INSERT INTO storage.buckets (id, name, public)
VALUES ('incidents', 'incidents', true)
ON CONFLICT DO NOTHING;
```

Utilisé pour :
- Upload de photos/vidéos lors de signalements d'incidents
- Stockage des enregistrements audio des appels (cloud recording Agora)
- Les URLs sont stockées dans `incidents.media_urls` (tableau)

---

## 4B. DATABASE TRIGGERS

### 4B.1 `deduplicate_incident()` — Dédoublonnage d'incidents

Empêche la création d'incidents en doublon quand le citoyen appuie plusieurs fois sur le bouton SOS.

```sql
CREATE OR REPLACE FUNCTION deduplicate_incident()
RETURNS TRIGGER AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM incidents
    WHERE citizen_id = NEW.citizen_id
      AND status IN ('new', 'in_progress')
      AND created_at > now() - interval '2 minutes'
      AND id != NEW.id
  ) THEN
    RAISE EXCEPTION 'Duplicate incident detected for citizen %', NEW.citizen_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_deduplicate_incident
  BEFORE INSERT ON incidents
  FOR EACH ROW EXECUTE FUNCTION deduplicate_incident();
```

### 4B.2 `on_call_history_status_change()` — Mise à jour automatique des horodatages

Met à jour automatiquement les colonnes `started_at`, `answered_at`, `ended_at` en fonction des transitions de statut.

```sql
CREATE OR REPLACE FUNCTION on_call_history_status_change()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'active' AND OLD.status = 'ringing' THEN
    NEW.answered_at = COALESCE(NEW.answered_at, now());
    NEW.started_at = COALESCE(NEW.started_at, now());
  END IF;

  IF NEW.status IN ('completed', 'missed', 'failed', 'abandoned')
     AND OLD.status NOT IN ('completed', 'missed', 'failed', 'abandoned') THEN
    NEW.ended_at = COALESCE(NEW.ended_at, now());
    IF NEW.answered_at IS NOT NULL THEN
      NEW.duration_seconds = COALESCE(
        NEW.duration_seconds,
        EXTRACT(EPOCH FROM (NEW.ended_at - NEW.answered_at))::integer
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_call_history_status
  BEFORE UPDATE OF status ON call_history
  FOR EACH ROW EXECUTE FUNCTION on_call_history_status_change();
```

---

## 5. ROW LEVEL SECURITY (RLS)

### 5.1 `notifications`

```sql
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own notifications"
  ON notifications FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "Users update own notifications"
  ON notifications FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Service role inserts notifications"
  ON notifications FOR INSERT TO service_role
  WITH CHECK (true);
```

### 5.2 `call_history`

```sql
ALTER TABLE call_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Citizens read own calls"
  ON call_history FOR SELECT TO authenticated
  USING (citizen_id = auth.uid());

CREATE POLICY "Citizens update own calls"
  ON call_history FOR UPDATE TO authenticated
  USING (citizen_id = auth.uid());

CREATE POLICY "Authenticated users insert calls"
  ON call_history FOR INSERT TO authenticated
  WITH CHECK (true);
```

### 5.3 `incidents`

```sql
ALTER TABLE incidents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Citizens read own incidents"
  ON incidents FOR SELECT TO authenticated
  USING (citizen_id = auth.uid());

CREATE POLICY "Citizens create incidents"
  ON incidents FOR INSERT TO authenticated
  WITH CHECK (citizen_id = auth.uid());

CREATE POLICY "Citizens update own incidents"
  ON incidents FOR UPDATE TO authenticated
  USING (citizen_id = auth.uid());

CREATE POLICY "Service role full access incidents"
  ON incidents FOR ALL TO service_role
  USING (true) WITH CHECK (true);
```

### 5.4 `messages`

```sql
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own messages"
  ON messages FOR SELECT TO authenticated
  USING (sender_id = auth.uid() OR recipient_id = auth.uid());

CREATE POLICY "Users send messages"
  ON messages FOR INSERT TO authenticated
  WITH CHECK (sender_id = auth.uid());
```

### 5.5 `users_directory`

```sql
ALTER TABLE users_directory ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users read own profile"
  ON users_directory FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid());

CREATE POLICY "Users update own profile"
  ON users_directory FOR UPDATE TO authenticated
  USING (auth_user_id = auth.uid());

CREATE POLICY "Service role full access profiles"
  ON users_directory FOR ALL TO service_role
  USING (true) WITH CHECK (true);
```

### 5.6 `sos_questions`

```sql
ALTER TABLE sos_questions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read active SOS questions"
  ON sos_questions FOR SELECT TO authenticated
  USING (is_active = true);

CREATE POLICY "Service role full access sos_questions"
  ON sos_questions FOR ALL TO service_role
  USING (true) WITH CHECK (true);
```

### 5.7 `sos_responses`

```sql
ALTER TABLE sos_responses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Citizens insert own responses"
  ON sos_responses FOR INSERT TO authenticated
  WITH CHECK (citizen_id = auth.uid());

CREATE POLICY "Citizens update own responses"
  ON sos_responses FOR UPDATE TO authenticated
  USING (citizen_id = auth.uid());

CREATE POLICY "Citizens read own responses"
  ON sos_responses FOR SELECT TO authenticated
  USING (citizen_id = auth.uid());

CREATE POLICY "Service role full access sos_responses"
  ON sos_responses FOR ALL TO service_role
  USING (true) WITH CHECK (true);
```

### 5.8 `dispatches`

```sql
ALTER TABLE dispatches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Citizens read dispatches for own incidents"
  ON dispatches FOR SELECT TO authenticated
  USING (incident_id IN (SELECT id FROM incidents WHERE citizen_id = auth.uid()));

CREATE POLICY "Service role full access dispatches"
  ON dispatches FOR ALL TO service_role
  USING (true) WITH CHECK (true);
```

---

## 6. FLUX DE DONNÉES

### 6.1 Flux SOS (Citoyen → Base → Dashboard)

1. Le citoyen maintient le bouton SOS pendant 1.2 secondes
2. L'app capture la télémétrie (`device_model`, `battery_level`, `network_state`)
3. **Reverse geocoding** : l'app transforme les coordonnées GPS en adresse textuelle (`placemarkFromCoordinates`) avec un timeout de 3s. Si le geocoding echoue, `location_address` reste NULL (le trigger SQL `auto_enrich_incident` servira de filet)
4. Un incident est créé dans `incidents` avec télémétrie + localisation GPS + `location_address` (ex: `"42 Av. Lumumba, Lemba, Kinshasa"`)
5. Une entrée `call_history` est créée avec `call_type = 'incoming'`, `status = 'ringing'`
6. Un token Agora est généré via `agora-token`
7. L'app appelle `send-call-push` pour notifier les opérateurs via FCM
8. L'app rejoint le canal Agora et attend un opérateur
9. **Tracking GPS citoyen** : l'app démarre `startCitizenTracking()` qui écrit `caller_realtime_lat`, `caller_realtime_lng`, `caller_realtime_updated_at` sur l'incident toutes les 5-10 secondes
10. Le dashboard reçoit l'incident en temps réel et affiche la fiche avec télémétrie + adresse + position temps réel
11. Quand l'appel se termine (hangup ou call ended), le tracking GPS est arrêté automatiquement

### 6.2 Flux appel dashboard → citoyen (CRITIQUE)

```
Dashboard                    Supabase                    Mobile
    |                           |                           |
    |-- INSERT call_history --->|                           |
    |   call_type='outgoing'    |                           |
    |   status='ringing'        |                           |
    |   citizen_id=<uuid>       |                           |
    |                           |--- Realtime INSERT ------>|
    |                           |                           |-- CallKit affiche appel
    |                           |                           |
    |                           |<-- UPDATE call_history ---|
    |                           |    status='active'        |
    |                           |    answered_at=now()       |
    |                           |                           |
    |<---- Agora joinChannel ---|--- Agora joinChannel ---->|
    |           (audio/vidéo bidirectionnel)                 |
    |                           |                           |
    |                           |<-- UPDATE call_history ---|
    |                           |    status='completed'     |
    |                           |    ended_at=now()         |
```

Le mobile écoute sur le canal `incoming-calls-$userId` les INSERT avec `call_type = 'outgoing'` et `status = 'ringing'`. Il lit `channel_name`, `id` (callHistoryId) et `caller_name` (affiché sur CallKit comme nom de l'appelant, défaut "Opérateur").

**Données Agora du mobile :**
- `clientRoleBroadcaster` (publie ET reçoit l'audio)
- `publishMicrophoneTrack: true`
- `autoSubscribeAudio: true`

Cela garantit que le dashboard peut recevoir et transcrire l'audio du citoyen.

### 6.3 Flux recommandations (Dashboard → Base → Citoyen)

1. Le régulateur saisit des recommandations dans la fiche incident active
2. `UPDATE incidents SET recommended_actions = '...', recommended_facility = '...' WHERE id = '<id>'`
3. L'app mobile reçoit la mise à jour via Realtime (canal `incident-reco-$incidentId`)
4. Les recommandations s'affichent sur l'écran d'urgence du citoyen

### 6.4 Flux dispatch (Dashboard → Base → Citoyen)

1. Le dashboard assigne une unité à un incident
2. `INSERT INTO dispatches (incident_id, rescuer_id, status, assigned_at) VALUES (..., ..., 'dispatched', now())`
3. L'app mobile reçoit via Realtime (canal `dispatches-$incidentId`)
4. La timeline se met à jour : "Assigné" → "En route" → "Sur place" → "Terminé"

### 6.5 Flux notifications (Admin → Base → Citoyen)

1. L'admin crée une notification depuis le panneau Dashboard
2. `INSERT INTO notifications (user_id, title, message, type) VALUES (...)`
3. L'app mobile reçoit via le StreamProvider Realtime
4. Le badge rouge sur la cloche s'incrémente + toast affiché

### 6.6 Flux questionnaire SOS (Mobile → Base → Dashboard)

1. Au démarrage, le mobile télécharge les `sos_questions` actives et les cache localement
2. Le mobile s'abonne en Realtime (canal `sos-questions-$ts`) pour recevoir les MAJ instantanément
3. Pendant un appel SOS, le panneau de triage sur l'écran d'appel affiche les questions dynamiques
4. Les questions respectent la logique conditionnelle (`parent_question_key` / `show_if_answer`)
5. **À chaque réponse :** le mobile fait un UPSERT dans `sos_responses` (1 row par question, conflit sur `(incident_id, question_key)`)
6. **À chaque réponse :** le mobile écrit aussi les données de triage dans `call_history.triage_data` (JSONB complet des réponses)
7. Le `gravity_score` et `gravity_level` sont recalculés et mis à jour **sur chaque ligne** après chaque réponse
8. Le dashboard reçoit les réponses en temps réel via Realtime (INSERT/UPDATE sur `sos_responses`)
9. Le dashboard peut aussi écrire dans `sos_responses` (l'opérateur répond à la place du citoyen via upsert)

**Score de gravité :**
- Chaque option a un `weight` (poids) défini dans `sos_questions.options`
- Le mobile additionne les poids des réponses sélectionnées
- `critical` (≥7), `high` (≥4), `low` (<4)
- Ce score aide le dashboard à prioriser les incidents

**Flux `send-call-push` :**
Juste après la création de l'incident + `call_history`, le mobile appelle `send-call-push` pour notifier les opérateurs actifs via FCM. En cas d'échec, l'appel SOS continue normalement.

### 6.7 Flux messagerie (Opérateur ↔ Citoyen)

1. L'opérateur ou le citoyen envoie un message
2. `INSERT INTO messages (sender_id, recipient_id, recipient_type, content, type) VALUES (...)`
3. L'autre partie reçoit via Realtime (canal `messages-$recipientId`)
4. Messages texte et audio supportés (champ `audio_url` pour les vocaux)

---

## 7. FONCTIONNALITÉS DASHBOARD — EXISTANTES À MAINTENIR

### A. Fiche incident — Télémétrie du citoyen

Afficher dans la fiche incident :
- **Appareil :** `device_model` (ex: "TECNO Spark 10")
- **Batterie :** icône + `battery_level` — rouge si < 20%
- **Connexion :** icône + `network_state` — orange si "None" ou "Unknown"

### B. Recommandations en temps réel

Pendant un incident actif (statuts `new` à `investigating`) :
- Textarea "Actions recommandées" → écrit dans `recommended_actions`
- Input "Structure de santé ciblée" → écrit dans `recommended_facility`
- Bouton "Envoyer" → UPDATE incidents

### C. Panneau Notifications citoyens

- Formulaire : titre, message, type (`info`/`alert`/`system`/`course`), destinataire (tous ou spécifique)
- Templates rapides : "Mise à jour système", "Alerte sanitaire", "Nouvelle formation"
- Historique des 50 derniers envois

### D. Sélecteur de statut incident

Permettre de changer le statut d'un incident (`new` → `pending` → `dispatched` → `en_route` → `arrived` → `investigating` → `ended`). Chaque changement est reflété en temps réel sur l'app mobile.

---

## 8. NOUVELLES FONCTIONNALITÉS DASHBOARD RECOMMANDÉES

### A. Panneau de messagerie dans la fiche incident

- Afficher les messages texte et audio échangés avec le citoyen (table `messages`, filtre sur `sender_id` / `recipient_id`)
- Permettre à l'opérateur de répondre en texte
- Lecteur audio intégré pour les messages vocaux (`audio_url`)
- Realtime : s'abonner aux INSERT sur `messages` pour afficher les nouveaux messages instantanément

### B. Carte temps réel des secouristes

- Afficher les positions GPS depuis `active_rescuers` sur une carte (Google Maps / Mapbox)
- Chaque secouriste est un marqueur avec `heading` et `speed`
- Bouton "Assigner le plus proche" qui calcule la distance et INSERT dans `dispatches`
- Stream Realtime pour mise à jour des positions en temps réel

### C. Tableau de bord citoyens connectés

- Lister les `users_directory` avec `status = 'online'`
- Afficher `last_seen_at`, présence FCM, batterie du dernier incident
- Bouton "Appeler" qui déclenche le flux 6.2 (INSERT call_history outgoing)
- Utile pour le suivi proactif des situations en cours

### D. Contacts d'urgence dans la fiche citoyen

- Afficher `emergency_contact_name` et `emergency_contact_phone` depuis `users_directory`
- Boutons "Appeler le contact" et "SMS au contact" directement depuis le dashboard
- Utile quand le citoyen ne répond plus ou que sa batterie est faible

### E. Historique des appels enrichi

- Tableau avec tous les `call_history` : durée réelle (calculée depuis `answered_at`), statut, type
- Distinction visuelle "Réussi" (vert, avec durée) vs "Manqué" (rouge, sans durée)
- Lien vers l'incident associé (`incident_id`)
- Bouton "Écouter" pour lire l'enregistrement cloud (fichier depuis le bucket `incidents`)

### F. Enregistrement d'appels (Cloud Recording Agora)

- Intégration via les Edge Functions `startCloudRecording` / `stopCloudRecording`
- Les fichiers sont stockés dans le bucket `incidents`
- Le dashboard doit stocker `resourceId` et `sid` pendant l'enregistrement
- Un tableau "Enregistrements" liste les fichiers avec lien de lecture

### G. Panneau de transcription dans la fiche appel

- Afficher les transcriptions depuis `call_transcriptions` filtrées par `call_id = channel_name`
- Distinguer visuellement `speaker = 'operator'` vs `speaker = 'caller'`
- Les segments avec `is_final = false` sont en italique (transcription partielle en cours)
- Permettre l'export de la transcription complète en texte
- Auto-connecter le callerScribe dès qu'un remoteUser avec audioTrack est détecté

### H. Éditeur de questionnaire SOS

Interface CRUD pour gérer les questions du triage dynamique (table `sos_questions`) :

- **Liste des questions** : triées par `display_order`, filtrage par `template` et `category`
- **Créer/Modifier** : formulaire avec :
  - `question_key` (identifiant unique, ex: `category`, `isConscious`)
  - `question_text` (texte en français par défaut)
  - `question_type` : `single_choice`, `boolean`, `multiple_choice`, `free_text`
  - Éditeur d'options : ajouter/supprimer des options avec label + weight (glisser-déposer pour réordonner)
  - `template` : sélection du template (`default`, `pediatric`, `cardiac`, etc.)
  - `parent_question_key` : sélection d'une question parente (optionnel)
  - `show_if_answer` : liste des valeurs attendues pour afficher cette question (conditionnel)
  - `translations` : éditeur multi-langue (EN, SW, LN, KG, LU)
  - Toggle `is_active` et `is_required`
- **Aperçu en direct** : prévisualisation du questionnaire tel qu'il apparaîtra sur le mobile (avec logique conditionnelle)
- **Réordonner** : glisser-déposer pour changer `display_order`
- **Templates** : onglets par template avec possibilité de dupliquer un template existant
- Les modifications sont reflétées en temps réel sur les mobiles connectés (via Realtime sur `sos_questions`)

### I. Réponses SOS dans la fiche incident

Afficher dans la fiche incident active :

- **Réponses du citoyen** : récupérer depuis `sos_responses` filtrée par `incident_id`
- Afficher chaque question/réponse avec le poids associé
- **Badge de gravité** : rouge (`critical`), orange (`high`), vert (`low`) — déduit de `gravity_level`
- **Score** : afficher le score total et le seuil
- Mis à jour en temps réel si le citoyen continue de répondre (Realtime INSERT/UPDATE sur `sos_responses`)

---

## 9. TRANSCRIPTION — EXIGENCES MOBILES POUR LE DASHBOARD

Le dashboard transcrit l'audio du citoyen en capturant le flux audio distant Agora via Web Audio API. Voici les conditions que le mobile remplit pour que cela fonctionne :

| Exigence | Valeur mobile | Fichier |
|----------|---------------|---------|
| Rôle Agora | `ClientRoleType.clientRoleBroadcaster` | `emergency_call_service.dart` |
| Publication micro | `publishMicrophoneTrack: true` | `ChannelMediaOptions` dans `joinChannel` |
| Profil audio | `audioProfileDefault` + `audioScenarioChatroom` | `_initAgoraEngine()` |
| Micro au démarrage | **Non muté** (pas de `muteLocalAudioStream(true)`) | Aucun appel au démarrage |
| Mute bouton | `muteLocalAudioStream(muted)` — pause la publication sans quitter le canal | `toggleMute()` |
| Audio activé | `enableAudio()` appelé **avant** `joinChannel()` | `_initAgoraEngine()` |

Le dashboard peut lire les transcriptions persistées dans `call_transcriptions` et le mobile s'y abonne en Realtime pour afficher la transcription en direct sur l'écran d'appel.

---

## 10. COMPATIBILITÉ MOBILE ↔ DASHBOARD

Ce tableau confirme la compatibilité entre les dernières corrections mobiles et dashboard :

| Fonctionnalité | Mobile | Dashboard | Statut |
|----------------|--------|-----------|--------|
| Publication audio Agora | `clientRoleBroadcaster` + `publishMicrophoneTrack: true` | Transcription via `remoteUsers.audioTrack` | Compatible |
| Profil audio | `audioProfileDefault` + `audioScenarioChatroom` | Web Audio API capture sans artefact | Compatible |
| Durée d'appel | Écrit `answered_at` au décrochage réel (voir note) | Calcule `duration = now - answered_at` | Compatible |
| Statuts d'appel | Écrit `completed` / `missed` correctement | Affiche distinctement réussi vs manqué | Compatible |
| Nettoyage appels périmés | Détecte `abandoned` via Realtime → `hangUp()` | `cleanup_stale_queue_entries()` | Compatible |
| Cloud Recording | `CloudRecordingService` démarre/stoppe via Edge Functions | `startCloudRecording` / `stopCloudRecording` | Compatible |
| Transcription temps réel | Affiche `call_transcriptions` via Realtime provider | Écrit dans `call_transcriptions` en temps réel | Compatible |
| Canal Realtime | `incoming-calls-$userId` (unique par citoyen) | Canal dynamique `outgoing-call-status-$timestamp-$random` | Indépendants |
| Busy guard | Rejette les appels entrants si SOS actif | Doit gérer le statut `missed` renvoyé | Compatible |
| Hangup safety net | Force `ended` si callback absent | Dashboard détecte le changement de statut | Compatible |
| Token invalide | Nettoie l'état + throw exception | Doit re-générer un nouveau token si retry | Compatible |
| Questionnaire SOS dynamique | Charge `sos_questions` + cache + Realtime, **upsert par question** dans `sos_responses` | Gère CRUD `sos_questions`, lit `sos_responses` par row (1 row = 1 question) via Realtime | Compatible |
| Score de gravité | Calculé côté mobile (somme des `weight`), écrit sur **chaque ligne** `sos_responses` | Lit `gravity_score`/`gravity_level` pour priorisation | Compatible |
| Triage data | Écrit dans `call_history.triage_data` (JSONB complet) | Lit `triage_data` depuis `call_history` | Compatible |
| Push notifications SOS | Appelle `send-call-push` après création incident | Reçoit FCM push, affiche l'appel entrant | Compatible |
| Dispatch tracking | Écoute `dispatches` Realtime (dispatched → en_route → arrived → completed) | Écrit les transitions de statut dans `dispatches` | Compatible |
| Reverse geocoding | `placemarkFromCoordinates(lat, lng)` avec timeout 3s → écrit `location_address` dans l'INSERT `incidents` | Lit et affiche `location_address` dans la fiche incident | Compatible |
| GPS temps réel citoyen | `startCitizenTracking()` au démarrage SOS, `stopCitizenTracking()` au hangup/call ended. Écrit `caller_realtime_lat/lng` + `caller_realtime_updated_at` sur `incidents` | Lit et affiche la position en temps réel sur la carte | Compatible |

> **\* Note sur `answered_at` :**
> - **Appels SOS (citoyen → dashboard)** : `answered_at` est écrit par le callback `onUserJoined` quand l'opérateur rejoint le canal Agora. La mise à jour est conditionnée par `status = 'ringing'` pour éviter les doubles écritures. La durée calculée par le dashboard (`now - answered_at`) reflète donc le temps réel de conversation.
> - **Appels entrants (dashboard → citoyen)** : `answered_at` est écrit par `answerIncomingCall()` quand le citoyen décroche (status passe directement à `active`). Le callback `onUserJoined` ne réécrit pas `answered_at` car le statut n'est plus `ringing`.

---

## 11. CORRECTIONS DASHBOARD RÉCENTES — Impact mobile

Les corrections suivantes ont été implémentées côté dashboard. Voici leur impact sur le mobile :

| Correction dashboard | Impact mobile |
|---------------------|---------------|
| Canal Realtime hardcodé → dynamique (`outgoing-call-status-$ts-$rand`) | Aucun — les canaux mobile et dashboard sont indépendants |
| Nettoyage appels périmés (`cleanup_stale_queue_entries`) | Le mobile détecte `abandoned` via Realtime UPDATE et déclenche `hangUp()` |
| Durée calculée depuis `answered_at` (pas `created_at`) | Le mobile écrit `answered_at` au décrochage réel (SOS: quand l'opérateur rejoint, Entrant: quand le citoyen décroche) — compatible |
| Cloud Recording via Edge Functions (pas local) | Le mobile utilise `CloudRecordingService` qui appelle les mêmes Edge Functions |
| Transcription auto-connect du caller | Le mobile publie l'audio (`publishMicrophoneTrack: true`) — compatible |
| Historique enrichi (réussi/manqué/durée/écouter) | Le mobile écrit `completed`/`missed` et `ended_at` correctement |

---

## 12. DONNÉES DE TEST

### Notifications

```sql
INSERT INTO notifications (user_id, title, message, type, is_read) VALUES
  ('<USER_UUID>', 'Bienvenue sur Étoile Bleue', 'Merci de faire partie de notre communauté de secours. Votre sécurité est notre priorité.', 'info', false),
  ('<USER_UUID>', 'Campagne de vaccination', 'Une campagne de vaccination contre la rougeole est en cours dans votre zone. Rendez-vous au centre de santé le plus proche.', 'alert', false),
  ('<USER_UUID>', 'Mise à jour système', 'L''application a été mise à jour avec de nouvelles fonctionnalités de suivi en temps réel.', 'system', true),
  ('<USER_UUID>', 'Formation premiers secours', 'Un nouveau module de formation est disponible : "Réagir face à un AVC". Commencez maintenant !', 'course', false);
```

Remplacer `<USER_UUID>` par un vrai `auth.users.id`.

### Questions SOS (template "default")

```sql
INSERT INTO sos_questions (question_key, question_text, question_type, options, display_order, is_active, is_required, category, template, translations) VALUES
(
  'category',
  'Nature de l''urgence ?',
  'single_choice',
  '[{"label":"Malaise","weight":2},{"label":"Accident","weight":3},{"label":"Agressions","weight":3},{"label":"Incendie","weight":3},{"label":"Autre","weight":1}]'::jsonb,
  0, true, true, 'triage', 'default',
  '{"en":{"text":"Nature of the emergency?","options":["Illness","Accident","Assault","Fire","Other"]},"sw":{"text":"Aina ya dharura?","options":["Ugonjwa","Ajali","Mashambulizi","Moto","Nyingine"]}}'::jsonb
),
(
  'isConscious',
  'La victime est-elle consciente ?',
  'boolean',
  '[{"label":"Oui, répond","weight":0},{"label":"Non","weight":4}]'::jsonb,
  1, true, true, 'triage', 'default',
  '{"en":{"text":"Is the victim conscious?","options":["Yes, responsive","No"]},"sw":{"text":"Mwathirika ana fahamu?","options":["Ndiyo","Hapana"]}}'::jsonb
),
(
  'isBreathing',
  'La victime respire-t-elle ?',
  'boolean',
  '[{"label":"Oui, respire","weight":0},{"label":"Non","weight":5}]'::jsonb,
  2, true, true, 'triage', 'default',
  '{"en":{"text":"Is the victim breathing?","options":["Yes, breathing","No"]},"sw":{"text":"Mwathirika anapumua?","options":["Ndiyo","Hapana"]}}'::jsonb
),
(
  'victimCount',
  'Combien de victimes ?',
  'single_choice',
  '[{"label":"1 personne","weight":0},{"label":"2-3 personnes","weight":2},{"label":"Plus de 3","weight":4}]'::jsonb,
  3, true, false, 'triage', 'default',
  '{"en":{"text":"How many victims?","options":["1 person","2-3 people","More than 3"]}}'::jsonb
),
(
  'accidentType',
  'Type d''accident ?',
  'single_choice',
  '[{"label":"Route","weight":3},{"label":"Domestique","weight":2},{"label":"Travail","weight":2},{"label":"Noyade","weight":4}]'::jsonb,
  4, true, false, 'triage', 'default',
  '{"en":{"text":"Type of accident?","options":["Road","Domestic","Work","Drowning"]}}'::jsonb
);

-- Question conditionnelle : s'affiche seulement si category = "Accident"
UPDATE sos_questions
SET parent_question_key = 'category',
    show_if_answer = '["Accident"]'::jsonb
WHERE question_key = 'accidentType';
```

---

## 13. SCALABILITÉ — 17M utilisateurs, 1M simultanés

### 13.1 Connection Pooling (pgbouncer)

Supabase utilise pgbouncer par défaut. Pour 1M de connexions simultanées :

- Activer le mode **transaction** (pas session) dans les paramètres Supabase
- Les connexions Realtime sont gérées séparément par le Realtime Engine (pas pgbouncer)
- Limite recommandée : **500 connexions directes max** côté pool, le reste via Realtime

### 13.2 Index partiels recommandés

```sql
-- Appels en attente de réponse (file d'attente active)
CREATE INDEX IF NOT EXISTS idx_call_history_ringing
  ON call_history (citizen_id, created_at DESC)
  WHERE status = 'ringing';

-- Notifications non lues (badge compteur)
CREATE INDEX IF NOT EXISTS idx_notifications_unread
  ON notifications (user_id, created_at DESC)
  WHERE is_read = false;

-- Incidents actifs (suivi temps réel)
CREATE INDEX IF NOT EXISTS idx_incidents_active
  ON incidents (citizen_id, created_at DESC)
  WHERE status NOT IN ('ended', 'cancelled');

-- File d'attente active (dispatch opérateurs)
CREATE INDEX IF NOT EXISTS idx_call_queue_waiting
  ON call_queue (priority DESC, created_at ASC)
  WHERE status IN ('waiting', 'assigned');
```

### 13.3 Limites Realtime

- Chaque client Supabase ouvre **1 connexion WebSocket** multiplexée en canaux
- Éviter `.stream()` côté mobile (crée un slot de réplication Postgres par client) — le mobile utilise désormais `fetch initial + .channel()` pour `user_provider` et `notifications_provider`
- Côté dashboard, les canaux Realtime doivent avoir des noms **uniques** (suffixe timestamp/random) pour éviter les collisions entre opérateurs

### 13.4 Pagination obligatoire

Toutes les requêtes qui retournent des listes doivent être paginées :

| Table | Limite recommandée | Implémenté |
|-------|-------------------|------------|
| `incidents` | 50 par page | ✅ `.limit(50)` dans `HistoryPage` |
| `notifications` | 100 par page | ✅ `.limit(100)` dans `notificationsProvider` |
| `call_history` | 50 par page | ✅ Dashboard pagine à 200 max |
| `call_queue` | 100 par page | ✅ Dashboard filtre actifs uniquement |

### 13.5 Rate Limiting — Edge Functions

Appliquer des limites de débit sur les Edge Functions critiques :

| Edge Function | Limite recommandée |
|---------------|-------------------|
| `twilio-verify` (send) | 3 tentatives / 10 min / utilisateur |
| `twilio-verify` (verify) | 5 tentatives / 10 min / utilisateur |
| `update-phone` | 1 appel / 10 min / utilisateur |
| `agora-token` | 10 appels / min / utilisateur |
| `startCloudRecording` | 2 appels / min / canal |

Implémentation recommandée : utiliser une table `rate_limits` :

```sql
CREATE TABLE IF NOT EXISTS rate_limits (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id),
  action TEXT NOT NULL,
  last_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  attempt_count INTEGER NOT NULL DEFAULT 1,
  window_start TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, action)
);
```

Chaque Edge Function vérifie en début d'exécution si l'utilisateur a atteint la limite. Le `attempt_count` est réinitialisé quand `now() - window_start > durée de la fenêtre`.

### 13.6 Nettoyage automatique

- `cleanup_stale_queue_entries()` : déjà implémenté, marque les appels > 5 min comme `abandoned`
- Recommandation : ajouter un CRON Supabase (`pg_cron`) pour exécuter cette fonction toutes les 2 minutes
- Purger les `notifications` marquées lues depuis plus de 90 jours
- Archiver les `incidents` de plus de 1 an dans une table `incidents_archive`

### 13.7 Debouncing côté mobile

Le mobile implémente les protections suivantes contre les soumissions multiples :

- **Bouton SOS** : hold 1.2s + guard `_isSosTriggered` empêche les doubles incidents
- **Changement de numéro** : guard `_isVerifying` dans `_PhoneEditSheet` + OTP 60s cooldown
- **Boutons d'action** : `HapticFeedback` + désactivation pendant le traitement
- **Questionnaire SOS** : chaque question verrouillée après réponse, upsert par question (conflit sur `incident_id, question_key`) — idempotent par conception
- **`send-call-push`** : appelé une seule fois après `call_history` insert — non bloquant, erreur silencieuse
