import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/signalement_enums.dart';
import '../models/signalement_models.dart';
import '../providers/signalement_providers.dart';

class SignalementDetailPage extends ConsumerWidget {
  final String signalementId;

  const SignalementDetailPage({super.key, required this.signalementId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(signalementDetailProvider(signalementId));

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          final isNetwork = e.toString().contains('SocketException') || e.toString().contains('TimeoutException');
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isNetwork ? CupertinoIcons.wifi_slash : CupertinoIcons.exclamationmark_triangle,
                  size: 40,
                  color: AppColors.textLight,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  isNetwork ? 'signalement.error_network'.tr() : 'signalement.error_not_found'.tr(),
                  style: AppTextStyles.bodyLarge.copyWith(fontSize: 15),
                ),
                const SizedBox(height: AppSpacing.md),
                if (isNetwork)
                  TextButton(
                    onPressed: () => ref.invalidate(signalementDetailProvider(signalementId)),
                    child: Text('signalement.retry'.tr()),
                  )
                else
                  TextButton(onPressed: () => context.pop(), child: Text('signalement.back'.tr())),
              ],
            ),
          );
        },
        data: (sig) {
          if (sig == null) {
            return Center(child: Text('signalement.error_not_found'.tr()));
          }
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              _buildSliverAppBar(context, sig),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeaderCard(sig),
                      const SizedBox(height: 16),
                      _buildInfoCard(sig),
                      const SizedBox(height: 16),
                      if (sig.description != null && sig.description!.isNotEmpty) ...[
                        _buildDescriptionCard(sig),
                        const SizedBox(height: 16),
                      ],
                      if (sig.commune != null || sig.lat != null || sig.structureName != null) ...[
                        _buildLocationCard(sig),
                        const SizedBox(height: 16),
                      ],
                      if (sig.media.isNotEmpty) ...[
                        _buildMediaCard(context, sig),
                        const SizedBox(height: 32),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, Signalement sig) {
    final firstImage = sig.media.where((m) => m.type == 'image').firstOrNull;
    final imageUrl = firstImage?.url;

    return SliverAppBar(
      expandedHeight: imageUrl != null ? 280.0 : 120.0,
      pinned: true,
      stretch: true,
      backgroundColor: AppColors.navyDeep,
      iconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 50, bottom: 16),
        title: Text(
          'signalement.detail_title'.tr(),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18, fontFamily: 'Marianne'),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null)
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: AppColors.navyDeep.withValues(alpha: 0.5),
                  child: const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
                ),
                errorWidget: (context, url, error) => Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.navyDeep, AppColors.blue],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Center(child: Icon(CupertinoIcons.photo, color: Colors.white54, size: 40)),
                ),
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.navyDeep, AppColors.blue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            // Gradient overlay for text readability
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildHeaderCard(Signalement sig) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sig.reference, style: const TextStyle(fontFamily: 'Marianne', fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.blue, letterSpacing: 1.0)),
          const SizedBox(height: 8),
          Text(sig.title, style: const TextStyle(fontFamily: 'Marianne', fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _badge(sig.status.localizedLabel, _statusColor(sig.status)),
              _badge(sig.priority.localizedLabel, Color(sig.priority.colorValue)),
              _badge(sig.category.localizedLabel, AppColors.textSecondary),
              if (sig.isAnonymous) _badge('signalement.badge_anonymous'.tr(), const Color(0xFF856404)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(Signalement sig) {
    final formattedDate = '${sig.createdAt.day.toString().padLeft(2, '0')}/${sig.createdAt.month.toString().padLeft(2, '0')}/${sig.createdAt.year} à ${sig.createdAt.hour.toString().padLeft(2, '0')}h${sig.createdAt.minute.toString().padLeft(2, '0')}';
    return _buildCard(
      child: Column(
        children: [
          _infoRow(CupertinoIcons.calendar, 'signalement.created_at'.tr(), formattedDate),
          if (sig.assignedTo != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, color: Color(0xFFEEEEEE)),
            ),
            _infoRow(CupertinoIcons.person_fill, 'signalement.assigned_to'.tr(), sig.assignedTo!),
          ],
        ],
      ),
    );
  }

  Widget _buildDescriptionCard(Signalement sig) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('signalement.description'.tr(), CupertinoIcons.text_alignleft),
          const SizedBox(height: 12),
          Text(sig.description!, style: const TextStyle(fontSize: 15, height: 1.6, fontFamily: 'Marianne', color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildLocationCard(Signalement sig) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sig.structureName != null) ...[
            _sectionTitle('signalement.structure_label'.tr(), CupertinoIcons.building_2_fill),
            const SizedBox(height: 8),
            Text(sig.structureName!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'Marianne')),
            const SizedBox(height: 16),
          ],
          if (sig.commune != null || sig.lat != null) ...[
            _sectionTitle('signalement.location_label'.tr(), CupertinoIcons.location_solid),
            const SizedBox(height: 8),
            Text(
              () {
                final parts = [sig.commune, sig.ville, sig.province]
                    .where((s) => s != null && s.isNotEmpty)
                    .join(', ');
                if (parts.isNotEmpty) return parts;
                if (sig.lat != null && sig.lng != null) {
                  return 'GPS: ${sig.lat!.toStringAsFixed(5)}, ${sig.lng!.toStringAsFixed(5)}';
                }
                return 'signalement.location_available'.tr();
              }(),
              style: const TextStyle(fontSize: 15, fontFamily: 'Marianne'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMediaCard(BuildContext context, Signalement sig) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('${'signalement.media_label'.tr()} (${sig.media.length})', CupertinoIcons.photo_fill_on_rectangle_fill),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: sig.media.map((m) {
              return GestureDetector(
                onTap: () async {
                  if (m.type == 'image' || m.type == 'video') {
                    try {
                      await launchUrl(Uri.parse(m.url), mode: LaunchMode.externalApplication);
                    } catch (e) {
                      debugPrint('[Signalement] Could not open media URL: $e');
                    }
                  }
                },
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(16),
                    image: m.thumbnail != null
                        ? DecorationImage(image: CachedNetworkImageProvider(m.thumbnail!), fit: BoxFit.cover)
                        : m.type == 'image'
                            ? DecorationImage(image: CachedNetworkImageProvider(m.url), fit: BoxFit.cover)
                            : null,
                  ),
                  child: (m.thumbnail == null && m.type != 'image')
                      ? Center(
                          child: Icon(
                            m.type == 'video' ? CupertinoIcons.play_circle_fill : CupertinoIcons.waveform,
                            color: AppColors.navy,
                            size: 32,
                          ),
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)),
    );
  }

  Widget _sectionTitle(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontFamily: 'Marianne', fontWeight: FontWeight.w700, color: AppColors.textSecondary, fontSize: 13, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.navy),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontFamily: 'Marianne', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        Expanded(child: Text(value, style: const TextStyle(fontFamily: 'Marianne', fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary), textAlign: TextAlign.right)),
      ],
    );
  }

  Color _statusColor(SignalementStatus status) {
    switch (status) {
      case SignalementStatus.nouveau: return AppColors.blue;
      case SignalementStatus.enCours: return AppColors.warning;
      case SignalementStatus.enquete: return const Color(0xFF8B5CF6);
      case SignalementStatus.resolu: return AppColors.success;
      case SignalementStatus.classe: return AppColors.textLight;
      case SignalementStatus.transfere: return const Color(0xFF06B6D4);
    }
  }
}
