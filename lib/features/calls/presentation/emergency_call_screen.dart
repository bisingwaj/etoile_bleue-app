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
                  callState.status == ActiveCallStatus.ringing)
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
             child: Container(
               width: 100,
               height: 150,
               decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
               ),
               clipBehavior: Clip.antiAlias,
               child: AgoraVideoView(
                 controller: VideoViewController(
                   rtcEngine: rtcEngine,
                   canvas: const VideoCanvas(uid: 0),
                 ),
               ),
             ),
          )
      ],
    );
  }

  Widget _buildAudioVisualizer(ActiveCallState callState) {
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
            callState.status == ActiveCallStatus.active
                ? 'Appel d\'urgence Actif'
                : 'Appel en cours...',
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ActiveCallState callState) {
    final isActive = callState.status == ActiveCallStatus.active;
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
               children: [
                 Icon(
                    isActive ? CupertinoIcons.circle_fill : CupertinoIcons.circle,
                    color: isActive ? Colors.green : Colors.orange,
                    size: 12,
                 ),
                 const SizedBox(width: 8),
                 Text(
                   isActive ? 'Connecté' : 'Connexion...',
                   style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
               isActive ? CupertinoIcons.wifi : CupertinoIcons.wifi,
               color: isActive ? Colors.green : Colors.grey,
               size: 20,
             ),
           ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(ActiveCallState callState) {
    final notifier = ref.read(callStateProvider.notifier);
    return Positioned(
      bottom: 24,
      left: 24,
      right: 24,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
