import 'package:flutter/material.dart';


/// Système de design ÉTOILE BLEU
/// Basé sur l'analyse des maquettes de référence
abstract class AppColors {
  // --- NOUVEAUX TOKENS APPLE/FINTECH ---
  static const primaryAccent = Color(0xFF000000); 
  static const sosGradientStart = Color(0xFF8A2387); 
  static const sosGradientMiddle = Color(0xFFE94057); 
  static const sosGradientEnd = Color(0xFFF27121); 

  static const textPrimary = Color(0xFF1D1D1F); 
  static const textSecondary = Color(0xFF86868B); 
  static const textLight = Color(0xFFA1A1A6);

  static const background = Color(0xFFF5F5F7); 
  static const surface = Color(0xFFFFFFFF); 
  static const border = Color(0xFFE5E5EA); 

  static const shadowColor = Color(0x0A000000); 

  // --- LEGACY TOKENS (Pour les autres pages en attente de refonte) ---
  static const blue = Color(0xFF1565C0);       
  static const yellow = Color(0xFFF9A825);     
  static const red = Color(0xFFE53935);        
  static const navyDeep = Color(0xFF0A1045);   
  static const navy = Color(0xFF0D1533);       
  static const white = Color(0xFFFFFFFF);
  static const success = Color(0xFF34C759);
  static const error = Color(0xFFFF3B30);
  static const warning = Color(0xFFFF9500);
}

abstract class AppTextStyles {
  /// Display mega — Titre splash (ÉTOILE BLEU.)
  static TextStyle get displayHero => const TextStyle(
        fontFamily: 'Marianne',
        fontSize: 72,
        fontWeight: FontWeight.w900,
        height: 0.92,
        color: AppColors.navyDeep,
        letterSpacing: -2.0,
      );

  /// Grand titre d'écran
  static TextStyle get headlineLarge => const TextStyle(
        fontFamily: 'Marianne',
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: AppColors.navy,
        letterSpacing: -0.5,
      );

  /// Titre de section
  static TextStyle get titleMedium => const TextStyle(
        fontFamily: 'Marianne',
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.navy,
      );

  /// Corps de texte
  static TextStyle get bodyLarge => const TextStyle(
        fontFamily: 'Marianne',
        fontSize: 18,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
        height: 1.5,
      );

  /// Légende / mention légale
  static TextStyle get caption => const TextStyle(
        fontFamily: 'Marianne',
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: AppColors.textLight,
        height: 1.5,
      );
}

abstract class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 36.0;
  static const double xxl = 60.0;
}

abstract class AppRadius {
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 20.0;
  static const double pill = 50.0;
}

class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.blue,
          brightness: Brightness.light,
          surface: AppColors.white,
        ),
        scaffoldBackgroundColor: AppColors.white,
        fontFamily: 'Marianne',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          iconTheme: IconThemeData(color: AppColors.navy),
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.blue,
          brightness: Brightness.dark,
          surface: const Color(0xFF000000), // AMOLED True Black
        ),
        scaffoldBackgroundColor: const Color(0xFF000000),
        fontFamily: 'Marianne',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          iconTheme: IconThemeData(color: Colors.white),
        ),
      );
}
