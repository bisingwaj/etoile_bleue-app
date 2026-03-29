import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ✅ CORRIGÉ: Utilise 'users_directory' au lieu de 'users'
/// Le champ de liaison est 'auth_user_id' (pas 'id' directement)
final userProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final user = Supabase.instance.client.auth.currentUser;

  if (user == null) {
    return Stream.value(null);
  }

  // ✅ Table correcte: users_directory
  // ✅ Filtre correct: auth_user_id = user.id (pas id = user.id)
  return Supabase.instance.client
      .from('users_directory')
      .stream(primaryKey: ['id'])
      .eq('auth_user_id', user.id)
      .map((list) => list.isNotEmpty ? list.first : null);
});
