import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:etoile_bleue_mobile/core/router/app_router.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'package:etoile_bleue_mobile/core/services/call_foreground_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:etoile_bleue_mobile/core/services/callkit_service.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/rescuer_gps_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/incoming_call_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/sos_questions_provider.dart';
import 'package:etoile_bleue_mobile/core/services/emergency_call_service.dart';
import 'package:etoile_bleue_mobile/features/calls/presentation/widgets/emergency_call_overlay.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('[main] dotenv.load failed (missing .env?): $e');
  }

  // Configuration Firebase pour FCM
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('[Firebase] Erreur init (google-services.json manquant?) : $e');
  }

  // Requête des permissions pour recevoir les appels en premier plan/arrière plan (Android 13+)
  await CallKitService.requestPermissions();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? 'YOUR_SUPABASE_URL',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? 'YOUR_SUPABASE_ANON_KEY',
  );

  CallForegroundService.initTaskHandler();

  await EasyLocalization.ensureInitialized();

  FlutterTts().setLanguage('fr-FR');

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  final container = ProviderContainer();

  _setupCallKitListener(container);
  _setupForegroundHangupListener(container);

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('en', 'US'),
        Locale('sw', 'KE'),
        Locale('ln', 'CD'),
        Locale('kg', 'CD'),
        Locale('lu', 'CD'),
      ],
      path: 'assets/translations',
      useOnlyLangCode: true,
      fallbackLocale: const Locale('fr', 'FR'),
      child: UncontrolledProviderScope(
        container: container,
        child: const EtoileBleuApp(),
      ),
    ),
  );
}

/// Routes native CallKit accept/decline/end events to callStateProvider.
void _setupCallKitListener(ProviderContainer container) {
  CallKitService.listenToCallEvents(
    onAccepted: (callId) async {
      debugPrint('[main] CallKit accepted: $callId');
      // Navigate FIRST so the user sees the call screen immediately
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          container.read(appRouterProvider).go('/call/active');
          debugPrint('[main] Navigated to /call/active');
        } catch (e) {
          debugPrint('[main] Navigation error: $e');
        }
      });
      // Then connect Agora in the background
      try {
        await container.read(callStateProvider.notifier).answerIncomingCall();
        debugPrint('[main] answerIncomingCall completed successfully');
      } catch (e) {
        debugPrint('[main] answerIncomingCall FAILED: $e');
      }
    },
    onDeclined: (callId) {
      debugPrint('[main] CallKit declined: $callId');
      container.read(callStateProvider.notifier).rejectIncomingCall();
    },
    onEnded: (callId) {
      debugPrint('[main] CallKit ended: $callId');
      final state = container.read(callStateProvider);
      if (state.isInCall) {
        container.read(callStateProvider.notifier).hangUp();
      }
    },
    onTimeout: (callId) {
      debugPrint('[main] CallKit timeout: $callId');
      final state = container.read(callStateProvider);
      if (state.status == ActiveCallStatus.incomingRinging) {
        container.read(callStateProvider.notifier).rejectIncomingCall();
      }
    },
  );
}

/// Listens for the foreground notification "Raccrocher" button tap.
void _setupForegroundHangupListener(ProviderContainer container) {
  FlutterForegroundTask.addTaskDataCallback((data) {
    if (data is String && data == 'btn_end_call') {
      debugPrint('[main] Foreground notification hangup received');
      final state = container.read(callStateProvider);
      if (state.isInCall || state.status == ActiveCallStatus.connecting) {
        container.read(callStateProvider.notifier).hangUp();
      }
    }
  });
}

class EtoileBleuApp extends ConsumerStatefulWidget {
  const EtoileBleuApp({super.key});

  @override
  ConsumerState<EtoileBleuApp> createState() => _EtoileBleuAppState();
}

class _EtoileBleuAppState extends ConsumerState<EtoileBleuApp>
    with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sosQuestionsProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Quand l'app revient au premier plan, si un appel est actif,
  /// on restaure automatiquement l'écran d'appel.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final callState = ref.read(callStateProvider);
      if (callState.isInCall) {
        ref.read(isCallMinimizedProvider.notifier).state = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            ref.read(appRouterProvider).go('/call/active');
          } catch (e) {
            debugPrint('[AppLifecycle] Navigation to /call/active failed: $e');
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    ref.watch(rescuerGpsProvider);
    ref.watch(incomingCallListenerProvider);

    return MaterialApp.router(
      title: 'ÉTOILE BLEU',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      builder: (context, child) {
        return EmergencyCallOverlay(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
