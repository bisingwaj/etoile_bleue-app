# Prompt Cursor : Migration Firebase → Twilio Verify + Supabase

## Contexte

Ce projet Flutter est une application mobile "Étoile Bleue" pour les citoyens de Kinshasa (RDC). Elle permet d'appeler les urgences (112), signaler des incidents, et communiquer avec les services de secours.

**Le backend est Supabase** (pas Firebase). Les Edge Functions suivantes sont déjà déployées :

| Fonction | URL | Description |
|----------|-----|-------------|
| `twilio-verify` | `POST https://npucuhlvoalcbwdfedae.supabase.co/functions/v1/twilio-verify` | Envoi et vérification OTP |
| `complete-profile` | `POST https://npucuhlvoalcbwdfedae.supabase.co/functions/v1/complete-profile` | Finalisation inscription |
| `agora-token` | `POST https://npucuhlvoalcbwdfedae.supabase.co/functions/v1/agora-token` | Token Agora pour appels VoIP |

**Constantes Supabase :**
```dart
const supabaseUrl = 'https://npucuhlvoalcbwdfedae.supabase.co';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5wdWN1aGx2b2FsY2J3ZGZlZGFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2NDQ3NzcsImV4cCI6MjA5MDIyMDc3N30.1XLmBbRpx3Q-raPvHDnLm3dLuQGRWFHaP-fXv9BbqQk';
```

---

## Tâche 1 : Supprimer Firebase

### Fichiers à supprimer :
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `lib/firebase_options.dart`
- Tout fichier `firebase_*.dart` dans `lib/services/` ou `lib/providers/`

### pubspec.yaml — Supprimer ces dépendances :
```yaml
firebase_core: ...
firebase_auth: ...
firebase_messaging: ...  # GARDER si vous utilisez FCM pour les push notifications
cloud_firestore: ...
```

### android/build.gradle — Supprimer :
```groovy
classpath 'com.google.gms:google-services:...'
```

### android/app/build.gradle — Supprimer :
```groovy
apply plugin: 'com.google.gms.google-services'
```

### ios/Podfile — Aucune modification nécessaire (les pods Firebase seront supprimés automatiquement)

---

## Tâche 2 : Ajouter les dépendances Supabase

```yaml
dependencies:
  supabase_flutter: ^2.8.0
  flutter_secure_storage: ^9.2.4
```

---

## Tâche 3 : Créer `lib/services/auth_service.dart`

```dart
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Envoie un OTP par SMS au numéro de téléphone
  Future<Map<String, dynamic>> sendOtp(String phone) async {
    final res = await _client.functions.invoke(
      'twilio-verify',
      body: {'action': 'send', 'phone': phone},
    );
    if (res.status != 200) {
      final error = res.data is Map ? res.data['error'] : 'Erreur inconnue';
      throw Exception(error);
    }
    return res.data as Map<String, dynamic>;
  }

  /// Vérifie le code OTP et retourne la session Supabase
  Future<Map<String, dynamic>> verifyOtp(String phone, String code, {String? fullName}) async {
    final res = await _client.functions.invoke(
      'twilio-verify',
      body: {
        'action': 'verify',
        'phone': phone,
        'code': code,
        if (fullName != null) 'fullName': fullName,
      },
    );
    if (res.status != 200) {
      final error = res.data is Map ? res.data['error'] : 'Code invalide';
      throw Exception(error);
    }
    final data = res.data as Map<String, dynamic>;

    // Restaurer la session Supabase côté client
    if (data['session'] != null) {
      final session = data['session'];
      await _client.auth.setSession(session['access_token'], session['refresh_token']);
    }

    return data;
  }

  /// Finalise l'inscription (nom + date de naissance)
  Future<Map<String, dynamic>> completeProfile({
    required String fullName,
    String? dateOfBirth,
  }) async {
    final res = await _client.functions.invoke(
      'complete-profile',
      body: {
        'full_name': fullName,
        if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
      },
    );
    if (res.status != 200) {
      final error = res.data is Map ? res.data['error'] : 'Erreur';
      throw Exception(error);
    }
    return res.data as Map<String, dynamic>;
  }

  /// Déconnexion
  Future<void> logout() async {
    // Mettre à jour le statut dans users_directory
    final user = _client.auth.currentUser;
    if (user != null) {
      await _client.from('users_directory').update({
        'status': 'offline',
        'last_seen_at': DateTime.now().toIso8601String(),
      }).eq('auth_user_id', user.id);
    }
    await _client.auth.signOut();
  }

  /// Session courante
  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;
  bool get isAuthenticated => currentSession != null;

  /// Stream d'état d'authentification
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
}
```

---

## Tâche 4 : Créer `lib/providers/auth_provider.dart`

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

enum AppAuthState {
  loading,
  unauthenticated,
  otpSent,
  authenticated,
  needsRegistration,
}

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  AppAuthState _state = AppAuthState.loading;
  String? _phone;
  String? _error;
  Map<String, dynamic>? _userData;
  Timer? _heartbeat;

  AppAuthState get state => _state;
  String? get phone => _phone;
  String? get error => _error;
  Map<String, dynamic>? get userData => _userData;
  bool get isAuthenticated => _state == AppAuthState.authenticated;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    // Vérifier la session existante
    if (_authService.isAuthenticated) {
      _state = AppAuthState.authenticated;
      _startHeartbeat();
    } else {
      _state = AppAuthState.unauthenticated;
    }
    notifyListeners();
  }

  /// Étape 1 : Envoyer l'OTP
  Future<void> sendOtp(String phone) async {
    _error = null;
    _phone = phone;
    try {
      await _authService.sendOtp(phone);
      _state = AppAuthState.otpSent;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }
    notifyListeners();
  }

  /// Étape 2 : Vérifier l'OTP
  Future<void> verifyOtp(String code) async {
    if (_phone == null) return;
    _error = null;
    try {
      final result = await _authService.verifyOtp(_phone!, code);
      _userData = result['user'];

      if (result['is_new_user'] == true) {
        _state = AppAuthState.needsRegistration;
      } else {
        _state = AppAuthState.authenticated;
        _startHeartbeat();
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }
    notifyListeners();
  }

  /// Étape 3 : Compléter le profil (nouveaux utilisateurs)
  Future<void> completeProfile(String fullName, String? dateOfBirth) async {
    _error = null;
    try {
      final result = await _authService.completeProfile(
        fullName: fullName,
        dateOfBirth: dateOfBirth,
      );
      _userData = result['user'];
      _state = AppAuthState.authenticated;
      _startHeartbeat();
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    }
    notifyListeners();
  }

  /// Renvoyer l'OTP
  Future<void> resendOtp() async {
    if (_phone != null) {
      await sendOtp(_phone!);
    }
  }

  /// Déconnexion
  Future<void> logout() async {
    _heartbeat?.cancel();
    await _authService.logout();
    _state = AppAuthState.unauthenticated;
    _phone = null;
    _userData = null;
    notifyListeners();
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) async {
      final user = _authService.currentUser;
      if (user != null) {
        // import supabase_flutter
        // await Supabase.instance.client.from('users_directory')
        //   .update({'last_seen_at': DateTime.now().toIso8601String()})
        //   .eq('auth_user_id', user.id);
      }
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }
}
```

---

## Tâche 5 : Créer les écrans d'authentification

### `lib/screens/phone_input_screen.dart`
- Champ de saisie avec préfixe `+243`
- Bouton "Envoyer le code"
- Appelle `authProvider.sendOtp(phone)`
- Navigue vers `OtpVerificationScreen` si succès

### `lib/screens/otp_verification_screen.dart`
- 6 champs OTP (PinCodeTextField ou similaire)
- Timer de renvoi 60 secondes
- Bouton "Vérifier"
- Appelle `authProvider.verifyOtp(code)`
- Si `is_new_user` → navigue vers `RegistrationScreen`
- Sinon → navigue vers l'écran d'accueil

### `lib/screens/registration_screen.dart`
- Champ "Nom complet"
- Sélecteur de date de naissance
- Bouton "Créer mon compte"
- Appelle `authProvider.completeProfile(name, dob)`
- Navigue vers l'écran d'accueil

---

## Tâche 6 : Modifier `main.dart`

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ❌ SUPPRIMER : await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ✅ AJOUTER :
  await Supabase.initialize(
    url: 'https://npucuhlvoalcbwdfedae.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5wdWN1aGx2b2FsY2J3ZGZlZGFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2NDQ3NzcsImV4cCI6MjA5MDIyMDc3N30.1XLmBbRpx3Q-raPvHDnLm3dLuQGRWFHaP-fXv9BbqQk',
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        // ... vos autres providers
      ],
      child: const MyApp(),
    ),
  );
}
```

---

## Tâche 7 : Adapter les services existants

### `emergency_call_service.dart`
Remplacer tout header Firebase par le header Supabase :
```dart
// ❌ AVANT (Firebase)
final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
headers['Authorization'] = 'Bearer $idToken';

// ✅ APRÈS (Supabase)
final session = Supabase.instance.client.auth.currentSession;
headers['Authorization'] = 'Bearer ${session?.accessToken}';
headers['apikey'] = supabaseAnonKey;
```

### Appels aux Edge Functions
Toujours utiliser `Supabase.instance.client.functions.invoke()` au lieu de `http.post()` :
```dart
// ✅ Exemple pour obtenir un token Agora
final res = await Supabase.instance.client.functions.invoke(
  'agora-token',
  body: {'channelName': channelName},
);
```

---

## Tâche 8 : Table `users_directory` — Structure de référence

Les citoyens créés via l'app mobile utilisent ces colonnes :

| Colonne | Type | Description |
|---------|------|-------------|
| `id` | uuid | ID interne (PK) |
| `auth_user_id` | uuid | Lié à auth.users |
| `role` | enum | Toujours `citoyen` pour l'app mobile |
| `first_name` | text | Prénom |
| `last_name` | text | Nom |
| `phone` | text | Numéro E.164 (+243...) |
| `date_of_birth` | date | YYYY-MM-DD |
| `status` | text | `online` / `offline` |
| `last_seen_at` | timestamptz | Heartbeat |
| `blood_type` | text | Groupe sanguin (optionnel) |
| `allergies` | text[] | Allergies (optionnel) |
| `medical_history` | text[] | Antécédents (optionnel) |
| `emergency_contact_name` | text | Contact d'urgence (optionnel) |
| `emergency_contact_phone` | text | Téléphone d'urgence (optionnel) |

---

## API Endpoints Reference

### 1. Envoyer OTP
```
POST https://npucuhlvoalcbwdfedae.supabase.co/functions/v1/twilio-verify
Headers: { "Content-Type": "application/json", "apikey": "<anon_key>" }
Body: { "action": "send", "phone": "+243812345678" }
Response: { "success": true, "status": "pending" }
```

### 2. Vérifier OTP
```
POST https://npucuhlvoalcbwdfedae.supabase.co/functions/v1/twilio-verify
Headers: { "Content-Type": "application/json", "apikey": "<anon_key>" }
Body: { "action": "verify", "phone": "+243812345678", "code": "123456" }
Response: {
  "success": true,
  "is_new_user": true/false,
  "session": { "access_token": "...", "refresh_token": "...", "expires_in": 3600 },
  "user": { "id": "...", "auth_user_id": "...", "phone": "+243...", "role": "citoyen" }
}
```

### 3. Compléter le profil
```
POST https://npucuhlvoalcbwdfedae.supabase.co/functions/v1/complete-profile
Headers: { "Authorization": "Bearer <access_token>", "apikey": "<anon_key>" }
Body: { "full_name": "Jean Kabila", "date_of_birth": "1990-05-15" }
Response: { "success": true, "user": { ... } }
```

---

## Résumé des fichiers à créer/modifier

| Action | Fichier |
|--------|---------|
| ✅ Créer | `lib/services/auth_service.dart` |
| ✅ Créer | `lib/providers/auth_provider.dart` |
| ✅ Créer | `lib/screens/phone_input_screen.dart` |
| ✅ Créer | `lib/screens/otp_verification_screen.dart` |
| ✅ Créer | `lib/screens/registration_screen.dart` |
| ✏️ Modifier | `main.dart` — supprimer Firebase, init Supabase |
| ✏️ Modifier | `pubspec.yaml` — supprimer deps Firebase, ajouter Supabase |
| ✏️ Modifier | `emergency_call_service.dart` — headers Supabase |
| ❌ Supprimer | `google-services.json`, `GoogleService-Info.plist`, `firebase_options.dart` |
