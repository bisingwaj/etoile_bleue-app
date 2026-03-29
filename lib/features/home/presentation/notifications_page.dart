import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

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
        title: Text('notifications.title'.tr(),
          style: TextStyle(color: AppColors.navyDeep, fontWeight: FontWeight.bold, fontFamily: 'Marianne'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _buildSectionHeader('notifications.news'.tr()),
          _buildNotificationCard(
            title: 'notifications.tip_title'.tr(),
            body: 'notifications.tip_body'.tr(),
            time: 'notifications.time_2h'.tr(),
            icon: CupertinoIcons.flame_fill,
            iconColor: Colors.orange,
            isUnread: true,
          ),
          _buildNotificationCard(
            title: 'notifications.traffic_title'.tr(),
            body: 'notifications.traffic_body'.tr(),
            time: 'notifications.time_yesterday'.tr(),
            icon: CupertinoIcons.car_detailed,
            iconColor: Colors.redAccent,
            isUnread: false,
          ),
          const SizedBox(height: AppSpacing.lg),
          _buildSectionHeader('notifications.courses'.tr()),
          _buildNotificationCard(
            title: 'notifications.course_title'.tr(),
            body: 'notifications.course_body'.tr(),
            time: 'notifications.time_3d'.tr(),
            icon: CupertinoIcons.book_fill,
            iconColor: AppColors.blue,
            isUnread: false,
            isCourse: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md, top: AppSpacing.sm),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.navyDeep,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          fontFamily: 'Marianne',
        ),
      ),
    );
  }

  Widget _buildNotificationCard({
    required String title,
    required String body,
    required String time,
    required IconData icon,
    required Color iconColor,
    required bool isUnread,
    bool isCourse = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isUnread ? Colors.white : Colors.grey[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isUnread ? AppColors.blue.withValues(alpha: 0.3) : Colors.grey[200]!),
        boxShadow: isUnread
            ? [BoxShadow(color: AppColors.blue.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]
            : [],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navyDeep),
                      ),
                    ),
                    Text(
                      time,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
                ),
                if (isCourse) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('notifications.start_course'.tr(), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  )
                ]
              ],
            ),
          ),
          if (isUnread) ...[
            const SizedBox(width: 12),
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: AppColors.blue,
                shape: BoxShape.circle,
              ),
            ),
          ]
        ],
      ),
    );
  }
}
