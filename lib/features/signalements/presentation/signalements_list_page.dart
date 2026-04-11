import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/signalement_enums.dart';
import '../models/signalement_models.dart';
import '../providers/signalement_providers.dart';

class SignalementsListPage extends ConsumerStatefulWidget {
  const SignalementsListPage({super.key});

  @override
  ConsumerState<SignalementsListPage> createState() => _SignalementsListPageState();
}

class _SignalementsListPageState extends ConsumerState<SignalementsListPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(signalementsListProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(signalementRealtimeProvider);
    final listState = ref.watch(signalementsListProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, size: 22),
          onPressed: () => context.go('/home'),
        ),
        title: Text('signalement.list_title'.tr(), style: AppTextStyles.titleMedium),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.add_circled, color: AppColors.blue),
            onPressed: () => context.push('/signalement-form'),
          ),
        ],
      ),
      body: listState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.exclamationmark_triangle, size: 40, color: AppColors.textLight),
              const SizedBox(height: AppSpacing.sm),
              Text('signalement.error_loading'.tr(), style: AppTextStyles.bodyLarge.copyWith(fontSize: 15)),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => ref.read(signalementsListProvider.notifier).loadInitial(),
                child: Text('signalement.retry'.tr()),
              ),
            ],
          ),
        ),
        data: (items) {
          if (items.isEmpty) return _buildEmptyState();
          return RefreshIndicator(
            onRefresh: () => ref.read(signalementsListProvider.notifier).loadInitial(),
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: items.length,
              separatorBuilder: (ctx, idx) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) => _buildCard(items[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.doc_text, size: 48, color: AppColors.textLight),
            const SizedBox(height: AppSpacing.md),
            Text('signalement.empty_title'.tr(), style: AppTextStyles.titleMedium.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'signalement.empty_body'.tr(),
              style: AppTextStyles.bodyLarge.copyWith(fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: () => context.push('/signalement-form'),
              icon: const Icon(CupertinoIcons.add, size: 18),
              label: Text('signalement.new_btn'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Signalement sig) {
    final statusColor = _statusColor(sig.status);
    return GestureDetector(
      onTap: () => context.push('/signalements/${sig.id}'),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    sig.status.localizedLabel,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Color(sig.priority.colorValue).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    sig.priority.localizedLabel,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(sig.priority.colorValue)),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(sig.createdAt),
                  style: AppTextStyles.caption,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              sig.title,
              style: const TextStyle(fontFamily: 'Marianne', fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              sig.category.localizedLabel,
              style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary),
            ),
            if (sig.reference.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(sig.reference, style: AppTextStyles.caption.copyWith(color: AppColors.blue, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(SignalementStatus status) {
    switch (status) {
      case SignalementStatus.nouveau:
        return AppColors.blue;
      case SignalementStatus.enCours:
        return AppColors.warning;
      case SignalementStatus.enquete:
        return const Color(0xFF8B5CF6);
      case SignalementStatus.resolu:
        return AppColors.success;
      case SignalementStatus.classe:
        return AppColors.textLight;
      case SignalementStatus.transfere:
        return const Color(0xFF06B6D4);
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.isNegative) return '${date.day}/${date.month}/${date.year}';
    if (diff.inMinutes < 1) return 'signalement.date_now'.tr();
    if (diff.inMinutes < 60) return 'signalement.date_minutes_ago'.tr(namedArgs: {'count': '${diff.inMinutes}'});
    if (diff.inHours < 24) return 'signalement.date_hours_ago'.tr(namedArgs: {'count': '${diff.inHours}'});
    if (diff.inDays == 1) return 'signalement.date_yesterday'.tr();
    return '${date.day}/${date.month}/${date.year}';
  }
}
