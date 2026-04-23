import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/active_intervention_provider.dart';
import 'package:etoile_bleue_mobile/core/services/emergency_call_service.dart';
import 'package:go_router/go_router.dart';
import 'package:etoile_bleue_mobile/core/router/app_router.dart';
import 'package:flutter_animate/flutter_animate.dart';

class EmergencyCallOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const EmergencyCallOverlay({super.key, required this.child});

  @override
  ConsumerState<EmergencyCallOverlay> createState() => _EmergencyCallOverlayState();
}

class _EmergencyCallOverlayState extends ConsumerState<EmergencyCallOverlay> {
  Timer? _vibrationTimer;
  bool _isCallActionPending = false;
  bool _showFullScreenIncoming = false;

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

  Timer? _durationTimer;
  String _formattedDuration = '00:00';

  void _startDurationTimer(DateTime? since) {
    _durationTimer?.cancel();
    if (since == null) {
      if (mounted) setState(() => _formattedDuration = '00:00');
      return;
    }

    _updateDuration(since);
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateDuration(since);
    });
  }

  void _updateDuration(DateTime since) {
    final duration = DateTime.now().difference(since);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    setState(() => _formattedDuration = '$minutes:$seconds');
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _stopVibration();
    _durationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ActiveCallState>(callStateProvider, (prev, next) {
      final isForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      final shouldVibrate = next.status == ActiveCallStatus.incomingRinging && isForeground;
      
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
      }
      // Reset full-screen incoming state when call is no longer ringing
      if (next.status != ActiveCallStatus.incomingRinging && _showFullScreenIncoming) {
        setState(() => _showFullScreenIncoming = false);
      }
    });

    final callState = ref.watch(callStateProvider);
    final isMinimized = ref.watch(isCallMinimizedProvider);

    // Listen to activeSince changes to restart timer
    ref.listen<DateTime?>(callStateProvider.select((s) => s.activeSince), (prev, next) {
      if (next != prev) {
        _startDurationTimer(next);
      }
    });

    final showMinimizedOverlay = isMinimized &&
        (callState.status == ActiveCallStatus.active ||
         callState.status == ActiveCallStatus.ringing ||
         callState.status == ActiveCallStatus.connecting ||
         callState.status == ActiveCallStatus.onHold);
    
    if (showMinimizedOverlay && callState.activeSince != null && _durationTimer == null) {
      _startDurationTimer(callState.activeSince);
    }
    
    if (!showMinimizedOverlay && _durationTimer != null) {
      _durationTimer?.cancel();
      _durationTimer = null;
    }

    // CallKit gère l'UI native sur iOS et Android — overlay s'affiche si déclenché par l'utilisateur.
    final showIncomingCall = callState.status == ActiveCallStatus.incomingRinging &&
        (_showFullScreenIncoming || !(Platform.isIOS || Platform.isAndroid));

    return Stack(
      children: [
        widget.child,

        if (showIncomingCall) _buildIncomingCallOverlay(callState),

        if (callState.status == ActiveCallStatus.incomingRinging)
          _buildIncomingCallDynamicIsland(callState),

        if (showMinimizedOverlay) _buildAudioDynamicIsland(callState),
      ],
    );
  }

  Widget _buildIncomingCallOverlay(ActiveCallState callState) {
    return Positioned.fill(
      child: Material(
        color: const Color(0xFF0B141B), // WhatsApp dark background color
        child: Stack(
          children: [
            // WhatsApp-style background pattern simulation
            Opacity(
              opacity: 0.04,
              child: GridView.builder(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final icons = [
                    Icons.emergency_outlined,
                    Icons.health_and_safety_outlined,
                    Icons.medical_services_outlined,
                    Icons.local_hospital_outlined,
                    Icons.healing_outlined,
                    Icons.monitor_heart_outlined,
                  ];
                  return Transform.rotate(
                    angle: index % 3 == 0 ? 0.2 : -0.2,
                    child: Icon(
                      icons[index % icons.length],
                      color: Colors.white,
                      size: 28,
                    ),
                  );
                },
              ),
            ),
            
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 80),
                  
                  // Top section: Name & Number
                  Text(
                    'Étoile Bleue',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(CupertinoIcons.phone_fill, color: Colors.white70, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        'Service d\'urgence',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 16,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                  
                  const Spacer(),

                  // Center Avatar: App Logo
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                    child: Center(
                      child: Container(
                        width: 170,
                        height: 170,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: ClipOval(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ).animate(onPlay: (c) => c.repeat(reverse: true))
                   .scale(begin: const Offset(0.96, 0.96), end: const Offset(1.04, 1.04), duration: 2.seconds, curve: Curves.easeInOut),

                  const Spacer(),
                  // Bottom Actions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildCallActionButton(
                          icon: CupertinoIcons.phone_down_fill,
                          color: Colors.red,
                          label: 'Decline',
                          onTap: () {
                            if (_isCallActionPending) return;
                            _isCallActionPending = true;
                            ref.read(callStateProvider.notifier).rejectIncomingCall();
                            setState(() => _showFullScreenIncoming = false);
                            Future.delayed(const Duration(seconds: 1), () {
                              if (mounted) _isCallActionPending = false;
                            });
                          },
                        ),
                        
                        // Middle button (Answer/Swipe up)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onVerticalDragUpdate: (details) {
                                if (details.delta.dy < -10) {
                                  // Swiped up to answer
                                  ref.read(callStateProvider.notifier).answerIncomingCall();
                                  GoRouter.of(context).push('/call/active');
                                }
                              },
                              onTap: () async {
                                if (_isCallActionPending) return;
                                _isCallActionPending = true;
                                await ref.read(callStateProvider.notifier).answerIncomingCall();
                                if (mounted) {
                                  GoRouter.of(context).push('/call/active');
                                  _isCallActionPending = false;
                                }
                              },
                              child: Container(
                                width: 75,
                                height: 75,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(color: Colors.greenAccent, blurRadius: 15, spreadRadius: 1)
                                  ],
                                ),
                                child: const Icon(CupertinoIcons.phone_fill, color: Colors.white, size: 35),
                              ).animate(onPlay: (c) => c.repeat())
                               .shimmer(delay: 800.ms, duration: 1.5.seconds, color: Colors.white24),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Glissez vers le haut',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        
                        _buildCallActionButton(
                          icon: CupertinoIcons.chat_bubble_fill,
                          color: Colors.white.withValues(alpha: 0.1),
                          label: 'Message',
                          onTap: () {
                            setState(() => _showFullScreenIncoming = false);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
            
            // Back button to close overlay
            Positioned(
              top: 10,
              left: 10,
              child: SafeArea(
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
                  onPressed: () => setState(() => _showFullScreenIncoming = false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingCallDynamicIsland(ActiveCallState callState) {
    return Positioned(
      top: MediaQuery.of(context).viewPadding.top + 6,
      left: 12,
      right: 12,
      child: GestureDetector(
        onTap: () => setState(() => _showFullScreenIncoming = true),
        child: Material(
          color: Colors.transparent,
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.98), // Slightly more opaque
            borderRadius: BorderRadius.circular(40),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 25,
                offset: const Offset(0, 12),
              )
            ],
            border: Border.all(color: Colors.white24, width: 0.8), // Slightly more visible border
          ),
          child: Row(
            children: [
              const SizedBox(width: 4),
              _AnimatedIncomingAvatarSmall(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Service d\'urgence'.toUpperCase(),
                      style: TextStyle(
                        color: Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Étoile Bleue',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18, // Increased from 16
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Decline Button
              GestureDetector(
                onTap: () {
                  if (_isCallActionPending) return;
                  _isCallActionPending = true;
                  ref.read(callStateProvider.notifier).rejectIncomingCall();
                  Future.delayed(const Duration(seconds: 1), () {
                    if (mounted) _isCallActionPending = false;
                  });
                },
                child: Container(
                  width: 52, // Increased from 44
                  height: 52, // Increased from 44
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red.withValues(alpha: 0.5), width: 1),
                  ),
                  child: const Center(
                    child: Icon(CupertinoIcons.phone_down_fill, color: Colors.redAccent, size: 24),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Accept Button
              GestureDetector(
                onTap: () async {
                  if (_isCallActionPending) return;
                  _isCallActionPending = true;
                  await ref.read(callStateProvider.notifier).answerIncomingCall();
                  if (mounted) {
                    GoRouter.of(context).push('/call/active');
                    _isCallActionPending = false;
                  }
                },
                child: Container(
                  width: 52, // Increased from 44
                  height: 52, // Increased from 44
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.green.withValues(alpha: 0.5), width: 1),
                  ),
                  child: const Center(
                    child: Icon(CupertinoIcons.phone_fill, color: Colors.greenAccent, size: 24),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    ).animate()
       .slideY(begin: -1.2, end: 0, duration: 600.ms, curve: Curves.elasticOut)
       .fadeIn(duration: 200.ms)
       .scaleXY(begin: 0.9, end: 1.0, duration: 400.ms, curve: Curves.easeOut),
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
      title = callState.callerName ?? 'calls.operator'.tr();
      color = Colors.green;
    } else if (isHold) {
      title = 'calls.waiting'.tr();
      color = Colors.redAccent;
    }

    return Positioned(
      top: MediaQuery.of(context).viewPadding.top + 6,
      left: 12,
      right: 12,
      child: GestureDetector(
        onTap: () {
          debugPrint('[CallOverlay] Dynamic Island tapped - restoring call');
          _restoreCall();
        },
        behavior: HitTestBehavior.opaque,
        child: Material(
          color: Colors.transparent,
          elevation: 20,
          borderRadius: BorderRadius.circular(40),
          child: Container(
            // Increased height and padding for a "bigger" look
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.9), // Deep rich black
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: Colors.white10, width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      _WaveIcon(color: color, isActive: isActive),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white, 
                                fontWeight: FontWeight.bold, 
                                fontSize: 15, // Larger font
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isActive ? 'calls.tap_to_return'.tr() : 'calls.connecting_sub'.tr(),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5), 
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isActive) ...[
                      Text(
                        _formattedDuration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontFeatures: [FontFeature.tabularFigures()],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    GestureDetector(
                       onTap: () => ref.read(callStateProvider.notifier).toggleMute(),
                       child: Container(
                         padding: const EdgeInsets.all(10),
                         decoration: BoxDecoration(
                           color: Colors.white.withValues(alpha: 0.08),
                           shape: BoxShape.circle,
                         ),
                         child: Icon(
                           callState.isMuted ? CupertinoIcons.mic_slash_fill : CupertinoIcons.mic_fill,
                           color: callState.isMuted ? Colors.red : Colors.white,
                           size: 20,
                         ),
                       )
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                       onTap: () => ref.read(callStateProvider.notifier).hangUp(),
                       child: Container(
                         padding: const EdgeInsets.all(10),
                         decoration: const BoxDecoration(
                           color: Colors.red,
                           shape: BoxShape.circle,
                         ),
                         child: const Icon(CupertinoIcons.phone_down_fill, color: Colors.white, size: 20),
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
    debugPrint('[CallOverlay] _restoreCall triggered');
    ref.read(isCallMinimizedProvider.notifier).state = false;
    
    final router = ref.read(appRouterProvider);
    
    // Ensure we navigate back to the call screen
    Future.delayed(const Duration(milliseconds: 50), () {
      try {
        final String currentRoute = router.routerDelegate.currentConfiguration.last.matchedLocation;
        if (currentRoute != '/call/active') {
          router.go('/call/active');
        } else {
          debugPrint('[CallOverlay] Already on /call/active, just un-minimized');
        }
      } catch (e) {
        debugPrint('[CallOverlay] Error during restoration navigation: $e');
        router.go('/call/active');
      }
    });
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

class _WaveIcon extends StatefulWidget {
  final Color color;
  final bool isActive;

  const _WaveIcon({required this.color, required this.isActive});

  @override
  State<_WaveIcon> createState() => _WaveIconState();
}

class _WaveIconState extends State<_WaveIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(CupertinoIcons.phone_fill, color: widget.color, size: 18),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final double value = (index == 1) 
                ? (0.5 + 0.5 * _controller.value) 
                : (index == 0) 
                    ? (0.3 + 0.7 * (1.0 - _controller.value)) 
                    : (0.4 + 0.6 * _controller.value);
            
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3.5,
              height: 18 * value,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          },
        );
      }),
    );
  }
}

class _AnimatedIncomingAvatarSmall extends StatefulWidget {
  @override
  State<_AnimatedIncomingAvatarSmall> createState() => _AnimatedIncomingAvatarSmallState();
}

class _AnimatedIncomingAvatarSmallState extends State<_AnimatedIncomingAvatarSmall>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this, 
      duration: const Duration(milliseconds: 1000)
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.9, end: 1.1).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.orange.withValues(alpha: 0.2),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.5), width: 1.5),
        ),
        child: ClipOval(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
