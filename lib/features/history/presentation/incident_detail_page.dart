import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';

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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    if (diff.inDays == 1) return 'Hier';
    return '${date.day.toString().padLeft(2,'0')}/${date.month.toString().padLeft(2,'0')}/${date.year}';
  }

  Widget _buildStatusChip(String? status) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case 'new':
      case 'pending':
        color = Colors.orange;
        label = 'En attente';
        icon = CupertinoIcons.clock_fill;
        break;
      case 'dispatched':
      case 'en_route':
        color = AppColors.blue;
        label = 'Unité en route';
        icon = CupertinoIcons.car_detailed;
        break;
      case 'arrived':
      case 'investigating':
        color = Colors.purple;
        label = 'Intervention en cours';
        icon = CupertinoIcons.group_solid;
        break;
      case 'ended':
      case 'resolved':
      case 'archived':
        color = Colors.green;
        label = 'Terminé';
        icon = CupertinoIcons.checkmark_seal_fill;
        break;
      default:
        color = Colors.grey;
        label = status ?? 'Inconnu';
        icon = CupertinoIcons.info_circle_fill;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _incidentData['status'] as String?;
    final title = _incidentData['title'] as String? ?? 'Signalement';
    final description = _incidentData['description'] as String? ?? '';
    final type = _incidentData['type'] as String? ?? '';
    final mediaUrl = _incidentData['media_url'] as String?;
    
    DateTime? createdAt;
    if (_incidentData['created_at'] != null) {
      createdAt = DateTime.tryParse(_incidentData['created_at']);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Suivi de l\'intervention', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.navyDeep)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.navyDeep),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
             // Header Status
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(
                children: [
                  _buildStatusChip(status),
                  const SizedBox(height: 16),
                  Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.navyDeep)),
                  if (createdAt != null) ...[
                    const SizedBox(height: 8),
                    Text('Initié ${_formatDate(createdAt)}', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                  ]
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Details Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Détails de l\'incident', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    if (type.isNotEmpty) ...[
                       Container(
                         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                         decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                         child: Text(type.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w800, color: Colors.grey[700], fontSize: 11)),
                       ),
                       const SizedBox(height: 12),
                    ],
                    if (description.isNotEmpty)
                      Text(description, style: TextStyle(color: Colors.grey[800], fontSize: 15, height: 1.5))
                    else
                      Text('Aucune description fournie.', style: TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic)),
                    
                    if (mediaUrl != null && mediaUrl.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text('Pièce jointe', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(mediaUrl, width: double.infinity, height: 200, fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: 100, color: Colors.grey[200], child: const Center(child: Icon(CupertinoIcons.photo, color: Colors.grey)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            // Info text
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                'Les informations sur le statut sont synchronisées en temps réel avec le centre opérationnel Sentinel.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
