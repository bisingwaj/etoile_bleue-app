import 'dart:io';
import 'signalement_enums.dart';

class Signalement {
  final String id;
  final String reference;
  final SignalementCategory category;
  final String title;
  final String? description;
  final String? citizenName;
  final String? citizenPhone;
  final bool isAnonymous;
  final String province;
  final String ville;
  final String? commune;
  final double? lat;
  final double? lng;
  final String? structureName;
  final String? structureId;
  final SignalementPriority priority;
  final SignalementStatus status;
  final String? assignedTo;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<SignalementMediaItem> media;

  const Signalement({
    required this.id,
    required this.reference,
    required this.category,
    required this.title,
    this.description,
    this.citizenName,
    this.citizenPhone,
    this.isAnonymous = false,
    this.province = 'Kinshasa',
    this.ville = 'Kinshasa',
    this.commune,
    this.lat,
    this.lng,
    this.structureName,
    this.structureId,
    this.priority = SignalementPriority.moyenne,
    this.status = SignalementStatus.nouveau,
    this.assignedTo,
    required this.createdAt,
    this.updatedAt,
    this.media = const [],
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'reference': reference,
    'category': category.code,
    'title': title,
    'description': description,
    'citizen_name': citizenName,
    'citizen_phone': citizenPhone,
    'is_anonymous': isAnonymous,
    'province': province,
    'ville': ville,
    'commune': commune,
    'lat': lat,
    'lng': lng,
    'structure_name': structureName,
    'structure_id': structureId,
    'priority': priority.code,
    'status': status.code,
    'assigned_to': assignedTo,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt?.toUtc().toIso8601String(),
  };

  factory Signalement.fromMap(Map<String, dynamic> map, {List<SignalementMediaItem> media = const []}) {
    return Signalement(
      id: map['id'] as String,
      reference: map['reference'] as String? ?? '',
      category: SignalementCategory.fromCode(map['category'] as String? ?? 'corruption'),
      title: map['title'] as String? ?? '',
      description: map['description'] as String?,
      citizenName: map['citizen_name'] as String?,
      citizenPhone: map['citizen_phone'] as String?,
      isAnonymous: map['is_anonymous'] as bool? ?? false,
      province: map['province'] as String? ?? 'Kinshasa',
      ville: map['ville'] as String? ?? 'Kinshasa',
      commune: map['commune'] as String?,
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      structureName: map['structure_name'] as String?,
      structureId: map['structure_id'] as String?,
      priority: SignalementPriority.fromCode(map['priority'] as String? ?? 'moyenne'),
      status: SignalementStatus.fromCode(map['status'] as String? ?? 'nouveau'),
      assignedTo: map['assigned_to'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'] as String) : null,
      media: media,
    );
  }
}

class SignalementMediaItem {
  final String id;
  final String signalementId;
  final String type; // 'image', 'video', 'audio'
  final String url;
  final String? thumbnail;
  final int? duration;
  final String filename;
  final DateTime createdAt;

  const SignalementMediaItem({
    required this.id,
    required this.signalementId,
    required this.type,
    required this.url,
    this.thumbnail,
    this.duration,
    required this.filename,
    required this.createdAt,
  });

  factory SignalementMediaItem.fromMap(Map<String, dynamic> map) {
    return SignalementMediaItem(
      id: map['id'] as String,
      signalementId: map['signalement_id'] as String,
      type: map['type'] as String? ?? 'image',
      url: map['url'] as String? ?? '',
      thumbnail: map['thumbnail'] as String?,
      duration: map['duration'] as int?,
      filename: map['filename'] as String? ?? '',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Fichier média en attente de soumission (avant upload)
class PendingMediaFile {
  final File file;
  final String type; // 'image', 'video', 'audio'
  final String originalFilename;
  final int? durationSeconds;

  const PendingMediaFile({
    required this.file,
    required this.type,
    required this.originalFilename,
    this.durationSeconds,
  });

  Future<int> get sizeBytes => file.length();
}
