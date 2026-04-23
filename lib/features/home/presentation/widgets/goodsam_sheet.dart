import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';

class GoodSamSheet extends StatefulWidget {
  final VoidCallback onCancel;
  const GoodSamSheet({super.key, required this.onCancel});

  @override
  State<GoodSamSheet> createState() => _GoodSamSheetState();
}

enum SamState { searching, notFound }

class _GoodSamSheetState extends State<GoodSamSheet> with SingleTickerProviderStateMixin {
  late AnimationController _radarController;
  SamState _state = SamState.searching;
  Timer? _simTimer;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    
    // Simulate searching for a while, then failing to find anyone
    _simTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _state = SamState.notFound);
    });
  }

  @override
  void dispose() {
    _radarController.dispose();
    _simTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 24),
            Text(
              _state == SamState.searching ? 'goodsam.searching_title'.tr() : 'goodsam.not_found_title'.tr(),
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineLarge.copyWith(fontWeight: FontWeight.w900, fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              _state == SamState.searching 
                  ? 'goodsam.searching_sub'.tr() 
                  : 'goodsam.not_found_body'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 15),
            ),
            const SizedBox(height: 40),

            // Radar Map UI
            SizedBox(
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                   // The Radar Rings
                  if (_state == SamState.searching)
                    ...List.generate(3, (index) {
                      return AnimatedBuilder(
                        animation: _radarController,
                        builder: (context, child) {
                          double value = (_radarController.value - (index * 0.3)).clamp(0.0, 1.0);
                          return Transform.scale(
                            scale: 1.0 + (value * 2),
                            child: Opacity(
                              opacity: 1.0 - value,
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.blue, width: 2),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }),
                    
                  // Center User Icon
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: _state == SamState.searching ? AppColors.blue : Colors.red,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: (_state == SamState.searching ? AppColors.blue : Colors.red).withOpacity(0.3), blurRadius: 20)],
                    ),
                    child: Icon(
                      _state == SamState.searching ? CupertinoIcons.location_fill : CupertinoIcons.xmark,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),

                  // Rescuer Icons (Removed as per request)
                ],
              ),
            ),

            const SizedBox(height: 32),
            
            // Rescuer Profile Card (Removed as per request)
            const SizedBox(height: 32),
            TextButton(
              onPressed: () {
                 if (_state == SamState.searching) {
                   widget.onCancel();
                   Navigator.pop(context);
                 } else {
                   // If already found, close and consider it active
                   Navigator.pop(context);
                 }
              },
              child: Text(_state == SamState.searching ? 'goodsam.cancel_search'.tr() : 'goodsam.close'.tr(), style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
