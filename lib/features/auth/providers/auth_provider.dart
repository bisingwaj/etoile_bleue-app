import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// ══════════════════════════════════════════════════════════════
// AUTH PROVIDER — Firebase SMS OTP → Supabase Session
// ══════════════════════════════════════════════════════════════

class AuthState {
  final bool isLoading;
  final bool isAuthenticated;
  final bool isNewUser;
  final String? error;
  final String? verificationId;
  final Map<String, dynamic>? user;

  const AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.isNewUser = false,
    this.error,
    this.verificationId,
    this.user,
  });

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    bool? isNewUser,
    String? error,
    String? verificationId,
    Map<String, dynamic>? user,
    bool resetVerificationId = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isNewUser: isNewUser ?? this.isNewUser,
      error: error,
      verificationId:
          resetVerificationId ? null : (verificationId ?? this.verificationId),
      user: user ?? this.user,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _checkExistingSession();
  }

  final _firebaseAuth = firebase.FirebaseAuth.instance;
  final _supabase = Supabase.instance.client;

  // URL de l'Edge Function firebase-auth
  String get _edgeFunctionUrl =>
      '${const String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://npucuhlvoalcbwdfedae.supabase.co')}/functions/v1/firebase-auth';

  /// Vérifie s'il y a une session Supabase existante
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
        // Mettre à jour le statut
        await _supabase
            .from('users_directory')
            .update({'status': 'online', 'last_seen_at': DateTime.now().toIso8601String()})
            .eq('auth_user_id', userId);
      }
    }
  }

  /// Étape 1 : Envoyer le SMS OTP via Firebase
  Future<void> sendOtp(String phoneNumber) async {
    state = state.copyWith(
      isLoading: true,
      error: null,
      resetVerificationId: true,
    );

    try {
      await _firebaseAuth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) async {
          // Auto-vérification Android
          await _signInWithCredential(credential);
        },
        verificationFailed: (e) {
          String msg = 'Erreur de vérification';
          if (e.code == 'invalid-phone-number') {
            msg = 'Numéro de téléphone invalide';
          } else if (e.code == 'too-many-requests') {
            msg = 'Trop de tentatives. Réessayez plus tard';
          }
          state = state.copyWith(isLoading: false, error: msg);
        },
        codeSent: (verificationId, resendToken) {
          state = state.copyWith(
            isLoading: false,
            verificationId: verificationId,
          );
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Erreur: $e');
    }
  }

  /// Étape 2 : Vérifier le code OTP
  Future<bool> verifyOtp(String smsCode, {String? fullName}) async {
    if (state.verificationId == null) {
      state = state.copyWith(error: 'Aucune vérification en cours');
      return false;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final credential = firebase.PhoneAuthProvider.credential(
        verificationId: state.verificationId!,
        smsCode: smsCode,
      );
      return await _signInWithCredential(credential, fullName: fullName);
    } catch (e) {
      String msg = 'Code invalide';
      if (e is firebase.FirebaseAuthException && e.code == 'invalid-verification-code') {
        msg = 'Le code saisi est incorrect';
      }
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  /// Signe avec Firebase puis échange le token contre une session Supabase
  Future<bool> _signInWithCredential(
    firebase.PhoneAuthCredential credential, {
    String? fullName,
  }) async {
    try {
      final result = await _firebaseAuth.signInWithCredential(credential);
      final idToken = await result.user?.getIdToken();

      if (idToken == null) {
        state = state.copyWith(isLoading: false, error: 'Impossible d\'obtenir le token');
        return false;
      }

      // Appeler l'Edge Function pour obtenir la session Supabase
      final response = await http.post(
        Uri.parse(_edgeFunctionUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'firebaseToken': idToken,
          'phone': result.user?.phoneNumber,
          'fullName': fullName,
        }),
      );

      if (response.statusCode != 200) {
        final err = jsonDecode(response.body);
        state = state.copyWith(
          isLoading: false,
          error: err['error'] ?? 'Erreur serveur',
        );
        return false;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final session = data['session'] as Map<String, dynamic>?;
      final refreshToken = session?['refresh_token'] as String?;
      if (refreshToken == null || refreshToken.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: 'Session invalide (refresh manquant)',
        );
        return false;
      }

      // GoTrue setSession attend le refresh_token, pas l'access_token.
      await _supabase.auth.setSession(refreshToken);

      state = state.copyWith(
        isLoading: false,
        isAuthenticated: true,
        isNewUser: data['is_new_user'] ?? false,
        user: data['user'],
      );

      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Erreur de connexion: $e');
      return false;
    }
  }

  /// Déconnexion
  Future<void> signOut() async {
    // Mettre hors ligne
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      await _supabase
          .from('users_directory')
          .update({'status': 'offline'})
          .eq('auth_user_id', userId);
    }

    await _firebaseAuth.signOut();
    await _supabase.auth.signOut();

    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
