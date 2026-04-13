import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/missed_calls_provider.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';

/// Widget affichant les appels manqués avec possibilité de rappeler.
/// Intégré dans la HomePage ou le HistoryPage.
class MissedCallsBanner extends ConsumerWidget {
  const MissedCallsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final missedCallsAsync = ref.watch(missedCallsProvider);

    return missedCallsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (calls) {
        if (calls.isEmpty) return const SizedBox.shrink();

        // Show only the most recent missed calls (max 3)
        final recentCalls = calls.take(3).toList();

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
            crossAxisAlignment: CrossAxisAlignment.start,
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
                      'Appels manqués',
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
              ...recentCalls.asMap().entries.map((entry) {
                final call = entry.value;
                final isLast = entry.key == recentCalls.length - 1;
                return _MissedCallTile(
                  call: call,
                  isLast: isLast,
                );
              }),
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

  String _formatTime(dynamic ts) {
    if (ts == null) return '';
    try {
      final date = DateTime.parse(ts.toString()).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) return "À l'instant";
      if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
      if (diff.inDays == 1) return 'Hier';
      return '${date.day}/${date.month} à ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelName = call['channel_name'] as String? ?? '';
    final rawCallerName = call['caller_name'] as String?;
    // Default name based on call source
    final callerName = rawCallerName ?? 
        (channelName.startsWith('RESCUER-') ? 'Urgentiste' : 'Centre d\'appels');
    final status = call['status'] as String? ?? 'missed';
    final callId = call['id'] as String;
    final createdAt = call['created_at'];

    // Determine the source type
    String sourceLabel;
    IconData sourceIcon;
    Color sourceColor;
    if (channelName.startsWith('RESCUER-')) {
      sourceLabel = 'Urgentiste';
      sourceIcon = CupertinoIcons.person_badge_plus_fill;
      sourceColor = Colors.orange;
    } else {
      sourceLabel = 'Centrale';
      sourceIcon = CupertinoIcons.building_2_fill;
      sourceColor = AppColors.blue;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
              ),
      ),
      child: Row(
        children: [
          // Avatar / source icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: sourceColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(sourceIcon, color: sourceColor, size: 22),
          ),
          const SizedBox(width: 12),

          // Caller info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        callerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (status == 'missed')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Manqué',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(CupertinoIcons.clock, size: 12, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(
                      _formatTime(createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '· $sourceLabel',
                      style: TextStyle(
                        fontSize: 12,
                        color: sourceColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Callback button
          GestureDetector(
            onTap: () async {
              final callState = ref.read(callStateProvider);
              if (callState.isInCall || callState.status == ActiveCallStatus.connecting) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Un appel est déjà en cours'),
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
                      content: Text('Erreur: $e'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                }
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.phone_fill,
                    color: Colors.white,
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Rappeler',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
