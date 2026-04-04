import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';

class BlockedScreen extends ConsumerStatefulWidget {
  final DateTime expiresAt;
  final String reason;

  const BlockedScreen({
    required this.expiresAt,
    required this.reason,
    super.key,
  });

  @override
  ConsumerState<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends ConsumerState<BlockedScreen> {
  late Timer _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }

  void _updateRemaining() {
    final now = DateTime.now();
    setState(() {
      _remaining = widget.expiresAt.difference(now);
      if (_remaining.isNegative) {
        _remaining = Duration.zero;
        _timer.cancel();
        _checkAndRedirect();
      }
    });
  }

  Future<void> _checkAndRedirect() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      
      final result = await Supabase.instance.client.rpc('is_citizen_blocked', params: {
        'p_citizen_id': user.id,
      });
      
      if (result != null && result['blocked'] == false && mounted) {
        context.go('/home'); // Back to main screen
      }
    } catch (e) {
      debugPrint('[BlockedScreen] Error checking status: $e');
    }
  }

  Future<void> _callSupport() async {
    final uri = Uri.parse('tel:+243810000000'); // Update with real support number
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = _remaining.inDays;
    final hours = _remaining.inHours % 24;
    final minutes = _remaining.inMinutes % 60;
    final seconds = _remaining.inSeconds % 60;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated shield icon
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.8, end: 1.0),
                  duration: const Duration(seconds: 2),
                  curve: Curves.easeInOut,
                  builder: (_, value, child) => Transform.scale(scale: value, child: child),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.shield_rounded, size: 40, color: Colors.red),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Title
                const Text(
                  'Compte temporairement suspendu',
                  style: TextStyle(
                    fontFamily: 'Marianne',
                    fontSize: 22, 
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyDeep,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                
                // Main message
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.orange.withOpacity(0.2)),
                  ),
                  child: const Text(
                    'Votre accès au service SOS est temporairement suspendu suite à une activité inhabituelle détectée sur votre compte.',
                    style: TextStyle(
                      fontFamily: 'Marianne',
                      fontSize: 15, 
                      height: 1.5,
                      color: AppColors.navyDeep,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 32),
                
                // Countdown
                const Text(
                  'Suspension levée dans :', 
                  style: TextStyle(fontFamily: 'Marianne', fontSize: 14, color: Colors.grey)
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTimeUnit(days.toString().padLeft(2, '0'), 'J'),
                    const Text(' : ', style: TextStyle(fontFamily: 'Marianne', fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.navyDeep)),
                    _buildTimeUnit(hours.toString().padLeft(2, '0'), 'H'),
                    const Text(' : ', style: TextStyle(fontFamily: 'Marianne', fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.navyDeep)),
                    _buildTimeUnit(minutes.toString().padLeft(2, '0'), 'M'),
                    const Text(' : ', style: TextStyle(fontFamily: 'Marianne', fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.navyDeep)),
                    _buildTimeUnit(seconds.toString().padLeft(2, '0'), 'S'),
                  ],
                ),
                const SizedBox(height: 32),
                
                // Explanation
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Pourquoi cette mesure ?',
                            style: TextStyle(
                              fontFamily: 'Marianne',
                              fontWeight: FontWeight.bold, 
                              color: Colors.orange[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Les appels abusifs empêchent les personnes en réelle détresse d\'accéder à l\'aide dont elles ont besoin.\n\nChaque faux appel mobilise des ressources qui pourraient sauver des vies.',
                        style: TextStyle(fontFamily: 'Marianne', fontSize: 14, height: 1.5, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Support contact
                Text(
                  'Si vous pensez qu\'il s\'agit d\'une erreur, contactez le support :',
                  style: TextStyle(fontFamily: 'Marianne', fontSize: 13, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _callSupport,
                  child: const Text(
                    '📞 +243 81 000 0000',
                    style: TextStyle(
                      fontFamily: 'Marianne',
                      fontSize: 16, 
                      fontWeight: FontWeight.w600, 
                      color: AppColors.blue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeUnit(String value, String label) {
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.navyDeep,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            value, 
            style: const TextStyle(
              fontFamily: 'Marianne',
              fontSize: 24, 
              fontWeight: FontWeight.bold, 
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label, 
          style: const TextStyle(fontFamily: 'Marianne', fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }
}
