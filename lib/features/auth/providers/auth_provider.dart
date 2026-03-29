import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ══════════════════════════════════════════════════════════════
// AUTH PROVIDER — Twilio Verify OTP → Supabase Session
// ══════════════════════════════════════════════════════════════

class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final bool isNewUser;
  final bool otpSent;
  final String? phone;
  final String? error;
  final Map<String, dynamic>? user;

  const AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.isNewUser = false,
    this.otpSent = false,
    this.phone,
    this.error,
    this.user,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    bool? isNewUser,
    bool? otpSent,
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
      phone: phone ?? this.phone,
      error: clearError ? null : (error ?? this.error),
      user: user ?? this.user,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _checkExistingSession();
  }

  final _supabase = Supabase.instance.client;

  Future<void> _checkExistingSession() async {
    final session = _supabase.auth.currentSession;
    if (session != null) {
      final userId = session.user.id;
      final profile = await _supabase
          .from('users_directory')
          .select()
          .eq('auth_user_id', userId)
          .maybeSingle();

      if (profile != null) {
        state = state.copyWith(
          isAuthenticated: true,
          user: profile,
        );
        await _supabase
            .from('users_directory')
            .update({
              'status': 'online',
              'last_seen_at': DateTime.now().toIso8601String(),
            })
            .eq('auth_user_id', userId);
      }
    }
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
      final res = await _supabase.functions.invoke(
        'twilio-verify',
        body: {'action': 'send', 'phone': phoneNumber},
      );

      if (res.status != 200) {
        final error = res.data is Map ? res.data['error'] : 'Erreur inconnue';
        state = state.copyWith(isLoading: false, error: error.toString());
        return;
      }

      state = state.copyWith(isLoading: false, otpSent: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Erreur: $e');
    }
  }

  /// Step 2: Verify OTP code and establish Supabase session
  Future<bool> verifyOtp(String code) async {
    if (state.phone == null) {
      state = state.copyWith(error: 'Aucune vérification en cours');
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

      if (res.status != 200) {
        final error = res.data is Map ? res.data['error'] : 'Code invalide';
        state = state.copyWith(isLoading: false, error: error.toString());
        return false;
      }

      final data = res.data as Map<String, dynamic>;
      final session = data['session'] as Map<String, dynamic>?;

      if (session == null || session['access_token'] == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'Session invalide',
        );
        return false;
      }

      await _supabase.auth.setSession(session['access_token']);

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        isNewUser: data['is_new_user'] == true,
        user: data['user'] as Map<String, dynamic>?,
      );

      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Code invalide');
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

      if (res.status != 200) {
        final error = res.data is Map ? res.data['error'] : 'Erreur';
        state = state.copyWith(isLoading: false, error: error.toString());
        return false;
      }

      final data = res.data as Map<String, dynamic>;
      state = state.copyWith(
        isLoading: false,
        isNewUser: false,
        user: data['user'] as Map<String, dynamic>?,
      );

      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Erreur: $e');
      return false;
    }
  }

  /// Sign out
  Future<void> signOut() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      await _supabase
          .from('users_directory')
          .update({'status': 'offline'})
          .eq('auth_user_id', userId);
    }

    await _supabase.auth.signOut();

    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
