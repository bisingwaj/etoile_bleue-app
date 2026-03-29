import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final profileImageProvider = StateNotifierProvider<ProfileImageNotifier, File?>((ref) {
  return ProfileImageNotifier();
});

class ProfileImageNotifier extends StateNotifier<File?> {
  ProfileImageNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('profile_image_path');
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (file.existsSync()) {
        state = file;
      }
    }
  }

  Future<void> setImage(File file) async {
    state = file;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_image_path', file.path);
  }
}
