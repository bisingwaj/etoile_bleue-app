import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:etoile_bleue_mobile/core/providers/agora_provider.dart';
import 'package:etoile_bleue_mobile/core/services/emergency_call_service.dart';
import 'package:etoile_bleue_mobile/features/calls/domain/entities/call_session.dart';
import 'package:go_router/go_router.dart';

/// Overlay global qui entoure l'application entière pour afficher le Dynamic Island
/// ou le Picture-in-Picture vidéo lorsque l'appel est réduit.
class EmergencyCallOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const EmergencyCallOverlay({super.key, required this.child});

  @override
  ConsumerState<EmergencyCallOverlay> createState() => _EmergencyCallOverlayState();
}

class _EmergencyCallOverlayState extends ConsumerState<EmergencyCallOverlay> {
  // Position pip (drag)
  Offset _pipOffset = const Offset(20, 100);

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(callSessionProvider);
    final isMinimized = ref.watch(isCallMinimizedProvider);

    final showOverlay = isMinimized &&
        (session.status == CallStatus.active ||
         session.status == CallStatus.ringing ||
         session.status == CallStatus.connecting);

    return Stack(
      children: [
        // App principale
        widget.child,

        // L'overlay
        if (showOverlay) ...[
          // Si Vidéo activée : PiP Draggable
          if (session.isVideoEnabled)
            Positioned(
              left: _pipOffset.dx,
              top: _pipOffset.dy,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _pipOffset += details.delta;
                  });
                },
                onTap: _restoreCall,
                child: Material(
                  color: Colors.transparent,
                  elevation: 10,
                  shadowColor: Colors.black45,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 120,
                    height: 160,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.redAccent, width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        AgoraVideoView(
                          controller: VideoViewController(
                            rtcEngine: ref.read(agoraClientProvider).engine,
                            canvas: const VideoCanvas(uid: 0),
                          ),
                        ),
                        // Badge pour restaurer
                        const Positioned(
                          bottom: 8,
                          right: 8,
                          child: Icon(CupertinoIcons.arrow_up_left_arrow_down_right, color: Colors.white, size: 20),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            // Sinon : Dynamic Island Audio en haut
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 20,
              right: 20,
              child: GestureDetector(
                onTap: _restoreCall,
                child: Material(
                  color: Colors.transparent,
                  elevation: 10,
                  borderRadius: BorderRadius.circular(40),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: session.status == CallStatus.active ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                CupertinoIcons.phone_fill,
                                color: session.status == CallStatus.active ? Colors.green : Colors.orange,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  session.status == CallStatus.active ? 'Appel en cours' : 'Connexion...',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                Text(
                                  'Appuyez pour revenir',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
                                ),
                              ],
                            ),
                          ],
                        ),
                        // Mini actions
                        Row(
                          children: [
                            GestureDetector(
                               onTap: () => ref.read(callSessionProvider.notifier).toggleAudio(),
                               child: Container(
                                 padding: const EdgeInsets.all(8),
                                 decoration: BoxDecoration(
                                   color: Colors.white.withValues(alpha: 0.1),
                                   shape: BoxShape.circle,
                                 ),
                                 child: Icon(
                                   session.isAudioEnabled ? CupertinoIcons.mic_fill : CupertinoIcons.mic_slash_fill,
                                   color: session.isAudioEnabled ? Colors.white : Colors.red,
                                   size: 16,
                                 ),
                               )
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                               onTap: () {
                                 ref.read(emergencyCallServiceProvider).endEmergencyCall();
                               },
                               child: Container(
                                 padding: const EdgeInsets.all(8),
                                 decoration: const BoxDecoration(
                                   color: Colors.red,
                                   shape: BoxShape.circle,
                                 ),
                                 child: const Icon(CupertinoIcons.phone_down_fill, color: Colors.white, size: 16),
                               )
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  void _restoreCall() {
    ref.read(isCallMinimizedProvider.notifier).state = false;
    // On force la navigation vers l'écran d'appel, en utilisant GoRouter
    // L'AppRouter doit avoir une route vers la page d'appel actif.
    // On utilisera AppRoutes.call
    GoRouter.of(context).push('/call/active');
  }
}
