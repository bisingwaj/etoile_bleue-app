import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etoile_bleue_mobile/features/calls/domain/entities/call_session.dart';
import 'package:etoile_bleue_mobile/features/calls/domain/repositories/call_repository.dart';
import 'package:etoile_bleue_mobile/features/calls/data/repositories/call_repository_impl.dart';
import 'package:etoile_bleue_mobile/core/network/agora_client.dart';
import 'package:etoile_bleue_mobile/core/services/call_foreground_service.dart';
import 'package:flutter/foundation.dart';

// --- Provider pour la qualité réseau en direct ---
final networkQualityProvider = StateProvider<int>((ref) => 0); // 0=Inconnu, 1=Excellent, 6=Dgradé

// --- Injection des Dépendances ---

/// Fournit l'instance unique du client de bas niveau
final agoraClientProvider = Provider<AgoraClient>((ref) {
  final client = AgoraClient();
  // Destruction finale : ferme aussi le StreamController
  ref.onDispose(() => client.closeStreamController());
  return client;
});

/// Fournit le Repository
final callRepositoryProvider = Provider<CallRepository>((ref) {
  final client = ref.watch(agoraClientProvider);
  return CallRepositoryImpl(client);
});

// --- State Management ---

/// Provider principal qui expose l'état complexe de l'appel
final callSessionProvider = StateNotifierProvider<CallSessionNotifier, CallSession>((ref) {
  final repository = ref.watch(callRepositoryProvider);
  return CallSessionNotifier(repository, ref);
});

class CallSessionNotifier extends StateNotifier<CallSession> {
  final CallRepository _repository;
  final Ref _ref;
  StreamSubscription? _eventsSubscription;
  bool _disposed = false;

  CallSessionNotifier(this._repository, this._ref) 
    : super(CallSession.initial(channelId: '', role: 'Unknown'));

  /// Lancement de l'appel (Processus complexe : permissions -> token -> join)
  Future<void> startCall({
    required String channelId,
    required String role,
    required String uid,
  }) async {
    // ✅ Correctif #5 : guard anti-double appel
    if (state.status == CallStatus.connecting ||
        state.status == CallStatus.ringing ||
        state.status == CallStatus.active) {
      return;
    }

    state = state.copyWith(
      channelId: channelId,
      role: role,
      status: CallStatus.connecting,
      errorMessage: null,
    );

    _listenToAgoraEvents();

    try {
      await _repository.joinCall(channelId: channelId, role: role, uid: uid);
      state = state.copyWith(status: CallStatus.ringing);
      // ✅ Démarrer le Foreground Service Android (maintient l'audio en background)
      await CallForegroundService.start(channelId: channelId, role: role);
    } catch (e) {
      debugPrint('CallSessionNotifier: Error starting call: $e');
      // ✅ Correctif #6 : annuler la subscription en cas d'erreur
      _eventsSubscription?.cancel();
      if (e.toString().contains('PERMISSIONS_DENIED')) {
        state = state.copyWith(
          status: CallStatus.error,
          errorMessage: 'errors.mic_permission'.tr(),
        );
      } else if (e.toString().contains('CALL_ALREADY_IN_PROGRESS')) {
        // Double appel ignoré silencieusement — ne pas changer l'état
      } else {
        state = state.copyWith(
          status: CallStatus.error,
          errorMessage: 'errors.channel_join_failed'.tr(),
        );
      }
    }
  }

  /// Écoute réactive des événements bas-niveau
  void _listenToAgoraEvents() {
    _eventsSubscription?.cancel();
    _eventsSubscription = _repository.agoraEventsStream.listen((event) {
      final type = event['type'];

      switch (type) {
        case 'onJoinChannelSuccess':
          state = state.copyWith(
            localUid: event['uid'] as int,
            status: CallStatus.ringing,
          );
          break;

        case 'onUserJoined':
          state = state.copyWith(
            remoteUid: event['remoteUid'] as int,
            status: CallStatus.active,
          );
          break;

        case 'onUserOffline':
          state = state.copyWith(
            remoteUid: null,
            status: CallStatus.ringing, // Repasse en attente si l'autre quitte
          );
          break;

        case 'onConnectionStateChanged':
          final connectionState = event['state'] as ConnectionStateType;
          if (connectionState == ConnectionStateType.connectionStateReconnecting) {
            state = state.copyWith(status: CallStatus.reconnecting);
          } else if (connectionState == ConnectionStateType.connectionStateConnected) {
            // Rétablir le statut selon si qqn est là ou non
            state = state.copyWith(status: state.remoteUid != null ? CallStatus.active : CallStatus.ringing);
          } else if (connectionState == ConnectionStateType.connectionStateFailed) {
            state = state.copyWith(status: CallStatus.error, errorMessage: 'errors.network_lost'.tr());
          }
          break;

        case 'onError':
          // Traitement des codes d'erreur bruts
          state = state.copyWith(
            status: CallStatus.error,
            errorMessage: '${'errors.technical_error'.tr()} (${event['code']}): ${event['msg']}',
          );
          break;

        // ─── TÉLÉMETRIE RÉSEAU (Latence Afrique) ────────────────────────────
        case 'onNetworkQuality':
          // txQuality: 1=Excellent, 2=Good, 3=Poor, 4=Bad, 5=VeryBad, 6=Down
          final txQ = event['txQuality'] as int? ?? 0;
          final rxQ = event['rxQuality'] as int? ?? 0;
          // on prend le pire des deux (max) sauf si 0 (unknown)
          int worstQ = (txQ > rxQ) ? txQ : rxQ;
          if (worstQ == 0) worstQ = txQ == 0 ? rxQ : txQ;
          
          _ref.read(networkQualityProvider.notifier).state = worstQ;
          debugPrint('[Network] Quality tx=$txQ rx=$rxQ -> final=$worstQ');
          break;

        case 'onRtcStats':
          final rtt = event['rtt'] as int? ?? 0;
          final txLoss = event['txPacketLossRate'] as int? ?? 0;
          final rxLoss = event['rxPacketLossRate'] as int? ?? 0;
          debugPrint('[Network] RTT=${rtt}ms | TX-Loss=$txLoss% | RX-Loss=$rxLoss%');
          // Si perte de paquets critique (>15%), on signale dans l'UI
          if (txLoss > 15 || rxLoss > 15) {
            debugPrint('[Network] ⚠️ Mauvaise connexion détectée — FEC actif');
          }
          break;
      }
    });
  }

  Future<void> endCall() async {
    // ✅ Arrêter le Foreground Service Android
    await CallForegroundService.stop();
    // ✅ Correctif #3 : silencieux si jamais connecté
    try {
      if (state.status != CallStatus.error || state.localUid != null) {
        await _repository.leaveCall();
      }
    } catch (_) {}
    _eventsSubscription?.cancel();
    state = state.copyWith(status: CallStatus.ended);
    await Future.delayed(const Duration(seconds: 2));
    if (!_disposed) {
      state = CallSession.initial(channelId: '', role: 'Unknown');
    }
  }

  Future<void> toggleAudio([bool? forceState]) async {
    final newState = forceState ?? !state.isAudioEnabled;
    await _repository.toggleAudio(newState);
    state = state.copyWith(isAudioEnabled: newState);
  }

  Future<void> toggleSpeaker([bool? forceState]) async {
    final newState = forceState ?? !state.isSpeakerEnabled;
    await _repository.toggleSpeaker(newState);
    state = state.copyWith(isSpeakerEnabled: newState);
  }

  Future<void> toggleVideo([bool? forceState]) async {
    final newState = forceState ?? !state.isVideoEnabled;
    await _repository.toggleVideo(newState);
    state = state.copyWith(isVideoEnabled: newState);
  }

  Future<void> switchCamera() async {
    // ✅ Correctif #9 : guard — pas de switch si l'appel n'est pas actif
    if (state.status != CallStatus.active && state.status != CallStatus.ringing) return;
    await _repository.switchCamera();
    state = state.copyWith(isFrontCamera: !state.isFrontCamera);
  }

  @override
  void dispose() {
    _disposed = true;
    _eventsSubscription?.cancel();
    super.dispose();
  }
}
