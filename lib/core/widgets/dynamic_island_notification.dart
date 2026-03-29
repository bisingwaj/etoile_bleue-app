import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class DynamicIslandNotification extends StatelessWidget {
  final String message;
  final IconData icon;

  const DynamicIslandNotification({super.key, required this.message, required this.icon});

  static void show(BuildContext context, {required String message, required IconData icon}) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 60, // Position du Dynamic Island
        left: 0,
        right: 0,
        child: Material(
          color: Colors.transparent,
          child: DynamicIslandNotification(message: message, icon: icon),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    Future.delayed(const Duration(seconds: 2), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: IntrinsicWidth(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black, // Couleur emblématique du Dynamic Island
            borderRadius: BorderRadius.circular(40),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 5)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
              const SizedBox(width: 12),
              Text(
                message,
                style: const TextStyle(
                  fontFamily: 'Marianne',
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ).animate()
          .fadeIn(duration: 250.ms)
          .slideY(begin: -0.5, end: 0, duration: 400.ms, curve: Curves.easeOutBack)
          // Hide animation (shrink & fade out) after 1.6 seconds, giving time for the view before popping
          .then(delay: 1400.ms)
          .slideY(begin: 0, end: -0.5, duration: 300.ms, curve: Curves.easeInBack)
          .fadeOut(duration: 300.ms),
      ),
    );
  }
}
