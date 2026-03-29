import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/theme/app_theme.dart';
import 'course_details_page.dart';

class TrainingPage extends StatelessWidget {
  const TrainingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: AppColors.navyDeep),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'training.title'.tr(),
          style: const TextStyle(color: AppColors.navyDeep, fontWeight: FontWeight.bold, fontFamily: 'Marianne'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _buildHeroCard(context),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'training.modules'.tr(),
            style: const TextStyle(color: AppColors.navyDeep, fontSize: 18, fontWeight: FontWeight.w800, fontFamily: 'Marianne'),
          ),
          const SizedBox(height: AppSpacing.md),
          _buildCourseCard(
            context,
            titleKey: 'training.course_cardiac',
            subtitleKey: 'training.course_cardiac_sub',
            icon: CupertinoIcons.heart_fill,
            color: Colors.redAccent,
            progress: 0.0,
            duration: '5 min',
          ),
          _buildCourseCard(
            context,
            titleKey: 'training.course_choking',
            subtitleKey: 'training.course_choking_sub',
            icon: CupertinoIcons.wind,
            color: AppColors.blue,
            progress: 1.0,
            duration: '3 min',
          ),
          _buildCourseCard(
            context,
            titleKey: 'training.course_bleed',
            subtitleKey: 'training.course_bleed_sub',
            icon: CupertinoIcons.drop_fill,
            color: Colors.orange,
            progress: 0.4,
            duration: '4 min',
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.blue, AppColors.navyDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: AppColors.blue.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'training.hero_title'.tr(),
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Marianne'),
                ),
                const SizedBox(height: 8),
                Text(
                  'training.hero_body'.tr(),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.star_fill, color: Colors.amber, size: 16),
                      const SizedBox(width: 4),
                      Text('training.hero_badge'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                )
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Icon(CupertinoIcons.star_circle_fill, size: 80, color: Colors.white24),
        ],
      ),
    );
  }

  Widget _buildCourseCard(
    BuildContext context, {
    required String titleKey,
    required String subtitleKey,
    required IconData icon,
    required Color color,
    required double progress,
    required String duration,
  }) {
    final bool isCompleted = progress >= 1.0;
    final title = titleKey.tr();

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => CourseDetailsPage(title: title, color: color)));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16)),
                  child: Icon(icon, color: color, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navyDeep))),
                          if (isCompleted)
                            const Icon(CupertinoIcons.checkmark_seal_fill, color: Colors.green, size: 20)
                          else
                            Text(duration, style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(subtitleKey.tr(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.3)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(isCompleted ? Colors.green : color),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  isCompleted ? 'training.course_done'.tr() : '${(progress * 100).toInt()}%',
                  style: TextStyle(
                    color: isCompleted ? Colors.green : AppColors.navyDeep,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }
}
