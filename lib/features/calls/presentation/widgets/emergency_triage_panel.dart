import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etoile_bleue_mobile/core/providers/agora_provider.dart';
import 'package:etoile_bleue_mobile/core/services/emergency_call_service.dart';

class EmergencyTriagePanel extends ConsumerStatefulWidget {
  const EmergencyTriagePanel({super.key});

  @override
  ConsumerState<EmergencyTriagePanel> createState() => _EmergencyTriagePanelState();
}

class _EmergencyTriagePanelState extends ConsumerState<EmergencyTriagePanel> {
  int _step = 0;

  final Map<String, dynamic> _triageData = {};

  void _nextStep(String key, dynamic value) async {
    final session = ref.read(callSessionProvider);

    setState(() {
      _triageData[key] = value;
      _step++;
    });

    if (session.channelId.isNotEmpty) {
      await ref.read(emergencyCallServiceProvider).updateTriageData(session.channelId, _triageData);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_step >= 3) {
      return _buildCompletionCard();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.0, 0.2), end: Offset.zero).animate(animation),
            child: child,
          ),
        );
      },
      child: Container(
        key: ValueKey<int>(_step),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white24),
        ),
        child: _buildCurrentStep(),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 0:
         return Column(
           crossAxisAlignment: CrossAxisAlignment.stretch,
           mainAxisSize: MainAxisSize.min,
           children: [
             const Text('Nature de l\'urgence ?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
             const SizedBox(height: 12),
             Wrap(
               spacing: 8,
               runSpacing: 8,
               children: [
                 _buildOptionChip('Malaise', () => _nextStep('category', 'Malaise')),
                 _buildOptionChip('Accident', () => _nextStep('category', 'Accident')),
                 _buildOptionChip('Agressions', () => _nextStep('category', 'Agressions')),
                 _buildOptionChip('Incendie', () => _nextStep('category', 'Incendie')),
                 _buildOptionChip('Autre', () => _nextStep('category', 'Autre')),
               ],
             )
           ],
         );
      case 1:
         return Column(
           crossAxisAlignment: CrossAxisAlignment.stretch,
           mainAxisSize: MainAxisSize.min,
           children: [
             const Text('La victime est-elle consciente ?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
             const SizedBox(height: 12),
             Row(
               children: [
                 Expanded(child: _buildOptionChip('Oui, répond', () => _nextStep('isConscious', true), color: Colors.green)),
                 const SizedBox(width: 12),
                 Expanded(child: _buildOptionChip('Non', () => _nextStep('isConscious', false), color: Colors.red)),
               ],
             )
           ],
         );
      case 2:
         return Column(
           crossAxisAlignment: CrossAxisAlignment.stretch,
           mainAxisSize: MainAxisSize.min,
           children: [
             const Text('La victime respire-t-elle ?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
             const SizedBox(height: 12),
             Row(
               children: [
                 Expanded(child: _buildOptionChip('Oui, respire', () => _nextStep('isBreathing', true), color: Colors.green)),
                 const SizedBox(width: 12),
                 Expanded(child: _buildOptionChip('Non', () => _nextStep('isBreathing', false), color: Colors.red)),
               ],
             )
           ],
         );
      default:
         return const SizedBox();
    }
  }

  Widget _buildCompletionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
           const Icon(CupertinoIcons.checkmark_seal_fill, color: Colors.green),
           const SizedBox(width: 12),
           const Expanded(
              child: Text(
                 'Informations transmises au centre d\'appel.',
                 style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
              ),
           )
        ],
      )
    );
  }

  Widget _buildOptionChip(String label, VoidCallback onTap, {Color color = Colors.blue}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
