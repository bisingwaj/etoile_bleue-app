# Guide Technique — Module Signalements & Plaintes (Application Mobile)

> **Version** : 1.0 — 4 avril 2026
> **Audience** : Développeurs mobile (Flutter/Dart)
> **Séparation critique** : Les signalements sont un flux **asynchrone** totalement distinct des incidents SOS et appels d'urgence. Ils ne passent PAS par la file d'attente (`call_queue`), n'ont PAS de canal Agora, et ne déclenchent PAS de dispatch.

---

## Table des matières

1. [Architecture générale](#1-architecture-générale)
2. [Schéma de données](#2-schéma-de-données)
3. [Authentification](#3-authentification)
4. [Création d'un signalement](#4-création-dun-signalement)
5. [Gestion des médias](#5-gestion-des-médias)
6. [Géolocalisation](#6-géolocalisation)
7. [Suivi en temps réel](#7-suivi-en-temps-réel)
8. [Anonymat](#8-anonymat)
9. [Catégories et priorités](#9-catégories-et-priorités)
10. [Scalabilité et performance](#10-scalabilité-et-performance)
11. [Contrats JSON complets](#11-contrats-json-complets)
12. [Exemples Dart/Flutter](#12-exemples-dartflutter)
13. [Matrice RLS](#13-matrice-rls)

---

## 1. Architecture générale

```
┌─────────────────────────────────────────────────────────────────┐
│                      APPLICATION MOBILE                         │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────┐  │
│  │ Formulaire   │  │ Capture      │  │ GPS                   │  │
│  │ signalement  │  │ média        │  │ (lat/lng WGS84)       │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬────────────┘  │
│         │                 │                      │              │
│         ▼                 ▼                      │              │
│  ┌──────────────────────────────────────────┐    │              │
│  │ Compression locale (image/vidéo/audio)   │    │              │
│  └──────────────────┬───────────────────────┘    │              │
│                     │                            │              │
│                     ▼                            ▼              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Supabase SDK (supabase-flutter)             │   │
│  │  1. storage.upload() → bucket "incidents"                │   │
│  │  2. signalements.insert() → table signalements           │   │
│  │  3. signalement_media.insert() → table signalement_media │   │
│  └──────────────────────────┬───────────────────────────────┘   │
└─────────────────────────────┼───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         SUPABASE                                │
│                                                                 │
│  ┌─────────────────┐  ┌──────────────────┐  ┌───────────────┐  │
│  │  signalements   │  │ signalement_media│  │ signalement_  │  │
│  │  (table)        │◄─┤ (table)          │  │ notes (table) │  │
│  └────────┬────────┘  └──────────────────┘  └───────────────┘  │
│           │                                                     │
│           ▼                                                     │
│  ┌─────────────────────────────────────────┐                   │
│  │  Supabase Realtime (postgres_changes)   │                   │
│  │  → Dashboard reçoit les nouveaux        │                   │
│  │    signalements instantanément          │                   │
│  └─────────────────────────────────────────┘                   │
│                                                                 │
│  ┌─────────────────────────────────────────┐                   │
│  │  Storage bucket "incidents"             │                   │
│  │  Path: signalements/{id}/{filename}     │                   │
│  └─────────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Schéma de données

### Table `signalements`

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Identifiant unique |
| `reference` | text | Non | — | Référence lisible (ex: `SIG-20260404-001`) |
| `category` | text | Non | — | Code catégorie (voir §9) |
| `title` | text | Non | — | Titre court du signalement |
| `description` | text | Oui | — | Description détaillée |
| `citizen_name` | text | Oui | — | Nom du plaignant (null si anonyme) |
| `citizen_phone` | text | Oui | — | Téléphone du plaignant |
| `is_anonymous` | boolean | Oui | `false` | Signalement anonyme |
| `province` | text | Non | `'Kinshasa'` | Province |
| `ville` | text | Non | `'Kinshasa'` | Ville |
| `commune` | text | Oui | — | Commune |
| `lat` | double precision | Oui | — | Latitude GPS (WGS84) |
| `lng` | double precision | Oui | — | Longitude GPS (WGS84) |
| `structure_name` | text | Oui | — | Nom de la structure concernée |
| `structure_id` | uuid | Oui | — | FK vers `health_structures.id` |
| `priority` | text | Non | `'moyenne'` | `critique`, `haute`, `moyenne`, `basse` |
| `status` | text | Non | `'nouveau'` | Statut du workflow (voir §9) |
| `assigned_to` | text | Oui | — | Nom de l'enquêteur assigné |
| `created_at` | timestamptz | Oui | `now()` | Date de création |
| `updated_at` | timestamptz | Oui | `now()` | Dernière mise à jour |

### Table `signalement_media`

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Identifiant unique |
| `signalement_id` | uuid | Non | — | FK vers `signalements.id` |
| `type` | text | Non | `'image'` | `image`, `video`, `audio` |
| `url` | text | Non | — | URL publique du fichier dans Storage |
| `thumbnail` | text | Oui | — | URL de la miniature (vidéo/image) |
| `duration` | integer | Oui | — | Durée en secondes (audio/vidéo) |
| `filename` | text | Non | — | Nom du fichier original |
| `created_at` | timestamptz | Oui | `now()` | Date d'upload |

### Table `signalement_notes`

| Colonne | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | Non | `gen_random_uuid()` | Identifiant unique |
| `signalement_id` | uuid | Non | — | FK vers `signalements.id` |
| `author` | text | Non | — | Nom de l'auteur de la note |
| `text` | text | Non | — | Contenu de la note |
| `created_at` | timestamptz | Oui | `now()` | Date de création |

---

## 3. Authentification

Les signalements sont créés par des **citoyens authentifiés** (rôle `citoyen`) via SMS OTP ou par des **opérateurs** du dashboard.

```dart
// Vérifier que l'utilisateur est authentifié
final user = supabase.auth.currentUser;
if (user == null) throw Exception('Non authentifié');
```

La politique RLS INSERT exige un rôle parmi : `call_center`, `admin`, `superviseur`, `citoyen`.

---

## 4. Création d'un signalement

### 4.1 Génération de la référence

La référence doit être générée côté client avec un format déterministe pour éviter les collisions :

```dart
String generateReference() {
  final now = DateTime.now();
  final date = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  final rand = (now.millisecondsSinceEpoch % 100000).toString().padLeft(5, '0');
  return 'SIG-$date-$rand';
}
```

### 4.2 Flux complet de soumission

```
1. Valider le formulaire (titre, catégorie, description obligatoires)
2. Capturer la position GPS (si autorisée)
3. Compresser les médias localement
4. Uploader chaque média vers Storage
5. INSERT dans `signalements`
6. INSERT dans `signalement_media` pour chaque fichier
7. Confirmer à l'utilisateur
```

### 4.3 Insertion dans `signalements`

```dart
Future<String> createSignalement({
  required String title,
  required String category,
  required String description,
  required String province,
  required String ville,
  String? commune,
  double? lat,
  double? lng,
  String? structureName,
  String? structureId,
  String priority = 'moyenne',
  bool isAnonymous = false,
}) async {
  final user = supabase.auth.currentUser;

  final response = await supabase.from('signalements').insert({
    'reference': generateReference(),
    'category': category,
    'title': title,
    'description': description,
    'citizen_name': isAnonymous ? null : user?.userMetadata?['full_name'],
    'citizen_phone': isAnonymous ? null : user?.phone,
    'is_anonymous': isAnonymous,
    'province': province,
    'ville': ville,
    'commune': commune,
    'lat': lat,
    'lng': lng,
    'structure_name': structureName,
    'structure_id': structureId,
    'priority': priority,
    'status': 'nouveau',
  }).select('id').single();

  return response['id'] as String;
}
```

---

## 5. Gestion des médias

### 5.1 Contraintes de compression

| Type | Format source | Format cible | Résolution max | Qualité | Taille max |
|---|---|---|---|---|---|
| **Photo** | JPEG, PNG, HEIC | JPEG | 1920×1080 | 70-80% | 2 MB |
| **Vidéo** | MP4, MOV | MP4 (H.264) | 720p | CRF 28 | 20 MB |
| **Audio** | M4A, AAC, WAV | AAC (.m4a) | — | 64 kbps | 5 MB |

### 5.2 Compression côté mobile

#### Images (Flutter)

```dart
import 'package:flutter_image_compress/flutter_image_compress.dart';

Future<Uint8List> compressImage(File file) async {
  final result = await FlutterImageCompress.compressWithFile(
    file.absolute.path,
    minWidth: 1920,
    minHeight: 1080,
    quality: 75,
    format: CompressFormat.jpeg,
  );
  if (result == null) throw Exception('Compression échouée');
  if (result.length > 2 * 1024 * 1024) {
    // Re-compress with lower quality
    return (await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: 1280,
      minHeight: 720,
      quality: 50,
      format: CompressFormat.jpeg,
    ))!;
  }
  return result;
}
```

#### Vidéos (Flutter)

```dart
import 'package:video_compress/video_compress.dart';

Future<File> compressVideo(File file) async {
  final info = await VideoCompress.compressVideo(
    file.path,
    quality: VideoQuality.MediumQuality, // 720p
    deleteOrigin: false,
    includeAudio: true,
  );
  if (info == null || info.file == null) throw Exception('Compression vidéo échouée');

  // Vérifier la taille max (20 MB)
  final size = await info.file!.length();
  if (size > 20 * 1024 * 1024) {
    // Re-compress at lower quality
    final retry = await VideoCompress.compressVideo(
      file.path,
      quality: VideoQuality.LowQuality,
      deleteOrigin: false,
      includeAudio: true,
    );
    return retry!.file!;
  }
  return info.file!;
}
```

#### Audio (Flutter)

```dart
import 'package:record/record.dart';

// Enregistrer directement en AAC 64kbps
final recorder = AudioRecorder();
await recorder.start(
  const RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 64000,
    sampleRate: 22050,
    numChannels: 1,
  ),
  path: '${tempDir.path}/recording_${DateTime.now().millisecondsSinceEpoch}.m4a',
);

// Arrêter et récupérer le fichier
final path = await recorder.stop();
```

### 5.3 Génération de miniatures

```dart
import 'package:video_compress/video_compress.dart';

// Pour les vidéos
Future<Uint8List?> generateVideoThumbnail(File videoFile) async {
  final thumb = await VideoCompress.getByteThumbnail(
    videoFile.path,
    quality: 60,
    position: 1, // 1 seconde
  );
  return thumb;
}

// Pour les images, utiliser la version compressée elle-même comme thumbnail
// avec une résolution plus basse
Future<Uint8List?> generateImageThumbnail(File imageFile) async {
  return await FlutterImageCompress.compressWithFile(
    imageFile.absolute.path,
    minWidth: 300,
    minHeight: 300,
    quality: 50,
    format: CompressFormat.jpeg,
  );
}
```

### 5.4 Upload vers Supabase Storage

Le bucket utilisé est **`incidents`** (public: true). Le chemin suit la convention :

```
signalements/{signalement_id}/{type}_{timestamp}.{ext}
```

```dart
Future<SignalementMediaResult> uploadMedia({
  required String signalementId,
  required Uint8List fileBytes,
  required String type, // 'image', 'video', 'audio'
  required String originalFilename,
  Uint8List? thumbnailBytes,
  int? durationSeconds,
}) async {
  final ext = type == 'image' ? 'jpg' : type == 'video' ? 'mp4' : 'm4a';
  final ts = DateTime.now().millisecondsSinceEpoch;
  final storagePath = 'signalements/$signalementId/${type}_$ts.$ext';

  // 1. Upload fichier principal
  await supabase.storage.from('incidents').uploadBinary(
    storagePath,
    fileBytes,
    fileOptions: FileOptions(
      contentType: type == 'image'
          ? 'image/jpeg'
          : type == 'video'
              ? 'video/mp4'
              : 'audio/mp4',
      upsert: true,
    ),
  );

  final publicUrl = supabase.storage.from('incidents').getPublicUrl(storagePath);

  // 2. Upload thumbnail si disponible
  String? thumbnailUrl;
  if (thumbnailBytes != null) {
    final thumbPath = 'signalements/$signalementId/thumb_${type}_$ts.jpg';
    await supabase.storage.from('incidents').uploadBinary(
      thumbPath,
      thumbnailBytes,
      fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
    );
    thumbnailUrl = supabase.storage.from('incidents').getPublicUrl(thumbPath);
  }

  // 3. INSERT dans signalement_media
  final mediaRow = await supabase.from('signalement_media').insert({
    'signalement_id': signalementId,
    'type': type,
    'url': publicUrl,
    'thumbnail': thumbnailUrl,
    'duration': durationSeconds,
    'filename': originalFilename,
  }).select('id').single();

  return SignalementMediaResult(
    id: mediaRow['id'],
    url: publicUrl,
    thumbnailUrl: thumbnailUrl,
  );
}
```

### 5.5 Upload avec retry et progression

```dart
Future<void> uploadWithRetry({
  required String bucket,
  required String path,
  required Uint8List bytes,
  required FileOptions options,
  int maxRetries = 3,
  void Function(double progress)? onProgress,
}) async {
  int attempt = 0;
  while (attempt < maxRetries) {
    try {
      await supabase.storage.from(bucket).uploadBinary(
        path,
        bytes,
        fileOptions: options,
      );
      onProgress?.call(1.0);
      return;
    } catch (e) {
      attempt++;
      if (attempt >= maxRetries) rethrow;
      // Backoff exponentiel
      await Future.delayed(Duration(seconds: attempt * 2));
    }
  }
}
```

### 5.6 Limites par signalement

| Contrainte | Valeur | Raison |
|---|---|---|
| Photos max | 10 | Limiter la charge Storage |
| Vidéos max | 3 | Bande passante RDC |
| Audios max | 5 | Témoignages vocaux multiples |
| Taille totale max | 50 MB | Contrainte réseau 3G/4G |
| Durée vidéo max | 120 secondes | Compression raisonnable |
| Durée audio max | 300 secondes | 5 min de témoignage |

---

## 6. Géolocalisation

### 6.1 Capture GPS

```dart
import 'package:geolocator/geolocator.dart';

Future<Position?> captureLocation() async {
  // Vérifier les permissions
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return null;
  }
  if (permission == LocationPermission.deniedForever) return null;

  try {
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );
  } catch (e) {
    // Fallback : dernière position connue
    return await Geolocator.getLastKnownPosition();
  }
}
```

### 6.2 Résolution de commune

Si l'application a accès à la table `commune_bounds`, la commune peut être déterminée côté client :

```dart
Future<String?> resolveCommune(double lat, double lng) async {
  final result = await supabase
      .from('commune_bounds')
      .select('commune_name')
      .lte('min_lat', lat)
      .gte('max_lat', lat)
      .lte('min_lng', lng)
      .gte('max_lng', lng)
      .order('max_lng', ascending: true) // Plus petit bounding box
      .limit(1)
      .maybeSingle();

  return result?['commune_name'] as String?;
}
```

### 6.3 Géolocalisation de la structure

Si le signalement concerne une structure enregistrée, l'app peut la sélectionner depuis la liste :

```dart
Future<List<Map<String, dynamic>>> searchStructures(String query) async {
  final result = await supabase
      .from('health_structures')
      .select('id, name, type, address, commune, lat, lng')
      .ilike('name', '%$query%')
      .limit(20);

  return List<Map<String, dynamic>>.from(result);
}
```

---

## 7. Suivi en temps réel

### 7.1 Écouter les mises à jour de ses propres signalements

Le citoyen peut suivre l'évolution de ses signalements en temps réel :

```dart
RealtimeChannel? _signalementChannel;

void listenToMySignalements(String citizenPhone) {
  _signalementChannel = supabase
      .channel('my-signalements-${DateTime.now().millisecondsSinceEpoch}')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'signalements',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'citizen_phone',
          value: citizenPhone,
        ),
        callback: (payload) {
          final newData = payload.newRecord;
          final status = newData['status'] as String;
          final reference = newData['reference'] as String;

          // Notification locale
          showLocalNotification(
            title: 'Signalement $reference',
            body: 'Statut mis à jour : ${_statusLabel(status)}',
          );

          // Rafraîchir la liste
          refreshSignalements();
        },
      )
      .subscribe();
}

void dispose() {
  if (_signalementChannel != null) {
    supabase.removeChannel(_signalementChannel!);
  }
}

String _statusLabel(String status) {
  const labels = {
    'nouveau': 'Nouveau',
    'en_cours': 'En cours de traitement',
    'enquete': 'En enquête',
    'resolu': 'Résolu',
    'classe': 'Classé',
    'transfere': 'Transféré',
  };
  return labels[status] ?? status;
}
```

### 7.2 Écouter les notes de suivi

```dart
void listenToSignalementNotes(String signalementId) {
  supabase
      .channel('sig-notes-$signalementId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'signalement_notes',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'signalement_id',
          value: signalementId,
        ),
        callback: (payload) {
          final note = payload.newRecord;
          // Afficher la nouvelle note dans le thread de suivi
          addNoteToUI(note);
        },
      )
      .subscribe();
}
```

### 7.3 Propagation au Dashboard

Le dashboard écoute déjà la table `signalements` via Realtime (hook `useSignalements` dans `useSupabaseData.ts`). Tout INSERT depuis le mobile apparaît **instantanément** :

- Sur la liste du module Signalements
- Sur la carte Radar (couche `signalements-layer`) si lat/lng sont renseignés
- Dans les statistiques (compteurs, graphiques par catégorie/province)
- Dans les vues matérialisées (`mv_signalements_by_commune`) après le prochain refresh pg_cron (5 min)

---

## 8. Anonymat

### 8.1 Règles strictes

Quand `is_anonymous = true` :

| Champ | Comportement |
|---|---|
| `citizen_name` | **DOIT** être `null` |
| `citizen_phone` | **DOIT** être `null` |
| `lat` / `lng` | Peuvent être fournis (localisation de l'incident, pas du plaignant) |
| `description` | Aucune mention de l'identité du plaignant |

### 8.2 Validation côté client

```dart
Map<String, dynamic> sanitizeForAnonymous(Map<String, dynamic> data) {
  if (data['is_anonymous'] == true) {
    data.remove('citizen_name');
    data.remove('citizen_phone');
    data['citizen_name'] = null;
    data['citizen_phone'] = null;
  }
  return data;
}
```

### 8.3 Affichage dashboard

Le dashboard affiche "Anonyme" en jaune dans la fiche détail quand `is_anonymous` est true. Le téléphone du plaignant est masqué et le bouton "Appeler le plaignant" est caché.

---

## 9. Catégories et priorités

### 9.1 Catégories disponibles

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

### 9.2 Statuts du workflow

```
nouveau → en_cours → enquete → resolu
                  ↘ classe
                  ↘ transfere
```

| Code | Libellé | Description |
|---|---|---|
| `nouveau` | Nouveau | Vient d'être créé, non pris en charge |
| `en_cours` | En cours | Un opérateur examine le dossier |
| `enquete` | En enquête | Investigation approfondie en cours |
| `resolu` | Résolu | Mesures correctives appliquées |
| `classe` | Classé | Classé sans suite (infondé, doublon...) |
| `transfere` | Transféré | Transmis à une autre autorité |

### 9.3 Priorités

| Code | Libellé | Couleur UI | Critère |
|---|---|---|---|
| `critique` | Critique | Rouge (#ef4444) | Danger immédiat pour des vies |
| `haute` | Haute | Orange (#f59e0b) | Impact grave, action rapide requise |
| `moyenne` | Moyenne | Bleu (#3b82f6) | Standard, traitement normal |
| `basse` | Basse | Gris (#6b7280) | Informationnel, pas urgent |

---

## 10. Scalabilité et performance

### 10.1 Stratégie de pagination

Le dashboard charge 200 signalements max. Pour l'app mobile, implémenter une pagination curseur :

```dart
Future<List<Map<String, dynamic>>> loadSignalements({
  String? cursor, // created_at du dernier élément chargé
  int limit = 30,
  String? citizenPhone,
}) async {
  var query = supabase
      .from('signalements')
      .select('*')
      .order('created_at', ascending: false)
      .limit(limit);

  if (citizenPhone != null) {
    query = query.eq('citizen_phone', citizenPhone);
  }
  if (cursor != null) {
    query = query.lt('created_at', cursor);
  }

  return List<Map<String, dynamic>>.from(await query);
}
```

### 10.2 Optimisation des uploads réseau

En conditions réseau dégradées (3G, VSAT) courantes en RDC :

```dart
class MediaUploadQueue {
  final List<PendingUpload> _queue = [];
  bool _isProcessing = false;

  /// Ajouter un média à la file d'upload
  void enqueue(PendingUpload upload) {
    _queue.add(upload);
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    while (_queue.isNotEmpty) {
      final upload = _queue.first;
      try {
        await uploadWithRetry(
          bucket: 'incidents',
          path: upload.storagePath,
          bytes: upload.bytes,
          options: FileOptions(contentType: upload.contentType, upsert: true),
          maxRetries: 5,
          onProgress: upload.onProgress,
        );

        // Enregistrer dans signalement_media
        await supabase.from('signalement_media').insert({
          'signalement_id': upload.signalementId,
          'type': upload.type,
          'url': supabase.storage.from('incidents').getPublicUrl(upload.storagePath),
          'thumbnail': upload.thumbnailUrl,
          'duration': upload.durationSeconds,
          'filename': upload.filename,
        });

        _queue.removeAt(0);
      } catch (e) {
        // Garder dans la queue pour retry ultérieur
        // Attendre avant de réessayer
        await Future.delayed(const Duration(seconds: 10));
      }
    }

    _isProcessing = false;
  }
}
```

### 10.3 Cache local (offline-first)

```dart
import 'package:hive/hive.dart';

/// Stocker les signalements en brouillon pour envoi ultérieur
class SignalementDraftStore {
  late Box<Map> _box;

  Future<void> init() async {
    _box = await Hive.openBox<Map>('signalement_drafts');
  }

  Future<void> saveDraft(String id, Map<String, dynamic> data) async {
    await _box.put(id, data);
  }

  List<Map<String, dynamic>> getPendingDrafts() {
    return _box.values.map((v) => Map<String, dynamic>.from(v)).toList();
  }

  Future<void> removeDraft(String id) async {
    await _box.delete(id);
  }

  /// Synchroniser les brouillons quand le réseau revient
  Future<void> syncPendingDrafts() async {
    final drafts = getPendingDrafts();
    for (final draft in drafts) {
      try {
        await supabase.from('signalements').insert(draft);
        await removeDraft(draft['local_id']);
      } catch (e) {
        // Garder pour le prochain sync
        continue;
      }
    }
  }
}
```

### 10.4 Index et vues matérialisées existants

Le backend dispose de :

- **`mv_signalements_by_commune`** : Vue matérialisée agrégée par commune, rafraîchie toutes les 5 minutes via `pg_cron`
- **Index sur `signalements.created_at`** : Pagination performante
- **Realtime** activé sur la table `signalements` via `supabase_realtime` publication

### 10.5 Dédoublonnage

Pour éviter les signalements en double (double tap, retry réseau) :

```dart
/// Générer un idempotency key basé sur le contenu
String generateIdempotencyKey(Map<String, dynamic> data) {
  final content = '${data['title']}_${data['category']}_${data['citizen_phone'] ?? 'anon'}_${DateTime.now().toIso8601String().substring(0, 13)}';
  return content.hashCode.toRadixString(16);
}

/// Vérifier si un signalement similaire existe récemment
Future<bool> isDuplicate(String title, String? phone) async {
  final thirtySecsAgo = DateTime.now().subtract(const Duration(seconds: 30)).toIso8601String();
  final result = await supabase
      .from('signalements')
      .select('id')
      .eq('title', title)
      .gte('created_at', thirtySecsAgo)
      .limit(1);

  return (result as List).isNotEmpty;
}
```

---

## 11. Contrats JSON complets

### 11.1 Création d'un signalement (INSERT)

```json
{
  "reference": "SIG-20260404-12345",
  "category": "corruption",
  "title": "Extorsion au service des urgences",
  "description": "Le personnel exige un paiement de 50$ avant toute prise en charge...",
  "citizen_name": "Jean Mukendi",
  "citizen_phone": "+243812345678",
  "is_anonymous": false,
  "province": "Kinshasa",
  "ville": "Kinshasa",
  "commune": "Lemba",
  "lat": -4.3447,
  "lng": 15.3271,
  "structure_name": "Hôpital Général de Kinshasa",
  "structure_id": "uuid-de-la-structure",
  "priority": "haute",
  "status": "nouveau"
}
```

### 11.2 Insertion média (INSERT dans `signalement_media`)

```json
{
  "signalement_id": "uuid-du-signalement",
  "type": "image",
  "url": "https://npucuhlvoalcbwdfedae.supabase.co/storage/v1/object/public/incidents/signalements/uuid/image_1712234567890.jpg",
  "thumbnail": "https://npucuhlvoalcbwdfedae.supabase.co/storage/v1/object/public/incidents/signalements/uuid/thumb_image_1712234567890.jpg",
  "duration": null,
  "filename": "preuve_extorsion.jpg"
}
```

### 11.3 Signalement anonyme

```json
{
  "reference": "SIG-20260404-67890",
  "category": "abus_sexuels",
  "title": "Harcèlement par un médecin-chef",
  "description": "Plusieurs stagiaires victimes...",
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

---

## 12. Exemples Dart/Flutter

### 12.1 Service complet de signalement

```dart
class SignalementService {
  final SupabaseClient supabase;
  final MediaUploadQueue _uploadQueue = MediaUploadQueue();

  SignalementService(this.supabase);

  /// Soumettre un signalement complet avec médias
  Future<SubmitResult> submit({
    required String title,
    required String category,
    required String description,
    required String province,
    required String ville,
    String? commune,
    bool isAnonymous = false,
    String priority = 'moyenne',
    String? structureName,
    String? structureId,
    List<MediaFile> mediaFiles = const [],
  }) async {
    // 1. Capturer GPS
    Position? position;
    try {
      position = await captureLocation();
    } catch (_) {}

    // 2. Résoudre la commune si GPS disponible et commune non fournie
    if (commune == null && position != null) {
      commune = await resolveCommune(position.latitude, position.longitude);
    }

    // 3. Vérifier doublon
    if (await isDuplicate(title, isAnonymous ? null : supabase.auth.currentUser?.phone)) {
      throw Exception('Un signalement similaire a été soumis récemment');
    }

    // 4. Insérer le signalement
    final signalementId = await createSignalement(
      title: title,
      category: category,
      description: description,
      province: province,
      ville: ville,
      commune: commune,
      lat: position?.latitude,
      lng: position?.longitude,
      structureName: structureName,
      structureId: structureId,
      priority: priority,
      isAnonymous: isAnonymous,
    );

    // 5. Uploader les médias en parallèle (max 3 simultanés)
    final mediaResults = <SignalementMediaResult>[];
    for (final media in mediaFiles) {
      final compressed = await _compressMedia(media);
      final thumbnail = await _generateThumbnail(media);

      _uploadQueue.enqueue(PendingUpload(
        signalementId: signalementId,
        storagePath: 'signalements/$signalementId/${media.type}_${DateTime.now().millisecondsSinceEpoch}.${_ext(media.type)}',
        bytes: compressed,
        contentType: _contentType(media.type),
        type: media.type,
        filename: media.originalFilename,
        thumbnailUrl: null, // sera mis à jour après upload thumbnail
        durationSeconds: media.durationSeconds,
      ));
    }

    return SubmitResult(
      signalementId: signalementId,
      mediaCount: mediaFiles.length,
      hasLocation: position != null,
    );
  }

  Future<Uint8List> _compressMedia(MediaFile media) async {
    switch (media.type) {
      case 'image':
        return await compressImage(media.file);
      case 'video':
        final compressed = await compressVideo(media.file);
        return await compressed.readAsBytes();
      case 'audio':
        return await media.file.readAsBytes(); // Déjà compressé à l'enregistrement
      default:
        return await media.file.readAsBytes();
    }
  }

  Future<Uint8List?> _generateThumbnail(MediaFile media) async {
    if (media.type == 'video') return generateVideoThumbnail(media.file);
    if (media.type == 'image') return generateImageThumbnail(media.file);
    return null;
  }

  String _ext(String type) => type == 'image' ? 'jpg' : type == 'video' ? 'mp4' : 'm4a';
  String _contentType(String type) => type == 'image' ? 'image/jpeg' : type == 'video' ? 'video/mp4' : 'audio/mp4';
}
```

### 12.2 Widget formulaire (structure Flutter)

```dart
// Arbre de widgets recommandé pour le formulaire
class SignalementFormScreen extends StatefulWidget {
  @override
  _SignalementFormScreenState createState() => _SignalementFormScreenState();
}

class _SignalementFormScreenState extends State<SignalementFormScreen> {
  final _formKey = GlobalKey<FormState>();
  String _category = 'corruption';
  String _priority = 'moyenne';
  String _province = 'Kinshasa';
  String _ville = 'Kinshasa';
  bool _isAnonymous = false;
  bool _isSubmitting = false;
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _communeController = TextEditingController();
  final List<MediaFile> _mediaFiles = [];

  // Structure sélectionnée (optionnel)
  Map<String, dynamic>? _selectedStructure;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau signalement')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Toggle anonyme
            SwitchListTile(
              title: const Text('Signalement anonyme'),
              subtitle: const Text('Votre identité ne sera pas révélée'),
              value: _isAnonymous,
              onChanged: (v) => setState(() => _isAnonymous = v),
            ),

            // Catégorie (dropdown)
            DropdownButtonFormField<String>(
              value: _category,
              items: categoryEntries.map((e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (v) => setState(() => _category = v!),
              decoration: const InputDecoration(labelText: 'Catégorie *'),
            ),

            // Priorité
            DropdownButtonFormField<String>(
              value: _priority,
              items: ['basse', 'moyenne', 'haute', 'critique'].map((p) =>
                DropdownMenuItem(value: p, child: Text(p.toUpperCase()))).toList(),
              onChanged: (v) => setState(() => _priority = v!),
              decoration: const InputDecoration(labelText: 'Priorité'),
            ),

            // Titre
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Titre *'),
              validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
              maxLength: 200,
            ),

            // Description
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description détaillée *'),
              validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
              maxLines: 5,
              maxLength: 2000,
            ),

            // Province / Ville / Commune
            // ... dropdowns similaires

            // Recherche de structure (optionnel)
            // ... autocomplete field

            // Section médias
            MediaPickerSection(
              files: _mediaFiles,
              onAdd: _pickMedia,
              onRemove: (i) => setState(() => _mediaFiles.removeAt(i)),
              maxPhotos: 10,
              maxVideos: 3,
              maxAudios: 5,
            ),

            // Bouton soumettre
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const CircularProgressIndicator()
                  : const Text('SOUMETTRE LE SIGNALEMENT'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    try {
      final service = SignalementService(Supabase.instance.client);
      await service.submit(
        title: _titleController.text,
        category: _category,
        description: _descriptionController.text,
        province: _province,
        ville: _ville,
        commune: _communeController.text.isNotEmpty ? _communeController.text : null,
        isAnonymous: _isAnonymous,
        priority: _priority,
        structureName: _selectedStructure?['name'],
        structureId: _selectedStructure?['id'],
        mediaFiles: _mediaFiles,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signalement envoyé avec succès')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }
}
```

---

## 13. Matrice RLS

### Table `signalements`

| Action | `citoyen` | `call_center` | `admin` | `superviseur` | `hopital` | `secouriste` |
|---|---|---|---|---|---|---|
| SELECT | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| INSERT | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| UPDATE | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ |
| DELETE | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

### Table `signalement_media`

| Action | `citoyen` | `call_center` | `admin` | `superviseur` |
|---|---|---|---|---|
| SELECT | ✅ | ✅ | ✅ | ✅ |
| INSERT | ✅ | ✅ | ✅ | ✅ |
| UPDATE | ❌ | ❌ | ❌ | ❌ |
| DELETE | ❌ | ❌ | ❌ | ❌ |

### Table `signalement_notes`

| Action | `citoyen` | `call_center` | `admin` | `superviseur` |
|---|---|---|---|---|
| SELECT | ✅ | ✅ | ✅ | ✅ |
| INSERT | ❌ | ✅ | ✅ | ✅ |
| UPDATE | ❌ | ❌ | ❌ | ❌ |
| DELETE | ❌ | ❌ | ❌ | ❌ |

### Storage (bucket `incidents`)

| Chemin | Lecture | Écriture |
|---|---|---|
| `signalements/{id}/*` | Public (bucket public) | Authentifié (citoyen, opérateur) |

---

## Checklist d'intégration mobile

- [ ] Configurer Supabase Flutter SDK avec l'URL et la clé anon
- [ ] Implémenter l'authentification citoyen (SMS OTP via `twilio-verify`)
- [ ] Créer le formulaire de signalement avec toutes les catégories
- [ ] Intégrer la capture GPS avec permission handling
- [ ] Implémenter la compression image (JPEG, max 2MB)
- [ ] Implémenter la compression vidéo (MP4 720p, max 20MB)
- [ ] Implémenter l'enregistrement audio (AAC 64kbps, max 5min)
- [ ] Implémenter la génération de miniatures
- [ ] Implémenter l'upload avec retry et backoff exponentiel
- [ ] Implémenter le cache offline (Hive) pour brouillons
- [ ] Configurer le listener Realtime pour le suivi des statuts
- [ ] Implémenter la pagination curseur pour la liste
- [ ] Implémenter le dédoublonnage (30s window)
- [ ] Gérer le mode anonyme (nullification des PII)
- [ ] Tester en conditions réseau dégradées (3G simulé)
- [ ] Valider que les signalements apparaissent en temps réel sur le dashboard
- [ ] Valider l'affichage des médias dans l'onglet Médias du dashboard
- [ ] Tester les 22 catégories
- [ ] Vérifier l'affichage sur la carte Radar (couche signalements)

---

*Document généré le 4 avril 2026 — Étoile Bleue RDC*
