import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/services/fcm_service.dart';

// ══════════════════════════════════════════════════════════════
// AUTH PROVIDER — Twilio Verify OTP → Supabase Session
// ══════════════════════════════════════════════════════════════

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:etoile_bleue_mobile/core/providers/user_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/profile_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/emergency_contacts_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/rescuer_gps_provider.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/core/services/emergency_call_service.dart';

class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final bool isNewUser;
  final bool otpSent;
  final bool bootstrapped;
  final String? phone;
  final String? error;
  final Map<String, dynamic>? user;

  const AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.isNewUser = false,
    this.otpSent = false,
    this.bootstrapped = false,
    this.phone,
    this.error,
    this.user,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    bool? isNewUser,
    bool? otpSent,
    bool? bootstrapped,
    String? phone,
    String? error,
    Map<String, dynamic>? user,
    bool clearError = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isNewUser: isNewUser ?? this.isNewUser,
      otpSent: otpSent ?? this.otpSent,
      bootstrapped: bootstrapped ?? this.bootstrapped,
      phone: phone ?? this.phone,
      error: clearError ? null : (error ?? this.error),
      user: user ?? this.user,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref ref;

  AuthNotifier(this.ref) : super(const AuthState()) {
    _checkExistingSession();
  }

  final _supabase = Supabase.instance.client;

  /// Returns true when the profile row has real first/last name values
  /// (i.e. the user completed the registration wizard).
  static bool isProfileComplete(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    final firstName = profile['first_name']?.toString().trim() ?? '';
    final lastName = profile['last_name']?.toString().trim() ?? '';
    return firstName.isNotEmpty &&
        firstName != 'Citoyen' &&
        lastName.isNotEmpty;
  }

  /// Normalizes invoke() JSON body to a String-keyed map (avoids cast crashes).
  static Map<String, dynamic>? _asJsonMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  /// Extracts a user-facing error message from Edge Function exceptions.
  String _extractError(Object e, String fallback) {
    if (e is FunctionException) {
      final details = e.details;
      if (details is Map && details['error'] != null) {
        return details['error'].toString();
      }
      if (e.reasonPhrase != null && e.reasonPhrase!.isNotEmpty) {
        return e.reasonPhrase!;
      }
    }
    final msg = e.toString().replaceAll('Exception: ', '');
    return msg.isNotEmpty ? msg : fallback;
  }

  Future<void> _checkExistingSession() async {
    try {
      final session = _supabase.auth.currentSession;
      if (session != null) {
        // Force-refresh so the access token is always fresh on startup,
        // even if the app was closed for hours/days.
        try {
          await _supabase.auth.refreshSession();
          debugPrint('[AuthProvider] Session refreshed successfully');
        } catch (e) {
          debugPrint('[AuthProvider] Token refresh failed, signing out: $e');
          await _supabase.auth.signOut();
          state = state.copyWith(bootstrapped: true);
          return;
        }

        final userId = _supabase.auth.currentUser!.id;
        final profile = await _supabase
            .from('users_directory')
            .select('auth_user_id, first_name, last_name, phone, role, created_at')
            .eq('auth_user_id', userId)
            .maybeSingle();

        if (profile != null) {
          final complete = isProfileComplete(profile);
          state = state.copyWith(
            isAuthenticated: complete,
            isNewUser: !complete,
            user: profile,
            bootstrapped: true,
          );
          if (complete) {
            try {
              await _supabase
                  .from('users_directory')
                  .update({
                    'status': 'online',
                    'last_seen_at': DateTime.now().toIso8601String(),
                  })
                  .eq('auth_user_id', userId);
            } catch (e) {
              debugPrint('[AuthProvider] status update failed (non-fatal): $e');
            }
            // Sync FCM token now that user is authenticated
            FcmService.syncToken();
          }
          return;
        }

        // Session exists but no profile row: user verified OTP but
        // registration (complete-profile) never succeeded.
        state = state.copyWith(
          isNewUser: true,
          bootstrapped: true,
        );
        return;
      }
    } catch (e) {
      debugPrint('[AuthProvider] _checkExistingSession error: $e');
    }
    state = state.copyWith(bootstrapped: true);
  }

  /// Step 1: Send SMS OTP via Twilio Verify
  Future<void> sendOtp(String phoneNumber) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      otpSent: false,
      phone: phoneNumber,
    );

    try {
      await _supabase.functions.invoke(
        'twilio-verify',
        body: {'action': 'send', 'phone': phoneNumber},
      );

      state = state.copyWith(isLoading: false, otpSent: true);
    } catch (e) {
      debugPrint('[AuthProvider] sendOtp error: $e');
      state = state.copyWith(
        isLoading: false,
        error: _extractError(e, 'errors.send_code_failed'.tr()),
      );
    }
  }

  /// Step 2: Verify OTP code and establish Supabase session
  Future<bool> verifyOtp(String code) async {
    if (state.phone == null) {
      state = state.copyWith(error: 'errors.no_verification'.tr());
      return false;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final res = await _supabase.functions.invoke(
        'twilio-verify',
        body: {
          'action': 'verify',
          'phone': state.phone!,
          'code': code,
        },
      );

      final data = _asJsonMap(res.data);
      if (data == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'errors.invalid_server_response'.tr(),
        );
        return false;
      }
      final session = _asJsonMap(data['session']);

      if (session == null || session['refresh_token'] == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'errors.invalid_session'.tr(),
        );
        return false;
      }

      await _supabase.auth.setSession(session['refresh_token']);

      final isNew = data['is_new_user'] == true;
      final userMap = _asJsonMap(data['user']);
      final needsRegistration = isNew || !isProfileComplete(userMap);

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: !needsRegistration,
        isNewUser: needsRegistration,
        user: userMap,
      );

      // Sync FCM token after successful login
      FcmService.syncToken();

      return true;
    } catch (e) {
      debugPrint('[AuthProvider] verifyOtp error: $e');
      state = state.copyWith(
        isLoading: false,
        error: _extractError(e, 'errors.invalid_code'.tr()),
      );
      return false;
    }
  }

  /// Step 3: Complete profile for new users via Edge Function
  Future<bool> completeProfile({
    required String firstName,
    required String lastName,
    String? language,
    int? birthYear,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final body = <String, dynamic>{
        'full_name': '$firstName $lastName',
        'first_name': firstName,
        'last_name': lastName,
      };
      if (language != null) body['language'] = language;
      if (birthYear != null) body['date_of_birth'] = '$birthYear-01-01';

      final res = await _supabase.functions.invoke(
        'complete-profile',
        body: body,
      );

      final data = _asJsonMap(res.data);
      if (data == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'errors.invalid_server_response'.tr(),
        );
        return false;
      }

      if (data['success'] == false) {
        final msg = data['error']?.toString() ?? 'errors.profile_update_failed'.tr();
        state = state.copyWith(
          isLoading: false,
          error: msg,
        );
        return false;
      }

      Map<String, dynamic>? userMap = _asJsonMap(data['user']);
      final uid = _supabase.auth.currentUser?.id;
      if (userMap == null && uid != null) {
        userMap = await _supabase
            .from('users_directory')
            .select('auth_user_id, first_name, last_name, phone, role, created_at')
            .eq('auth_user_id', uid)
            .maybeSingle();
      }

      final complete = isProfileComplete(userMap);
      state = state.copyWith(
        isLoading: false,
        isNewUser: !complete,
        isAuthenticated: complete,
        user: userMap,
      );

      if (!complete) {
        state = state.copyWith(
          error: 'errors.profile_not_updated'.tr(),
        );
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('[AuthProvider] completeProfile error: $e');
      state = state.copyWith(
        isLoading: false,
        error: _extractError(e, 'errors.profile_finalize_error'.tr()),
      );
      return false;
    }
  }

  /// Sign out complètement — raccroche tout appel actif avant la déconnexion
  Future<void> signOut() async {
    // 1. Terminate any active call (Agora + CallKit + foreground service)
    try {
      final callState = ref.read(callStateProvider);
      if (callState.isInCall || callState.status == ActiveCallStatus.connecting) {
        await ref.read(callStateProvider.notifier).hangUp();
      }
    } catch (e) {
      debugPrint('[AuthProvider] hangUp during signOut failed (non-fatal): $e');
    }
    ref.read(isCallMinimizedProvider.notifier).state = false;
    ref.invalidate(callStateProvider);

    // 2. Update user status
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      try {
        await _supabase
            .from('users_directory')
            .update({'status': 'offline'})
            .eq('auth_user_id', userId);
      } catch (_) {}
    }

    // 3. Sign out Supabase session
    try {
      await _supabase.auth.signOut(scope: SignOutScope.local);
    } catch (_) {}

    // 4. Clear local storage
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      const storage = FlutterSecureStorage();
      await storage.deleteAll();
    } catch (_) {}

    // 5. Clean RAM providers
    ref.invalidate(userProvider);
    ref.invalidate(profileImageProvider);
    ref.invalidate(emergencyContactsProvider);
    ref.invalidate(rescuerGpsProvider);

    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref),
);
