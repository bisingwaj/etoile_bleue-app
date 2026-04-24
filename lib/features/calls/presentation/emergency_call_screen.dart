import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show ImageFilter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/transcription_provider.dart';
import 'package:etoile_bleue_mobile/core/services/emergency_call_service.dart';
import 'package:etoile_bleue_mobile/features/history/presentation/history_page.dart';
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
  RealtimeChannel? _dispatchChannel;

  // Recommendations from dispatcher (Realtime on incidents table)
  RealtimeChannel? _incidentChannel;
  String? _recommendedActions;
  String? _recommendedFacility;

  // Riverpod listenManual subscriptions (must be closed in dispose)
  ProviderSubscription? _statusSub;
  ProviderSubscription? _incidentIdSub;

  // Auto-hide controls
  bool _isControlsVisible = true;
  Timer? _interactionTimer;

  // PiP (Picture in Picture) position
  Offset _pipPosition = const Offset(16, 80);

  // Anti-spam des boutons (Debouncer)
  bool _isActionProcessing = false;

  void _executeWithDebounce(Future<void> Function() action) async {
    if (_isActionProcessing) return;
    setState(() => _isActionProcessing = true);
    try {
      await action();
    } finally {
      // 500ms de cooldown
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _isActionProcessing = false);
      });
    }
  }

  void _resetInteractionTimer() {
    setState(() => _isControlsVisible = true);
    _interactionTimer?.cancel();
    _interactionTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _isControlsVisible = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _resetInteractionTimer();

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
          final incidentId = ref.read(callStateProvider).incidentId;

          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) {
              ref.read(callHistoryProvider.notifier).refresh();
              
              if (incidentId != null) {
                context.go('/incident/$incidentId');
              } else {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/home');
                }
              }
            }
          });
        }

        if (next == ActiveCallStatus.blocked) {
          _stopTimer();
          _cancelConnectionIssueTimer();
          final callState = ref.read(callStateProvider);
          context.go('/blocked', extra: {
            'expires_at': callState.blockedExpiresAt,
            'reason': callState.blockedReason,
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
      }, fireImmediately: true);

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
            if (!mounted) return;
            // Status update received, but _trackingStep is currently unused in UI
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
    _interactionTimer?.cancel();
    super.dispose();
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callStateProvider);
    final hasReco = _recommendedActions != null || _recommendedFacility != null;
    final isCallLive = callState.status == ActiveCallStatus.active ||
        callState.status == ActiveCallStatus.onHold;

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
      child: Listener(
        onPointerDown: (_) => _resetInteractionTimer(),
        behavior: HitTestBehavior.translucent,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: callState.isVideoOn
                ? _buildVideoLayout(callState, hasReco, isCallLive)
                : _buildAudioLayout(callState, hasReco, isCallLive),
          ),
        ),
      ),
    );
  }

  /// Full-screen video layout: video has the highest z-index and is fully
  /// interactive. Only the header and bottom controls float on top.
  Widget _buildVideoLayout(ActiveCallState callState, bool hasReco, bool isCallLive) {
    return Stack(
      children: [
        // 1. Video grid fills the entire screen — highest visual priority
        Positioned.fill(
          child: _buildVideoGrid(callState),
        ),

        // 2. Header floating on top of video
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !_isControlsVisible,
            child: AnimatedOpacity(
              opacity: _isControlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _buildHeader(callState),
              ),
            ),
          ),
        ),

        // 3. Bottom controls floating on top of video
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !_isControlsVisible,
            child: AnimatedOpacity(
              opacity: _isControlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: _buildBottomControls(callState),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Audio layout: visualizer in background, cards/triage in the middle,
  /// controls at the bottom.
  Widget _buildAudioLayout(ActiveCallState callState, bool hasReco, bool isCallLive) {
    return Stack(
      children: [
        // Background audio visualizer
        Positioned.fill(
          child: _buildAudioVisualizer(callState),
        ),

        // Foreground layout
        Column(
          children: [
            // Top header (status + minimize)
            IgnorePointer(
              ignoring: !_isControlsVisible,
              child: AnimatedOpacity(
                opacity: _isControlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _buildHeader(callState),
                ),
              ),
            ),

            // Scrollable middle space for dynamic banners
            Expanded(
              child: IgnorePointer(
                ignoring: !_isControlsVisible,
                child: AnimatedOpacity(
                  opacity: _isControlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    children: [
                      if (!callState.isCentraleCall) ...[
                        _buildEmergencyActionButtons(callState),
                        if (hasReco || (callState.channelName != null && isCallLive) || _showConnectionIssue)
                          const SizedBox(height: 16),
                      ],
                      if (hasReco) ...[
                        _buildRecommendationsBanner(),
                        if ((callState.channelName != null && isCallLive) || _showConnectionIssue)
                          const SizedBox(height: 16),
                      ],
                      if (callState.channelName != null && isCallLive) ...[
                        _buildTranscriptionPanel(callState.channelName!),
                        if (_showConnectionIssue) const SizedBox(height: 16),
                      ],
                      if (_showConnectionIssue) _buildConnectionIssueBanner(),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom triage panel
            if ((isCallLive || callState.status == ActiveCallStatus.ringing) && 
                _isControlsVisible && 
                !callState.isCentraleCall)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: const EmergencyTriagePanel(),
              ),

            // Bottom controls
            IgnorePointer(
              ignoring: !_isControlsVisible,
              child: AnimatedOpacity(
                opacity: _isControlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: _buildBottomControls(callState),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }



  // ─── Actions Secours (SMS / 199) ───────────────────────────────────────────

  Widget _buildEmergencyActionButtons(ActiveCallState callState) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _executeWithDebounce(() async {
              HapticFeedback.mediumImpact();
              // Raccrocher l'appel numérique avant de lancer le SMS GSM
              await ref.read(callStateProvider.notifier).hangUp();
              final uri = Uri.parse('sms:199?body=${Uri.encodeComponent('calls.sms_body'.tr())}');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.chat_bubble_text_fill, color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Text('calls.sms_rescue'.tr(), style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => _executeWithDebounce(() async {
              HapticFeedback.heavyImpact();
              // Raccrocher l'appel numérique avant de lancer l'appel GSM
              await ref.read(callStateProvider.notifier).hangUp();
              final uri = Uri.parse('tel:199');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.phone_fill, color: Colors.red, size: 18),
                  SizedBox(width: 8),
                  Text('calls.call_rescue'.tr(), style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
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
          Expanded(
            child: Text(
              'calls.connection_issue'.tr(),
              style: TextStyle(
                color: Colors.orange,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _executeWithDebounce(() async {
              // Raccrocher l'appel numérique avant de lancer l'appel GSM
              await ref.read(callStateProvider.notifier).hangUp();
              final uri = Uri.parse('tel:199');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'calls.call_199'.tr(),
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
          _FrostedGlass(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            backgroundColor: Colors.black26,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Text('calls.recommended_actions'.tr(), style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(_recommendedActions!, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        if (_recommendedFacility != null)
          _FrostedGlass(
            padding: const EdgeInsets.all(14),
            backgroundColor: Colors.black26,
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
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 120),
          child: _FrostedGlass(
            padding: const EdgeInsets.all(12),
            backgroundColor: Colors.black26,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Row(
                children: [
                  Icon(CupertinoIcons.waveform, color: Colors.cyan.withValues(alpha: 0.8), size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'calls.live_transcription'.tr(),
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
                  '${e.speaker == 'operator' ? 'calls.operator'.tr() : 'calls.you'.tr()}: ${e.content}',
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
        ));
      },
      loading: () => const SizedBox.shrink(),
      error: (err, stack) => const SizedBox.shrink(),
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
                  'calls.waiting_rescuer'.tr(),
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        if (callState.remoteUid != null)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 100),
            left: _pipPosition.dx,
            top: _pipPosition.dy,
            child: AnimatedOpacity(
              opacity: _isControlsVisible ? 1.0 : 0.4, // Semi-transparent si inactif
              duration: const Duration(milliseconds: 300),
              child: GestureDetector(
                onPanUpdate: (details) {
                  _resetInteractionTimer();
                  setState(() {
                    _pipPosition += details.delta;
                    // Clamp pour ne pas sortir de l'écran
                    final size = MediaQuery.of(context).size;
                    _pipPosition = Offset(
                      _pipPosition.dx.clamp(16.0, size.width - 116.0),
                      _pipPosition.dy.clamp(60.0, size.height - 180.0),
                    );
                  });
                },
                onTap: () {
                  _resetInteractionTimer();
                  _executeWithDebounce(() => ref.read(callStateProvider.notifier).switchCamera());
                },
                child: Container(
                  width: 100,
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16), // Arrondis plus doux
                    border: Border.all(color: Colors.white24),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: 2),
                    ],
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
                        bottom: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(6),
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
          ),
      ],
    );
  }

// ─── Audio visualizer avec ondes ──────────────────────────────────────────────

  Widget _buildAudioVisualizer(ActiveCallState callState) {
    String label;
    switch (callState.status) {
      case ActiveCallStatus.active:
        label = 'calls.emergency_call_active'.tr();
        break;
      case ActiveCallStatus.ended:
        label = 'calls.call_ended'.tr();
        break;
      case ActiveCallStatus.onHold:
        label = 'calls.waiting'.tr();
        break;
      default:
        label = 'calls.call_in_progress'.tr();
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingAvatar(),
          const SizedBox(height: 32),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(ActiveCallState callState) {
    final statusInfo = _statusInfo(callState.status);

    return Row(
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
    );
  }

  ({String label, Color color}) _statusInfo(ActiveCallStatus status) {
    switch (status) {
      case ActiveCallStatus.connecting:
        return (label: 'calls.connecting'.tr(), color: Colors.orange);
      case ActiveCallStatus.ringing:
        return (label: 'calls.ringing'.tr(), color: Colors.orange);
      case ActiveCallStatus.active:
        return (label: '${'calls.connected'.tr()} · $_elapsed', color: Colors.green);
      case ActiveCallStatus.onHold:
        return (label: 'calls.waiting'.tr(), color: Colors.amber);
      case ActiveCallStatus.ended:
        return (label: 'calls.call_ended'.tr(), color: Colors.red);
      default:
        return (label: 'calls.connecting'.tr(), color: Colors.orange);
    }
  }

  // ─── Bottom controls ────────────────────────────────────────────────────────

  Widget _buildBottomControls(ActiveCallState callState) {
    final notifier = ref.read(callStateProvider.notifier);
    final showCameraFlip = callState.isVideoOn;

    return _FrostedGlass(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      borderRadius: BorderRadius.circular(32),
      backgroundColor: Colors.black26,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildControlButton(
            icon: callState.isMuted
                ? CupertinoIcons.mic_slash_fill
                : CupertinoIcons.mic_fill,
            isActive: !callState.isMuted,
            onTap: () => _executeWithDebounce(() => notifier.toggleMute()),
          ),
          _buildControlButton(
            icon: callState.isVideoOn
                ? CupertinoIcons.video_camera_solid
                : CupertinoIcons.video_camera,
            isActive: callState.isVideoOn,
            onTap: () => _executeWithDebounce(() => notifier.toggleVideo()),
          ),
          if (showCameraFlip)
            _buildControlButton(
              icon: CupertinoIcons.camera_rotate,
              isActive: true,
              onTap: () => _executeWithDebounce(() => notifier.switchCamera()),
            ),
          _buildControlButton(
            icon: callState.isSpeakerOn
                ? CupertinoIcons.speaker_3_fill
                : CupertinoIcons.speaker_1_fill,
            isActive: callState.isSpeakerOn,
            onTap: () => _executeWithDebounce(() => notifier.toggleSpeaker()),
          ),
          _buildControlButton(
            icon: CupertinoIcons.phone_down_fill,
            isActive: true,
            color: Colors.red,
            onTap: () => _executeWithDebounce(() => notifier.hangUp()),
          ),
        ],
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

// ─── Composant Verre Dépoli (Frosted Glass) ───────────────────────────────────

class _FrostedGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color backgroundColor;

  const _FrostedGlass({
    required this.child,
    this.borderRadius,
    this.padding,
    this.margin,
    this.backgroundColor = Colors.black12,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ?? BorderRadius.circular(16);
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: effectiveRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: effectiveRadius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ─── Widget de point pulsant pour l'étape active de la timeline ─────────────

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale   = Tween(begin: 0.85, end: 1.15).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _opacity = Tween(begin: 0.6,  end: 1.0 ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: FadeTransition(
        opacity: _opacity,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.greenAccent,
            boxShadow: [
              BoxShadow(
                color: Colors.greenAccent.withValues(alpha: 0.6),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Visualiseur Audio Pulsant ──────────────────────────────────────────────

class _PulsingAvatar extends StatefulWidget {
  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _anim = Tween(begin: 1.0, end: 1.4).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ScaleTransition(
          scale: _anim,
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.6, end: 0.0).animate(_ctrl),
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.redAccent.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.redAccent.withValues(alpha: 0.2),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.8), width: 2),
            boxShadow: [
              BoxShadow(color: Colors.redAccent.withValues(alpha: 0.4), blurRadius: 20),
            ],
          ),
          child: const Icon(CupertinoIcons.phone_fill, color: Colors.white, size: 36),
        ),
      ],
    );
  }
}

