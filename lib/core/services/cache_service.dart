import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class CacheService {
  static const _profileBox = 'cache_profile';
  static const _signalementsBox = 'cache_signalements';
  static const _historyBox = 'cache_history';
  static const _notificationsBox = 'cache_notifications';
  static const _offlineQueueBox = 'signalement_offline_queue';

  static Future<void> initialize() async {
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox<String>(_profileBox),
      Hive.openBox<String>(_signalementsBox),
      Hive.openBox<String>(_historyBox),
      Hive.openBox<String>(_notificationsBox),
      Hive.openBox<String>(_offlineQueueBox),
    ]);
    debugPrint('[Cache] Hive initialized with 5 boxes');
  }

  // --- Generic helpers ---

  static Future<void> putJson(String boxName, String key, dynamic data) async {
    try {
      final box = Hive.box<String>(boxName);
      await box.put(key, jsonEncode(data));
    } catch (e) {
      debugPrint('[Cache] putJson error ($boxName/$key): $e');
    }
  }

  static T? getJson<T>(String boxName, String key, T Function(dynamic) decoder) {
    try {
      final box = Hive.box<String>(boxName);
      final raw = box.get(key);
      if (raw == null) return null;
      return decoder(jsonDecode(raw));
    } catch (e) {
      debugPrint('[Cache] getJson error ($boxName/$key): $e');
      return null;
    }
  }

  static Future<void> clear(String boxName) async {
    try {
      final box = Hive.box<String>(boxName);
      await box.clear();
    } catch (e) {
      debugPrint('[Cache] clear error ($boxName): $e');
    }
  }

  // --- Profile ---

  static Future<void> cacheProfile(Map<String, dynamic> profile) =>
      putJson(_profileBox, 'current', profile);

  static Map<String, dynamic>? getCachedProfile() =>
      getJson(_profileBox, 'current', (d) => Map<String, dynamic>.from(d as Map));

  // --- Signalements ---

  static Future<void> cacheSignalements(List<Map<String, dynamic>> items) =>
      putJson(_signalementsBox, 'list', items);

  static List<Map<String, dynamic>>? getCachedSignalements() =>
      getJson(_signalementsBox, 'list', (d) => (d as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());

  // --- History ---

  static Future<void> cacheHistory(List<Map<String, dynamic>> items) =>
      putJson(_historyBox, 'list', items);

  static List<Map<String, dynamic>>? getCachedHistory() =>
      getJson(_historyBox, 'list', (d) => (d as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());

  // --- Notifications ---

  static Future<void> cacheNotifications(List<Map<String, dynamic>> items) =>
      putJson(_notificationsBox, 'list', items);

  static List<Map<String, dynamic>>? getCachedNotifications() =>
      getJson(_notificationsBox, 'list', (d) => (d as List).map((e) => Map<String, dynamic>.from(e as Map)).toList());

  // --- Clear all ---

  static Future<void> clearAll() async {
    await Future.wait([
      clear(_profileBox),
      clear(_signalementsBox),
      clear(_historyBox),
      clear(_notificationsBox),
    ]);
  }
}
