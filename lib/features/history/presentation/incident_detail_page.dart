import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etoile_bleue_mobile/core/providers/dispatch_timeline_provider.dart';
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
  Map<String, dynamic>? _dispatchData;
  RealtimeChannel? _incidentSub;
  RealtimeChannel? _dispatchSub;

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

    _dispatchSub = Supabase.instance.client
        .channel('public:dispatches:${widget.incidentId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'dispatches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'incident_id',
            value: widget.incidentId,
          ),
          callback: (payload) {
            if (mounted && payload.newRecord.isNotEmpty) {
              setState(() => _dispatchData = payload.newRecord);
            }
          },
        )
        .subscribe();

    _fetchDispatchData();
  }

  Future<void> _fetchDispatchData() async {
    try {
      final data = await Supabase.instance.client
          .from('dispatches')
          .select()
          .eq('incident_id', widget.incidentId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data != null && mounted) {
        setState(() => _dispatchData = data);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _incidentSub?.unsubscribe();
    _dispatchSub?.unsubscribe();
    super.dispose();
  }

  Widget _buildTimelineStep(String title, String subtitle, String time, String subtime, bool isActive, bool isLast) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? AppColors.blue : Colors.transparent,
                border: Border.all(
                  color: isActive ? AppColors.blue.withValues(alpha: 0.2) : Colors.grey[300]!,
                  width: isActive ? 4 : 2,
                ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: isActive ? AppColors.blue.withValues(alpha: 0.3) : Colors.grey[200],
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title, 
                style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? Colors.black87 : Colors.grey[600], fontSize: 15)
              ),
              if (subtitle.isNotEmpty)
                Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              if (!isLast) const SizedBox(height: 16),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(time, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            if (subtime.isNotEmpty)
              Text(subtime, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        )
      ],
    );
  }

  Widget _buildTerrainTimelineItem(Map<String, dynamic> item, bool isLast) {
    final type = item['type']?.toString() ?? 'info';
    final title = item['title']?.toString() ?? 'incident_detail.action_default'.tr();
    final content = item['content']?.toString() ?? '';
    final createdAt = DateTime.tryParse(item['created_at']?.toString() ?? '')?.toLocal();
    final timeStr = createdAt != null 
        ? "${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}"
        : '--:--';

    IconData icon;
    Color color;
    switch (type) {
      case 'vitals':
        icon = CupertinoIcons.waveform_path_ecg;
        color = Colors.blue;
        break;
      case 'care':
        icon = CupertinoIcons.bandage;
        color = Colors.green;
        break;
      case 'decision':
        icon = CupertinoIcons.checkmark_circle_fill;
        color = Colors.orange;
        break;
      case 'evaluation':
        icon = CupertinoIcons.doc_text_viewfinder;
        color = Colors.purple;
        break;
      default:
        icon = CupertinoIcons.info_circle_fill;
        color = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(timeStr, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ],
                ),
                if (content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(content, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timelineAsync = ref.watch(dispatchTimelineProvider(widget.incidentId));
    final status = _incidentData['status']?.toString();
    final rawLocation = _incidentData['location_address']?.toString().trim();
    final timeline1Subtitle = (rawLocation != null && rawLocation.isNotEmpty)
        ? 'incident_detail.timeline_1_meta'.tr(namedArgs: {'address': rawLocation})
        : 'incident_detail.timeline_1_sub'.tr();
    
    int statusIndex = 0;
    if (status == 'dispatched' || status == 'en_route') statusIndex = 1;
    if (status == 'arrived' || status == 'investigating') statusIndex = 2;
    if (status == 'ended' || status == 'resolved') statusIndex = 3;

    String formatTime(String? isoString) {
      if (isoString == null) return '--:--';
      final dt = DateTime.tryParse(isoString)?.toLocal();
      if (dt == null) return '--:--';
      return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    }

    final createdAtStr = formatTime(_incidentData['created_at']?.toString());
    final updatedAtStr = formatTime(_incidentData['updated_at']?.toString());
    final resolvedAtStr = formatTime(_incidentData['resolved_at']?.toString());

    final dispatchedAtStr = formatTime(_dispatchData?['dispatched_at']?.toString());
    final arrivedAtStr = formatTime(_dispatchData?['arrived_at']?.toString());
    
    final unitName = _dispatchData?['assigned_structure_name']?.toString() ?? 'incident_detail.coordination_pending'.tr();

    // Step 2 : Prise en charge
    final step2Active = statusIndex >= 1 || _incidentData['assigned_operator_id'] != null;
    final step2Time = step2Active ? (dispatchedAtStr != '--:--' ? dispatchedAtStr : updatedAtStr) : '--:--';

    // Step 3 : En route
    final step3Active = _dispatchData != null || statusIndex >= 1;
    final step3Time = _dispatchData?['dispatched_at'] != null ? dispatchedAtStr : '--:--';

    // Step 4 : Sur place / Résolu
    final step4Active = statusIndex >= 2 || _dispatchData?['arrived_at'] != null;
    final step4Time = _dispatchData?['arrived_at'] != null ? arrivedAtStr : (statusIndex >= 3 ? resolvedAtStr : '--:--');

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
            child: SingleChildScrollView(
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
                  
                  // Trip Info equivalent (Timeline)
                  Text('incident_detail.tracking_title'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 20),
                  _buildTimelineStep(
                    'incident_detail.timeline_1_title'.tr(),
                    timeline1Subtitle,
                    createdAtStr,
                    'incident_detail.validated'.tr(),
                    true,
                    false,
                  ),
                  _buildTimelineStep('incident_detail.timeline_2_title'.tr(), 'incident_detail.timeline_2_sub'.tr(), step2Time, '', step2Active, false),
                  _buildTimelineStep(
                    'incident_detail.timeline_3_title'.tr(),
                    step3Active ? 'incident_detail.timeline_3_sub_active'.tr(namedArgs: {'unit': unitName}) : 'incident_detail.timeline_3_sub_wait'.tr(),
                    step3Time,
                    '',
                    step3Active,
                    false,
                  ),
                  _buildTimelineStep(
                    statusIndex >= 3 ? 'incident_detail.timeline_4_done_title'.tr() : 'incident_detail.timeline_4_active_title'.tr(),
                    statusIndex >= 3 ? 'incident_detail.timeline_4_done_sub'.tr() : 'incident_detail.timeline_4_active_sub'.tr(),
                    step4Time,
                    '',
                    step4Active,
                    true,
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Live terrain actions from dispatch_timeline
                  timelineAsync.when(
                    data: (terrainActions) {
                      if (terrainActions.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(CupertinoIcons.waveform_path_ecg, color: AppColors.blue, size: 20),
                              const SizedBox(width: 8),
                              Text('incident_detail.terrain_title'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('incident_detail.live_badge'.tr(), style: const TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Column(
                              children: [
                                for (int i = 0; i < terrainActions.length; i++)
                                  _buildTerrainTimelineItem(terrainActions[i], i == terrainActions.length - 1),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CupertinoActivityIndicator()),
                    ),
                    error: (e, _) => const SizedBox.shrink(),
                  ),

                  const SizedBox(height: 24),

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
          
          // Actions: SMS Offline, Red Call Button
          Container(
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
                        final uri = Uri.parse('sms:112?body=${Uri.encodeComponent('incident_detail.sms_followup_body'.tr())}');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      } catch (e) {
                        debugPrint('[IncidentDetail] SMS launch error: $e');
                      }
                    },
                    icon: const Icon(CupertinoIcons.chat_bubble_text_fill, size: 16, color: Colors.orange),
                    label: Text('incident_detail.sms_normal'.tr(), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
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
                        final uri = Uri.parse('tel:112');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      } catch (e) {
                        debugPrint('[IncidentDetail] Call launch error: $e');
                      }
                    },
                    icon: const Icon(CupertinoIcons.phone_fill, size: 16, color: Colors.white),
                    label: Text('incident_detail.call_normal'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
        ],
      ),
    );
  }
}
