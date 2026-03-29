import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ✅ Provider pour les contacts d'urgence depuis users_directory
final emergencyContactsProvider = FutureProvider<Map<String, String?>>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return {};

  final profile = await Supabase.instance.client
      .from('users_directory')
      .select('emergency_contact_name, emergency_contact_phone')
      .eq('auth_user_id', user.id)
      .maybeSingle();

  if (profile == null) return {};

  return {
    'name': profile['emergency_contact_name'] as String?,
    'phone': profile['emergency_contact_phone'] as String?,
  };
});
