import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'package:etoile_bleue_mobile/core/router/app_router.dart';

/// Onboarding structuré :
/// - Fonds colorés dynamiques selon la page
/// - SVGs rigoureusement encadrés
/// - Transitions ultra-fluides (Color.lerp + AnimatedContainer)
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pageController = PageController();
  double _currentPage = 0.0;

  static const List<Color> _bgColors = [
    Color(0xFF4A51C5), // Bleu-violet (Slide 1)
    Color(0xFFE36463), // Rouge corail (Slide 2)
    Color(0xFF1E88E5), // Bleu clair (Slide 3)
  ];

  static const _slides = [
    _OnboardingSlide(
      imagePath: 'assets/images/onboarding/onboarding_1.svg',
      titleKey: 'onboarding.slide1_title',
      subtitleKey: 'onboarding.slide1_desc',
    ),
    _OnboardingSlide(
      imagePath: 'assets/images/onboarding/onboarding_2.svg',
      titleKey: 'onboarding.slide2_title',
      subtitleKey: 'onboarding.slide2_desc',
    ),
    _OnboardingSlide(
      imagePath: 'assets/images/onboarding/onboarding_3.svg',
      titleKey: 'onboarding.slide3_title',
      subtitleKey: 'onboarding.slide3_desc',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      setState(() {
        _currentPage = _pageController.page ?? 0.0;
      });
    });
  }


  void _next() async {
    final nextIndex = _currentPage.round() + 1;
    if (nextIndex < _slides.length) {
      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.fastOutSlowIn,
      );
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasSeenOnboarding', true);
      if (mounted) context.go(AppRoutes.login);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Color _getCurrentBackgroundColor() {
    if (_currentPage <= 0.0) return _bgColors[0];
    if (_currentPage >= _bgColors.length - 1) return _bgColors.last;

    int lowerIndex = _currentPage.floor();
    int upperIndex = lowerIndex + 1;
    double t = _currentPage - lowerIndex;

    return Color.lerp(_bgColors[lowerIndex], _bgColors[upperIndex], t) ?? _bgColors[lowerIndex];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _getCurrentBackgroundColor(),
      body: SafeArea(
        child: Column(
          children: [
            // ─── SLIDES (Strictement bornées) ──────────────────────
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                itemBuilder: (context, i) => _SlideView(slide: _slides[i]),
              ),
            ),

            // ─── BOTTOM CONTROLS (Dots + Button) ───────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                   // Indicateurs
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slides.length,
                      (i) {
                        double diff = (_currentPage - i).abs();
                        double width = diff < 0.5 ? 32.0 : 8.0;
                        double alpha = diff < 0.5 ? 1.0 : 0.3;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: width,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: alpha),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Pill Button Blanc
                  FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: _getCurrentBackgroundColor(), // Texte de la couleur du fond actif
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      textStyle: const TextStyle(
                        fontFamily: 'Marianne',
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _currentPage.round() < _slides.length - 1
                              ? 'onboarding.next'.tr()
                              : 'onboarding.get_started'.tr(),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        const Icon(Icons.arrow_forward),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide {
  final String imagePath;
  final String titleKey;
  final String subtitleKey;

  const _OnboardingSlide({
    required this.imagePath,
    required this.titleKey,
    required this.subtitleKey,
  });
}

class _SlideView extends StatelessWidget {
  final _OnboardingSlide slide;

  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, // Alignement structuré à gauche
        children: [
          // Illustration SVG (bornée pour ne jamais déborder)
          Expanded(
            flex: 6,
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300), 
                child: SizedBox.expand(
                  child: SvgPicture.asset(
                    slide.imagePath,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          
          // Texte et Titre en bas (Typography forte blanche)
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  slide.titleKey.tr(),
                  style: OnboardingStyles.onboardingTitle,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  slide.subtitleKey.tr(),
                  style: OnboardingStyles.onboardingBody,
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Styles locaux pour l'onboarding Swiss Design (Fond foncé)
abstract class OnboardingStyles {
  // Titre énorme, très gras, blanc, interligne serré
  static const onboardingTitle = TextStyle(
    fontFamily: 'Marianne',
    fontSize: 44,
    fontWeight: FontWeight.w900,
    color: Colors.white,
    height: 1.0,
    letterSpacing: -1.5,
  );

  // Sous-titre lisible, neutre, blanc cassé
  static const onboardingBody = TextStyle(
    fontFamily: 'Marianne',
    fontSize: 18,
    fontWeight: FontWeight.w400,
    color: Color(0xE6FFFFFF), // Blanc légerement transparent pour contraste
    height: 1.4,
  );
}
