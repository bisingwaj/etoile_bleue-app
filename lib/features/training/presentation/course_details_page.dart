import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/theme/app_theme.dart';
import 'quiz_page.dart';

class CourseDetailsPage extends StatelessWidget {
  final String title;
  final Color color;

  const CourseDetailsPage({super.key, required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: AppColors.navyDeep),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: const TextStyle(color: AppColors.navyDeep, fontWeight: FontWeight.bold, fontFamily: 'Marianne'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Video placeholder
            Container(
              height: 220,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 8))
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                   const Icon(CupertinoIcons.play_circle_fill, color: Colors.white, size: 60),
                   const Positioned(
                     bottom: 16,
                     left: 16,
                     child: Padding(
                       padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                       child: Text('01:24', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                     ),
                   )
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Text(
              'training.course_react_title'.tr(),
              style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'training.course_react_body'.tr(),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
            ),

            const SizedBox(height: AppSpacing.lg),
            _buildStep(1, 'training.course_step1'.tr(), 'training.course_step1_desc'.tr()),
            _buildStep(2, 'training.course_step2'.tr(), 'training.course_step2_desc'.tr()),
            _buildStep(3, 'training.course_step3'.tr(), 'training.course_step3_desc'.tr()),
            _buildStep(4, 'training.course_step4'.tr(), 'training.course_step4_desc'.tr()),

            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => QuizPage(title: title, themeColor: color)));
                },
                child: Text('training.course_quiz'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(int number, String stepTitle, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number.toString(),
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stepTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navyDeep)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
