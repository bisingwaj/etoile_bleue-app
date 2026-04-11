import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';

class SignalementSuccessPage extends StatelessWidget {
  final String reference;
  final int mediaCount;
  final int mediaUploaded;
  final bool pendingSync;

  const SignalementSuccessPage({
    super.key,
    required this.reference,
    required this.mediaCount,
    required this.mediaUploaded,
    this.pendingSync = false,
  });

  @override
  Widget build(BuildContext context) {
    final allUploaded = mediaUploaded >= mediaCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Checkmark
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (pendingSync ? AppColors.warning : AppColors.success).withValues(alpha: 0.12),
                ),
                child: Icon(
                  pendingSync ? CupertinoIcons.clock_fill : CupertinoIcons.checkmark_alt_circle_fill,
                  size: 56,
                  color: pendingSync ? AppColors.warning : AppColors.success,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              Text(
                pendingSync ? 'common.pending_sync'.tr() : 'signalement.success_title'.tr(),
                style: AppTextStyles.headlineLarge.copyWith(fontSize: 24),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  reference,
                  style: const TextStyle(
                    fontFamily: 'Marianne',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: AppColors.blue,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              Text(
                'signalement.success_body'.tr(),
                style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),

              if (mediaCount > 0)
                Text(
                  allUploaded
                      ? 'signalement.success_media'.tr(namedArgs: {'count': '$mediaUploaded'})
                      : 'signalement.success_media_partial'.tr(namedArgs: {'uploaded': '$mediaUploaded', 'total': '$mediaCount'}),
                  style: AppTextStyles.caption.copyWith(
                    color: allUploaded ? AppColors.success : AppColors.warning,
                  ),
                  textAlign: TextAlign.center,
                ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => context.go('/signalements'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    elevation: 0,
                  ),
                  child: Text('signalement.view_list'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              TextButton(
                onPressed: () => context.go('/home'),
                child: Text('signalement.back_home'.tr(), style: const TextStyle(color: AppColors.textSecondary)),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
