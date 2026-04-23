import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etoile_bleue_mobile/features/history/models/patient_timeline_models.dart';
import 'package:etoile_bleue_mobile/features/history/providers/patient_timeline_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';

class IncidentDetailPage extends ConsumerStatefulWidget {
  final String incidentId;
  final Map<String, dynamic> initialData;

  const IncidentDetailPage({
    super.key,
    required this.incidentId,
    required this.initialData,
  });

  @override
  ConsumerState<IncidentDetailPage> createState() => _IncidentDetailPageState();
}

class _IncidentDetailPageState extends ConsumerState<IncidentDetailPage> {
  Map<String, dynamic> _incidentData = {};
  RealtimeChannel? _incidentSub;
  RealtimeChannel? _timelineRealtimeSub;

  /// `null` = afficher toutes les sources ; sinon filtre sur `TimelineEvent.source`.
  String? _eventSourceFilter;

  /// Clés d’événements dont les détails (description, vitaux…) sont dépliés.
  final Set<String> _expandedTimelineEventKeys = {};

  @override
  void initState() {
    super.initState();
    _incidentData = widget.initialData;
    _listenToIncident();
  }

  void _listenToIncident() {
    _incidentSub = Supabase.instance.client
        .channel('public:incidents:${widget.incidentId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'incidents',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.incidentId,
          ),
          callback: (payload) {
            if (mounted && payload.newRecord.isNotEmpty) {
              setState(() => _incidentData = payload.newRecord);
            }
          },
        )
        .subscribe();

    // Rafraîchit la chronologie unifiée (centrale / terrain / hôpital).
    _timelineRealtimeSub = Supabase.instance.client
        .channel('public:patient_timeline:${widget.incidentId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'dispatches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'incident_id',
            value: widget.incidentId,
          ),
          callback: (_) {
            if (mounted) {
              ref.invalidate(patientTimelineProvider(widget.incidentId));
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'hospital_reports',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'incident_id',
            value: widget.incidentId,
          ),
          callback: (_) {
            if (mounted) {
              ref.invalidate(patientTimelineProvider(widget.incidentId));
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _incidentSub?.unsubscribe();
    _timelineRealtimeSub?.unsubscribe();
    super.dispose();
  }

  /// Couleurs désaturées pour une chronologie lisible sans effet « alarme ».
  (Color, IconData) _sourceStyle(String source) {
    switch (source) {
      case 'centrale':
        return (const Color(0xFF5C7A99), CupertinoIcons.antenna_radiowaves_left_right);
      case 'terrain':
        return (const Color(0xFF6D8F7E), CupertinoIcons.car_fill);
      case 'hopital':
        return (const Color(0xFF8E86A3), CupertinoIcons.building_2_fill);
      case 'systeme':
      default:
        return (AppColors.textSecondary, CupertinoIcons.gear_alt_fill);
    }
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'centrale':
        return 'incident_detail.timeline_source_centrale'.tr();
      case 'terrain':
        return 'incident_detail.timeline_source_terrain'.tr();
      case 'hopital':
        return 'incident_detail.timeline_source_hopital'.tr();
      case 'systeme':
      default:
        return 'incident_detail.timeline_source_systeme'.tr();
    }
  }

  static const List<String> _filterSourceOrder = ['centrale', 'terrain', 'hopital', 'systeme'];

  /// Sources présentes dans la chronologie (ordre : centrale → terrain → hôpital → système → autres).
  List<String> _sourcesInEvents(List<TimelineEvent> events) {
    final set = <String>{};
    for (final e in events) {
      set.add(e.source);
    }
    final ordered = <String>[];
    for (final s in _filterSourceOrder) {
      if (set.contains(s)) ordered.add(s);
    }
    final rest = set.where((s) => !_filterSourceOrder.contains(s)).toList()..sort();
    ordered.addAll(rest);
    return ordered;
  }

  String _filterEntityLabel(String source) {
    switch (source) {
      case 'centrale':
        return 'incident_detail.filter_label_centrale'.tr();
      case 'terrain':
        return 'incident_detail.filter_label_terrain'.tr();
      case 'hopital':
        return 'incident_detail.filter_label_hopital'.tr();
      case 'systeme':
        return 'incident_detail.filter_label_systeme'.tr();
      default:
        return source;
    }
  }

  List<TimelineEvent> _filteredEvents(List<TimelineEvent> all) {
    if (_eventSourceFilter == null) return all;
    return all.where((e) => e.source == _eventSourceFilter).toList();
  }

  Widget _buildEntityFilterBar(List<String> sourcesPresent) {
    if (sourcesPresent.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildEntityFilterChip(
            label: 'incident_detail.filter_all'.tr(),
            selected: _eventSourceFilter == null,
            accent: AppColors.textPrimary,
            onTap: () => setState(() => _eventSourceFilter = null),
          ),
          for (final source in sourcesPresent)
            _buildEntityFilterChip(
              label: _filterEntityLabel(source),
              selected: _eventSourceFilter == source,
              accent: _sourceStyle(source).$1,
              onTap: () => setState(() => _eventSourceFilter = source),
            ),
        ],
      ),
    );
  }

  Widget _buildEntityFilterChip({
    required String label,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          splashColor: accent.withValues(alpha: 0.08),
          highlightColor: accent.withValues(alpha: 0.05),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.1) : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? accent.withValues(alpha: 0.32) : AppColors.border,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? accent : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatEventTime(DateTime at) {
    final local = at.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildVitalsCard(Map<String, dynamic> vitals) {
    final entries = vitals.entries.where((e) => e.value != null && e.value.toString().isNotEmpty).toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'incident_detail.vitals_title'.tr(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: entries.map((e) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.85)),
                ),
                child: Text(
                  '${e.key}: ${e.value}',
                  style: const TextStyle(fontSize: 12, height: 1.25, color: AppColors.textPrimary),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _timelineEventKey(TimelineEvent e) {
    return '${e.at.toIso8601String()}|${e.source}|${e.category}|${e.title.hashCode}';
  }

  bool _eventHasExpandableDetail(TimelineEvent e) {
    final hasDesc = e.description != null && e.description!.trim().isNotEmpty;
    final hasVitals =
        (e.category == 'triage' || e.category == 'assessment') && e.vitalsFromMetadata != null;
    return hasDesc || hasVitals;
  }

  void _toggleTimelineEventExpanded(String key) {
    setState(() {
      if (_expandedTimelineEventKeys.contains(key)) {
        _expandedTimelineEventKeys.remove(key);
      } else {
        _expandedTimelineEventKeys.add(key);
      }
    });
  }

  Widget _buildTimelineEventItem(TimelineEvent e, bool isLast) {
    final (color, icon) = _sourceStyle(e.source);
    final title = e.title.trim().isEmpty ? 'incident_detail.timeline_event_fallback'.tr() : e.title;
    final showVitals = (e.category == 'triage' || e.category == 'assessment') && e.vitalsFromMetadata != null;
    final eventKey = _timelineEventKey(e);
    final expanded = _expandedTimelineEventKeys.contains(eventKey);
    final canExpand = _eventHasExpandableDetail(e);
    final hasDesc = e.description != null && e.description!.trim().isNotEmpty;

    final titleText = Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 15,
        height: 1.25,
        color: AppColors.textPrimary,
      ),
      maxLines: canExpand && !expanded ? 2 : null,
      overflow: canExpand && !expanded ? TextOverflow.ellipsis : null,
    );

    Widget titleRow;
    if (canExpand) {
      titleRow = Semantics(
        button: true,
        label: 'incident_detail.timeline_expand_a11y'.tr(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _toggleTimelineEventExpanded(eventKey),
            borderRadius: BorderRadius.circular(10),
            splashColor: color.withValues(alpha: 0.08),
            highlightColor: color.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: titleText),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 0),
                    child: AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: AppColors.textLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      titleRow = titleText;
    }

    final detailColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasDesc)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              e.description!,
              style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary),
            ),
          ),
        if (showVitals) _buildVitalsCard(e.vitalsFromMetadata!),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.09),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color.withValues(alpha: 0.88), size: 17),
              ),
              if (!isLast)
                Container(
                  width: 1,
                  height: 28,
                  margin: const EdgeInsets.only(top: 6),
                  color: AppColors.border,
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _sourceLabel(e.source),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                          color: color.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatEventTime(e.at),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textLight),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                titleRow,
                if (!canExpand) detailColumn,
                if (canExpand)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: expanded
                        ? Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: detailColumn,
                          )
                        : const SizedBox(width: double.infinity),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openReportSheet(HospitalReportSummary r) {
    final pretty = r.reportData != null
        ? const JsonEncoder.withIndent('  ').convert(r.reportData)
        : '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.35,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'incident_detail.hospital_report_title'.tr(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 17,
                              letterSpacing: -0.3,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                          tooltip: 'incident_detail.report_close'.tr(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      children: [
                        if (r.summary != null && r.summary!.isNotEmpty) ...[
                          Text(
                            r.summary!,
                            style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.textPrimary),
                          ),
                          if (pretty.isNotEmpty) const SizedBox(height: 20),
                        ],
                        if (pretty.isNotEmpty)
                          SelectableText(
                            pretty,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              height: 1.45,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        if ((r.summary == null || r.summary!.isEmpty) && pretty.isEmpty)
                          Text(
                            'incident_detail.report_empty'.tr(),
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final timelineAsync = ref.watch(patientTimelineProvider(widget.incidentId));
    final status = _incidentData['status']?.toString();

    final unitName = timelineAsync.maybeWhen(
      data: (pt) {
        if (pt == null) return null;
        for (final d in pt.dispatches) {
          final n = d.structureName;
          if (n != null && n.isNotEmpty) return n;
        }
        return null;
      },
      orElse: () => null,
    ) ??
        'incident_detail.coordination_pending'.tr();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('incident_detail.title'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.navyDeep)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.navyDeep),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(patientTimelineProvider(widget.incidentId));
                await ref.read(patientTimelineProvider(widget.incidentId).future);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(top: 12, left: 24, right: 24, bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(CupertinoIcons.heart_circle_fill, color: AppColors.red, size: 28),
                      const SizedBox(width: 8),
                      Text('incident_detail.brand'.tr(), style: AppTextStyles.headlineLarge.copyWith(fontWeight: FontWeight.bold, fontSize: 22)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // Driver Profile equivalent
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.blue[50],
                        child: const Icon(CupertinoIcons.person_3_fill, color: AppColors.blue),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('incident_detail.rescue_unit'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Row(
                              children: [
                                const Icon(Icons.verified_user, color: Colors.amber, size: 14),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    unitName, 
                                    style: TextStyle(color: Colors.grey[600], fontSize: 13), 
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (status != 'ended' && status != 'resolved')
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('incident_detail.delay_est'.tr(), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            Text('incident_detail.calculating'.tr(), style: TextStyle(color: Colors.grey[800], fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        )
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Badges Premium
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(16)),
                          child: Row(
                            children: [
                              const Icon(CupertinoIcons.location_solid, color: AppColors.blue, size: 14),
                              const SizedBox(width: 4),
                              Text('incident_detail.badge_gps'.tr(), style: const TextStyle(color: AppColors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(16)),
                          child: Row(
                            children: [
                              const Icon(CupertinoIcons.waveform_path_ecg, color: Colors.green, size: 14),
                              const SizedBox(width: 4),
                              Text('incident_detail.badge_medical'.tr(), style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  Text(
                    'incident_detail.chronology_title'.tr(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      letterSpacing: -0.2,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  timelineAsync.when(
                    data: (pt) {
                      if (pt == null) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            'incident_detail.timeline_load_error'.tr(),
                            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
                          ),
                        );
                      }
                      final events = pt.events;
                      if (events.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            'incident_detail.timeline_empty'.tr(),
                            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
                          ),
                        );
                      }
                      final sourcesPresent = _sourcesInEvents(events);
                      if (_eventSourceFilter != null && !sourcesPresent.contains(_eventSourceFilter)) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _eventSourceFilter = null);
                        });
                      }
                      final filtered = _filteredEvents(events);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildEntityFilterBar(sourcesPresent),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.border),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.shadowColor,
                                  blurRadius: 12,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: filtered.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Text(
                                      'incident_detail.timeline_filter_empty'.tr(),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      for (int i = 0; i < filtered.length; i++)
                                        _buildTimelineEventItem(filtered[i], i == filtered.length - 1),
                                    ],
                                  ),
                          ),
                        ],
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: CupertinoActivityIndicator(color: AppColors.textLight, radius: 12),
                      ),
                    ),
                    error: (_, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'incident_detail.timeline_load_error'.tr(),
                        style: TextStyle(color: AppColors.error.withValues(alpha: 0.85), height: 1.4),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  timelineAsync.maybeWhen(
                    data: (pt) {
                      if (pt == null || pt.reports.isEmpty) return const SizedBox.shrink();
                      // Rapports hospitaliers : visibles pour « Tout » ou filtre Hôpital uniquement.
                      if (_eventSourceFilter != null && _eventSourceFilter != 'hopital') {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'incident_detail.reports_section_title'.tr(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              letterSpacing: -0.2,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...pt.reports.map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _openReportSheet(r),
                                  borderRadius: BorderRadius.circular(14),
                                  splashColor: AppColors.blue.withValues(alpha: 0.06),
                                  highlightColor: AppColors.blue.withValues(alpha: 0.04),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: AppColors.border),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.shadowColor,
                                          blurRadius: 8,
                                          offset: const Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF2F2F7),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(
                                            CupertinoIcons.doc_text_fill,
                                            size: 20,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                r.summary?.trim().isNotEmpty == true
                                                    ? r.summary!
                                                    : 'incident_detail.hospital_report_title'.tr(),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 15,
                                                  height: 1.25,
                                                  color: AppColors.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'incident_detail.view_report'.tr(),
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w400,
                                                  color: AppColors.textSecondary,
                                                ),
                                              ),
                                              if (r.sentAt != null)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 2),
                                                  child: Text(
                                                    _formatEventTime(r.sentAt!),
                                                    style: const TextStyle(fontSize: 12, color: AppColors.textLight),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.chevron_right_rounded, color: AppColors.textLight, size: 22),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),

                  const SizedBox(height: 16),

                  // Recommandations Center
                  if (_incidentData['recommended_actions'] != null && _incidentData['recommended_actions'].toString().isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.orange, size: 18),
                              const SizedBox(width: 8),
                              Text('incident_detail.recommended_actions'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(_incidentData['recommended_actions'].toString(), style: TextStyle(color: Colors.orange[800], fontSize: 14, height: 1.5)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_incidentData['recommended_facility'] != null && _incidentData['recommended_facility'].toString().isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.blue.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.blue.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(CupertinoIcons.building_2_fill, color: AppColors.blue, size: 18),
                              const SizedBox(width: 8),
                              Text('incident_detail.recommended_facility'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.blue)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(_incidentData['recommended_facility'].toString(), style: const TextStyle(color: AppColors.navyDeep, fontSize: 14, height: 1.5, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  
                  // Animated Radar Status Box
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.blue.withValues(alpha: 0.1), Colors.white.withValues(alpha: 0.5)], 
                        begin: Alignment.topCenter, 
                        end: Alignment.bottomCenter
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.blue.withValues(alpha: 0.2)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.blue.withValues(alpha: 0.05),
                          blurRadius: 10,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: Column(
                      children: [
                        Text('incident_detail.sos_alert'.tr(), style: const TextStyle(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Text('incident_detail.current_status'.tr(), style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(
                          status == 'ended' || status == 'resolved'
                              ? 'incident_detail.status_done'.tr()
                              : (status == 'dispatched' || status == 'en_route' ? 'incident_detail.status_approach'.tr() : 'incident_detail.status_analysis'.tr()),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.black87),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            ),
          ),
          
          // Actions: SMS Offline, Red Call Button
          if (_incidentData['status'] != 'arrived' && 
              _incidentData['status'] != 'resolved' && 
              _incidentData['status'] != 'ended')
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -4))],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final body = 'URGENCE ANNULEE - Réf: ${_incidentData['reference'] ?? widget.incidentId}';
                          final uri = Uri.parse('sms:199?body=${Uri.encodeComponent(body)}');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        } catch (e) {
                          debugPrint('[IncidentDetail] SMS launch error: $e');
                        }
                      },
                      icon: const Icon(CupertinoIcons.xmark_circle_fill, size: 16, color: Colors.orange),
                      label: Text(
                        'incident_detail.cancel'.tr(), 
                        style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: Colors.orange.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        backgroundColor: Colors.orange[50],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          final uri = Uri.parse('tel:199');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        } catch (e) {
                          debugPrint('[IncidentDetail] Call launch error: $e');
                        }
                      },
                      icon: const Icon(CupertinoIcons.phone_fill, size: 16, color: Colors.white),
                      label: Text(
                        'incident_detail.call_center'.tr(), 
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
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
