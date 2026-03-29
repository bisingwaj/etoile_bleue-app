# Prompt Cursor — Migration complète Flutter : Firebase → Supabase + Twilio Verify

## Contexte du projet

Tu travailles sur **Étoile Bleue Mobile**, une application Flutter pour les citoyens de Kinshasa (RDC) qui leur permet d'appeler les secours, signaler des urgences et communiquer avec les opérateurs d'un centre d'appels d'urgence.

**Le backend est déjà opérationnel** sur Supabase (Lovable Cloud). L'objectif est de **supprimer 100% de Firebase** et utiliser exclusivement Supabase + Twilio Verify pour l'authentification.

---

## Architecture backend (DÉJÀ EN PLACE — ne pas modifier)

### URL Supabase
```
URL: https://npucuhlvoalcbwdfedae.supabase.co
Anon Key: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5wdWN1aGx2b2FsY2J3ZGZlZGFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2NDQ3NzcsImV4cCI6MjA5MDIyMDc3N30.1XLmBbRpx3Q-raPvHDnLm3dLuQGRWFHaP-fXv9BbqQk
```

### Edge Functions disponibles

#### 1. `twilio-verify` — Envoi et vérification OTP
- **URL** : `https://npucuhlvoalcbwdfedae.supabase.co/functions/v1/twilio-verify`
- **Méthode** : POST
- **Headers** : `Content-Type: application/json`, `apikey: <anon_key>`
- **Pas besoin de JWT** (verify_jwt = false)

**Action `send`** — Envoyer un OTP :
```json
{
  "action": "send",
  "phone": "+243812345678"
}
```
Réponse : `{ "success": true, "status": "pending" }`

**Action `verify`** — Vérifier le code OTP :
```json
{
  "action": "verify",
  "phone": "+243812345678",
  "code": "123456"
}
```
Réponse succès :
```json
{
  "success": true,
  "is_new_user": true,
  "session": {
    "access_token": "...",
    "refresh_token": "...",
    "expires_in": 3600,
    "expires_at": 1234567890,
    "token_type": "bearer"
  },
  "user": {
    "id": "uuid-directory",
    "auth_user_id": "uuid-auth",
    "phone": "+243812345678",
    "role": "citoyen",
    "first_name": "Citoyen",
    "last_name": "",
    "date_of_birth": null
  }
}
```

**Champ clé : `is_new_user`** → Si `true`, rediriger vers l'écran d'inscription (saisie nom + date de naissance).

#### 2. `complete-profile` — Finaliser le profil citoyen
- **URL** : `https://npucuhlvoalcbwdfedae.supabase.co/functions/v1/complete-profile`
- **Méthode** : POST
- **Headers** : `Content-Type: application/json`, `apikey: <anon_key>`, `Authorization: Bearer <access_token>`
- **Requiert un JWT valide**

```json
{
  "full_name": "Jean Kabila",
  "date_of_birth": "1990-05-15"
}
```
Réponse :
```json
{
  "success": true,
  "user": {
    "id": "uuid",
    "first_name": "Jean",
    "last_name": "Kabila",
    "phone": "+243812345678",
    "date_of_birth": "1990-05-15",
    "role": "citoyen"
  }
}
```

#### 3. `agora-token` — Token pour appels audio/vidéo
- **URL** : `https://npucuhlvoalcbwdfedae.supabase.co/functions/v1/agora-token`
- Requiert JWT

---

## Étape 1 : Nettoyer Firebase

### pubspec.yaml — Supprimer ces dépendances :
```yaml
# SUPPRIMER TOUTES CES LIGNES :
firebase_core: ...
firebase_auth: ...
firebase_messaging: ...
cloud_firestore: ...
firebase_storage: ...
firebase_analytics: ...
firebase_crashlytics: ...
```

### Ajouter ces dépendances :
```yaml
dependencies:
  supabase_flutter: ^2.8.0
  flutter_secure_storage: ^9.2.4
  http: ^1.2.2
```

### Fichiers à supprimer :
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `lib/firebase_options.dart`
- Tout fichier `*firebase*` dans `lib/`

### android/app/build.gradle — Supprimer :
```groovy
// SUPPRIMER :
apply plugin: 'com.google.gms.google-services'
apply plugin: 'com.google.firebase.crashlytics'
```

### android/build.gradle — Supprimer :
```groovy
// SUPPRIMER dans dependencies :
classpath 'com.google.gms:google-services:...'
classpath 'com.google.firebase.crashlytics:...'
```

---

## Étape 2 : Initialiser Supabase

### `lib/main.dart`
```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://npucuhlvoalcbwdfedae.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5wdWN1aGx2b2FsY2J3ZGZlZGFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2NDQ3NzcsImV4cCI6MjA5MDIyMDc3N30.1XLmBbRpx3Q-raPvHDnLm3dLuQGRWFHaP-fXv9BbqQk',
  );

  runApp(const EtoileBleueApp());
}

final supabase = Supabase.instance.client;
```

---

## Étape 3 : Service d'authentification

### `lib/services/auth_service.dart`
```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  static const _baseUrl = 'https://npucuhlvoalcbwdfedae.supabase.co/functions/v1';
  static const _anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5wdWN1aGx2b2FsY2J3ZGZlZGFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2NDQ3NzcsImV4cCI6MjA5MDIyMDc3N30.1XLmBbRpx3Q-raPvHDnLm3dLuQGRWFHaP-fXv9BbqQk';
  
  final _storage = const FlutterSecureStorage();
  final _supabase = Supabase.instance.client;

  /// Envoyer un OTP par SMS
  Future<bool> sendOtp(String phone) async {
    final normalized = _normalizePhone(phone);
    final response = await http.post(
      Uri.parse('$_baseUrl/twilio-verify'),
      headers: {
        'Content-Type': 'application/json',
        'apikey': _anonKey,
      },
      body: jsonEncode({
        'action': 'send',
        'phone': normalized,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw AuthException(error['error'] ?? 'Failed to send OTP');
    }
    return true;
  }

  /// Vérifier le code OTP et obtenir une session
  Future<VerifyResult> verifyOtp(String phone, String code) async {
    final normalized = _normalizePhone(phone);
    final response = await http.post(
      Uri.parse('$_baseUrl/twilio-verify'),
      headers: {
        'Content-Type': 'application/json',
        'apikey': _anonKey,
      },
      body: jsonEncode({
        'action': 'verify',
        'phone': normalized,
        'code': code,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw AuthException(
        error['error'] ?? 'Verification failed',
        code: error['code'],
      );
    }

    final data = jsonDecode(response.body);
    final session = data['session'];
    final user = data['user'];

    // Restaurer la session Supabase côté client
    await _supabase.auth.setSession(session['access_token']);

    // Stocker les tokens
    await _storage.write(key: 'access_token', value: session['access_token']);
    await _storage.write(key: 'refresh_token', value: session['refresh_token']);

    return VerifyResult(
      isNewUser: data['is_new_user'] ?? false,
      accessToken: session['access_token'],
      refreshToken: session['refresh_token'],
      user: CitizenUser.fromJson(user),
    );
  }

  /// Compléter le profil d'un nouveau citoyen
  Future<CitizenUser> completeProfile({
    required String fullName,
    String? dateOfBirth,
  }) async {
    final accessToken = await _storage.read(key: 'access_token');
    if (accessToken == null) throw AuthException('Not authenticated');

    final body = <String, dynamic>{'full_name': fullName};
    if (dateOfBirth != null) body['date_of_birth'] = dateOfBirth;

    final response = await http.post(
      Uri.parse('$_baseUrl/complete-profile'),
      headers: {
        'Content-Type': 'application/json',
        'apikey': _anonKey,
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw AuthException(error['error'] ?? 'Profile update failed');
    }

    final data = jsonDecode(response.body);
    return CitizenUser.fromJson(data['user']);
  }

  /// Vérifier si une session existe
  Future<bool> hasSession() async {
    final session = _supabase.auth.currentSession;
    return session != null;
  }

  /// Récupérer le profil citoyen depuis users_directory
  Future<CitizenUser?> getCurrentUser() async {
    final session = _supabase.auth.currentSession;
    if (session == null) return null;

    final response = await _supabase
        .from('users_directory')
        .select('id, auth_user_id, first_name, last_name, phone, date_of_birth, role, photo_url')
        .eq('auth_user_id', session.user.id)
        .maybeSingle();

    if (response == null) return null;
    return CitizenUser.fromJson(response);
  }

  /// Déconnexion
  Future<void> signOut() async {
    await _supabase.auth.signOut();
    await _storage.deleteAll();
  }

  /// Normaliser le numéro de téléphone (format RDC)
  String _normalizePhone(String phone) {
    String n = phone.trim().replaceAll(RegExp(r'\s+'), '');
    if (!n.startsWith('+')) {
      if (n.startsWith('0')) {
        n = '+243${n.substring(1)}';
      } else if (n.startsWith('243')) {
        n = '+$n';
      } else {
        n = '+$n';
      }
    }
    return n;
  }
}

// ─── Modèles ─────────────────────────────────────────────

class CitizenUser {
  final String id;
  final String authUserId;
  final String phone;
  final String firstName;
  final String lastName;
  final String? dateOfBirth;
  final String role;
  final String? photoUrl;

  CitizenUser({
    required this.id,
    required this.authUserId,
    required this.phone,
    required this.firstName,
    required this.lastName,
    this.dateOfBirth,
    this.role = 'citoyen',
    this.photoUrl,
  });

  String get fullName => '$firstName $lastName'.trim();

  bool get isProfileComplete =>
      firstName.isNotEmpty &&
      firstName != 'Citoyen' &&
      lastName.isNotEmpty;

  factory CitizenUser.fromJson(Map<String, dynamic> json) {
    return CitizenUser(
      id: json['id'] ?? '',
      authUserId: json['auth_user_id'] ?? '',
      phone: json['phone'] ?? '',
      firstName: json['first_name'] ?? '',
      lastName: json['last_name'] ?? '',
      dateOfBirth: json['date_of_birth'],
      role: json['role'] ?? 'citoyen',
      photoUrl: json['photo_url'],
    );
  }
}

class VerifyResult {
  final bool isNewUser;
  final String accessToken;
  final String refreshToken;
  final CitizenUser user;

  VerifyResult({
    required this.isNewUser,
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });
}

class AuthException implements Exception {
  final String message;
  final String? code;
  AuthException(this.message, {this.code});

  @override
  String toString() => 'AuthException: $message (code: $code)';
}
```

---

## Étape 4 : State Management (ChangeNotifier)

### `lib/providers/auth_provider.dart`
```dart
import 'package:flutter/material.dart';
import '../services/auth_service.dart';

enum AuthStatus {
  initial,
  unauthenticated,
  otpSent,
  verifying,
  needsRegistration,
  authenticated,
  error,
}

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  AuthStatus _status = AuthStatus.initial;
  CitizenUser? _user;
  String? _phone;
  String? _errorMessage;
  bool _loading = false;

  AuthStatus get status => _status;
  CitizenUser? get user => _user;
  String? get phone => _phone;
  String? get errorMessage => _errorMessage;
  bool get loading => _loading;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  /// Initialiser — vérifier la session existante
  Future<void> initialize() async {
    _loading = true;
    notifyListeners();

    try {
      final hasSession = await _authService.hasSession();
      if (hasSession) {
        _user = await _authService.getCurrentUser();
        if (_user != null && _user!.isProfileComplete) {
          _status = AuthStatus.authenticated;
        } else if (_user != null) {
          _status = AuthStatus.needsRegistration;
        } else {
          _status = AuthStatus.unauthenticated;
        }
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (e) {
      _status = AuthStatus.unauthenticated;
    }

    _loading = false;
    notifyListeners();
  }

  /// Envoyer un OTP
  Future<void> sendOtp(String phone) async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _authService.sendOtp(phone);
      _phone = phone;
      _status = AuthStatus.otpSent;
    } on AuthException catch (e) {
      _errorMessage = e.message;
      _status = AuthStatus.error;
    } catch (e) {
      _errorMessage = 'Erreur réseau. Vérifiez votre connexion.';
      _status = AuthStatus.error;
    }

    _loading = false;
    notifyListeners();
  }

  /// Vérifier le code OTP
  Future<void> verifyOtp(String code) async {
    if (_phone == null) return;

    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _authService.verifyOtp(_phone!, code);
      _user = result.user;

      if (result.isNewUser || !result.user.isProfileComplete) {
        _status = AuthStatus.needsRegistration;
      } else {
        _status = AuthStatus.authenticated;
      }
    } on AuthException catch (e) {
      _errorMessage = e.code == 'INVALID_CODE'
          ? 'Code incorrect ou expiré. Réessayez.'
          : e.message;
      _status = AuthStatus.error;
    } catch (e) {
      _errorMessage = 'Erreur de vérification. Réessayez.';
      _status = AuthStatus.error;
    }

    _loading = false;
    notifyListeners();
  }

  /// Compléter le profil
  Future<void> completeProfile(String fullName, String? dateOfBirth) async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _authService.completeProfile(
        fullName: fullName,
        dateOfBirth: dateOfBirth,
      );
      _status = AuthStatus.authenticated;
    } on AuthException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Erreur lors de la mise à jour du profil.';
    }

    _loading = false;
    notifyListeners();
  }

  /// Déconnexion
  Future<void> signOut() async {
    await _authService.signOut();
    _user = null;
    _phone = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  /// Réinitialiser l'erreur
  void clearError() {
    _errorMessage = null;
    _status = _phone != null ? AuthStatus.otpSent : AuthStatus.unauthenticated;
    notifyListeners();
  }
}
```

---

## Étape 5 : Écrans d'authentification

### `lib/screens/auth/phone_input_screen.dart`
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class PhoneInputScreen extends StatefulWidget {
  const PhoneInputScreen({super.key});

  @override
  State<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends State<PhoneInputScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                // Logo Étoile Bleue
                const Icon(Icons.local_hospital, size: 80, color: Colors.blue),
                const SizedBox(height: 16),
                const Text(
                  'Étoile Bleue',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Entrez votre numéro de téléphone pour commencer',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _controller,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Numéro de téléphone',
                    hintText: '0812345678',
                    prefixText: '+243 ',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().length < 9) {
                      return 'Numéro invalide (min 9 chiffres)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                if (auth.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      auth.errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ElevatedButton(
                  onPressed: auth.loading
                      ? null
                      : () {
                          if (_formKey.currentState!.validate()) {
                            auth.sendOtp(_controller.text.trim());
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blue,
                  ),
                  child: auth.loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Recevoir le code SMS',
                          style: TextStyle(fontSize: 16)),
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

### `lib/screens/auth/otp_verification_screen.dart`
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({super.key});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Vérification')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            Text(
              'Code envoyé au ${auth.phone}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 32, letterSpacing: 12),
              decoration: const InputDecoration(
                hintText: '------',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            if (auth.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  auth.errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            ElevatedButton(
              onPressed: auth.loading
                  ? null
                  : () {
                      if (_controller.text.length == 6) {
                        auth.verifyOtp(_controller.text);
                      }
                    },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: auth.loading
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : const Text('Vérifier', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: auth.loading
                  ? null
                  : () => auth.sendOtp(auth.phone!),
              child: const Text('Renvoyer le code'),
            ),
          ],
        ),
      ),
    );
  }
}
```

### `lib/screens/auth/registration_screen.dart`
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  DateTime? _selectedDate;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Compléter votre profil')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Text(
                'Bienvenue ! Complétez votre profil pour continuer.',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nom complet *',
                  hintText: 'Jean Kabila',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.trim().length < 2) {
                    return 'Minimum 2 caractères';
                  }
                  if (!value.trim().contains(' ')) {
                    return 'Entrez votre prénom et nom';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(
                  _selectedDate != null
                      ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}'
                      : 'Date de naissance (optionnel)',
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.shade400),
                ),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime(2000),
                    firstDate: DateTime(1920),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    setState(() => _selectedDate = date);
                  }
                },
              ),
              const SizedBox(height: 24),
              if (auth.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    auth.errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              ElevatedButton(
                onPressed: auth.loading
                    ? null
                    : () {
                        if (_formKey.currentState!.validate()) {
                          String? dob;
                          if (_selectedDate != null) {
                            dob = '${_selectedDate!.year}-'
                                '${_selectedDate!.month.toString().padLeft(2, '0')}-'
                                '${_selectedDate!.day.toString().padLeft(2, '0')}';
                          }
                          auth.completeProfile(
                            _nameController.text.trim(),
                            dob,
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: auth.loading
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : const Text('Valider', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

---

## Étape 6 : Navigation basée sur l'état d'auth

### `lib/app_router.dart`
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/phone_input_screen.dart';
import 'screens/auth/otp_verification_screen.dart';
import 'screens/auth/registration_screen.dart';
import 'screens/home_screen.dart'; // Ton écran principal existant

class AppRouter extends StatelessWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.loading && auth.status == AuthStatus.initial) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    switch (auth.status) {
      case AuthStatus.unauthenticated:
      case AuthStatus.error:
        return const PhoneInputScreen();
      case AuthStatus.otpSent:
      case AuthStatus.verifying:
        return const OtpVerificationScreen();
      case AuthStatus.needsRegistration:
        return const RegistrationScreen();
      case AuthStatus.authenticated:
        return const HomeScreen(); // Remplace par ton écran principal
      default:
        return const PhoneInputScreen();
    }
  }
}
```

### Mise à jour `main.dart` avec Provider :
```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'providers/auth_provider.dart';
import 'app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://npucuhlvoalcbwdfedae.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5wdWN1aGx2b2FsY2J3ZGZlZGFlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2NDQ3NzcsImV4cCI6MjA5MDIyMDc3N30.1XLmBbRpx3Q-raPvHDnLm3dLuQGRWFHaP-fXv9BbqQk',
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthProvider()..initialize(),
      child: const EtoileBleueApp(),
    ),
  );
}

class EtoileBleueApp extends StatelessWidget {
  const EtoileBleueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Étoile Bleue',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const AppRouter(),
    );
  }
}
```

---

## Étape 7 : Accès aux données Supabase (exemples)

### Lire les incidents du citoyen
```dart
final response = await supabase
    .from('incidents')
    .select('*')
    .eq('citizen_id', user.id)
    .order('created_at', ascending: false);
```

### Créer un signalement
```dart
await supabase.from('signalements').insert({
  'reference': 'SIG-${DateTime.now().millisecondsSinceEpoch}',
  'category': 'urgence_medicale',
  'title': 'Urgence médicale',
  'description': description,
  'citizen_name': user.fullName,
  'citizen_phone': user.phone,
  'lat': position.latitude,
  'lng': position.longitude,
  'commune': commune,
  'province': 'Kinshasa',
  'ville': 'Kinshasa',
});
```

### Écouter les mises à jour en temps réel
```dart
supabase
    .channel('my-incidents')
    .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'incidents',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'citizen_id',
        value: user.id,
      ),
      callback: (payload) {
        // Mettre à jour l'UI
      },
    )
    .subscribe();
```

---

## Résumé des fichiers à créer/modifier

| Fichier | Action |
|---------|--------|
| `pubspec.yaml` | Supprimer Firebase, ajouter supabase_flutter + http + flutter_secure_storage |
| `lib/firebase_options.dart` | SUPPRIMER |
| `android/app/google-services.json` | SUPPRIMER |
| `ios/Runner/GoogleService-Info.plist` | SUPPRIMER |
| `lib/main.dart` | Remplacer Firebase.initializeApp → Supabase.initialize + Provider |
| `lib/services/auth_service.dart` | CRÉER — appels HTTP aux Edge Functions |
| `lib/providers/auth_provider.dart` | CRÉER — ChangeNotifier avec états d'auth |
| `lib/screens/auth/phone_input_screen.dart` | CRÉER |
| `lib/screens/auth/otp_verification_screen.dart` | CRÉER |
| `lib/screens/auth/registration_screen.dart` | CRÉER |
| `lib/app_router.dart` | CRÉER — navigation déclarative par état |

## Points importants

1. **Seul le rôle `citoyen`** est créé via l'app mobile. Les opérateurs/admins se connectent via le dashboard web.
2. **`is_new_user`** détermine si l'écran d'inscription s'affiche.
3. **`isProfileComplete`** vérifie que le nom n'est pas "Citoyen" par défaut.
4. **La normalisation du numéro** ajoute automatiquement `+243` pour les numéros congolais.
5. **Pas de mot de passe côté utilisateur** — le mot de passe est généré côté serveur pour la session.
