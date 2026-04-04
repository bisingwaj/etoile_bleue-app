import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';

import 'package:url_launcher/url_launcher.dart';

class IncidentDetailPage extends StatefulWidget {
  final String incidentId;
  final Map<String, dynamic> initialData;

  const IncidentDetailPage({
    super.key,
    required this.incidentId,
    required this.initialData,
  });

  @override
  State<IncidentDetailPage> createState() => _IncidentDetailPageState();
}

class _IncidentDetailPageState extends State<IncidentDetailPage> {
  Map<String, dynamic> _incidentData = {};
  RealtimeChannel? _incidentSub;

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
              setState(() {
                _incidentData = payload.newRecord;
              });
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

  @override
  Widget build(BuildContext context) {
    final status = _incidentData['status']?.toString();
    final title = _incidentData['title']?.toString() ?? 'SOS Triage Rapide';
    final address = _incidentData['location_address']?.toString() ?? 'Adresse inconnue';
    
    int statusIndex = 0;
    if (status == 'dispatched' || status == 'en_route') statusIndex = 1;
    if (status == 'arrived' || status == 'investigating') statusIndex = 2;
    if (status == 'ended' || status == 'resolved') statusIndex = 3;

    DateTime? createdAt;
    if (_incidentData['created_at'] != null) {
      createdAt = DateTime.tryParse(_incidentData['created_at'].toString());
    }
    final timeStr = createdAt != null ? "${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}" : "--:--";

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Détails de l\'incident', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.navyDeep)),
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
                      Text('Étoile Bleue', style: AppTextStyles.headlineLarge.copyWith(fontWeight: FontWeight.bold, fontSize: 22)),
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
                      if (status != 'ended' && status != 'resolved')
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
                          const Row(
                            children: [
                              Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.orange, size: 18),
                              SizedBox(width: 8),
                              Text('Actions Recommandées', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
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
                          const Row(
                            children: [
                              Icon(CupertinoIcons.building_2_fill, color: AppColors.blue, size: 18),
                              SizedBox(width: 8),
                              Text('Structure de santé orientée', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.blue)),
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
                        Text('Alerte SOS', style: TextStyle(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        const Text('Statut Actuel', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(status == 'ended' || status == 'resolved' ? 'Terminé' : (status == 'dispatched' ? 'En route' : 'En traitement'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.black87), textAlign: TextAlign.center),
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
                        final uri = Uri.parse('sms:112?body=${Uri.encodeComponent("Urgence Etoile Bleue - Suivi Incident")}');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri);
                        }
                      } catch (e) {
                        debugPrint('[IncidentDetail] SMS launch error: $e');
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
                        debugPrint('[IncidentDetail] Call launch error: $e');
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
      ),
    );
  }
}
