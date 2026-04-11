import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';

class DynamicIslandToast {
  static void showSuccess(BuildContext context, String message) {
    _showIsland(context, message, CupertinoIcons.checkmark_alt, Colors.greenAccent);
  }

  static void showInfo(BuildContext context, String message) {
    _showIsland(context, message, CupertinoIcons.info, AppColors.blue);
  }

  static void showError(BuildContext context, String message) {
    _showIsland(context, message, CupertinoIcons.exclamationmark_triangle_fill, Colors.redAccent);
  }

  static OverlayEntry? _currentEntry;

  static void _showIsland(BuildContext context, String message, IconData icon, Color iconColor) {
    final overlay = Overlay.of(context);
    
    if (_currentEntry != null && _currentEntry!.mounted) {
      _currentEntry!.remove();
      _currentEntry = null;
    }

    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 0,
          right: 0,
          child: Material(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                constraints: const BoxConstraints(maxWidth: 320, minWidth: 200),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.9), // Deep rich black for the island
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.2), shape: BoxShape.circle),
                      child: Icon(icon, color: iconColor, size: 18),
                    )
                    .animate()
                    .scale(delay: 300.ms, duration: 400.ms, curve: Curves.elasticOut)
                    .fadeIn(),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        message,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                        textAlign: TextAlign.center,
                      )
                      .animate()
                      .fadeIn(delay: 200.ms, duration: 300.ms)
                      .slideX(begin: 0.1, end: 0),
                    ),
                  ],
                ),
              )
              .animate(
                onComplete: (controller) async {
                  await Future.delayed(const Duration(seconds: 2));
                  if (!overlayEntry.mounted) return;
                  controller.reverse().then((value) {
                    if (overlayEntry.mounted) {
                      overlayEntry.remove();
                      if (_currentEntry == overlayEntry) {
                        _currentEntry = null;
                      }
                    }
                  });
                }
              )
              .slideY(begin: -1.5, end: 0, duration: 600.ms, curve: Curves.elasticOut)
              .fadeIn(duration: 200.ms)
              .scaleXY(begin: 0.8, end: 1.0, duration: 400.ms, curve: Curves.easeOut),
            ),
          ),
        );
      },
    );

    _currentEntry = overlayEntry;
    overlay.insert(overlayEntry);
  }
}
