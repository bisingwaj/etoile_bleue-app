import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/core/services/emergency_call_service.dart';
import 'package:go_router/go_router.dart';

class EmergencyCallOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const EmergencyCallOverlay({super.key, required this.child});

  @override
  ConsumerState<EmergencyCallOverlay> createState() => _EmergencyCallOverlayState();
}

class _EmergencyCallOverlayState extends ConsumerState<EmergencyCallOverlay> {
  Offset _pipOffset = const Offset(20, 100);
  Timer? _vibrationTimer;

  void _startVibration() {
    _vibrationTimer?.cancel();
    HapticFeedback.heavyImpact();
    _vibrationTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  void _stopVibration() {
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
  }

  @override
  void dispose() {
    _stopVibration();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callStateProvider);
    final isMinimized = ref.watch(isCallMinimizedProvider);

    final showMinimizedOverlay = isMinimized &&
        (callState.status == ActiveCallStatus.active ||
         callState.status == ActiveCallStatus.ringing ||
         callState.status == ActiveCallStatus.connecting ||
         callState.status == ActiveCallStatus.onHold);

    // CallKit handles native incoming call UI on iOS and Android.
    // Only show the in-app overlay on platforms where CallKit is unavailable.
    final showIncomingCall = callState.status == ActiveCallStatus.incomingRinging &&
        !(Platform.isIOS || Platform.isAndroid);

    if (showIncomingCall && _vibrationTimer == null) {
      _startVibration();
    } else if (!showIncomingCall && _vibrationTimer != null) {
      _stopVibration();
    }

    return Stack(
      children: [
        widget.child,

        if (showIncomingCall) _buildIncomingCallOverlay(callState),

        if (showMinimizedOverlay) ...[
          if (callState.isVideoOn)
            _buildVideoPip(callState)
          else
            _buildAudioDynamicIsland(callState),
        ],
      ],
    );
  }

  Widget _buildIncomingCallOverlay(ActiveCallState callState) {
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.95),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Appel Entrant',
                  style: TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 30),

              _AnimatedIncomingAvatar(),
              const SizedBox(height: 24),

              Text(
                callState.callerName ?? 'Opérateur',
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Centre d\'appel d\'urgence',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),

              const Spacer(),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 50),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildCallActionButton(
                      icon: Icons.call_end,
                      color: Colors.red,
                      label: 'Rejeter',
                      onTap: () => ref.read(callStateProvider.notifier).rejectIncomingCall(),
                    ),
                    _buildCallActionButton(
                      icon: Icons.call,
                      color: Colors.green,
                      label: 'Décrocher',
                      size: 80,
                      onTap: () async {
                        await ref.read(callStateProvider.notifier).answerIncomingCall();
                        if (mounted) {
                          GoRouter.of(context).push('/call/active');
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
      ),
    );
  }

  Widget _buildCallActionButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
    double size = 65,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Icon(icon, color: Colors.white, size: size * 0.45),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }

  Widget _buildVideoPip(ActiveCallState callState) {
    final rtcEngine = ref.read(emergencyCallServiceProvider).engine;
    if (rtcEngine == null) return const SizedBox.shrink();

    return Positioned(
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
                    rtcEngine: rtcEngine,
                    canvas: const VideoCanvas(uid: 0),
                  ),
                ),
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
    );
  }

  Widget _buildAudioDynamicIsland(ActiveCallState callState) {
    final isActive = callState.status == ActiveCallStatus.active;
    return Positioned(
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
                        color: isActive
                            ? Colors.green.withValues(alpha: 0.2)
                            : Colors.orange.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        CupertinoIcons.phone_fill,
                        color: isActive ? Colors.green : Colors.orange,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isActive ? 'Appel en cours' : 'Connexion...',
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
                Row(
                  children: [
                    GestureDetector(
                       onTap: () => ref.read(callStateProvider.notifier).toggleMute(),
                       child: Container(
                         padding: const EdgeInsets.all(8),
                         decoration: BoxDecoration(
                           color: Colors.white.withValues(alpha: 0.1),
                           shape: BoxShape.circle,
                         ),
                         child: Icon(
                           callState.isMuted ? CupertinoIcons.mic_slash_fill : CupertinoIcons.mic_fill,
                           color: callState.isMuted ? Colors.red : Colors.white,
                           size: 16,
                         ),
                       )
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                       onTap: () => ref.read(callStateProvider.notifier).hangUp(),
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
    );
  }

  void _restoreCall() {
    ref.read(isCallMinimizedProvider.notifier).state = false;
    GoRouter.of(context).push('/call/active');
  }
}

class _AnimatedIncomingAvatar extends StatefulWidget {
  @override
  State<_AnimatedIncomingAvatar> createState() => _AnimatedIncomingAvatarState();
}

class _AnimatedIncomingAvatarState extends State<_AnimatedIncomingAvatar>
    with TickerProviderStateMixin {
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
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          FadeTransition(
            opacity: Tween(begin: 0.6, end: 0.0).animate(_pingController),
            child: ScaleTransition(
              scale: Tween(begin: 0.8, end: 1.5).animate(_pingController),
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.green, width: 2),
                ),
              ),
            ),
          ),
          ScaleTransition(
            scale: Tween(begin: 0.95, end: 1.05).animate(_pulseController),
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withValues(alpha: 0.15),
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
