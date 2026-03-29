# Prompt Cursor : Intégration bidirectionnelle des appels Mobile ↔ Dashboard

## Contexte

L'application Flutter mobile (citoyens) et le dashboard web (call center) partagent le même backend Supabase. L'objectif est d'implémenter les appels audio/vidéo bidirectionnels via **Agora RTC**, en utilisant les tables Supabase existantes comme couche de signalisation.

### Backend Supabase

- **URL** : `https://npucuhlvoalcbwdfedae.supabase.co`
- **Anon Key** : `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5wdWN1aGx2b2FsY2J3ZGZlZGFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2NDQ3NzcsImV4cCI6MjA5MDIyMDc3N30.1XLmBbRpx3Q-raPvHDnLm3dLuQGRWFHaP-fXv9BbqQk`
- **App ID Agora** : `e2e0e5a6ef0d4ce3b2ab9efad48d62cf`

### Architecture existante (côté dashboard web)

Le dashboard utilise déjà :
- **Table `incidents`** : chaque appel SOS crée un incident avec `reference` = nom du canal Agora
- **Table `call_queue`** : file d'attente avec auto-assignation aux opérateurs via trigger SQL
- **Table `call_history`** : historique complet des appels (utilisé aussi pour les appels sortants du call center vers les citoyens)
- **Table `users_directory`** : profils utilisateurs avec `auth_user_id`, `role`, `phone`, `is_on_call`, `active_call_id`
- **Edge Function `agora-token`** : génère des tokens RTC sécurisés

### Tables Supabase pertinentes — Schéma exact

#### Table `incidents`
```sql
id                        uuid PRIMARY KEY DEFAULT gen_random_uuid()
reference                 text NOT NULL          -- "SOS-{userId_8chars}-{timestamp}" = canal Agora
type                      text NOT NULL          -- "urgence_medicale", "accident", "agression", etc.
title                     text NOT NULL
description               text
status                    incident_status DEFAULT 'new'  -- 'new','dispatched','in_progress','resolved','archived'
priority                  incident_priority DEFAULT 'medium'  -- 'critical','high','medium','low'
caller_name               text
caller_phone              text
location_lat              double precision
location_lng              double precision
location_address          text
citizen_id                uuid                   -- FK vers users_directory.id
assigned_operator_id      uuid
caller_realtime_lat       double precision       -- GPS temps réel pendant l'appel
caller_realtime_lng       double precision
caller_realtime_updated_at timestamptz
commune                   text
ville                     text DEFAULT 'Kinshasa'
province                  text DEFAULT 'Kinshasa'
media_urls                text[] DEFAULT '{}'
media_type                text DEFAULT 'photo'
notes                     text
ended_by                  text                   -- "citizen", "operator", "system"
incident_at               timestamptz
created_at                timestamptz DEFAULT now()
updated_at                timestamptz DEFAULT now()
resolved_at               timestamptz
archived_at               timestamptz
```

#### Table `call_queue`
```sql
id                        uuid PRIMARY KEY DEFAULT gen_random_uuid()
incident_id               uuid                   -- FK vers incidents.id
call_id                   uuid                   -- FK vers call_history.id
channel_name              text NOT NULL           -- = incident.reference = canal Agora
caller_name               text
caller_phone              text
caller_lat                double precision
caller_lng                double precision
priority                  text DEFAULT 'medium'
category                  text DEFAULT 'general'
status                    text DEFAULT 'waiting'  -- 'waiting','assigned','answered','completed'
assigned_operator_id      uuid
assigned_at               timestamptz
answered_at               timestamptz
completed_at              timestamptz
abandoned_at              timestamptz
estimated_wait_seconds    integer DEFAULT 0
notes                     text
created_at                timestamptz DEFAULT now()
```

#### Table `call_history`
```sql
id                        uuid PRIMARY KEY DEFAULT gen_random_uuid()
incident_id               uuid                   -- FK vers incidents.id
operator_id               uuid
citizen_id                uuid                   -- FK vers users_directory.id (pour appels sortants)
call_type                 call_type DEFAULT 'incoming'  -- 'incoming','outgoing','internal'
status                    call_status DEFAULT 'ringing' -- 'ringing','active','completed','missed','failed'
channel_name              text NOT NULL           -- canal Agora
caller_name               text
caller_phone              text
caller_lat                double precision
caller_lng                double precision
has_video                 boolean DEFAULT false
agora_uid                 integer
agora_token               text
location                  jsonb
triage_data               jsonb DEFAULT '{}'
notes                     text
commune                   text
ville                     text DEFAULT 'Kinshasa'
province                  text DEFAULT 'Kinshasa'
role                      text
ended_by                  text                   -- "citizen", "operator"
started_at                timestamptz DEFAULT now()
answered_at               timestamptz
ended_at                  timestamptz
duration_seconds          integer
created_at                timestamptz DEFAULT now()
```

#### Table `users_directory`
```sql
id                        uuid PRIMARY KEY DEFAULT gen_random_uuid()
auth_user_id              uuid                   -- FK vers auth.users.id
first_name                text NOT NULL
last_name                 text NOT NULL
phone                     text
email                     text
role                      user_role DEFAULT 'citoyen'  -- 'citoyen','secouriste','call_center','hopital','volontaire','superviseur','admin'
status                    text DEFAULT 'active'
available                 boolean DEFAULT true
is_on_call                boolean DEFAULT false
active_call_id            text
call_count                integer DEFAULT 0
last_call_at              timestamptz
date_of_birth             date
blood_type                text
allergies                 text[] DEFAULT '{}'
medical_history           text[] DEFAULT '{}'
medications               text[] DEFAULT '{}'
zone                      text
-- ... autres champs
```

### Triggers SQL existants

1. **`on_incident_created`** : Quand un incident est inséré avec `status='new'`, il crée automatiquement une entrée dans `call_queue` avec `status='waiting'` et appelle `auto_assign_queue()`.

2. **`auto_assign_queue()`** : Cherche un opérateur `call_center`/`admin`/`superviseur` avec `status='online'`, `is_on_call=false`, `available=true` et l'assigne à l'appel en attente.

3. **`on_incident_resolved`** : Quand un incident passe à `resolved` ou `archived`, complète les entrées `call_queue` associées.

### Edge Function `agora-token`

**Endpoint** : `POST /functions/v1/agora-token`

**Request body** :
```json
{
  "channelName": "SOS-abc12345-1711234567",
  "uid": 0,
  "role": "publisher",
  "expireTime": 3600
}
```

**Response** :
```json
{
  "token": "007eJxT...",
  "appId": "e2e0e5a6ef0d4ce3b2ab9efad48d62cf",
  "channelName": "SOS-abc12345-1711234567",
  "uid": 0,
  "expiresAt": 1711238167
}
```

**Appel depuis Flutter** :
```dart
final response = await Supabase.instance.client.functions.invoke(
  'agora-token',
  body: {'channelName': channelName, 'uid': uid, 'role': 'publisher'},
);
final token = response.data['token'] as String;
final appId = response.data['appId'] as String;
```

---

## Tâches à implémenter

### Tâche 1 : Service Agora RTC (`lib/services/agora_service.dart`)

Créer un service singleton qui encapsule le SDK `agora_rtc_engine` Flutter :

```dart
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AgoraService {
  static final AgoraService instance = AgoraService._();
  AgoraService._();

  static const String appId = "e2e0e5a6ef0d4ce3b2ab9efad48d62cf";
  RtcEngine? _engine;
  bool _isInitialized = false;

  // Callbacks que les providers/screens peuvent enregistrer
  Function(RtcConnection, int, int)? onUserJoined;
  Function(RtcConnection, int, UserOfflineReasonType)? onUserOffline;
  Function(RtcConnection, ConnectionStateType, ConnectionChangedReasonType)? onConnectionStateChanged;
  Function(RtcConnection, RtcStats)? onRtcStats;

  /// Initialiser le moteur Agora (appeler au démarrage de l'app, une seule fois)
  Future<void> initialize() async {
    if (_isInitialized) return;
    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));
    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        print('[Agora] Joined channel: ${connection.channelId}');
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        print('[Agora] Remote user joined: $remoteUid');
        onUserJoined?.call(connection, remoteUid, elapsed);
      },
      onUserOffline: (connection, remoteUid, reason) {
        print('[Agora] Remote user left: $remoteUid');
        onUserOffline?.call(connection, remoteUid, reason);
      },
      onConnectionStateChanged: (connection, state, reason) {
        print('[Agora] Connection state: $state, reason: $reason');
        onConnectionStateChanged?.call(connection, state, reason);
      },
    ));
    _isInitialized = true;
  }

  /// Demander les permissions micro + caméra
  Future<bool> requestPermissions() async {
    final micStatus = await Permission.microphone.request();
    final camStatus = await Permission.camera.request();
    return micStatus.isGranted && camStatus.isGranted;
  }

  /// Récupérer un token Agora via l'Edge Function Supabase
  Future<Map<String, dynamic>> fetchToken(String channelName, {int uid = 0}) async {
    final response = await Supabase.instance.client.functions.invoke(
      'agora-token',
      body: {'channelName': channelName, 'uid': uid, 'role': 'publisher'},
    );
    if (response.status != 200) {
      throw Exception('Failed to fetch Agora token: ${response.data}');
    }
    return response.data as Map<String, dynamic>;
  }

  /// Rejoindre un canal audio uniquement
  Future<void> joinAudioChannel(String channelName, String token, {int uid = 0}) async {
    await _engine!.enableAudio();
    await _engine!.disableVideo();
    await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await _engine!.joinChannel(
      token: token,
      channelId: channelName,
      uid: uid,
      options: const ChannelMediaOptions(
        autoSubscribeAudio: true,
        autoSubscribeVideo: false,
        publishMicrophoneTrack: true,
        publishCameraTrack: false,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  /// Rejoindre un canal vidéo (audio + vidéo)
  Future<void> joinVideoChannel(String channelName, String token, {int uid = 0}) async {
    await _engine!.enableAudio();
    await _engine!.enableVideo();
    await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await _engine!.joinChannel(
      token: token,
      channelId: channelName,
      uid: uid,
      options: const ChannelMediaOptions(
        autoSubscribeAudio: true,
        autoSubscribeVideo: true,
        publishMicrophoneTrack: true,
        publishCameraTrack: true,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  /// Quitter le canal actuel
  Future<void> leaveChannel() async {
    await _engine?.leaveChannel();
  }

  /// Mute/unmute le microphone local
  Future<void> setMuted(bool muted) async {
    await _engine?.muteLocalAudioStream(muted);
  }

  /// Activer/désactiver le haut-parleur
  Future<void> setSpeakerOn(bool speakerOn) async {
    await _engine?.setEnableSpeakerphone(speakerOn);
  }

  /// Basculer entre caméra avant/arrière
  Future<void> switchCamera() async {
    await _engine?.switchCamera();
  }

  /// Activer/désactiver la vidéo locale en cours d'appel
  Future<void> setVideoEnabled(bool enabled) async {
    if (enabled) {
      await _engine?.enableVideo();
      await _engine?.muteLocalVideoStream(false);
    } else {
      await _engine?.muteLocalVideoStream(true);
    }
  }

  /// Obtenir le moteur pour les widgets vidéo
  RtcEngine? get engine => _engine;

  /// Libérer les ressources
  Future<void> dispose() async {
    await _engine?.leaveChannel();
    await _engine?.release();
    _isInitialized = false;
  }
}
```

### Tâche 2 : Service d'appel SOS — Citoyen → Call Center (`lib/services/sos_call_service.dart`)

```dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class SosCallService {
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _queueChannel;

  /// Lance un appel SOS
  ///
  /// Retourne le `reference` de l'incident créé (= nom du canal Agora)
  Future<Map<String, dynamic>> startSosCall({
    required String myDirectoryId,
    required String myName,
    required String myPhone,
    required String callType,  // "audio" ou "video"
    required double lat,
    required double lng,
    String emergencyType = 'urgence_medicale',
    String? description,
  }) async {
    // 1. Générer la référence unique = canal Agora
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final shortId = myDirectoryId.substring(0, 8);
    final reference = 'SOS-$shortId-$timestamp';

    // 2. Créer l'incident dans Supabase
    //    Le trigger `on_incident_created` créera automatiquement
    //    une entrée dans `call_queue` et appellera `auto_assign_queue()`
    final incidentResponse = await _supabase.from('incidents').insert({
      'reference': reference,
      'type': emergencyType,
      'title': 'Appel SOS - $myName',
      'description': description ?? 'Appel d\'urgence depuis l\'application mobile',
      'status': 'new',
      'priority': 'critical',
      'caller_name': myName,
      'caller_phone': myPhone,
      'location_lat': lat,
      'location_lng': lng,
      'citizen_id': myDirectoryId,
      'ville': 'Kinshasa',
      'province': 'Kinshasa',
      'media_type': callType == 'video' ? 'video' : 'audio',
    }).select().single();

    // 3. Créer aussi une entrée dans call_history pour le suivi
    final callHistoryResponse = await _supabase.from('call_history').insert({
      'incident_id': incidentResponse['id'],
      'channel_name': reference,
      'call_type': 'incoming',  // incoming du point de vue du call center
      'status': 'ringing',
      'caller_name': myName,
      'caller_phone': myPhone,
      'caller_lat': lat,
      'caller_lng': lng,
      'citizen_id': myDirectoryId,
      'has_video': callType == 'video',
      'role': 'citoyen',
    }).select().single();

    return {
      'incident': incidentResponse,
      'callHistory': callHistoryResponse,
      'channelName': reference,
      'incidentId': incidentResponse['id'],
      'callHistoryId': callHistoryResponse['id'],
    };
  }

  /// Écoute les changements sur call_queue pour savoir quand un opérateur est assigné
  ///
  /// Callback `onOperatorAssigned` appelé quand status passe à 'assigned' ou 'answered'
  void listenForOperatorAssignment({
    required String incidentId,
    required Function(Map<String, dynamic> queueEntry) onOperatorAssigned,
    required Function() onOperatorAnswered,
  }) {
    _queueChannel = _supabase.channel('sos-queue-$incidentId')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'call_queue',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'incident_id',
          value: incidentId,
        ),
        callback: (payload) {
          final newRecord = payload.newRecord;
          final status = newRecord['status'] as String?;
          if (status == 'assigned') {
            onOperatorAssigned(newRecord);
          } else if (status == 'answered') {
            onOperatorAnswered();
          }
        },
      )
      .subscribe();
  }

  /// Met à jour la position GPS en temps réel pendant un appel
  Future<void> updateRealtimeLocation(String incidentId, double lat, double lng) async {
    await _supabase.from('incidents').update({
      'caller_realtime_lat': lat,
      'caller_realtime_lng': lng,
      'caller_realtime_updated_at': DateTime.now().toIso8601String(),
    }).eq('id', incidentId);
  }

  /// Termine l'appel SOS côté citoyen
  Future<void> endCall({
    required String incidentId,
    required String callHistoryId,
  }) async {
    final now = DateTime.now().toIso8601String();

    // Mettre à jour l'incident
    await _supabase.from('incidents').update({
      'status': 'resolved',
      'resolved_at': now,
      'ended_by': 'citizen',
    }).eq('id', incidentId);

    // Mettre à jour call_history
    await _supabase.from('call_history').update({
      'status': 'completed',
      'ended_at': now,
      'ended_by': 'citizen',
    }).eq('id', callHistoryId);

    // Cleanup
    await _queueChannel?.unsubscribe();
    _queueChannel = null;
  }

  /// Annuler un appel SOS avant qu'un opérateur ne décroche
  Future<void> cancelCall({
    required String incidentId,
    required String callHistoryId,
  }) async {
    final now = DateTime.now().toIso8601String();

    await _supabase.from('incidents').update({
      'status': 'archived',
      'archived_at': now,
      'ended_by': 'citizen',
    }).eq('id', incidentId);

    await _supabase.from('call_history').update({
      'status': 'missed',
      'ended_at': now,
      'ended_by': 'citizen',
    }).eq('id', callHistoryId);

    await _supabase.from('call_queue').update({
      'status': 'completed',
      'abandoned_at': now,
    }).eq('incident_id', incidentId);

    await _queueChannel?.unsubscribe();
    _queueChannel = null;
  }

  void dispose() {
    _queueChannel?.unsubscribe();
  }
}
```

### Tâche 3 : Service d'écoute des appels entrants — Call Center → Citoyen (`lib/services/incoming_call_service.dart`)

```dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class IncomingCallService {
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _incomingChannel;

  /// Commencer à écouter les appels entrants pour ce citoyen
  ///
  /// Le dashboard crée un enregistrement dans `call_history` avec :
  ///   - call_type: "outgoing" (du point de vue du dashboard)
  ///   - citizen_id: l'ID users_directory du citoyen
  ///   - channel_name: le canal Agora à rejoindre
  ///   - status: "ringing"
  void startListening({
    required String myDirectoryId,
    required Function(Map<String, dynamic> callRecord) onIncomingCall,
  }) {
    _incomingChannel = _supabase.channel('incoming-calls-$myDirectoryId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'call_history',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'citizen_id',
          value: myDirectoryId,
        ),
        callback: (payload) {
          final record = payload.newRecord;
          final status = record['status'] as String?;
          final callType = record['call_type'] as String?;

          // Un appel "outgoing" du dashboard avec status "ringing" = appel entrant pour le citoyen
          if (status == 'ringing' && callType == 'outgoing') {
            onIncomingCall(record);
          }
        },
      )
      .subscribe();
  }

  /// Aussi écouter les updates (si l'opérateur raccroche pendant la sonnerie)
  void listenForCallUpdates({
    required String callId,
    required Function() onCallerHungUp,
  }) {
    _supabase.channel('call-updates-$callId')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'call_history',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: callId,
        ),
        callback: (payload) {
          final newStatus = payload.newRecord['status'] as String?;
          if (newStatus == 'completed' || newStatus == 'missed' || newStatus == 'failed') {
            onCallerHungUp();
          }
        },
      )
      .subscribe();
  }

  /// Le citoyen décroche l'appel entrant
  Future<void> answerCall(String callId) async {
    await _supabase.from('call_history').update({
      'status': 'active',
      'answered_at': DateTime.now().toIso8601String(),
    }).eq('id', callId);
  }

  /// Le citoyen refuse l'appel entrant
  Future<void> rejectCall(String callId) async {
    await _supabase.from('call_history').update({
      'status': 'missed',
      'ended_at': DateTime.now().toIso8601String(),
      'ended_by': 'citizen',
    }).eq('id', callId);
  }

  /// Terminer un appel actif (entrant depuis le call center)
  Future<void> endCall(String callId) async {
    await _supabase.from('call_history').update({
      'status': 'completed',
      'ended_at': DateTime.now().toIso8601String(),
      'ended_by': 'citizen',
    }).eq('id', callId);
  }

  void stopListening() {
    _incomingChannel?.unsubscribe();
    _incomingChannel = null;
  }

  void dispose() {
    stopListening();
  }
}
```

### Tâche 4 : Provider d'état des appels (`lib/providers/call_provider.dart`)

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../services/agora_service.dart';
import '../services/sos_call_service.dart';
import '../services/incoming_call_service.dart';

enum CallState { idle, outgoingRinging, incomingRinging, connecting, active, ended }

class CallProvider extends ChangeNotifier {
  final AgoraService _agora = AgoraService.instance;
  final SosCallService _sosService = SosCallService();
  final IncomingCallService _incomingService = IncomingCallService();

  CallState _state = CallState.idle;
  String? _currentChannelName;
  String? _currentIncidentId;
  String? _currentCallHistoryId;
  String? _callerName;
  String? _callType;  // "audio" ou "video"
  bool _isMuted = false;
  bool _isSpeakerOn = true;
  bool _isVideoEnabled = false;
  int _durationSeconds = 0;
  Timer? _durationTimer;
  Timer? _gpsTimer;
  Map<String, dynamic>? _incomingCallData;  // Données de l'appel entrant

  // Getters
  CallState get state => _state;
  String? get currentChannelName => _currentChannelName;
  String? get currentIncidentId => _currentIncidentId;
  String? get callerName => _callerName;
  String? get callType => _callType;
  bool get isMuted => _isMuted;
  bool get isSpeakerOn => _isSpeakerOn;
  bool get isVideoEnabled => _isVideoEnabled;
  int get durationSeconds => _durationSeconds;
  Map<String, dynamic>? get incomingCallData => _incomingCallData;

  /// Démarrer l'écoute des appels entrants (appeler après login)
  void startListeningForIncomingCalls(String myDirectoryId) {
    _incomingService.startListening(
      myDirectoryId: myDirectoryId,
      onIncomingCall: (callRecord) {
        _incomingCallData = callRecord;
        _callerName = callRecord['caller_name'] as String? ?? 'Opérateur';
        _callType = (callRecord['has_video'] == true) ? 'video' : 'audio';
        _currentChannelName = callRecord['channel_name'] as String?;
        _currentCallHistoryId = callRecord['id'] as String?;
        _state = CallState.incomingRinging;
        notifyListeners();
      },
    );
  }

  /// ═══════════════════════════════════════════
  /// FLUX 1 : Appel SOS sortant (Citoyen → Call Center)
  /// ═══════════════════════════════════════════

  Future<void> startSosCall({
    required String myDirectoryId,
    required String myName,
    required String myPhone,
    required String callType,
    required double lat,
    required double lng,
    String emergencyType = 'urgence_medicale',
    String? description,
  }) async {
    _state = CallState.outgoingRinging;
    _callType = callType;
    notifyListeners();

    try {
      // 1. Créer l'incident + call_history dans Supabase
      final result = await _sosService.startSosCall(
        myDirectoryId: myDirectoryId,
        myName: myName,
        myPhone: myPhone,
        callType: callType,
        lat: lat,
        lng: lng,
        emergencyType: emergencyType,
        description: description,
      );

      _currentChannelName = result['channelName'];
      _currentIncidentId = result['incidentId'];
      _currentCallHistoryId = result['callHistoryId'];

      // 2. Demander les permissions
      final hasPermissions = await _agora.requestPermissions();
      if (!hasPermissions) {
        throw Exception('Permissions micro/caméra refusées');
      }

      // 3. Récupérer le token Agora
      final tokenData = await _agora.fetchToken(_currentChannelName!);
      final token = tokenData['token'] as String;

      // 4. Rejoindre le canal Agora
      _state = CallState.connecting;
      notifyListeners();

      if (callType == 'video') {
        await _agora.joinVideoChannel(_currentChannelName!, token);
      } else {
        await _agora.joinAudioChannel(_currentChannelName!, token);
      }

      // 5. Écouter quand un opérateur rejoint le canal
      _agora.onUserJoined = (connection, remoteUid, elapsed) {
        _state = CallState.active;
        _startDurationTimer();
        _startGpsTracking();
        notifyListeners();
      };

      _agora.onUserOffline = (connection, remoteUid, reason) {
        // L'opérateur a raccroché
        hangUp();
      };

      // 6. Aussi écouter via Realtime quand l'opérateur est assigné
      _sosService.listenForOperatorAssignment(
        incidentId: _currentIncidentId!,
        onOperatorAssigned: (queueEntry) {
          // Un opérateur a été assigné, il va bientôt rejoindre Agora
          print('[SOS] Opérateur assigné: ${queueEntry['assigned_operator_id']}');
        },
        onOperatorAnswered: () {
          // L'opérateur a décroché côté dashboard
          print('[SOS] Opérateur a décroché');
        },
      );

    } catch (e) {
      _state = CallState.idle;
      notifyListeners();
      rethrow;
    }
  }

  /// ═══════════════════════════════════════════
  /// FLUX 2 : Répondre à un appel entrant (Call Center → Citoyen)
  /// ═══════════════════════════════════════════

  Future<void> answerIncomingCall() async {
    if (_currentCallHistoryId == null || _currentChannelName == null) return;

    _state = CallState.connecting;
    notifyListeners();

    try {
      // 1. Mettre à jour call_history: status → "active"
      await _incomingService.answerCall(_currentCallHistoryId!);

      // 2. Demander les permissions
      final hasPermissions = await _agora.requestPermissions();
      if (!hasPermissions) {
        throw Exception('Permissions micro/caméra refusées');
      }

      // 3. Récupérer le token Agora pour le canal
      final tokenData = await _agora.fetchToken(_currentChannelName!);
      final token = tokenData['token'] as String;

      // 4. Rejoindre le canal Agora
      if (_callType == 'video') {
        await _agora.joinVideoChannel(_currentChannelName!, token);
      } else {
        await _agora.joinAudioChannel(_currentChannelName!, token);
      }

      _state = CallState.active;
      _startDurationTimer();
      notifyListeners();

      // 5. Écouter si l'opérateur raccroche
      _agora.onUserOffline = (connection, remoteUid, reason) {
        hangUp();
      };

    } catch (e) {
      _state = CallState.idle;
      _incomingCallData = null;
      notifyListeners();
      rethrow;
    }
  }

  /// Rejeter un appel entrant
  Future<void> rejectIncomingCall() async {
    if (_currentCallHistoryId != null) {
      await _incomingService.rejectCall(_currentCallHistoryId!);
    }
    _resetState();
  }

  /// ═══════════════════════════════════════════
  /// Raccrocher (fonctionne dans les deux sens)
  /// ═══════════════════════════════════════════

  Future<void> hangUp() async {
    // Quitter le canal Agora
    await _agora.leaveChannel();

    // Mettre à jour Supabase selon le flux
    if (_currentIncidentId != null && _currentCallHistoryId != null) {
      // Flux SOS sortant
      await _sosService.endCall(
        incidentId: _currentIncidentId!,
        callHistoryId: _currentCallHistoryId!,
      );
    } else if (_currentCallHistoryId != null) {
      // Flux appel entrant du call center
      await _incomingService.endCall(_currentCallHistoryId!);
    }

    _state = CallState.ended;
    notifyListeners();

    // Reset après un court délai pour permettre l'affichage du "Call ended"
    Future.delayed(const Duration(seconds: 2), () {
      _resetState();
    });
  }

  /// ═══════════════════════════════════════════
  /// Contrôles audio/vidéo
  /// ═══════════════════════════════════════════

  Future<void> toggleMute() async {
    _isMuted = !_isMuted;
    await _agora.setMuted(_isMuted);
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    _isSpeakerOn = !_isSpeakerOn;
    await _agora.setSpeakerOn(_isSpeakerOn);
    notifyListeners();
  }

  Future<void> toggleVideo() async {
    _isVideoEnabled = !_isVideoEnabled;
    await _agora.setVideoEnabled(_isVideoEnabled);
    notifyListeners();
  }

  Future<void> switchCamera() async {
    await _agora.switchCamera();
  }

  /// ═══════════════════════════════════════════
  /// Helpers privés
  /// ═══════════════════════════════════════════

  void _startDurationTimer() {
    _durationSeconds = 0;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _durationSeconds++;
      notifyListeners();
    });
  }

  void _startGpsTracking() {
    if (_currentIncidentId == null) return;
    _gpsTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        await _sosService.updateRealtimeLocation(
          _currentIncidentId!,
          position.latitude,
          position.longitude,
        );
      } catch (e) {
        print('[GPS] Erreur tracking: $e');
      }
    });
  }

  void _resetState() {
    _state = CallState.idle;
    _currentChannelName = null;
    _currentIncidentId = null;
    _currentCallHistoryId = null;
    _callerName = null;
    _callType = null;
    _isMuted = false;
    _isSpeakerOn = true;
    _isVideoEnabled = false;
    _durationSeconds = 0;
    _durationTimer?.cancel();
    _durationTimer = null;
    _gpsTimer?.cancel();
    _gpsTimer = null;
    _incomingCallData = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _gpsTimer?.cancel();
    _sosService.dispose();
    _incomingService.dispose();
    super.dispose();
  }
}
```

### Tâche 5 : Écrans d'appel Flutter

#### 5a. Écran d'appel sortant SOS (`lib/screens/sos_call_screen.dart`)

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/call_provider.dart';

class SosCallScreen extends StatelessWidget {
  const SosCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, callProvider, _) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // État de l'appel
                _buildStatusIndicator(callProvider),
                const SizedBox(height: 40),

                // Nom / info
                Text(
                  callProvider.state == CallState.active
                    ? 'Opérateur en ligne'
                    : 'Recherche d\'un opérateur...',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                // Timer
                if (callProvider.state == CallState.active)
                  Text(
                    _formatDuration(callProvider.durationSeconds),
                    style: const TextStyle(color: Colors.white70, fontSize: 18, fontFamily: 'monospace'),
                  ),

                const Spacer(),

                // Contrôles
                if (callProvider.state == CallState.active) _buildControls(callProvider),
                const SizedBox(height: 30),

                // Bouton raccrocher
                _buildHangUpButton(context, callProvider),
                const SizedBox(height: 50),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusIndicator(CallProvider provider) {
    if (provider.state == CallState.outgoingRinging || provider.state == CallState.connecting) {
      return Column(
        children: [
          // Animated pulsing circle
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.8, end: 1.2),
            duration: const Duration(milliseconds: 800),
            builder: (context, value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red.withOpacity(0.2),
                    border: Border.all(color: Colors.red, width: 3),
                  ),
                  child: const Icon(Icons.emergency, color: Colors.red, size: 50),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          // Loading dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _PulsingDot(delay: i * 200),
            )),
          ),
        ],
      );
    }
    // Active state
    return Container(
      width: 80, height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.green.withOpacity(0.2),
        border: Border.all(color: Colors.green, width: 2),
      ),
      child: const Icon(Icons.phone_in_talk, color: Colors.green, size: 40),
    );
  }

  Widget _buildControls(CallProvider provider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ControlButton(
          icon: provider.isMuted ? Icons.mic_off : Icons.mic,
          label: provider.isMuted ? 'Unmute' : 'Mute',
          isActive: provider.isMuted,
          onTap: () => provider.toggleMute(),
        ),
        _ControlButton(
          icon: provider.isSpeakerOn ? Icons.volume_up : Icons.volume_off,
          label: 'Speaker',
          isActive: provider.isSpeakerOn,
          onTap: () => provider.toggleSpeaker(),
        ),
        _ControlButton(
          icon: provider.isVideoEnabled ? Icons.videocam : Icons.videocam_off,
          label: 'Vidéo',
          isActive: provider.isVideoEnabled,
          onTap: () => provider.toggleVideo(),
        ),
        if (provider.isVideoEnabled)
          _ControlButton(
            icon: Icons.switch_camera,
            label: 'Caméra',
            isActive: false,
            onTap: () => provider.switchCamera(),
          ),
      ],
    );
  }

  Widget _buildHangUpButton(BuildContext context, CallProvider provider) {
    return GestureDetector(
      onTap: () async {
        if (provider.state == CallState.outgoingRinging || provider.state == CallState.connecting) {
          // Annuler avant connexion — utiliser cancelCall si disponible
        }
        await provider.hangUp();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Container(
        width: 70, height: 70,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.red,
        ),
        child: const Icon(Icons.call_end, color: Colors.white, size: 35),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ControlButton({required this.icon, required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? Colors.white : Colors.white.withOpacity(0.15),
            ),
            child: Icon(icon, color: isActive ? Colors.black : Colors.white, size: 28),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final int delay;
  const _PulsingDot({required this.delay});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 10, height: 10,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.orange),
      ),
    );
  }
}
```

#### 5b. Écran d'appel entrant (`lib/screens/incoming_call_screen.dart`)

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/call_provider.dart';

/// Affiché en overlay plein écran quand le call center appelle le citoyen.
/// Utilisez `showDialog` ou un `Overlay` depuis le widget racine quand
/// `callProvider.state == CallState.incomingRinging`.
class IncomingCallScreen extends StatelessWidget {
  const IncomingCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final callProvider = context.watch<CallProvider>();

    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.95),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),

            // Type d'appel
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                callProvider.callType == 'video' ? '📹 Appel Vidéo' : '📞 Appel Audio',
                style: const TextStyle(color: Colors.orange, fontSize: 14),
              ),
            ),
            const SizedBox(height: 30),

            // Avatar animé
            _AnimatedAvatar(),
            const SizedBox(height: 24),

            // Nom de l'appelant
            Text(
              callProvider.callerName ?? 'Opérateur',
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Centre d\'appel d\'urgence',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),

            const Spacer(),

            // Boutons Décrocher / Rejeter
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 50),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Rejeter
                  _CallActionButton(
                    icon: Icons.call_end,
                    color: Colors.red,
                    label: 'Rejeter',
                    onTap: () async {
                      await callProvider.rejectIncomingCall();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                  // Décrocher
                  _CallActionButton(
                    icon: Icons.call,
                    color: Colors.green,
                    label: 'Décrocher',
                    size: 80,
                    onTap: () async {
                      await callProvider.answerIncomingCall();
                      // Naviguer vers l'écran d'appel actif
                      if (context.mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const ActiveCallScreen()),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}

class _AnimatedAvatar extends StatefulWidget {
  @override
  State<_AnimatedAvatar> createState() => _AnimatedAvatarState();
}

class _AnimatedAvatarState extends State<_AnimatedAvatar> with TickerProviderStateMixin {
  late AnimationController _pingController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pingController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pingController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120, height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ping animation
          FadeTransition(
            opacity: Tween(begin: 0.6, end: 0.0).animate(_pingController),
            child: ScaleTransition(
              scale: Tween(begin: 0.8, end: 1.5).animate(_pingController),
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.green, width: 2),
                ),
              ),
            ),
          ),
          // Avatar
          ScaleTransition(
            scale: Tween(begin: 0.95, end: 1.05).animate(_pulseController),
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withOpacity(0.15),
                border: Border.all(color: Colors.green, width: 2),
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 40),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final double size;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon, required this.color, required this.label,
    required this.onTap, this.size = 65,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size, height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Icon(icon, color: Colors.white, size: size * 0.45),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}
```

#### 5c. Écran d'appel actif (`lib/screens/active_call_screen.dart`)

Même structure que le `SosCallScreen` en mode actif — réutiliser les contrôles. Ajouter le support vidéo avec les widgets Agora :

```dart
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/call_provider.dart';
import '../services/agora_service.dart';

class ActiveCallScreen extends StatelessWidget {
  const ActiveCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, callProvider, _) {
        if (callProvider.state == CallState.ended || callProvider.state == CallState.idle) {
          // Auto-pop quand l'appel se termine
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).pop();
          });
        }

        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                // Vidéo distante (plein écran)
                if (callProvider.isVideoEnabled && AgoraService.instance.engine != null)
                  AgoraVideoView(
                    controller: VideoViewController.remote(
                      rtcEngine: AgoraService.instance.engine!,
                      canvas: const VideoCanvas(uid: 0), // remote user
                      connection: RtcConnection(channelId: callProvider.currentChannelName),
                    ),
                  ),

                // Vidéo locale (PiP en haut à droite)
                if (callProvider.isVideoEnabled && AgoraService.instance.engine != null)
                  Positioned(
                    top: 20, right: 20,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 120, height: 160,
                        child: AgoraVideoView(
                          controller: VideoViewController(
                            rtcEngine: AgoraService.instance.engine!,
                            canvas: const VideoCanvas(uid: 0),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Overlay contrôles
                Column(
                  children: [
                    const Spacer(),
                    // Info
                    Text(
                      callProvider.callerName ?? 'En ligne',
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatDuration(callProvider.durationSeconds),
                      style: const TextStyle(color: Colors.white70, fontSize: 16, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 40),

                    // Contrôles
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CtrlBtn(
                          icon: callProvider.isMuted ? Icons.mic_off : Icons.mic,
                          active: callProvider.isMuted,
                          onTap: () => callProvider.toggleMute(),
                        ),
                        _CtrlBtn(
                          icon: callProvider.isSpeakerOn ? Icons.volume_up : Icons.volume_off,
                          active: callProvider.isSpeakerOn,
                          onTap: () => callProvider.toggleSpeaker(),
                        ),
                        _CtrlBtn(
                          icon: callProvider.isVideoEnabled ? Icons.videocam : Icons.videocam_off,
                          active: callProvider.isVideoEnabled,
                          onTap: () => callProvider.toggleVideo(),
                        ),
                        if (callProvider.isVideoEnabled)
                          _CtrlBtn(
                            icon: Icons.switch_camera,
                            active: false,
                            onTap: () => callProvider.switchCamera(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 30),

                    // Raccrocher
                    GestureDetector(
                      onTap: () => callProvider.hangUp(),
                      child: Container(
                        width: 70, height: 70,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red),
                        child: const Icon(Icons.call_end, color: Colors.white, size: 35),
                      ),
                    ),
                    const SizedBox(height: 50),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _CtrlBtn({required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52, height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? Colors.white : Colors.white.withOpacity(0.15),
        ),
        child: Icon(icon, color: active ? Colors.black : Colors.white, size: 26),
      ),
    );
  }
}
```

### Tâche 6 : Configuration `pubspec.yaml`

Ajouter ces dépendances :
```yaml
dependencies:
  agora_rtc_engine: ^6.3.0
  permission_handler: ^11.3.0
  geolocator: ^12.0.0
```

### Tâche 7 : Configuration native

#### Android (`android/app/src/main/AndroidManifest.xml`)
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

#### iOS (`ios/Runner/Info.plist`)
```xml
<key>NSCameraUsageDescription</key>
<string>Pour les appels vidéo d'urgence</string>
<key>NSMicrophoneUsageDescription</key>
<string>Pour les appels audio d'urgence</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Pour localiser votre position pendant un appel d'urgence</string>
```

### Tâche 8 : Initialisation dans `main.dart`

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://npucuhlvoalcbwdfedae.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5wdWN1aGx2b2FsY2J3ZGZlZGFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2NDQ3NzcsImV4cCI6MjA5MDIyMDc3N30.1XLmBbRpx3Q-raPvHDnLm3dLuQGRWFHaP-fXv9BbqQk',
  );

  // Initialiser Agora
  await AgoraService.instance.initialize();

  runApp(
    MultiProvider(
      providers: [
        // ... existing providers ...
        ChangeNotifierProvider(create: (_) => CallProvider()),
      ],
      child: const MyApp(),
    ),
  );
}
```

Dans le widget racine ou le home screen, après login :
```dart
// Quand l'utilisateur est connecté, démarrer l'écoute des appels entrants
final myProfile = await getMyUsersDirectoryProfile();
context.read<CallProvider>().startListeningForIncomingCalls(myProfile['id']);

// Observer l'état pour afficher l'overlay d'appel entrant
// Dans le build() du widget racine :
final callState = context.watch<CallProvider>().state;
if (callState == CallState.incomingRinging) {
  // Afficher IncomingCallScreen en overlay
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const IncomingCallScreen(),
  );
}
```

---

## Résumé du flux complet

```text
CITOYEN → CALL CENTER (appel SOS) :
┌─────────────┐     INSERT incident     ┌──────────────┐
│  App Mobile  │ ──────────────────────> │   Supabase   │
│  (Flutter)   │     status="new"        │  incidents   │
└──────┬──────┘                          └──────┬───────┘
       │                                        │ trigger on_incident_created
       │ join Agora channel                     ▼
       │ (channel = incident.reference)  ┌──────────────┐
       │                                 │  call_queue   │
       │                                 │ status=waiting│
       │                                 └──────┬───────┘
       │                                        │ auto_assign_queue()
       │                                        ▼
       │                                 ┌──────────────┐
       │     Realtime: status=assigned   │   Dashboard   │
       │ <────────────────────────────── │  (opérateur)  │
       │                                 └──────┬───────┘
       │                                        │ opérateur join Agora
       │     Agora: both in same channel        │
       │ <═══════════════════════════════════════╝
       │         AUDIO/VIDEO CONNECTED

CALL CENTER → CITOYEN (appel sortant) :
┌─────────────┐     INSERT call_history  ┌──────────────┐
│  Dashboard   │ ──────────────────────> │   Supabase   │
│  (opérateur) │  call_type="outgoing"   │ call_history  │
└──────┬──────┘  citizen_id=XYZ          └──────┬───────┘
       │  join Agora channel                    │
       │  (channel = call_history.channel_name) │ Realtime filter citizen_id
       │                                        ▼
       │                                 ┌──────────────┐
       │                                 │  App Mobile   │
       │     Agora: citoyen joins        │  (sonnerie)   │
       │ <═══════════════════════════════│  → décroche   │
       │         AUDIO/VIDEO CONNECTED   └──────────────┘
```

## Points critiques

1. **Le canal Agora = `incident.reference`** pour les appels SOS. Les deux côtés (mobile + dashboard) rejoignent le même canal.
2. **Pour les appels sortants du call center** : le canal Agora = `call_history.channel_name`.
3. **Realtime obligatoire** : l'app mobile doit écouter `call_history` filtré par `citizen_id` pour les appels entrants.
4. **Permissions** : demander micro + caméra AVANT de tenter de rejoindre un canal.
5. **Token Agora** : toujours généré via l'Edge Function `agora-token`, jamais en dur.
6. **GPS temps réel** : pendant un appel SOS, mettre à jour `incidents.caller_realtime_lat/lng` toutes les 5 secondes.
7. **Nettoyage** : quand l'appel se termine, mettre à jour `call_history.ended_at`, `call_history.status` et `incidents.status`.
8. **Le trigger `on_incident_created` gère automatiquement** la création de l'entrée `call_queue` et l'auto-assignation — ne pas dupliquer cette logique côté Flutter.

## Fichiers à créer

| Fichier | Description |
|---------|-------------|
| `lib/services/agora_service.dart` | Service singleton Agora RTC |
| `lib/services/sos_call_service.dart` | Logique appel SOS sortant |
| `lib/services/incoming_call_service.dart` | Écoute appels entrants |
| `lib/providers/call_provider.dart` | State management des appels |
| `lib/screens/sos_call_screen.dart` | UI appel SOS sortant |
| `lib/screens/incoming_call_screen.dart` | UI appel entrant (overlay) |
| `lib/screens/active_call_screen.dart` | UI appel actif avec vidéo |

## Fichiers à modifier

| Fichier | Modification |
|---------|-------------|
| `pubspec.yaml` | Ajouter `agora_rtc_engine`, `permission_handler`, `geolocator` |
| `android/app/src/main/AndroidManifest.xml` | Permissions caméra, micro, localisation |
| `ios/Runner/Info.plist` | Descriptions usage caméra, micro, localisation |
| `main.dart` | Initialiser `AgoraService`, ajouter `CallProvider` |
| Home screen | Démarrer l'écoute des appels entrants après login |
