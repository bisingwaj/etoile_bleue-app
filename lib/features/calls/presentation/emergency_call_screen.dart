import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:go_router/go_router.dart';
import 'package:etoile_bleue_mobile/core/providers/agora_provider.dart';
import 'package:etoile_bleue_mobile/features/calls/domain/entities/call_session.dart';
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
    final session = ref.watch(callSessionProvider);
    final networkQ = ref.watch(networkQualityProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // On Back press, minimize to PIP instead of closing
        ref.read(isCallMinimizedProvider.notifier).state = true;
        context.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black, // Sleek dark mode
        body: SafeArea(
          child: Stack(
            children: [
              // Main Visual (Video or Audio Pulsing Avatar)
              if (session.isVideoEnabled)
                _buildVideoGrid(session)
              else
                _buildAudioVisualizer(session),

              // Header (Minimize Button & Connection Status)
              _buildHeader(session, networkQ),

              // Triage Panel (Pushed up if not minimized)
              const Positioned(
                left: 16,
                right: 16,
                bottom: 120, // Above controls
                child: EmergencyTriagePanel(),
              ),

              // Bottom Controls
              _buildBottomControls(session),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoGrid(CallSession session) {
    final rtcEngine = ref.read(agoraClientProvider).engine;
    return Stack(
      children: [
        // Full screen remote video or waiting screen
        if (session.remoteUid != null)
          AgoraVideoView(
             controller: VideoViewController.remote(
               rtcEngine: rtcEngine,
               canvas: VideoCanvas(uid: session.remoteUid!),
               connection: RtcConnection(channelId: session.channelId),
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
          
        // Local PIP Video
        if (session.remoteUid != null)
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

  Widget _buildAudioVisualizer(CallSession session) {
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
            session.status == CallStatus.active ? 'Appel d\'urgence Actif' : 'Appel en cours...',
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(CallSession session, int networkQuality) {
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
                    session.status == CallStatus.active ? CupertinoIcons.circle_fill : CupertinoIcons.circle,
                    color: session.status == CallStatus.active ? Colors.green : Colors.orange,
                    size: 12,
                 ),
                 const SizedBox(width: 8),
                 Text(
                   session.status == CallStatus.active ? 'Connecté' : 'Connexion...',
                   style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                 ),
               ],
             ),
           ),
           _buildNetworkIndicator(networkQuality),
        ],
      ),
    );
  }

  Widget _buildNetworkIndicator(int quality) {
    IconData icon;
    Color color;

    // 0=Unknown, 1=Excellent, 2=Good, 3=Poor, 4=Bad, 5=VeryBad, 6=Down
    if (quality == 1 || quality == 2) {
      icon = CupertinoIcons.wifi;
      color = Colors.green;
    } else if (quality == 3 || quality == 4) {
      icon = CupertinoIcons.wifi_exclamationmark;
      color = Colors.orange;
    } else if (quality >= 5) {
      icon = CupertinoIcons.wifi_slash;
      color = Colors.red;
    } else {
      icon = CupertinoIcons.wifi;
      color = Colors.grey; // Unknown or not connected yet
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildBottomControls(CallSession session) {
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
              icon: session.isAudioEnabled ? CupertinoIcons.mic_fill : CupertinoIcons.mic_slash_fill,
              isActive: session.isAudioEnabled,
              onTap: () => ref.read(callSessionProvider.notifier).toggleAudio(),
            ),
            _buildControlButton(
              icon: session.isVideoEnabled ? CupertinoIcons.video_camera_solid : CupertinoIcons.video_camera,
              isActive: session.isVideoEnabled,
              onTap: () => ref.read(callSessionProvider.notifier).toggleVideo(),
            ),
            _buildControlButton(
              icon: session.isSpeakerEnabled ? CupertinoIcons.speaker_3_fill : CupertinoIcons.speaker_1_fill,
              isActive: session.isSpeakerEnabled,
              onTap: () => ref.read(callSessionProvider.notifier).toggleSpeaker(),
            ),
            _buildControlButton(
              icon: CupertinoIcons.phone_down_fill,
              isActive: true,
              color: Colors.red,
              onTap: () async {
                await ref.read(emergencyCallServiceProvider).endEmergencyCall();
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
