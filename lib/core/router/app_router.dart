import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/features/splash/presentation/splash_page.dart';
import 'package:etoile_bleue_mobile/features/onboarding/presentation/onboarding_page.dart';
import 'package:etoile_bleue_mobile/features/home/presentation/home_page.dart';
import 'package:etoile_bleue_mobile/features/auth/presentation/login_page.dart';
import 'package:etoile_bleue_mobile/features/auth/presentation/otp_page.dart';
import 'package:etoile_bleue_mobile/features/auth/presentation/register_page.dart';
import 'package:etoile_bleue_mobile/features/calls/presentation/emergency_call_screen.dart';
import 'package:etoile_bleue_mobile/features/auth/providers/auth_provider.dart';

abstract class AppRoutes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const home = '/home';
  static const register = '/register';
  static const login = '/login';
  static const otp = '/otp';
  static const callActive = '/call/active';
}

// The GoRouter is created ONCE and never rebuilt.
// The redirect function checks Supabase session directly to avoid
// subscribing to Riverpod state changes that cause router restarts.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final user = Supabase.instance.client.auth.currentUser;
      final loc = state.matchedLocation;

      // Only block /login and /otp if the user is already authenticated.
      // /register is intentionally NOT blocked: a newly-verified user needs
      // to reach it to complete their profile creation.
      final isStrictAuthScreen = loc == AppRoutes.login || loc == AppRoutes.otp;

      if (user != null && isStrictAuthScreen) {
        final authState = ref.read(authProvider);
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
        builder: (context, state) => const EmergencyCallScreen(),
      ),
    ],
  );
});
