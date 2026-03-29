import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:etoile_bleue_mobile/core/router/app_router.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'package:etoile_bleue_mobile/core/services/call_foreground_service.dart';
import 'package:etoile_bleue_mobile/core/providers/rescuer_gps_provider.dart';
import 'package:etoile_bleue_mobile/features/calls/presentation/widgets/emergency_call_overlay.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Chargement des variables d'environnement (Sécurité Agora)
  await dotenv.load(fileName: ".env");

  // Force portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ✅ Initialisation de Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? 'YOUR_SUPABASE_URL',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? 'YOUR_SUPABASE_ANON_KEY',
  );

  // ✅ Configuration du Foreground Service Android
  CallForegroundService.initTaskHandler();

  // Initialisation de EasyLocalization
  await EasyLocalization.ensureInitialized();

  // Pre-warming TTS (Zero Latency Boot)
  FlutterTts().setLanguage('fr-FR');

  // StatusBar style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('fr', 'FR'), // Français
        Locale('en', 'US'), // Anglais
        Locale('sw', 'KE'), // Swahili
        Locale('ln', 'CD'), // Lingala
        Locale('kg', 'CD'), // Kikongo
        Locale('lu', 'CD'), // Tshiluba
      ],
      path: 'assets/translations',
      useOnlyLangCode: true,
      fallbackLocale: const Locale('fr', 'FR'),
      child: const ProviderScope(
        child: EtoileBleuApp(),
      ),
    ),
  );
}

class EtoileBleuApp extends ConsumerWidget {
  const EtoileBleuApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    // Fix #4 : Active le suivi GPS si l'utilisateur est un secouriste disponible.
    // Le provider gère lui-même le cycle de vie start/stop.
    ref.watch(rescuerGpsProvider);
    
    return MaterialApp.router(
      title: 'ÉTOILE BLEU',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      // Configuration gérée par EasyLocalization
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: (context, child) {
        return EmergencyCallOverlay(child: child!);
      },
    );
  }
}
