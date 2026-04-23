import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'package:etoile_bleue_mobile/core/services/cache_service.dart';
import 'package:etoile_bleue_mobile/core/providers/missed_calls_provider.dart';
import 'package:etoile_bleue_mobile/features/calls/presentation/widgets/missed_calls_banner.dart';
import 'package:etoile_bleue_mobile/core/error/error_handler.dart';
import 'incident_detail_page.dart';

class _HistoryListNotifier extends StateNotifier<AsyncValue<List<Map<String, dynamic>>>> {
  String? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  final String? _uid;

  _HistoryListNotifier(this._uid) : super(const AsyncValue.loading()) {
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    if (_uid == null) {
      state = const AsyncValue.data([]);
      return;
    }

    // Cache-first
    final cached = CacheService.getCachedHistory();
    if (cached != null && cached.isNotEmpty) {
      state = AsyncValue.data(cached);
    }

    try {
      final data = await Supabase.instance.client
          .from('incidents')
          .select('id, reference, type, title, description, status, priority, media_urls, media_type, created_at, resolved_at')
          .eq('citizen_id', _uid)
          .order('created_at', ascending: false)
          .limit(50);
      final items = (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _cursor = items.isNotEmpty ? items.last['created_at'] as String? : null;
      _hasMore = items.length >= 50;
      state = AsyncValue.data(items);
      CacheService.cacheHistory(items);
    } catch (e, st) {
      if (cached == null || cached.isEmpty) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || _loading || _uid == null) return;
    _loading = true;
    try {
      final data = await Supabase.instance.client
          .from('incidents')
          .select('id, reference, type, title, description, status, priority, media_urls, media_type, created_at, resolved_at')
          .eq('citizen_id', _uid)
          .lt('created_at', _cursor!)
          .order('created_at', ascending: false)
          .limit(50);
      final items = (data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (items.isEmpty) {
        _hasMore = false;
      } else {
        _cursor = items.last['created_at'] as String?;
        _hasMore = items.length >= 50;
        final current = state.valueOrNull ?? [];
        state = AsyncValue.data([...current, ...items]);
      }
    } catch (_) {}
    _loading = false;
  }

  Future<void> refresh() async {
    _cursor = null;
    _hasMore = true;
    await _loadInitial();
  }

  bool get hasMore => _hasMore;
}

final callHistoryProvider =
    StateNotifierProvider<_HistoryListNotifier, AsyncValue<List<Map<String, dynamic>>>>((ref) {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  return _HistoryListNotifier(uid);
});

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  String _currentFilter = 'Tous';
  /// 0 = historique d'événements, 1 = appels manqués
  int _historyTab = 0;

  String _formatDate(dynamic ts) {
    if (ts == null) return '—';
    DateTime date;
    if (ts is String) {
      date = DateTime.tryParse(ts) ?? DateTime.now();
    } else {
      return '—';
    }
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    if (diff.inDays == 1) return 'Hier';
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatDuration(dynamic start, dynamic end) {
    if (start == null || end == null) return '';
    try {
      final s = DateTime.parse(start.toString());
      final e = DateTime.parse(end.toString());
      final dur = e.difference(s);
      if (dur.inSeconds < 60) return '${dur.inSeconds}s';
      return '${dur.inMinutes}min ${dur.inSeconds % 60}s';
    } catch (_) {
      return '';
    }
  }

  void _showFilterMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.only(top: 16, bottom: 40, left: 24, right: 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Container(width: 48, height: 5,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
                const SizedBox(height: 24),
                Text('history.filter_history'.tr(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.navyDeep)),
                const SizedBox(height: 20),
                ...['Tous', 'new', 'dispatched', 'ended'].map((str) {
                  final isSelected = _currentFilter == str;
                  IconData icon;
                  Color color;
                  String label;
                  switch (str) {
                    case 'new': icon = CupertinoIcons.waveform_path_ecg; color = AppColors.red; label = 'history.filter_pending'.tr(); break;
                    case 'dispatched': icon = CupertinoIcons.car_detailed; color = Colors.green; label = 'history.filter_in_progress'.tr(); break;
                    case 'ended': icon = CupertinoIcons.checkmark_circle_fill; color = AppColors.blue; label = 'history.filter_completed'.tr(); break;
                    default: icon = CupertinoIcons.list_bullet; color = Colors.grey[800]!; label = 'history.filter_all'.tr();
                  }
                  return GestureDetector(
                    onTap: () { setState(() => _currentFilter = str); Navigator.pop(ctx); },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: isSelected ? color.withValues(alpha: 0.1) : Colors.grey[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isSelected ? color.withValues(alpha: 0.3) : Colors.transparent),
                      ),
                      child: Row(children: [
                        Icon(icon, color: isSelected ? color : Colors.grey[500], size: 22),
                        const SizedBox(width: 16),
                        Text(label, style: TextStyle(fontSize: 16, fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600, color: isSelected ? color : Colors.grey[700])),
                        const Spacer(),
                        if (isSelected) Icon(CupertinoIcons.checkmark_alt, color: color, size: 20),
                      ]),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(callHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 70,
        title: Padding(
          padding: const EdgeInsets.only(top: 10.0),
          child: Text('history.title'.tr(), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, fontFamily: 'Marianne', color: AppColors.navyDeep, letterSpacing: -1.0)),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 10.0),
            child: GestureDetector(
              onTap: () => _showFilterMenu(context),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
                child: Row(children: [Icon(CupertinoIcons.slider_horizontal_3, size: 22, color: _currentFilter == 'Tous' ? Colors.black87 : AppColors.blue)]),
              ),
            ),
          )
        ],
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (e, _) => Center(child: Text(ErrorHandler.getLocalizedError(e))),
        data: (allCalls) {
          final filtered = _currentFilter == 'Tous'
              ? allCalls
              : allCalls.where((c) {
                  final s = c['status'] as String? ?? '';
                  switch (_currentFilter) {
                    case 'new': return s == 'new' || s == 'pending';
                    case 'dispatched': return s == 'dispatched' || s == 'en_route' || s == 'arrived' || s == 'investigating';
                    case 'ended': return s == 'ended' || s == 'resolved' || s == 'archived';
                    default: return true;
                  }
                }).toList();

          final sosCount = allCalls.length;
          final endedCount = allCalls.where((c) {
            final s = c['status'] as String? ?? '';
            return s == 'ended' || s == 'resolved' || s == 'archived';
          }).length;

          return RefreshIndicator(
            onRefresh: () async {
              await ref.read(callHistoryProvider.notifier).refresh();
              await ref.read(missedCallsProvider.notifier).refresh();
            },
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text("history.citizen_engagement".tr(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey[600]))),
                        const SizedBox(height: 12),
                        SizedBox(height: 110, child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            _buildStatCard(title: 'history.alerts_issued'.tr(), value: '$sosCount', icon: CupertinoIcons.waveform_path_ecg, color: AppColors.red),
                            const SizedBox(width: 12),
                            _buildStatCard(title: 'history.calls_completed'.tr(), value: '$endedCount', icon: CupertinoIcons.checkmark_circle_fill, color: AppColors.blue),
                            const SizedBox(width: 12),
                            _buildStatCard(title: 'history.badges_earned'.tr(), value: '3', icon: CupertinoIcons.rosette, color: Colors.orangeAccent),
                          ],
                        )),
                        const SizedBox(height: 32),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 22,
                                  runSpacing: 8,
                                  children: [
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => setState(() => _historyTab = 0),
                                      child: Text(
                                        'history.event_history'.tr(),
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: _historyTab == 0 ? FontWeight.bold : FontWeight.w600,
                                          color: _historyTab == 0 ? AppColors.navyDeep : Colors.grey,
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => setState(() => _historyTab = 1),
                                      child: Text(
                                        'calls.missed_calls_title'.tr(),
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: _historyTab == 1 ? FontWeight.bold : FontWeight.w600,
                                          color: _historyTab == 1 ? AppColors.navyDeep : Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_historyTab == 0)
                                Text(
                                  'history.see_all'.tr(),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.blue),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                if (_historyTab == 0) ...[
                  if (filtered.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Center(child: Text('history.timeline_empty'.tr(), style: const TextStyle(fontFamily: 'Marianne', color: Colors.grey))),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList.builder(
                        itemCount: filtered.length + (ref.read(callHistoryProvider.notifier).hasMore ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= filtered.length) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              ref.read(callHistoryProvider.notifier).loadMore();
                            });
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CupertinoActivityIndicator()),
                            );
                          }
                          final c = filtered[i];
                          final status = c['status'] as String? ?? 'unknown';
                          final icon = status == 'ended' || status == 'resolved' ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.waveform_path_ecg;
                          final color = status == 'ended' || status == 'resolved' ? AppColors.blue : AppColors.red;
                          final duration = _formatDuration(c['created_at'], c['resolved_at']);
                          return _buildHistoryTile(
                            title: c['title'] ?? 'Incident',
                            subtitle: status == 'ended' || status == 'resolved' ? 'Terminé${duration.isNotEmpty ? " ($duration)" : ""}' : 'Statut: $status',
                            date: _formatDate(c['created_at']),
                            icon: icon, color: color,
                            isLast: i == filtered.length - 1,
                            onTap: () {
                              Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (context) => IncidentDetailPage(
                                    incidentId: c['id'].toString(),
                                    initialData: c,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                ] else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: MissedCallsBanner(embedded: true),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard({required String title, required String value, required IconData icon, required Color color}) {
    return Container(
      width: 140, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))],
        border: Border.all(color: color.withValues(alpha: 0.1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20)),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.navyDeep)),
        ]),
        Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700])),
      ]),
    );
  }

  Widget _buildHistoryTile({required String title, required String subtitle, required String date, required IconData icon, required Color color, required bool isLast, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: isLast ? const BorderRadius.vertical(bottom: Radius.circular(20)) : null,
          border: isLast ? null : Border(bottom: BorderSide(color: Colors.grey[100]!)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 24)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87), overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text(date, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey[500])),
            ]),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ])),
          const SizedBox(width: 8),
          const Icon(CupertinoIcons.chevron_right, color: Colors.grey, size: 16),
        ]),
      ),
    );
  }
}
