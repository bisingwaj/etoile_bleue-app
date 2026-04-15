import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/missed_calls_provider.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';

/// Widget affichant les appels manqués avec possibilité de rappeler.
/// [embedded] : sans marge ni en-tête interne (ex. onglet Historique).
class MissedCallsBanner extends ConsumerWidget {
  const MissedCallsBanner({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missedCallsAsync = ref.watch(missedCallsProvider);

    return missedCallsAsync.when(
      loading: () => embedded
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CupertinoActivityIndicator()),
            )
          : const SizedBox.shrink(),
      error: (e, _) => embedded
          ? Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'errors.detail'.tr(namedArgs: {'error': e.toString()}),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ),
            )
          : const SizedBox.shrink(),
      data: (calls) {
        if (calls.isEmpty) {
          if (embedded) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'calls.missed_list_empty'.tr(),
                  style: TextStyle(fontSize: 15, color: Colors.grey[600], fontFamily: 'Marianne'),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }

        // Mode onglet Historique : même liste que les incidents ; mode bannière : max 3
        final rows = embedded ? calls : calls.take(3).toList();

        final list = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows.asMap().entries.map((entry) {
            final call = entry.value;
            final isLast = entry.key == rows.length - 1;
            return _MissedCallTile(
              call: call,
              isLast: isLast,
            );
          }).toList(),
        );

        if (embedded) {
          return list;
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.phone_arrow_down_left,
                        color: Colors.red,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'calls.missed_calls_title'.tr(),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.navyDeep,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${calls.length}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              list,
            ],
          ),
        );
      },
    );
  }
}

class _MissedCallTile extends ConsumerWidget {
  final Map<String, dynamic> call;
  final bool isLast;

  const _MissedCallTile({
    required this.call,
    required this.isLast,
  });

  String _formatTime(BuildContext context, dynamic ts) {
    if (ts == null) return '';
    try {
      final date = DateTime.parse(ts.toString()).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) return 'calls.time_now'.tr();
      if (diff.inMinutes < 60) {
        return 'calls.time_minutes_ago'.tr(args: [diff.inMinutes.toString()]);
      }
      if (diff.inHours < 24) {
        return 'calls.time_hours_ago'.tr(args: [diff.inHours.toString()]);
      }
      if (diff.inDays == 1) return 'calls.time_yesterday'.tr();
      return 'calls.time_date_at'.tr(namedArgs: {
        'day': '${date.day}',
        'month': '${date.month}',
        'hour': date.hour.toString().padLeft(2, '0'),
        'minute': date.minute.toString().padLeft(2, '0'),
      });
    } catch (_) {
      return '';
    }
  }

  Future<void> _onRowTap(BuildContext context, WidgetRef ref) async {
    final channelName = call['channel_name'] as String? ?? '';
    final isFromUrgentiste = channelName.startsWith('RESCUER-');
    if (isFromUrgentiste) return;

    final citizenId = call['citizen_id'] as String?;
    final currentUid = Supabase.instance.client.auth.currentUser?.id;
    if (citizenId == null || currentUid == null || citizenId != currentUid) {
      return;
    }

    final callId = call['id'] as String;
    final callState = ref.read(callStateProvider);
    if (callState.isInCall || callState.status == ActiveCallStatus.connecting) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('calls.call_already_active'.tr()),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    try {
      await ref.read(callStateProvider.notifier).startCallbackCall(callId);
      if (context.mounted) {
        context.go('/call/active');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('errors.detail'.tr(namedArgs: {'error': e.toString()})),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelName = call['channel_name'] as String? ?? '';
    final isFromUrgentiste = channelName.startsWith('RESCUER-');
    final citizenId = call['citizen_id'] as String?;
    final currentUid = Supabase.instance.client.auth.currentUser?.id;
    final isOwnCall =
        citizenId != null && currentUid != null && citizenId == currentUid;
    final canRappel = isOwnCall && !isFromUrgentiste;

    final rawCallerName = call['caller_name'] as String?;
    final callerName = rawCallerName ??
        (channelName.startsWith('RESCUER-')
            ? 'calls.source_urgentiste'.tr()
            : 'calls.caller_fallback_centrale'.tr());
    final status = call['status'] as String? ?? 'missed';
    final createdAt = call['created_at'];

    String sourceLabel;
    IconData sourceIcon;
    Color sourceColor;
    if (channelName.startsWith('RESCUER-')) {
      sourceLabel = 'calls.source_urgentiste'.tr();
      sourceIcon = CupertinoIcons.person_badge_plus_fill;
      sourceColor = Colors.orange;
    } else {
      sourceLabel = 'calls.source_centrale_short'.tr();
      sourceIcon = CupertinoIcons.building_2_fill;
      sourceColor = AppColors.blue;
    }

    final statusPrefix =
        status == 'missed' ? 'calls.missed_status'.tr() : status;
    final subtitle = '$statusPrefix · $sourceLabel';

    // Même disposition que [HistoryPage._buildHistoryTile]
    return GestureDetector(
      onTap: canRappel ? () => _onRowTap(context, ref) : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: isLast ? const BorderRadius.vertical(bottom: Radius.circular(20)) : null,
          border: isLast ? null : Border(bottom: BorderSide(color: Colors.grey[100]!)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: sourceColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(sourceIcon, color: sourceColor, size: 24),
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
                          callerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(context, createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.chevron_right,
              color: canRappel ? Colors.grey : Colors.grey.withValues(alpha: 0.35),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
