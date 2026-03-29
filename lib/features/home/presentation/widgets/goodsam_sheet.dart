import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';

import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';

class GoodSamSheet extends StatefulWidget {
  final VoidCallback onCancel;
  const GoodSamSheet({super.key, required this.onCancel});

  @override
  State<GoodSamSheet> createState() => _GoodSamSheetState();
}

enum SamState { searching, found, arriving }

class _GoodSamSheetState extends State<GoodSamSheet> with SingleTickerProviderStateMixin {
  late AnimationController _radarController;
  SamState _state = SamState.searching;
  Timer? _simTimer;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    
    _simTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _state = SamState.found);
      _simTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _state = SamState.arriving);
      });
    });
  }

  @override
  void dispose() {
    _radarController.dispose();
    _simTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 24),
            Text(
              _state == SamState.searching ? 'Recherche de Secouristes...' : 'Secouriste en Route !',
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineLarge.copyWith(fontWeight: FontWeight.w900, fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              _state == SamState.searching 
                ? 'Alerte silencieuse envoyée aux volontaires certifiés dans un rayon de 500m.' 
                : 'Un bénévole médical arrive pour vous faire les premiers soins avant l\'ambulance.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 15),
            ),
            const SizedBox(height: 40),

            // Radar Map UI
            SizedBox(
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                   // The Radar Rings
                  if (_state == SamState.searching)
                    ...List.generate(3, (index) {
                      return AnimatedBuilder(
                        animation: _radarController,
                        builder: (context, child) {
                          double value = (_radarController.value - (index * 0.3)).clamp(0.0, 1.0);
                          return Transform.scale(
                            scale: 1.0 + (value * 2),
                            child: Opacity(
                              opacity: 1.0 - value,
                              child: Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.blue, width: 2),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }),
                    
                  // Center User Icon
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: _state == SamState.searching ? AppColors.blue : Colors.green,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: (_state == SamState.searching ? AppColors.blue : Colors.green).withOpacity(0.3), blurRadius: 20)],
                    ),
                    child: Icon(
                      _state == SamState.searching ? CupertinoIcons.location_fill : CupertinoIcons.checkmark_alt,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),

                  // Rescuer Icons (Mocked)
                  if (_state != SamState.searching)
                    Positioned(
                      top: 20,
                      right: 50,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.elasticOut,
                        builder: (context, val, child) {
                          return Transform.scale(
                            scale: val,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
                              ),
                              child: const Icon(CupertinoIcons.heart_fill, color: Colors.red, size: 28),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            
            // Rescuer Profile Card
            if (_state != SamState.searching)
              AnimatedOpacity(
                opacity: _state != SamState.searching ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey[200]!),
                    boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, 10))],
                  ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: AppColors.blue.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(CupertinoIcons.person_fill, color: AppColors.blue),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Dr. Jonathan M.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  Text('Médecin Urgentiste Volontaire', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(12)),
                              child: const Text('2 min', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                            )
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  // Action pour voir le profil détaillé
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: Colors.transparent,
                                    builder: (ctx) => Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
                                      ),
                                      child: SafeArea(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
                                            const SizedBox(height: 24),
                                            const CircleAvatar(radius: 40, backgroundColor: AppColors.blue, child: Icon(CupertinoIcons.person_fill, size: 40, color: Colors.white)),
                                            const SizedBox(height: 16),
                                            const Text('Dr. Jonathan M.', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Marianne', fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.navyDeep)),
                                            const SizedBox(height: 8),
                                            const Text('Médecin Urgentiste Volontaire - CHU', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16)),
                                            const SizedBox(height: 24),
                                            const Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                              children: [
                                                Column(children: [Text('45', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.navyDeep)), Text('Interventions', style: TextStyle(color: Colors.grey))]),
                                                Column(children: [Text('4.9', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.navyDeep)), Text('Évaluation', style: TextStyle(color: Colors.grey))]),
                                                Column(children: [Text('200m', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.navyDeep)), Text('Distance', style: TextStyle(color: Colors.grey))]),
                                              ],
                                            ),
                                            const SizedBox(height: 32),
                                            ElevatedButton(
                                              onPressed: () => Navigator.pop(ctx),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppColors.blue, padding: const EdgeInsets.symmetric(vertical: 16),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                              ),
                                              child: const Text('FERMER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                            )
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  side: BorderSide(color: Colors.grey[300]!),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('VOIR PROFIL', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  // Action pour appeler le secouriste
                                  final uri = Uri.parse('tel:+243990000000');
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                icon: const Icon(CupertinoIcons.phone_fill, size: 18),
                                label: const Text('APPELER', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                ),
              ),
            
            const SizedBox(height: 32),
            TextButton(
              onPressed: () {
                 if (_state == SamState.searching) {
                   widget.onCancel();
                   Navigator.pop(context);
                 } else {
                   // If already found, close and consider it active
                   Navigator.pop(context);
                 }
              },
              child: Text(_state == SamState.searching ? 'ANNULER LA RECHERCHE' : 'FERMER', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
