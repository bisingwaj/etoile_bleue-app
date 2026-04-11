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
import 'package:etoile_bleue_mobile/core/services/fcm_service.dart';
import 'package:etoile_bleue_mobile/core/services/cache_service.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/rescuer_gps_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/incoming_call_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/sos_questions_provider.dart';
import 'package:etoile_bleue_mobile/core/services/emergency_call_service.dart';
import 'package:etoile_bleue_mobile/core/widgets/offline_banner.dart';
import 'package:etoile_bleue_mobile/features/calls/presentation/widgets/emergency_call_overlay.dart';
import 'package:etoile_bleue_mobile/features/signalements/domain/signalement_sync_service.dart';

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Parallel initialization of independent SDKs
  await Future.wait<void>([
    dotenv.load(fileName: ".env").catchError((e) {
      debugPrint('[main] dotenv.load failed (missing .env?): $e');
    }),
    Firebase.initializeApp().then((_) {}).catchError((e) {
      debugPrint('[Firebase] Erreur init (google-services.json manquant?) : $e');
    }),
    EasyLocalization.ensureInitialized(),
    CacheService.initialize(),
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]),
  ]);

  // Sequential: depends on dotenv being loaded
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? 'YOUR_SUPABASE_URL',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? 'YOUR_SUPABASE_ANON_KEY',
  );

  await FcmService.initialize();
  await CallKitService.requestPermissions();
  CallForegroundService.initTaskHandler();

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
    onAccepted: (callId, extra) async {
      debugPrint('[main] CallKit accepted: $callId, extra: $extra');
      final state = container.read(callStateProvider);
      
      // If we don't have a channel name, get it from extra
      if (state.channelName == null) {
        final channelName = extra['channelName']?.toString();
        if (channelName != null && channelName.isNotEmpty) {
          debugPrint('[main] Recovered channelName from extra: $channelName');
          container.read(callStateProvider.notifier).setIncomingCall(
            channelName: channelName,
            callHistoryId: callId,
          );
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          container.read(appRouterProvider).go('/call/active');
          debugPrint('[main] Navigated to /call/active');
        } catch (e) {
          debugPrint('[main] Navigation error: $e');
        }
      });
      // Then connect Agora
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
  final FlutterTts _tts = FlutterTts();
  Locale? _lastTtsLocale;

  static const _ttsLocaleMap = {
    'fr': 'fr-FR',
    'en': 'en-US',
    'sw': 'sw-KE',
    'ln': 'fr-FR',
    'kg': 'fr-FR',
    'lu': 'fr-FR',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sosQuestionsProvider.notifier).initialize();
      _syncTtsLocale();
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

  void _syncTtsLocale() {
    final locale = context.locale;
    if (locale != _lastTtsLocale) {
      _lastTtsLocale = locale;
      final ttsLang = _ttsLocaleMap[locale.languageCode] ?? 'fr-FR';
      _tts.setLanguage(ttsLang);
      debugPrint('[TTS] Langue synchronisée: $ttsLang (locale: $locale)');
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncTtsLocale();
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    ref.watch(rescuerGpsProvider);
    ref.watch(incomingCallListenerProvider);
    ref.watch(signalementSyncServiceProvider);

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
        return EmergencyCallOverlay(
          child: OfflineBanner(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
