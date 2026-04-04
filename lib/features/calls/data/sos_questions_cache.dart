import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'sos_question_model.dart';

class SOSQuestionsCache {
  static const _cacheKey = 'sos_questions_cache';
  static const _lastSyncKey = 'sos_questions_last_sync';

  static Future<List<SOSQuestion>?> loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_cacheKey);
    if (cached == null) return null;
    try {
      final list = jsonDecode(cached) as List;
      return list.map((e) => SOSQuestion.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveToCache(List<SOSQuestion> questions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode(questions.map((q) => q.toJson()).toList()));
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
  }

  static Future<DateTime?> getLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_lastSyncKey);
    return s != null ? DateTime.tryParse(s) : null;
  }

  static Future<void> invalidate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSyncKey);
  }
}
