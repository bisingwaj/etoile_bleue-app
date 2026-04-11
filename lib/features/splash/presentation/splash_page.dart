import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'package:etoile_bleue_mobile/core/router/app_router.dart';
import 'package:etoile_bleue_mobile/features/auth/providers/auth_provider.dart';

/// Splash Screen — ÉTOILE BLEUE
/// Design 100% fidèle à la maquette Splashscreen-1.png :
/// Fond blanc, bandeau SVG officiel (bandoncouleur.svg), 
/// titre ÉTOILE BLEUE en Marianne ultra-bold,
/// et pied de page contextualisé.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  Timer? _navTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 1.0, curve: Curves.easeIn),
      ),
    );

    _controller.forward();


    // Navigation dynamique après 3s
    _navTimer = Timer(const Duration(milliseconds: 3000), () async {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;

      if (!mounted) return;

      if (!hasSeenOnboarding) {
        context.go(AppRoutes.onboarding);
        return;
      }

      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        context.go(AppRoutes.login);
        return;
      }

      try {
        final profile = await Supabase.instance.client
            .from('users_directory')
            .select('auth_user_id, first_name, last_name, phone, role, ville, commune, created_at')
            .eq('auth_user_id', currentUser.id)
            .maybeSingle();

        if (mounted) {
          if (profile != null && AuthNotifier.isProfileComplete(profile)) {
            context.go(AppRoutes.home);
          } else {
            context.go(AppRoutes.register);
          }
        }
      } catch (e) {
        debugPrint('[Splash] profile fetch error: $e');
        if (mounted) context.go(AppRoutes.login);
      }
    });
  }

  @override
  void dispose() {
    _navTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── Zone principale (bandeau SVG + titre) ──────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Spacer(),
                      // Bandeau SVG officiel (Couleurs RDC + étoile)
                      SvgPicture.asset(
                        'assets/images/bandoncouleur.svg',
                        width: 146,
                        height: 53,
                      ),

                      const SizedBox(height: AppSpacing.lg),

                      // Titre ÉTOILE BLEUE
                      Text(
                        'ÉTOILE\nBLEUE',
                        style: AppTextStyles.displayHero.copyWith(
                          fontFamily: 'Marianne',
                          fontSize: 64, // Ajusté pour mobile proportionnellement
                        ),
                      ),
                      
                      const SizedBox(height: AppSpacing.md),

                      // Sous-titre graphique adapté au contexte médical
                      Text(
                        'splash.subtitle'.tr(),
                        style: AppTextStyles.titleMedium.copyWith(
                          fontFamily: 'Marianne',
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          color: AppColors.navy,
                          height: 1.3,
                        ),
                      ),
                      
                      const Spacer(),
                    ],
                  ),
                ),
              ),

              // ─── Footer : Croix rouge + texte officiel ───────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Croix rouge épaisse dessinée fidèlement à la maquette
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(width: 8, height: 24, color: AppColors.red),
                          Container(width: 24, height: 8, color: AppColors.red),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    
                    // Texte officiel du Ministère
                    Text(
                      'splash.footer'.tr(),
                      style: AppTextStyles.caption.copyWith(
                        fontFamily: 'Marianne',
                        fontSize: 12,
                        color: const Color(0xFF6B7A9E), // Gris subtil similaire à la maquette
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
