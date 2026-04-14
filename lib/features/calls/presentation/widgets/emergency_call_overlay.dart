import 'dart:async';
import 'dart:io' show Platform;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/active_intervention_provider.dart';
import 'package:etoile_bleue_mobile/core/services/emergency_call_service.dart';
import 'package:go_router/go_router.dart';

class EmergencyCallOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const EmergencyCallOverlay({super.key, required this.child});

  @override
  ConsumerState<EmergencyCallOverlay> createState() => _EmergencyCallOverlayState();
}

class _EmergencyCallOverlayState extends ConsumerState<EmergencyCallOverlay> {
  Timer? _vibrationTimer;
  bool _isCallActionPending = false;

  void _startVibration() {
    _vibrationTimer?.cancel();
    HapticFeedback.heavyImpact();
    _vibrationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      HapticFeedback.heavyImpact();
    });
  }

  void _stopVibration() {
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _stopVibration();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ActiveCallState>(callStateProvider, (prev, next) {
      final shouldVibrate = next.status == ActiveCallStatus.incomingRinging &&
          !(Platform.isIOS || Platform.isAndroid);
      if (shouldVibrate && _vibrationTimer == null) {
        _startVibration();
      } else if (!shouldVibrate && _vibrationTimer != null) {
        _stopVibration();
      }

      // Start/stop intervention tracking based on incidentId
      final prevIncident = prev?.incidentId;
      final nextIncident = next.incidentId;
      if (nextIncident != null && nextIncident != prevIncident) {
        ref.read(activeInterventionProvider.notifier).startTracking(nextIncident);
      } else if (nextIncident == null && prevIncident != null && !next.isInCall) {
        // Don't stop tracking when call ends — keep showing the banner
      }
    });

    final callState = ref.watch(callStateProvider);
    final isMinimized = ref.watch(isCallMinimizedProvider);

    final showMinimizedOverlay = isMinimized &&
        (callState.status == ActiveCallStatus.active ||
         callState.status == ActiveCallStatus.ringing ||
         callState.status == ActiveCallStatus.connecting ||
         callState.status == ActiveCallStatus.onHold);

    // CallKit gère l'UI native sur iOS et Android — overlay uniquement sur desktop/web.
    final showIncomingCall = callState.status == ActiveCallStatus.incomingRinging &&
        !(Platform.isIOS || Platform.isAndroid);

    return Stack(
      children: [
        widget.child,

        if (showIncomingCall) _buildIncomingCallOverlay(callState),

        if (showMinimizedOverlay) _buildAudioDynamicIsland(callState),
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
                child: Text(
                  'calls.incoming_call'.tr(),
                  style: TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 30),

              _AnimatedIncomingAvatar(),
              const SizedBox(height: 24),

              Text(
                callState.callerName ?? 'calls.operator'.tr(),
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'calls.emergency_center'.tr(),
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
                      label: 'calls.reject'.tr(),
                      onTap: () {
                        if (_isCallActionPending) return;
                        _isCallActionPending = true;
                        ref.read(callStateProvider.notifier).rejectIncomingCall();
                        Future.delayed(const Duration(seconds: 2), () {
                          if (mounted) _isCallActionPending = false;
                        });
                      },
                    ),
                    _buildCallActionButton(
                      icon: Icons.call,
                      color: Colors.green,
                      label: 'calls.answer'.tr(),
                      size: 80,
                      onTap: () async {
                        if (_isCallActionPending) return;
                        _isCallActionPending = true;
                        await ref.read(callStateProvider.notifier).answerIncomingCall();
                        if (mounted) {
                          GoRouter.of(context).push('/call/active');
                          _isCallActionPending = false;
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

  Widget _buildAudioDynamicIsland(ActiveCallState callState) {
    final status = callState.status;
    final isActive = status == ActiveCallStatus.active;
    final isHold = status == ActiveCallStatus.onHold;
    
    String title = 'calls.connecting'.tr();
    Color color = Colors.orange;
    
    if (isActive) {
      title = 'calls.call_in_progress'.tr();
      color = Colors.green;
    } else if (isHold) {
      title = 'calls.waiting'.tr();
      color = Colors.redAccent;
    }

    return Positioned(
      top: MediaQuery.of(context).viewPadding.top + 8,
      left: 16,
      right: 16,
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
                        color: color.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        CupertinoIcons.phone_fill,
                        color: color,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          'calls.tap_to_return'.tr(),
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
    final String currentRoute = GoRouterState.of(context).matchedLocation;
    if (currentRoute != '/call/active') {
      GoRouter.of(context).go('/call/active');
    }
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
