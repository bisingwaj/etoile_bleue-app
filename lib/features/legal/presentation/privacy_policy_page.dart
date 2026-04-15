import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';

/// Politique de confidentialité — contenu entièrement fourni par les clés `privacy_policy.*`.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  static const List<({String titleKey, String bodyKey})> _sections = [
    (titleKey: 'privacy_policy.s1_title', bodyKey: 'privacy_policy.s1_body'),
    (titleKey: 'privacy_policy.s2_title', bodyKey: 'privacy_policy.s2_body'),
    (titleKey: 'privacy_policy.s3_title', bodyKey: 'privacy_policy.s3_body'),
    (titleKey: 'privacy_policy.s4_title', bodyKey: 'privacy_policy.s4_body'),
    (titleKey: 'privacy_policy.s5_title', bodyKey: 'privacy_policy.s5_body'),
    (titleKey: 'privacy_policy.s6_title', bodyKey: 'privacy_policy.s6_body'),
    (titleKey: 'privacy_policy.s7_title', bodyKey: 'privacy_policy.s7_body'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'privacy_policy.app_bar_title'.tr(),
          style: const TextStyle(
            fontFamily: 'Marianne',
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: AppColors.navy,
          ),
        ),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'privacy_policy.updated'.tr(),
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ..._sections.expand((s) => [
                  Text(
                    s.titleKey.tr(),
                    style: const TextStyle(
                      fontFamily: 'Marianne',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    s.bodyKey.tr(),
                    style: const TextStyle(
                      fontFamily: 'Marianne',
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      height: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ]),
          ],
        ),
      ),
    );
  }
}
