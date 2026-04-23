import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/locale/app_locale.dart';
import 'package:etoile_bleue_mobile/features/splash/presentation/splash_page.dart';
import 'package:etoile_bleue_mobile/features/onboarding/presentation/onboarding_page.dart';
import 'package:etoile_bleue_mobile/features/legal/presentation/privacy_policy_page.dart';
import 'package:etoile_bleue_mobile/features/home/presentation/home_page.dart';
import 'package:etoile_bleue_mobile/features/auth/presentation/login_page.dart';
import 'package:etoile_bleue_mobile/features/auth/presentation/otp_page.dart';
import 'package:etoile_bleue_mobile/features/auth/presentation/register_page.dart';
import 'package:etoile_bleue_mobile/features/calls/presentation/emergency_call_screen.dart';
import 'package:etoile_bleue_mobile/features/history/presentation/incident_detail_page.dart';
import 'package:etoile_bleue_mobile/features/history/presentation/active_tracking_page.dart';
import 'package:etoile_bleue_mobile/features/home/presentation/notifications_page.dart';
import 'package:etoile_bleue_mobile/features/auth/presentation/logout_screen.dart';
import 'package:etoile_bleue_mobile/features/calls/presentation/blocked_screen.dart';
import 'package:etoile_bleue_mobile/features/signalements/presentation/signalement_flow_page.dart';
import 'package:etoile_bleue_mobile/features/signalements/presentation/signalement_success_page.dart';
import 'package:etoile_bleue_mobile/features/signalements/presentation/signalements_list_page.dart';
import 'package:etoile_bleue_mobile/features/signalements/presentation/signalement_detail_page.dart';
import 'package:etoile_bleue_mobile/features/auth/providers/auth_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/features/home/presentation/full_screen_map_page.dart';

abstract class AppRoutes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const privacyPolicy = '/privacy-policy';
  static const home = '/home';
  static const register = '/register';
  static const login = '/login';
  static const otp = '/otp';
  static const callActive = '/call/active';
  static const incidentDetail = '/incident/:id';
  static const activeTracking = '/active_tracking';
  static const notifications = '/notifications';
  static const logout = '/logout';
  static const blocked = '/blocked';
  static const signalementForm = '/signalement-form';
  static const signalementSuccess = '/signalement-success';
  static const signalements = '/signalements';
  static const signalementDetail = '/signalements/:id';
  static const fullScreenMap = '/full-screen-map';
}

final rootNavigatorKey = GlobalKey<NavigatorState>();

// The GoRouter is created ONCE and never rebuilt.
// The redirect function checks Supabase session directly to avoid
// subscribing to Riverpod state changes that cause router restarts.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    refreshListenable: appLocaleRefreshNotifier,
    redirect: (context, state) {
      final user = Supabase.instance.client.auth.currentUser;
      final loc = state.matchedLocation;

      // Public routes that don't require authentication
      const publicRoutes = {
        AppRoutes.splash,
        AppRoutes.onboarding,
        AppRoutes.privacyPolicy,
        AppRoutes.login,
        AppRoutes.otp,
        AppRoutes.register,
      };

      // Skip splash screen if user is already authenticated.
      // The splash is only useful on cold start without a session.
      if (loc == AppRoutes.splash && user != null) {
        return AppRoutes.home;
      }

      // Redirect unauthenticated users away from protected routes
      if (user == null && !publicRoutes.contains(loc)) {
        return AppRoutes.login;
      }

      // Only block /login and /otp if the user is already authenticated.
      // /register is intentionally NOT blocked: a newly-verified user needs
      // to reach it to complete their profile creation.
      final isStrictAuthScreen = loc == AppRoutes.login || loc == AppRoutes.otp;

      if (user != null && isStrictAuthScreen) {
        final authState = ref.read(authProvider);
        if (!authState.bootstrapped) return null;
        return authState.isNewUser ? AppRoutes.register : AppRoutes.home;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: AppRoutes.privacyPolicy,
        name: 'privacy_policy',
        builder: (context, state) => const PrivacyPolicyPage(),
      ),
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: AppRoutes.register,
        name: 'register',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.otp,
        name: 'otp',
        builder: (context, state) => OtpPage(phoneNumber: state.extra as String? ?? ''),
      ),
      GoRoute(
        path: AppRoutes.callActive,
        name: 'call_active',
        redirect: (context, state) {
          final callState = ref.read(callStateProvider);
          if (!callState.isInCall && callState.status != ActiveCallStatus.connecting) {
            return AppRoutes.home;
          }
          return null;
        },
        builder: (context, state) => const EmergencyCallScreen(),
      ),
      GoRoute(
        path: AppRoutes.incidentDetail,
        name: 'incident_detail',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          // extra may carry pre-fetched data (e.g. from HistoryPage)
          final initialData =
              state.extra is Map<String, dynamic>
                  ? state.extra as Map<String, dynamic>
                  : <String, dynamic>{'id': id};
          return IncidentDetailPage(
            incidentId: id,
            initialData: initialData,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.activeTracking,
        name: 'active_tracking',
        builder: (context, state) => const ActiveTrackingPage(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        name: 'notifications',
        builder: (context, state) => const NotificationsPage(),
      ),
      GoRoute(
        path: AppRoutes.logout,
        name: 'logout',
        builder: (context, state) => const LogoutScreen(),
      ),
      GoRoute(
        path: AppRoutes.blocked,
        name: 'blocked',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final expiresAtStr = extra['expires_at'] as String?;
          final expiresAt = expiresAtStr != null 
              ? DateTime.tryParse(expiresAtStr) ?? DateTime.now() 
              : DateTime.now();
          final reason = extra['reason'] as String? ?? '';
          
          return BlockedScreen(expiresAt: expiresAt, reason: reason);
        },
      ),
      GoRoute(
        path: AppRoutes.signalementForm,
        name: 'signalement_form',
        builder: (context, state) => const SignalementFlowPage(),
      ),
      GoRoute(
        path: AppRoutes.signalementSuccess,
        name: 'signalement_success',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return SignalementSuccessPage(
            reference: extra['reference'] as String? ?? '',
            mediaCount: extra['mediaCount'] as int? ?? 0,
            mediaUploaded: extra['mediaUploaded'] as int? ?? 0,
            pendingSync: extra['pendingSync'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.signalements,
        name: 'signalements',
        builder: (context, state) => const SignalementsListPage(),
      ),
      GoRoute(
        path: AppRoutes.signalementDetail,
        name: 'signalement_detail',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return SignalementDetailPage(signalementId: id);
        },
      ),
      GoRoute(
        path: AppRoutes.fullScreenMap,
        name: 'full_screen_map',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return FullScreenMapPage(
            initialUserPosition: extra?['position'],
          );
        },
      ),
    ],
  );
});
