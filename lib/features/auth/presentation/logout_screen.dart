import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:etoile_bleue_mobile/features/auth/providers/auth_provider.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';

class LogoutScreen extends ConsumerStatefulWidget {
  const LogoutScreen({super.key});

  @override
  ConsumerState<LogoutScreen> createState() => _LogoutScreenState();
}

class _LogoutScreenState extends ConsumerState<LogoutScreen> {
  @override
  void initState() {
    super.initState();
    _performLogout();
  }

  Future<void> _performLogout() async {
    final stopwatch = Stopwatch()..start();
    await ref.read(authProvider.notifier).signOut();
    stopwatch.stop();

    // Minimum 1.5s for a smooth visual transition
    final remaining = 1500 - stopwatch.elapsedMilliseconds;
    if (remaining > 0) {
      await Future.delayed(Duration(milliseconds: remaining));
    }

    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ÉTOILE\nBLEUE',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Marianne',
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.navyDeep,
                height: 1.2,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.navyDeep.withOpacity(0.4),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'common.disconnecting'.tr(),
              style: TextStyle(
                fontFamily: 'Marianne',
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
