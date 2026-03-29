import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:go_router/go_router.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/core/services/emergency_call_service.dart';
import 'widgets/emergency_triage_panel.dart';

class EmergencyCallScreen extends ConsumerStatefulWidget {
  const EmergencyCallScreen({super.key});

  @override
  ConsumerState<EmergencyCallScreen> createState() => _EmergencyCallScreenState();
}

class _EmergencyCallScreenState extends ConsumerState<EmergencyCallScreen> {
  final Stopwatch _callTimer = Stopwatch();
  Timer? _timerTick;
  String _elapsed = '00:00';

  @override
  void initState() {
    super.initState();

    // Auto-pop when call ends, and manage call timer
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listenManual(callStateProvider.select((s) => s.status), (prev, next) {
        if (next == ActiveCallStatus.active && prev != ActiveCallStatus.active) {
          _startTimer();
        }

        if (next == ActiveCallStatus.ended) {
          _stopTimer();
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) context.pop();
          });
        }

        if (next == ActiveCallStatus.onHold) {
          _stopTimer();
        }

        if (next == ActiveCallStatus.active && prev == ActiveCallStatus.onHold) {
          _startTimer();
        }
      });
    });
  }

  void _startTimer() {
    _callTimer.start();
    _timerTick?.cancel();
    _timerTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final secs = _callTimer.elapsed.inSeconds;
      setState(() {
        _elapsed = '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';
      });
    });
  }

  void _stopTimer() {
    _callTimer.stop();
    _timerTick?.cancel();
  }

  @override
  void dispose() {
    _timerTick?.cancel();
    _callTimer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callStateProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        ref.read(isCallMinimizedProvider.notifier).state = true;
        context.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              if (callState.isVideoOn)
                _buildVideoGrid(callState)
              else
                _buildAudioVisualizer(callState),

              _buildHeader(callState),

              if (callState.status == ActiveCallStatus.active ||
                  callState.status == ActiveCallStatus.ringing ||
                  callState.status == ActiveCallStatus.onHold)
                const Positioned(
                  left: 16,
                  right: 16,
                  bottom: 120,
                  child: EmergencyTriagePanel(),
                ),

              _buildBottomControls(callState),
            ],
          ),
        ),
      ),
    );
  }

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
                   Text('En attente du secouriste...', style: TextStyle(color: Colors.white70)),
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
                         child: const Icon(CupertinoIcons.camera_rotate, color: Colors.white, size: 14),
                       ),
                     ),
                   ],
                 ),
               ),
             ),
          )
      ],
    );
  }

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
             child: const Icon(CupertinoIcons.phone_fill, size: 64, color: Colors.redAccent),
          ),
          const SizedBox(height: 32),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

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
                context.pop();
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
                   style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
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
               color: callState.status == ActiveCallStatus.active ? Colors.green : Colors.grey,
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
              icon: callState.isMuted ? CupertinoIcons.mic_slash_fill : CupertinoIcons.mic_fill,
              isActive: !callState.isMuted,
              onTap: () => notifier.toggleMute(),
            ),
            _buildControlButton(
              icon: callState.isVideoOn ? CupertinoIcons.video_camera_solid : CupertinoIcons.video_camera,
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
              icon: callState.isSpeakerOn ? CupertinoIcons.speaker_3_fill : CupertinoIcons.speaker_1_fill,
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

  Widget _buildControlButton({required IconData icon, required bool isActive, required VoidCallback onTap, Color? color}) {
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
