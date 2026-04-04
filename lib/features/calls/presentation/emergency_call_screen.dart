import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/transcription_provider.dart';
import 'package:etoile_bleue_mobile/core/services/emergency_call_service.dart';
import 'widgets/emergency_triage_panel.dart';

// ─── Incident tracking ────────────────────────────────────────────────────────

enum IncidentTrackingStep { processing, dispatched, enRoute, arrived, completed }

class EmergencyCallScreen extends ConsumerStatefulWidget {
  const EmergencyCallScreen({super.key});

  @override
  ConsumerState<EmergencyCallScreen> createState() => _EmergencyCallScreenState();
}

class _EmergencyCallScreenState extends ConsumerState<EmergencyCallScreen> {
  final Stopwatch _callTimer = Stopwatch();
  Timer? _timerTick;
  String _elapsed = '00:00';

  // Connection-problem fallback
  bool _showConnectionIssue = false;
  Timer? _connectionIssueTimer;

  // Incident tracking
  IncidentTrackingStep _trackingStep = IncidentTrackingStep.processing;
  RealtimeChannel? _dispatchChannel;

  // Recommendations from dispatcher (Realtime on incidents table)
  RealtimeChannel? _incidentChannel;
  String? _recommendedActions;
  String? _recommendedFacility;

  // Riverpod listenManual subscriptions (must be closed in dispose)
  ProviderSubscription? _statusSub;
  ProviderSubscription? _incidentIdSub;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // S'assurer que l'île dynamique n'est pas affichée quand on est sur l'écran d'appel
      ref.read(isCallMinimizedProvider.notifier).state = false;

      _statusSub = ref.listenManual(callStateProvider.select((s) => s.status), (prev, next) {
        if (next == ActiveCallStatus.active && prev != ActiveCallStatus.active) {
          _startTimer();
          _cancelConnectionIssueTimer();
        }

        if (next == ActiveCallStatus.ended) {
          _stopTimer();
          _cancelConnectionIssueTimer();
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            }
          });
        }

        if (next == ActiveCallStatus.onHold) {
          _stopTimer();
          _startConnectionIssueTimer();
        }

        if (next == ActiveCallStatus.active && prev == ActiveCallStatus.onHold) {
          _startTimer();
          _cancelConnectionIssueTimer();
        }

        // Show connection issue if stuck on connecting for too long
        if (next == ActiveCallStatus.connecting) {
          _startConnectionIssueTimer();
        }
      });

      // Subscribe to incident tracking + recommendations once we have an incidentId
      _incidentIdSub = ref.listenManual(callStateProvider.select((s) => s.incidentId), (prev, next) {
        if (next != null && next != prev) {
          _subscribeToIncidentTracking(next);
          _listenToIncidentRecommendations(next);
        }
      });

      // Check if incidentId already available on mount
      final incidentId = ref.read(callStateProvider).incidentId;
      if (incidentId != null) {
        _subscribeToIncidentTracking(incidentId);
        _listenToIncidentRecommendations(incidentId);
      }
    });
  }

  // ─── Connection issue timer ─────────────────────────────────────────────────

  void _startConnectionIssueTimer() {
    _connectionIssueTimer?.cancel();
    _connectionIssueTimer = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _showConnectionIssue = true);
    });
  }

  void _cancelConnectionIssueTimer() {
    _connectionIssueTimer?.cancel();
    _connectionIssueTimer = null;
    if (mounted) setState(() => _showConnectionIssue = false);
  }

  // ─── Incident tracking subscription ────────────────────────────────────────

  void _subscribeToIncidentTracking(String incidentId) {
    _dispatchChannel?.unsubscribe();
    _dispatchChannel = Supabase.instance.client
        .channel('dispatches-$incidentId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'dispatches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'incident_id',
            value: incidentId,
          ),
          callback: (payload) {
            final dispatch = payload.newRecord;
            final status = dispatch['status'] as String?;
            if (!mounted) return;
            setState(() {
              if (status == 'dispatched') {
                _trackingStep = IncidentTrackingStep.dispatched;
              } else if (status == 'en_route') {
                _trackingStep = IncidentTrackingStep.enRoute;
              } else if (status == 'arrived') {
                _trackingStep = IncidentTrackingStep.arrived;
              } else if (status == 'completed') {
                _trackingStep = IncidentTrackingStep.completed;
              }
            });
          },
        )
        .subscribe();
  }

  // ─── Incident recommendations subscription (Realtime on incidents) ─────────

  void _listenToIncidentRecommendations(String incidentId) {
    _incidentChannel?.unsubscribe();
    _incidentChannel = Supabase.instance.client
        .channel('incident-reco-$incidentId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'incidents',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: incidentId,
          ),
          callback: (payload) {
            if (!mounted) return;
            final record = payload.newRecord;
            setState(() {
              final actions = record['recommended_actions'];
              final facility = record['recommended_facility'];
              _recommendedActions = (actions != null && actions.toString().isNotEmpty) ? actions.toString() : null;
              _recommendedFacility = (facility != null && facility.toString().isNotEmpty) ? facility.toString() : null;
            });
          },
        )
        .subscribe();
  }

  // ─── Timer helpers ──────────────────────────────────────────────────────────

  void _startTimer() {
    _callTimer.start();
    _timerTick?.cancel();
    _timerTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final secs = _callTimer.elapsed.inSeconds;
      setState(() {
        _elapsed =
            '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';
      });
    });
  }

  void _stopTimer() {
    _callTimer.stop();
    _timerTick?.cancel();
  }

  @override
  void dispose() {
    _statusSub?.close();
    _incidentIdSub?.close();
    _timerTick?.cancel();
    _callTimer.stop();
    _connectionIssueTimer?.cancel();
    _dispatchChannel?.unsubscribe();
    _incidentChannel?.unsubscribe();
    super.dispose();
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callStateProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        ref.read(isCallMinimizedProvider.notifier).state = true;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/home');
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // Background
              if (callState.isVideoOn)
                _buildVideoGrid(callState)
              else
                _buildAudioVisualizer(callState),

              // Top header (status + minimize)
              _buildHeader(callState),

              // Incident progress bar (just below header)
              Positioned(
                top: 70,
                left: 16,
                right: 16,
                child: _buildIncidentProgress(callState),
              ),

              // Triage panel & Secours
              if (callState.status == ActiveCallStatus.active ||
                  callState.status == ActiveCallStatus.ringing ||
                  callState.status == ActiveCallStatus.onHold)
                const Positioned(
                  left: 16,
                  right: 16,
                  bottom: 120,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      EmergencyTriagePanel(),
                    ],
                  ),
                ),

              // Boutons de secours (SMS/Appel normal)
              Positioned(
                left: 16,
                right: 16,
                top: 210, // Juste sous la barre de progression
                child: _buildEmergencyActionButtons(callState),
              ),

              // Recommendations from dispatcher (Realtime)
              if (_recommendedActions != null || _recommendedFacility != null)
                Positioned(
                  left: 16,
                  right: 16,
                  top: 310,
                  child: _buildRecommendationsBanner(),
                ),

              // Live transcription from dashboard
              if (callState.channelName != null &&
                  (callState.status == ActiveCallStatus.active || callState.status == ActiveCallStatus.onHold))
                Positioned(
                  left: 16,
                  right: 16,
                  top: (_recommendedActions != null || _recommendedFacility != null) ? 440 : 310,
                  child: _buildTranscriptionPanel(callState.channelName!),
                ),

              // Connection problem fallback
              if (_showConnectionIssue)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 200,
                  child: _buildConnectionIssueBanner(),
                ),

              // Bottom controls
              _buildBottomControls(callState),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Incident progress ──────────────────────────────────────────────────────

  Widget _buildIncidentProgress(ActiveCallState callState) {
    final incidentId = callState.incidentId;
    final steps = [
      IncidentTrackingStep.processing,
      IncidentTrackingStep.dispatched,
      IncidentTrackingStep.enRoute,
      IncidentTrackingStep.arrived,
      IncidentTrackingStep.completed,
    ];
    final labels = ['Traitement', 'Assigné', 'En route', 'Sur place', 'Terminé'];
    final currentIdx = steps.indexOf(_trackingStep);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 15,
            spreadRadius: 2,
          )
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Statut de l\'intervention',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (incidentId != null)
                GestureDetector(
                  onTap: () => context.push('/incident/$incidentId'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.doc_plaintext, color: Colors.white, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'Détails incident',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(steps.length, (i) {
              final isActive = i <= currentIdx;
              final isLast = i == steps.length - 1;
              return Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isActive ? Colors.greenAccent : Colors.transparent,
                              border: Border.all(
                                color: isActive ? Colors.greenAccent : Colors.white38,
                                width: 2,
                              ),
                              boxShadow: isActive
                                  ? [
                                      BoxShadow(
                                        color: Colors.greenAccent.withValues(alpha: 0.5),
                                        blurRadius: 6,
                                      )
                                    ]
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            labels[i],
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.white38,
                              fontSize: 10,
                              fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: i < currentIdx ? Colors.greenAccent : Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ─── Actions Secours (SMS / 151) ───────────────────────────────────────────

  Widget _buildEmergencyActionButtons(ActiveCallState callState) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () async {
              HapticFeedback.mediumImpact();
              // L'URI complète dépendrait de la localisation. Exemple basique:
              final uri = Uri.parse('sms:112?body=${Uri.encodeComponent("Urgence Etoile Bleue en cours.")}');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.chat_bubble_text_fill, color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Text('SMS Secours', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () async {
              HapticFeedback.heavyImpact();
              final uri = Uri.parse('tel:112');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.phone_fill, color: Colors.red, size: 18),
                  SizedBox(width: 8),
                  Text('Appel Secours', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Connection issue banner ─────────────────────────────────────────────────

  Widget _buildConnectionIssueBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Problème de connexion',
              style: TextStyle(
                color: Colors.orange,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: () async {
              final uri = Uri.parse('tel:151');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Appeler le 151',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Recommendations banner ─────────────────────────────────────────────────

  Widget _buildRecommendationsBanner() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_recommendedActions != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Text('Actions recommandées', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(_recommendedActions!, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        if (_recommendedFacility != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(CupertinoIcons.building_2_fill, color: Colors.blue, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _recommendedFacility!,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ─── Transcription panel ────────────────────────────────────────────────────

  Widget _buildTranscriptionPanel(String channelName) {
    final transcriptions = ref.watch(transcriptionProvider(channelName));

    return transcriptions.when(
      data: (entries) {
        if (entries.isEmpty) return const SizedBox.shrink();
        final latest = entries.length > 3 ? entries.sublist(entries.length - 3) : entries;
        return Container(
          constraints: const BoxConstraints(maxHeight: 120),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(CupertinoIcons.waveform, color: Colors.cyan.withValues(alpha: 0.8), size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Transcription en direct',
                    style: TextStyle(
                      color: Colors.cyan.withValues(alpha: 0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...latest.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${e.speaker == 'operator' ? 'Opérateur' : 'Vous'}: ${e.content}',
                  style: TextStyle(
                    color: e.speaker == 'operator' ? Colors.white70 : Colors.greenAccent.withValues(alpha: 0.8),
                    fontSize: 12,
                    fontStyle: e.isFinal ? FontStyle.normal : FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              )),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  // ─── Video grid ─────────────────────────────────────────────────────────────

  Widget _buildVideoGrid(ActiveCallState callState) {
    final rtcEngine = ref.read(emergencyCallServiceProvider).engine;
    if (rtcEngine == null) return _buildAudioVisualizer(callState);

    return Stack(
      children: [
        if (callState.remoteUid != null)
          AgoraVideoView(
            controller: VideoViewController.remote(
              rtcEngine: rtcEngine,
              canvas: VideoCanvas(uid: callState.remoteUid!),
              connection: RtcConnection(channelId: callState.channelName),
            ),
          )
        else
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.redAccent),
                const SizedBox(height: 16),
                Text(
                  'En attente du secouriste...',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        if (callState.remoteUid != null)
          Positioned(
            right: 16,
            top: 80,
            child: GestureDetector(
              onTap: () => ref.read(callStateProvider.notifier).switchCamera(),
              child: Container(
                width: 100,
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: rtcEngine,
                        canvas: const VideoCanvas(uid: 0),
                      ),
                    ),
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          CupertinoIcons.camera_rotate,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Audio visualizer ───────────────────────────────────────────────────────

  Widget _buildAudioVisualizer(ActiveCallState callState) {
    String label;
    switch (callState.status) {
      case ActiveCallStatus.active:
        label = 'Appel d\'urgence Actif';
        break;
      case ActiveCallStatus.ended:
        label = 'Appel terminé';
        break;
      case ActiveCallStatus.onHold:
        label = 'En attente...';
        break;
      default:
        label = 'Appel en cours...';
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              CupertinoIcons.phone_fill,
              size: 64,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(ActiveCallState callState) {
    final statusInfo = _statusInfo(callState.status);

    return Positioned(
      top: 16,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () {
              ref.read(isCallMinimizedProvider.notifier).state = true;
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(CupertinoIcons.chevron_down, color: Colors.white),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.circle_fill,
                  color: statusInfo.color,
                  size: 10,
                ),
                const SizedBox(width: 8),
                Text(
                  statusInfo.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.wifi,
              color: callState.status == ActiveCallStatus.active
                  ? Colors.green
                  : Colors.grey,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  ({String label, Color color}) _statusInfo(ActiveCallStatus status) {
    switch (status) {
      case ActiveCallStatus.connecting:
        return (label: 'Connexion...', color: Colors.orange);
      case ActiveCallStatus.ringing:
        return (label: 'Sonnerie...', color: Colors.orange);
      case ActiveCallStatus.active:
        return (label: 'Connecté · $_elapsed', color: Colors.green);
      case ActiveCallStatus.onHold:
        return (label: 'En attente', color: Colors.amber);
      case ActiveCallStatus.ended:
        return (label: 'Appel terminé', color: Colors.red);
      default:
        return (label: 'Connexion...', color: Colors.orange);
    }
  }

  // ─── Bottom controls ────────────────────────────────────────────────────────

  Widget _buildBottomControls(ActiveCallState callState) {
    final notifier = ref.read(callStateProvider.notifier);
    final showCameraFlip = callState.isVideoOn;

    return Positioned(
      bottom: 24,
      left: 24,
      right: 24,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildControlButton(
              icon: callState.isMuted
                  ? CupertinoIcons.mic_slash_fill
                  : CupertinoIcons.mic_fill,
              isActive: !callState.isMuted,
              onTap: () => notifier.toggleMute(),
            ),
            _buildControlButton(
              icon: callState.isVideoOn
                  ? CupertinoIcons.video_camera_solid
                  : CupertinoIcons.video_camera,
              isActive: callState.isVideoOn,
              onTap: () => notifier.toggleVideo(),
            ),
            if (showCameraFlip)
              _buildControlButton(
                icon: CupertinoIcons.camera_rotate,
                isActive: true,
                onTap: () => notifier.switchCamera(),
              ),
            _buildControlButton(
              icon: callState.isSpeakerOn
                  ? CupertinoIcons.speaker_3_fill
                  : CupertinoIcons.speaker_1_fill,
              isActive: callState.isSpeakerOn,
              onTap: () => notifier.toggleSpeaker(),
            ),
            _buildControlButton(
              icon: CupertinoIcons.phone_down_fill,
              isActive: true,
              color: Colors.red,
              onTap: () async {
                await notifier.hangUp();
                if (mounted) context.pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color ?? (isActive ? Colors.white : Colors.white24),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: color != null ? Colors.white : (isActive ? Colors.black : Colors.white),
          size: 24,
        ),
      ),
    );
  }
}
