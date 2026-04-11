import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';

class ActiveTrackingPage extends StatefulWidget {
  const ActiveTrackingPage({super.key});

  @override
  State<ActiveTrackingPage> createState() => _ActiveTrackingPageState();
}

class _ActiveTrackingPageState extends State<ActiveTrackingPage> {
  Map<String, dynamic>? _activeIncident;
  Map<String, dynamic>? _activeDispatch;
  RealtimeChannel? _incidentSub;
  RealtimeChannel? _dispatchSub;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isLaunchingAction = false;

  @override
  void initState() {
    super.initState();
    _fetchActiveIncident();
  }

  Future<void> _fetchActiveIncident() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('incidents')
          .select(
            'id, reference, type, title, description, status, priority, '
            'location_lat, location_lng, location_address, '
            'recommended_actions, recommended_facility, '
            'media_urls, media_type, created_at',
          )
          .eq('citizen_id', uid)
          .inFilter('status', ['new', 'pending', 'dispatched', 'en_route', 'arrived', 'investigating'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _activeIncident = response;
          _isLoading = false;
        });
        final incidentId = response['id'].toString();
        _listenToIncident(incidentId);
        await _fetchDispatch(incidentId);
        _listenToDispatch(incidentId);
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('[ActiveTracking] Erreur fetch incident: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchDispatch(String incidentId) async {
    try {
      final dispatch = await Supabase.instance.client
          .from('dispatches')
          .select('id, status, dispatched_at, en_route_at, arrived_at, unit_id')
          .eq('incident_id', incidentId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (dispatch != null && mounted) {
        setState(() => _activeDispatch = dispatch);
      }
    } catch (e) {
      debugPrint('[ActiveTracking] Erreur fetch dispatch: $e');
    }
  }

  void _listenToIncident(String incidentId) {
    if (_incidentSub != null) {
      Supabase.instance.client.removeChannel(_incidentSub!);
    }
    _incidentSub = Supabase.instance.client
        .channel('tracking:incidents:$incidentId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'incidents',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: incidentId,
          ),
          callback: (payload) {
            if (!mounted || payload.newRecord.isEmpty) return;
            final newStatus = payload.newRecord['status']?.toString();
            setState(() => _activeIncident = {
              ...?_activeIncident,
              ...payload.newRecord,
            });
            if (newStatus == 'ended' || newStatus == 'resolved' || newStatus == 'archived') {
              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) {
                  _incidentSub?.unsubscribe();
                  _dispatchSub?.unsubscribe();
                  setState(() {
                    _activeIncident = null;
                    _activeDispatch = null;
                  });
                }
              });
            }
          },
        )
        .subscribe();
  }

  void _listenToDispatch(String incidentId) {
    if (_dispatchSub != null) {
      Supabase.instance.client.removeChannel(_dispatchSub!);
    }
    _dispatchSub = Supabase.instance.client
        .channel('tracking:dispatches:$incidentId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'dispatches',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'incident_id',
            value: incidentId,
          ),
          callback: (payload) {
            if (!mounted || payload.newRecord.isEmpty) return;
            setState(() => _activeDispatch = {
              ...?_activeDispatch,
              ...payload.newRecord,
            });
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_incidentSub != null) {
      Supabase.instance.client.removeChannel(_incidentSub!);
    }
    if (_dispatchSub != null) {
      Supabase.instance.client.removeChannel(_dispatchSub!);
    }
    super.dispose();
  }

  // ─── Timeline helpers ─────────────────────────────────────────────────────

  Future<void> _launchAction(String url) async {
    if (_isLaunchingAction) return;
    setState(() => _isLaunchingAction = true);
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('home.tracking_action_error'.tr())),
          );
        }
      }
    } catch (e) {
      debugPrint('[ActiveTracking] Action launch error: $e');
    } finally {
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) setState(() => _isLaunchingAction = false);
        });
      }
    }
  }

  String _formatTime(dynamic ts) {
    if (ts == null) return '';
    final dt = ts is String ? DateTime.tryParse(ts)?.toLocal() : null;
    if (dt == null) return '';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Retourne l'index courant (0-3) selon incidents.status
  int _statusIndex(String? status) {
    if (status == 'dispatched') return 1;
    if (status == 'en_route')   return 2;
    if (status == 'arrived' || status == 'investigating') return 3;
    if (status == 'ended' || status == 'resolved')        return 4;
    return 0;
  }

  // ─── Widgets ──────────────────────────────────────────────────────────────

  Widget _buildTimeline(int currentStep, String createdAt) {
    final steps = [
      _TimelineStep(
        title: 'home.tracking_sos_triggered'.tr(),
        subtitle: _activeIncident?['location_address']?.toString() ?? '',
        time: _formatTime(createdAt),
      ),
      _TimelineStep(
        title: 'home.tracking_status_dispatched'.tr(),
        subtitle: 'home.tracking_evaluating'.tr(),
        time: _formatTime(_activeDispatch?['dispatched_at']),
      ),
      _TimelineStep(
        title: 'home.tracking_status_en_route'.tr(),
        subtitle: 'home.step_assigned'.tr(),
        time: _formatTime(_activeDispatch?['en_route_at']),
      ),
      _TimelineStep(
        title: 'home.tracking_status_arrived'.tr(),
        subtitle: 'home.step_calm'.tr(),
        time: _formatTime(_activeDispatch?['arrived_at']),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(steps.length, (i) {
        final step     = steps[i];
        final isPast   = i < currentStep;
        final isCurrent = i == currentStep;
        final isLast   = i == steps.length - 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Indicateur vertical
            Column(
              children: [
                if (isPast)
                  const Icon(CupertinoIcons.checkmark_circle_fill, color: AppColors.blue, size: 20)
                else if (isCurrent)
                  _TrackingPulsingDot()
                else
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey[300]!, width: 2),
                    ),
                  ),
                if (!isLast)
                  Container(
                    width: 3, // Ligne plus épaisse
                    height: isCurrent ? 48 : 36,
                    decoration: BoxDecoration(
                      color: isPast ? AppColors.blue.withValues(alpha: 0.4) : Colors.grey[200],
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            // Contenu : textes toujours visibles
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          step.title,
                          style: TextStyle(
                            fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
                            color: isCurrent
                                ? Colors.black87
                                : isPast
                                    ? Colors.black54
                                    : Colors.grey[400],
                            fontSize: isCurrent ? 16 : 14,
                          ),
                        ),
                        if (step.time.isNotEmpty)
                          Text(
                            step.time,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isCurrent ? Colors.black87 : Colors.grey[500],
                            ),
                          ),
                      ],
                    ),
                    // Sous-titre visible pour les étapes actives ET passées
                    if ((isCurrent || isPast) && step.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        step.subtitle,
                        style: TextStyle(
                          fontSize: 13, 
                          color: isCurrent ? Colors.grey[600] : Colors.grey[400],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    SizedBox(height: isLast ? 0 : 20),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(CupertinoIcons.wifi_exclamationmark, size: 50, color: Colors.redAccent),
            ),
            const SizedBox(height: 32),
            Text(
              'home.tracking_error_title'.tr(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.navyDeep),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'home.tracking_error_body'.tr(),
              style: TextStyle(fontSize: 15, color: Colors.grey[600], height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _hasError = false;
                  });
                  _fetchActiveIncident();
                },
                icon: const Icon(CupertinoIcons.refresh, size: 18),
                label: const Text('Réessayer', style: TextStyle(fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: AppColors.blue.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(CupertinoIcons.checkmark_shield_fill, size: 60, color: AppColors.blue),
            ),
            const SizedBox(height: 32),
            Text(
              'home.tracking_empty_title'.tr(),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.navyDeep),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'home.tracking_empty_body'.tr(),
              style: TextStyle(fontSize: 15, color: Colors.grey[600], height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(CupertinoIcons.list_bullet, size: 18),
                label: Text('home.tracking_history_btn'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: AppColors.blue.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTracker() {
    final status             = _activeIncident!['status']?.toString();
    final recommendedActions = _activeIncident!['recommended_actions']?.toString();
    final recommendedFacility= _activeIncident!['recommended_facility']?.toString();
    final currentStep        = _statusIndex(status);
    final createdAt          = _activeIncident!['created_at']?.toString() ?? '';

    final statusLabel = switch (status) {
      'dispatched'    => 'home.tracking_status_dispatched'.tr(),
      'en_route'      => 'home.tracking_status_en_route'.tr(),
      'arrived'       => 'home.tracking_status_arrived'.tr(),
      'investigating' => 'home.tracking_status_investigating'.tr(),
      'ended'         => 'home.tracking_status_ended'.tr(),
      'resolved'      => 'home.tracking_status_ended'.tr(),
      _               => 'home.tracking_status_processing'.tr(),
    };

    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 12, left: 24, right: 24, bottom: 120), // Bottom padding pour la barre flottante
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Carte Unité
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, spreadRadius: 4, offset: const Offset(0, 8)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.blue.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(CupertinoIcons.person_3_fill, color: AppColors.blue, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('home.rescue_unit'.tr(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.navyDeep)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.verified_user, color: Colors.amber, size: 16),
                                const SizedBox(width: 6),
                                Text('home.tracking_certified'.tr(), style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Statut actuel en badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          statusLabel,
                          style: const TextStyle(
                            color: AppColors.blue,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 2. Carte Timeline
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 24, spreadRadius: 4, offset: const Offset(0, 8)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Évolution de l\'incident',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.navyDeep),
                      ),
                      const SizedBox(height: 24),
                      _buildTimeline(currentStep, createdAt),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 3. Cartes Recommandations dynamiques
                AnimatedSize(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: (recommendedActions != null && recommendedActions.isNotEmpty)
                        ? Container(
                            key: const ValueKey('reco-actions'),
                            padding: const EdgeInsets.all(24),
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.08), // Plus de bordure dure, juste un fond doux
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withValues(alpha: 0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.orange, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Text('home.tracking_first_aid'.tr(), style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.orange, fontSize: 16)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(recommendedActions, style: TextStyle(color: Colors.orange[900], fontSize: 15, height: 1.6, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),

                AnimatedSize(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: (recommendedFacility != null && recommendedFacility.isNotEmpty)
                        ? Container(
                            key: const ValueKey('reco-facility'),
                            padding: const EdgeInsets.all(24),
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: AppColors.blue.withValues(alpha: 0.08), // Sans bordure
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.blue.withValues(alpha: 0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(CupertinoIcons.building_2_fill, color: AppColors.blue, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Text('home.tracking_facility'.tr(), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.blue, fontSize: 16)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(recommendedFacility, style: const TextStyle(color: AppColors.navyDeep, fontSize: 15, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 4. Barre de boutons flottante
        Positioned(
          left: 24,
          right: 24,
          bottom: 24,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32), // Coins très arrondis
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 30, spreadRadius: 5, offset: const Offset(0, 10)),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextButton.icon(
                    onPressed: () => _launchAction('sms:112?body=${Uri.encodeComponent("Urgence Etoile Bleue - Suivi Incident")}'),
                    icon: const Icon(CupertinoIcons.chat_bubble_text_fill, size: 22, color: Colors.orange),
                    label: const Text('SMS', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w800, fontSize: 16)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      backgroundColor: Colors.orange.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: ElevatedButton(
                    onPressed: () => _launchAction('tel:112'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(CupertinoIcons.phone_fill, size: 22, color: Colors.white),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('home.tracking_call_112'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // Fond très clair
      appBar: AppBar(
        title: Text(
          'home.track_timeline'.tr(),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.navyDeep),
        ),
        backgroundColor: Colors.transparent, // AppBar transparente
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.navyDeep),
      ),
      body: _isLoading
          ? const Center(child: CupertinoActivityIndicator())
          : _hasError 
              ? _buildErrorState()
              : (_activeIncident == null ? _buildEmptyState() : _buildActiveTracker()),
    );
  }
}

// ─── Data model simple pour les étapes ───────────────────────────────────────

class _TimelineStep {
  final String title;
  final String subtitle;
  final String time;

  const _TimelineStep({required this.title, required this.subtitle, required this.time});
}

// ─── Point pulsant pour l'étape active ───────────────────────────────────────

class _TrackingPulsingDot extends StatefulWidget {
  @override
  State<_TrackingPulsingDot> createState() => _TrackingPulsingDotState();
}

class _TrackingPulsingDotState extends State<_TrackingPulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _scale = Tween(begin: 0.8, end: 1.2).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.blue,
          boxShadow: [
            BoxShadow(color: AppColors.blue.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 2),
          ],
        ),
      ),
    );
  }
}
