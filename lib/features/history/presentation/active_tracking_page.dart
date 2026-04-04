import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';

class ActiveTrackingPage extends StatefulWidget {
  const ActiveTrackingPage({super.key});

  @override
  State<ActiveTrackingPage> createState() => _ActiveTrackingPageState();
}

class _ActiveTrackingPageState extends State<ActiveTrackingPage> {
  Map<String, dynamic>? _activeIncident;
  RealtimeChannel? _incidentSub;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchActiveIncident();
  }

  Future<void> _fetchActiveIncident() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Chercher un incident actif
      final response = await Supabase.instance.client
          .from('incidents')
          .select()
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
        _listenToIncident(response['id'].toString());
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('[ActiveTracking] Erreur fetch incident: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _listenToIncident(String incidentId) {
    _incidentSub?.unsubscribe();
    _incidentSub = Supabase.instance.client
        .channel('public:incidents:$incidentId')
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
            if (mounted && payload.newRecord.isNotEmpty) {
              final newStatus = payload.newRecord['status']?.toString();
              setState(() {
                _activeIncident = payload.newRecord;
              });
              if (newStatus == 'ended' || newStatus == 'resolved' || newStatus == 'archived') {
                Future.delayed(const Duration(seconds: 3), () {
                  if (mounted) {
                    _incidentSub?.unsubscribe();
                    setState(() => _activeIncident = null);
                  }
                });
              }
            }
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _incidentSub?.unsubscribe();
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
            const Text(
              "Aucune urgence en cours",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.navyDeep,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              "Vous n'avez pas de signalement SOS actif en ce moment. Vous pouvez dormir sur vos deux oreilles.",
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[600],
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  context.pop();
                  // Rediriger vers l'historique complet (index 2 dans HomePage)
                  // On simule le pop pour revenir à l'accueil, puis l'accueil gère l'état si on veut.
                },
                icon: const Icon(CupertinoIcons.list_bullet, size: 18),
                label: const Text('Voir l\'historique', style: TextStyle(fontWeight: FontWeight.bold)),
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
    final status = _activeIncident!['status']?.toString();
    final address = _activeIncident!['location_address']?.toString() ?? 'Adresse inconnue';
    final recommendedActions = _activeIncident!['recommended_actions']?.toString();
    final recommendedFacility = _activeIncident!['recommended_facility']?.toString();
    
    int statusIndex = 0;
    if (status == 'dispatched' || status == 'en_route') statusIndex = 1;
    if (status == 'arrived' || status == 'investigating') statusIndex = 2;
    if (status == 'ended' || status == 'resolved') statusIndex = 3;

    DateTime? createdAt;
    if (_activeIncident!['created_at'] != null) {
      createdAt = DateTime.tryParse(_activeIncident!['created_at'].toString());
    }
    final timeStr = createdAt != null ? "${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}" : "--:--";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 12, left: 24, right: 24, bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                          const Text('Unité de secours', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Row(
                            children: [
                              const Icon(Icons.verified_user, color: Colors.amber, size: 14),
                              const SizedBox(width: 4),
                              Text('Croix-Rouge', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Délai est.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        Text('Calcul...', style: TextStyle(color: Colors.grey[800], fontWeight: FontWeight.bold, fontSize: 14)),
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
                        child: const Row(
                          children: [
                            Icon(CupertinoIcons.location_solid, color: AppColors.blue, size: 14),
                            SizedBox(width: 4),
                            Text('Véhicule GPS', style: TextStyle(color: AppColors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(16)),
                        child: const Row(
                          children: [
                            Icon(CupertinoIcons.waveform_path_ecg, color: Colors.green, size: 14),
                            SizedBox(width: 4),
                            Text('Liaison Médicale', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                // Trip Info equivalent (Timeline)
                const Text('Historique du suivi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 20),
                _buildTimelineStep('SOS Déclenché', address, timeStr, 'Validé', true, false),
                _buildTimelineStep('Pris en charge', 'Évaluation en cours', '--:--', 'Patienter', statusIndex >= 1, false),
                _buildTimelineStep('En route', 'Unité assignée', '--:--', '', statusIndex >= 2, false),
                _buildTimelineStep('Sur place', 'Restez calme', '--:--', 'Estimé', statusIndex >= 3, true),
                
                const SizedBox(height: 24),
                
                // Recommandations Center
                if (recommendedActions != null && recommendedActions.isNotEmpty) ...[
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
                        const Row(
                          children: [
                            Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.orange, size: 18),
                            SizedBox(width: 8),
                            Text('Actions Recommandées', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(recommendedActions, style: TextStyle(color: Colors.orange[800], fontSize: 14, height: 1.5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                if (recommendedFacility != null && recommendedFacility.isNotEmpty) ...[
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
                        const Row(
                          children: [
                            Icon(CupertinoIcons.building_2_fill, color: AppColors.blue, size: 18),
                            SizedBox(width: 8),
                            Text('Structure de santé orientée', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.blue)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(recommendedFacility, style: const TextStyle(color: AppColors.navyDeep, fontSize: 14, fontWeight: FontWeight.w600)),
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
                      Text('Alerte SOS', style: TextStyle(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      const Text('Statut Actuel', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(status == 'ended' || status == 'resolved' ? 'Terminé' : (status == 'dispatched' ? 'En route' : 'En traitement'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.black87), textAlign: TextAlign.center),
                    ],
                  ),
                ),
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
                      final uri = Uri.parse('sms:112?body=${Uri.encodeComponent("Urgence Etoile Bleue - Suivi Incident")}');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    } catch (e) {
                      debugPrint('[ActiveTracking] SMS launch error: $e');
                    }
                  },
                  icon: const Icon(CupertinoIcons.chat_bubble_text_fill, size: 16, color: Colors.orange),
                  label: const Text('SMS Normal', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
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
                      debugPrint('[ActiveTracking] Call launch error: $e');
                    }
                  },
                  icon: const Icon(CupertinoIcons.phone_fill, size: 16, color: Colors.white),
                  label: const Text('Appel Normal', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Suivi de l\'incident', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.navyDeep)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.navyDeep),
      ),
      body: _isLoading 
        ? const Center(child: CupertinoActivityIndicator())
        : (_activeIncident == null ? _buildEmptyState() : _buildActiveTracker()),
    );
  }
}
