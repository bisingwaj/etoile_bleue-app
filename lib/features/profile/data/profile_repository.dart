import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ✅ CORRIGÉ: Utilise 'users_directory' au lieu de 'users'
/// Toutes les colonnes sont alignées sur le schéma réel de la DB
class ProfileRepository {
  final SupabaseClient _db;
  final String? _uid;

  ProfileRepository({SupabaseClient? db})
      : _db = db ?? Supabase.instance.client,
        _uid = Supabase.instance.client.auth.currentUser?.id;

  String? get uid => _uid;

  // ─── LECTURE ─────────────────────────────────────────────────────────────────

  /// ✅ Stream du profil complet depuis users_directory
  Stream<Map<String, dynamic>?> watchProfile() {
    if (_uid == null) return Stream.value(null);
    return _db
        .from('users_directory')
        .stream(primaryKey: ['id'])
        .eq('auth_user_id', _uid!)
        .map((list) => list.isNotEmpty ? list.first : null);
  }

  /// ✅ Lecture ponctuelle du profil
  Future<Map<String, dynamic>?> getProfile() async {
    if (_uid == null) return null;
    final result = await _db
        .from('users_directory')
        .select()
        .eq('auth_user_id', _uid!)
        .maybeSingle();
    return result;
  }

  // ─── DONNÉES MÉDICALES ───────────────────────────────────────────────────────

  /// ✅ Sauvegarder le groupe sanguin (colonne ajoutée par migration)
  Future<void> saveBloodType(String bloodType) async {
    if (_uid == null) return;
    await _db.from('users_directory').update({
      'blood_type': bloodType,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('auth_user_id', _uid!);
    debugPrint('[ProfileRepository] Groupe sanguin mis à jour: $bloodType');
  }

  /// ✅ Sauvegarder les allergies (colonne text[] ajoutée par migration)
  Future<void> saveAllergies(List<String> allergies) async {
    if (_uid == null) return;
    await _db.from('users_directory').update({
      'allergies': allergies,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('auth_user_id', _uid!);
    debugPrint('[ProfileRepository] Allergies mises à jour: $allergies');
  }

  /// ✅ Sauvegarder les antécédents médicaux (colonne text[] ajoutée par migration)
  Future<void> saveMedicalHistory(List<String> history) async {
    if (_uid == null) return;
    await _db.from('users_directory').update({
      'medical_history': history,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('auth_user_id', _uid!);
    debugPrint('[ProfileRepository] Antécédents mis à jour: $history');
  }

  /// ✅ Sauvegarder les médicaments en cours (colonne text[] ajoutée par migration)
  Future<void> saveMedications(List<String> medications) async {
    if (_uid == null) return;
    await _db.from('users_directory').update({
      'medications': medications,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('auth_user_id', _uid!);
    debugPrint('[ProfileRepository] Médicaments mis à jour: $medications');
  }

  // ─── CONTACTS D'URGENCE ──────────────────────────────────────────────────────

  /// ✅ Sauvegarder le contact d'urgence (colonnes ajoutées par migration)
  Future<void> saveEmergencyContact({
    required String name,
    required String phone,
  }) async {
    if (_uid == null) return;
    await _db.from('users_directory').update({
      'emergency_contact_name': name,
      'emergency_contact_phone': phone,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('auth_user_id', _uid!);
    debugPrint('[ProfileRepository] Contact urgence: $name ($phone)');
  }

  // ─── DONNÉES SECOURISTE ───────────────────────────────────────────────────────

  /// ✅ Basculer la disponibilité du secouriste
  Future<void> setAvailability(bool isAvailable) async {
    if (_uid == null) return;
    await _db.from('users_directory').update({
      'available': isAvailable,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('auth_user_id', _uid!);
    debugPrint('[ProfileRepository] Disponibilité: $isAvailable');
  }

  /// ✅ Mettre à jour la zone d'intervention (colonnes existantes dans users_directory)
  Future<void> saveOperationalInfo({
    required String specialty,
    required String zone,
    String? vehicleId,
  }) async {
    if (_uid == null) return;
    await _db.from('users_directory').update({
      'specialization': specialty,
      'zone': zone,
      if (vehicleId != null) 'vehicle_id': vehicleId,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('auth_user_id', _uid!);
    debugPrint('[ProfileRepository] Infos opérationnelles mises à jour');
  }

  /// ✅ Mettre à jour les infos de base du profil
  Future<void> updateBasicInfo({
    String? firstName,
    String? lastName,
    String? phone,
    String? address,
    String? photoUrl,
  }) async {
    if (_uid == null) return;
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (firstName != null) updates['first_name'] = firstName;
    if (lastName != null) updates['last_name'] = lastName;
    if (phone != null) updates['phone'] = phone;
    if (address != null) updates['address'] = address;
    if (photoUrl != null) updates['photo_url'] = photoUrl;

    await _db.from('users_directory').update(updates).eq('auth_user_id', _uid!);
    debugPrint('[ProfileRepository] Profil mis à jour');
  }
}

/// Provider Riverpod
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository();
});
