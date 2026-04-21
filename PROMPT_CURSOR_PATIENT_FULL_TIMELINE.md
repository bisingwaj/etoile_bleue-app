# Prompt Cursor — Chronologie complète d'intervention pour le patient (citoyen)

> **Destinataire :** équipe mobile patient (Cursor / Anti Gravity)
> **Backend :** Lovable Cloud (Supabase)
> **Date :** avril 2026
> **Contexte :** Le patient ne reçoit actuellement que la partie centrale/terrain de la chronologie. Il manque toute la partie hospitalière (admission, triage, vitaux, PEC, monitoring, clôture, rapport final). Cette mise à jour expose **toute** la chronologie au patient via une Edge Function dédiée et déclenche une notification push à chaque transition hospitalière.

---

## 1. Vue d'ensemble du backend (déjà déployé côté Lovable)

### 1.1 Nouvelle Edge Function : `get-patient-timeline`

Agrège en un seul appel toutes les sources de la chronologie patient :

| Source | Table | Contenu inclus |
|--------|-------|----------------|
| Centrale | `incidents`, `call_history` | Création de l'alerte, appels opérateur |
| Terrain | `dispatches`, `dispatch_timeline`, `incident_assessments` | Assignation équipe, arrivée, évaluations vitales, notes terrain |
| Hôpital | `dispatches.hospital_data`, `hospital_reports` | Admission, triage (vitaux, symptômes, diagnostic), PEC (observations, examens, traitements), monitoring, clôture, rapport final |

**URL :** `https://<PROJECT_REF>.functions.supabase.co/get-patient-timeline`
**Auth :** JWT Supabase obligatoire (header `Authorization: Bearer <token>`).
**Autorisation backend :** seul le citoyen propriétaire de l'incident OU un opérateur peut lire la timeline.

### 1.2 Trigger SQL : `trg_notify_patient_hospital_status`

Se déclenche automatiquement quand `dispatches.hospital_data->>'status'` change vers l'une de ces valeurs :

- `admis`
- `triage`
- `prise_en_charge`
- `monitoring`
- `termine`

Il appelle l'Edge Function `send-patient-hospital-push` qui :
1. Crée une notification dans la table `notifications` du patient.
2. Envoie un push FCM via `send-dispatch-push`.

### 1.3 Politiques RLS ajoutées (lecture seule pour le citoyen)

Le citoyen peut désormais lire directement les lignes liées à ses propres incidents :

- `dispatches` (incl. `hospital_data` complet)
- `dispatch_timeline`
- `incident_assessments`
- `hospital_reports`

Les autres rôles (terrain, hôpital, opérateurs) ne sont pas affectés.

---

## 2. Contrat de l'Edge Function `get-patient-timeline`

### 2.1 Requête

**Méthode :** `POST` (recommandé) ou `GET`

**Body JSON (POST) :**
```json
{
  "incident_id": "uuid-de-l-incident"
}
```

**OU query params (GET) :**
```
?incident_id=<uuid>
```

**OU avec dispatch_id :**
```json
{ "dispatch_id": "uuid-du-dispatch" }
```

### 2.2 Réponse (200 OK)

```json
{
  "success": true,
  "incident": {
    "id": "uuid",
    "reference": "EBR-2026-0042",
    "title": "Douleur thoracique",
    "type": "medical",
    "status": "in_progress",
    "priority": "high",
    "created_at": "2026-04-17T14:32:00Z",
    "resolved_at": null
  },
  "dispatches": [
    {
      "id": "uuid",
      "status": "completed",
      "hospital_status": "accepted",
      "structure_name": "Centre Hospitalier Monkole",
      "structure_type": "hopital",
      "structure_phone": "+243...",
      "structure_address": "Mont-Ngafula, Kinshasa",
      "hospital_data": {
        "status": "termine",
        "arrivalMode": "ambulance",
        "arrivalState": "stable",
        "admissionService": "urgence_generale",
        "arrivalTime": "14:55",
        "triageLevel": "orange",
        "vitals": { "bloodPressure": "140/90", "heartRate": 88, "spO2": 96 },
        "observations": [{ "at": "15:10", "label": "Patient conscient" }],
        "exams": [{ "at": "15:20", "label": "ECG réalisé" }],
        "treatments": [{ "at": "15:30", "label": "Paracétamol 1g IV" }],
        "dischargeType": "guerison",
        "dischargeNotes": "Patient stable, sortie autorisée",
        "dischargedAt": "2026-04-17T18:45:00Z"
      }
    }
  ],
  "events": [
    {
      "at": "2026-04-17T14:32:00Z",
      "source": "centrale",
      "category": "incident_created",
      "title": "Alerte enregistrée",
      "description": "Douleur thoracique sévère",
      "metadata": { "reference": "EBR-2026-0042", "type": "medical", "priority": "high" }
    },
    {
      "at": "2026-04-17T14:34:10Z",
      "source": "terrain",
      "category": "dispatch_created",
      "title": "Équipe de secours assignée",
      "description": "Structure : Centre Hospitalier Monkole",
      "metadata": { "structure_type": "hopital" }
    },
    {
      "at": "2026-04-17T14:55:00Z",
      "source": "hopital",
      "category": "admission",
      "title": "Admission à l'hôpital",
      "description": "Service : urgence_generale",
      "metadata": { "arrivalMode": "ambulance", "arrivalState": "stable" }
    },
    {
      "at": "2026-04-17T15:05:00Z",
      "source": "hopital",
      "category": "triage",
      "title": "Triage : niveau orange",
      "description": "Suspicion SCA",
      "metadata": {
        "triageLevel": "orange",
        "vitals": { "bloodPressure": "140/90", "heartRate": 88, "spO2": 96 }
      }
    },
    {
      "at": "2026-04-17T15:30:00Z",
      "source": "hopital",
      "category": "treatment",
      "title": "Traitement administré",
      "description": "Paracétamol 1g IV",
      "metadata": { "at": "15:30", "label": "Paracétamol 1g IV" }
    },
    {
      "at": "2026-04-17T18:45:00Z",
      "source": "hopital",
      "category": "discharge",
      "title": "Sortie : guérison",
      "description": "Patient stable, sortie autorisée"
    }
  ],
  "reports": [
    {
      "id": "uuid",
      "sent_at": "2026-04-17T18:50:00Z",
      "summary": "Patient pris en charge pour douleur thoracique. ECG normal, sortie après 4h d'observation.",
      "report_data": { /* ... payload complet ... */ }
    }
  ]
}
```

### 2.3 Catégories d'événements

| `source` | `category` | Sens |
|----------|------------|------|
| `centrale` | `incident_created` | Création de l'alerte |
| `centrale` | `call` | Appel avec opérateur |
| `terrain` | `dispatch_created` | Équipe assignée |
| `terrain` | `on_scene` | Arrivée sur les lieux |
| `terrain` | `assessment` | Évaluation médicale terrain (vitaux, conscience, respiration) |
| `terrain` | `mission_completed` | Mission terminée |
| `hopital` | `hospital_accepted` / `hospital_refused` | Réponse de la structure |
| `hopital` | `admission` | Admission validée |
| `hopital` | `triage` | Triage avec niveau + vitaux |
| `hopital` | `observation` | Observation clinique |
| `hopital` | `exam` | Examen réalisé |
| `hopital` | `treatment` | Traitement administré |
| `hopital` | `monitoring` | Patient sous monitoring |
| `hopital` | `discharge` | Clôture (guérison, transfert, décès, sortie contre avis) |
| `hopital` | `final_report` | Rapport final envoyé par l'hôpital |

### 2.4 Codes d'erreur

| Code HTTP | `error` | Cause |
|-----------|---------|-------|
| 400 | `incident_id_or_dispatch_id_required` | Aucun ID fourni |
| 401 | `missing_auth` / `invalid_auth` | Token JWT absent ou invalide |
| 403 | `forbidden` | Le caller n'est ni propriétaire ni opérateur |
| 404 | `incident_not_found` | Incident inexistant |
| 500 | `internal_error` | Voir `detail` |

---

## 3. Code Dart — Récupération de la chronologie

```dart
Future<Map<String, dynamic>?> fetchPatientTimeline(String incidentId) async {
  try {
    final response = await supabase.functions.invoke(
      'get-patient-timeline',
      body: { 'incident_id': incidentId },
    );

    if (response.status != 200) {
      debugPrint('Timeline error: ${response.data}');
      return null;
    }
    return Map<String, dynamic>.from(response.data);
  } catch (e) {
    debugPrint('fetchPatientTimeline failed: $e');
    return null;
  }
}
```

### 3.1 Modèle Dart suggéré

```dart
class TimelineEvent {
  final DateTime at;
  final String source; // centrale | terrain | hopital | systeme
  final String category;
  final String title;
  final String? description;
  final Map<String, dynamic> metadata;

  TimelineEvent.fromJson(Map<String, dynamic> j)
      : at = DateTime.parse(j['at'] as String),
        source = j['source'] as String,
        category = j['category'] as String,
        title = j['title'] as String,
        description = j['description'] as String?,
        metadata = Map<String, dynamic>.from(j['metadata'] ?? {});

  bool get isHospital => source == 'hopital';
  bool get isField => source == 'terrain';
  bool get isCenter => source == 'centrale';
}
```

### 3.2 Affichage suggéré (PatientTimelineScreen)

- Regrouper par `source` avec une icône distincte (📞 centrale, 🚑 terrain, 🏥 hôpital).
- Afficher `vitals` sous forme de petite carte (TA, FC, T°, SpO₂) pour les events `triage` et `assessment`.
- Pour `final_report`, ouvrir un écran dédié avec le `report_data` complet.

---

## 4. Realtime — Mise à jour automatique de la timeline

L'app patient doit s'abonner aux changements de `dispatches.hospital_data` pour rafraîchir la timeline en direct **sans attendre un push** :

```dart
final channel = supabase.channel('patient_timeline_$incidentId')
  .onPostgresChanges(
    event: PostgresChangeEvent.update,
    schema: 'public',
    table: 'dispatches',
    filter: PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'incident_id',
      value: incidentId,
    ),
    callback: (payload) {
      // Recharger la timeline complète
      refreshTimeline();
    },
  )
  .subscribe();
```

S'abonner aussi à `hospital_reports` (event `INSERT`, filter `incident_id = incidentId`) pour le rapport final.

---

## 5. Notifications push patient

### 5.1 Trigger backend (déjà déployé)

À chaque transition de `hospital_data.status` vers `admis | triage | prise_en_charge | monitoring | termine` :

1. Une ligne est insérée dans `notifications` (visible dans le centre de notifications de l'app patient).
2. Un push FCM est envoyé via `send-dispatch-push` avec :
   - `title` : libellé court de l'étape
   - `body` : description
   - `data.status` : `hospital_<status>` (ex. `hospital_admis`)
   - `data.incident_id` : pour ouvrir directement la timeline

### 5.2 Libellés envoyés

| `hospital_data.status` | Titre push | Corps |
|------------------------|-----------|-------|
| `admis` | Patient admis à l'hôpital | Votre dossier hospitalier vient d'être ouvert. |
| `triage` | Triage en cours | L'équipe médicale évalue la priorité. |
| `prise_en_charge` | Prise en charge démarrée | Les soins ont commencé. |
| `monitoring` | Patient sous monitoring | L'équipe surveille votre état en continu. |
| `termine` | Dossier hospitalier clôturé | La prise en charge est terminée. Consultez le rapport final. |

### 5.3 Côté mobile — Handler suggéré

```dart
FirebaseMessaging.onMessage.listen((message) {
  final data = message.data;
  final status = data['status'] as String?;
  if (status != null && status.startsWith('hospital_')) {
    final incidentId = data['incident_id'] as String?;
    if (incidentId != null) {
      // Naviguer vers la timeline patient
      navigatorKey.currentState?.pushNamed(
        '/patient-timeline',
        arguments: incidentId,
      );
    }
  }
});
```

---

## 6. Checklist d'intégration mobile patient

### Affichage timeline
- [ ] Ajouter `PatientTimelineScreen` qui appelle `get-patient-timeline` au montage.
- [ ] Implémenter le modèle `TimelineEvent` ci-dessus.
- [ ] Grouper visuellement par `source` (centrale / terrain / hôpital).
- [ ] Afficher les vitaux structurés pour `triage` et `assessment`.
- [ ] Bouton "Voir le rapport final" pour ouvrir `report_data`.

### Realtime
- [ ] S'abonner aux changements de `dispatches` filtrés par `incident_id`.
- [ ] S'abonner aux INSERT sur `hospital_reports` filtrés par `incident_id`.
- [ ] Rafraîchir la timeline à chaque event reçu.

### Notifications push
- [ ] Gérer les pushes avec `data.status` commençant par `hospital_`.
- [ ] Naviguer automatiquement vers la timeline du bon incident.
- [ ] Marquer la notification comme lue à l'ouverture.

### RLS / Sécurité
- [ ] Vérifier que les requêtes directes `supabase.from('dispatches').select()` filtrent bien par `incident_id` (les RLS bloquent automatiquement le reste).
- [ ] Ne JAMAIS exposer le `service_role_key` côté mobile.

---

## 7. Politiques RLS appliquées (référence)

| Table | Politique | Effet pour le citoyen |
|-------|-----------|------------------------|
| `dispatches` | `citizen_select_own_dispatches` | SELECT si `incident.citizen_id = auth.uid()` |
| `dispatch_timeline` | `citizen_select_own_timeline` | SELECT si l'incident lié appartient au citoyen |
| `incident_assessments` | `citizen_select_own_assessment` | SELECT si l'incident lié appartient au citoyen |
| `hospital_reports` | `citizen_select_own_hospital_reports` | SELECT si l'incident lié appartient au citoyen |

---

## 8. Test rapide (curl)

```bash
curl -X POST \
  "https://<PROJECT_REF>.functions.supabase.co/get-patient-timeline" \
  -H "Authorization: Bearer <CITIZEN_JWT>" \
  -H "Content-Type: application/json" \
  -d '{"incident_id": "<UUID_INCIDENT>"}'
```

Vérifier que la réponse contient bien des events `source: "hopital"` quand l'hôpital a renseigné `hospital_data`.

---

*Document contrat Lovable → Cursor. La structure de la réponse de `get-patient-timeline` est stable côté backend. Toute modification sera coordonnée.*
