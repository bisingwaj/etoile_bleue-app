import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class OfflineSignalement {
  final String localId;
  final String title;
  final String category;
  final String description;
  final String province;
  final String ville;
  final String? commune;
  final bool isAnonymous;
  final String priority;
  final String? structureName;
  final String? structureId;
  final List<OfflineMediaRef> mediaRefs;
  final DateTime createdAt;
  final int retryCount;

  const OfflineSignalement({
    required this.localId,
    required this.title,
    required this.category,
    required this.description,
    this.province = 'Kinshasa',
    this.ville = 'Kinshasa',
    this.commune,
    this.isAnonymous = false,
    this.priority = 'moyenne',
    this.structureName,
    this.structureId,
    this.mediaRefs = const [],
    required this.createdAt,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'localId': localId,
    'title': title,
    'category': category,
    'description': description,
    'province': province,
    'ville': ville,
    'commune': commune,
    'isAnonymous': isAnonymous,
    'priority': priority,
    'structureName': structureName,
    'structureId': structureId,
    'mediaRefs': mediaRefs.map((m) => m.toJson()).toList(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'retryCount': retryCount,
  };

  factory OfflineSignalement.fromJson(Map<String, dynamic> json) => OfflineSignalement(
    localId: json['localId'] as String,
    title: json['title'] as String,
    category: json['category'] as String,
    description: json['description'] as String,
    province: json['province'] as String? ?? 'Kinshasa',
    ville: json['ville'] as String? ?? 'Kinshasa',
    commune: json['commune'] as String?,
    isAnonymous: json['isAnonymous'] as bool? ?? false,
    priority: json['priority'] as String? ?? 'moyenne',
    structureName: json['structureName'] as String?,
    structureId: json['structureId'] as String?,
    mediaRefs: (json['mediaRefs'] as List?)?.map((m) => OfflineMediaRef.fromJson(Map<String, dynamic>.from(m as Map))).toList() ?? [],
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    retryCount: json['retryCount'] as int? ?? 0,
  );

  OfflineSignalement copyWith({int? retryCount}) => OfflineSignalement(
    localId: localId,
    title: title,
    category: category,
    description: description,
    province: province,
    ville: ville,
    commune: commune,
    isAnonymous: isAnonymous,
    priority: priority,
    structureName: structureName,
    structureId: structureId,
    mediaRefs: mediaRefs,
    createdAt: createdAt,
    retryCount: retryCount ?? this.retryCount,
  );
}

class OfflineMediaRef {
  final String localPath;
  final String type;
  final String originalFilename;
  final int? durationSeconds;

  const OfflineMediaRef({
    required this.localPath,
    required this.type,
    required this.originalFilename,
    this.durationSeconds,
  });

  Map<String, dynamic> toJson() => {
    'localPath': localPath,
    'type': type,
    'originalFilename': originalFilename,
    'durationSeconds': durationSeconds,
  };

  factory OfflineMediaRef.fromJson(Map<String, dynamic> json) => OfflineMediaRef(
    localPath: json['localPath'] as String,
    type: json['type'] as String,
    originalFilename: json['originalFilename'] as String,
    durationSeconds: json['durationSeconds'] as int?,
  );
}

class OrphanMedia {
  final String id;
  final String signalementId;
  final OfflineMediaRef mediaRef;
  final DateTime createdAt;
  final int retryCount;

  const OrphanMedia({
    required this.id,
    required this.signalementId,
    required this.mediaRef,
    required this.createdAt,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'signalementId': signalementId,
    'mediaRef': mediaRef.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'retryCount': retryCount,
  };

  factory OrphanMedia.fromJson(Map<String, dynamic> json) => OrphanMedia(
    id: json['id'] as String,
    signalementId: json['signalementId'] as String,
    mediaRef: OfflineMediaRef.fromJson(Map<String, dynamic>.from(json['mediaRef'] as Map)),
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    retryCount: json['retryCount'] as int? ?? 0,
  );

  OrphanMedia copyWith({int? retryCount}) => OrphanMedia(
    id: id,
    signalementId: signalementId,
    mediaRef: mediaRef,
    createdAt: createdAt,
    retryCount: retryCount ?? this.retryCount,
  );
}

class SignalementOfflineQueue {
  static const _boxName = 'signalement_offline_queue';
  static const _orphanBoxName = 'signalement_orphan_media_queue';

  static Future<void> initialize() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox<String>(_boxName);
    }
    if (!Hive.isBoxOpen(_orphanBoxName)) {
      await Hive.openBox<String>(_orphanBoxName);
    }
  }

  static Box<String> get _box => Hive.box<String>(_boxName);
  static Box<String> get _orphanBox => Hive.box<String>(_orphanBoxName);

  static Future<void> enqueue(OfflineSignalement item) async {
    await initialize();
    await _box.put(item.localId, jsonEncode(item.toJson()));
    debugPrint('[OfflineQueue] Enqueued: ${item.localId} (${item.title})');
  }

  static Future<List<OfflineSignalement>> getPending() async {
    await initialize();
    final items = <OfflineSignalement>[];
    final keysToDelete = <dynamic>[];
    for (final key in _box.keys) {
      try {
        final raw = _box.get(key);
        if (raw != null) {
          items.add(OfflineSignalement.fromJson(jsonDecode(raw) as Map<String, dynamic>));
        }
      } catch (e) {
        debugPrint('[OfflineQueue] Parse error for key $key (purging): $e');
        keysToDelete.add(key);
      }
    }
    // Purge corrupted entries so they don't block future syncs
    for (final key in keysToDelete) {
      try {
        await _box.delete(key);
      } catch (_) {}
    }
    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  static Future<void> remove(String localId) async {
    await initialize();
    await _box.delete(localId);
    debugPrint('[OfflineQueue] Removed: $localId');
  }

  static Future<void> updateRetryCount(String localId, int count) async {
    await initialize();
    final raw = _box.get(localId);
    if (raw == null) return;
    try {
      final item = OfflineSignalement.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      await _box.put(localId, jsonEncode(item.copyWith(retryCount: count).toJson()));
    } catch (e) {
      debugPrint('[OfflineQueue] Update retry count error: $e');
    }
  }

  static Future<int> get pendingCount async {
    await initialize();
    return _box.length + _orphanBox.length;
  }

  static Future<void> clear() async {
    await initialize();
    await _box.clear();
    await _orphanBox.clear();
  }

  // ─── ORPHAN MEDIA MANAGEMENT ────────────────────────────────────────────────

  static Future<void> enqueueOrphan(OrphanMedia item) async {
    await initialize();
    await _orphanBox.put(item.id, jsonEncode(item.toJson()));
    debugPrint('[OfflineQueue] Enqueued Orphan Media: ${item.id}');
  }

  static Future<List<OrphanMedia>> getPendingOrphans() async {
    await initialize();
    final items = <OrphanMedia>[];
    final keysToDelete = <dynamic>[];
    for (final key in _orphanBox.keys) {
      try {
        final raw = _orphanBox.get(key);
        if (raw != null) {
          items.add(OrphanMedia.fromJson(jsonDecode(raw) as Map<String, dynamic>));
        }
      } catch (e) {
        debugPrint('[OfflineQueue] Parse error for orphan key $key (purging): $e');
        keysToDelete.add(key);
      }
    }
    // Purge corrupted entries
    for (final key in keysToDelete) {
      try {
        await _orphanBox.delete(key);
      } catch (_) {}
    }
    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  static Future<void> removeOrphan(String id) async {
    await initialize();
    await _orphanBox.delete(id);
    debugPrint('[OfflineQueue] Removed Orphan Media: $id');
  }

  static Future<void> updateOrphanRetryCount(String id, int count) async {
    await initialize();
    final raw = _orphanBox.get(id);
    if (raw == null) return;
    try {
      final item = OrphanMedia.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      await _orphanBox.put(id, jsonEncode(item.copyWith(retryCount: count).toJson()));
    } catch (e) {
      debugPrint('[OfflineQueue] Update orphan retry count error: $e');
    }
  }
}
