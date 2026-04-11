import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:video_compress/video_compress.dart';
import '../models/signalement_models.dart';

/// Contraintes médias — §5.1 & §5.6 du guide
class MediaLimits {
  static const int maxPhotos = 10;
  static const int maxVideos = 3;
  static const int maxAudios = 5;
  static const int maxTotalBytes = 50 * 1024 * 1024; // 50 MB
  static const int maxImageBytes = 2 * 1024 * 1024;  // 2 MB
  static const int maxVideoBytes = 20 * 1024 * 1024;  // 20 MB
  static const int maxAudioBytes = 5 * 1024 * 1024;   // 5 MB
  static const int maxVideoDuration = 120;             // 2 min
  static const int maxAudioDuration = 300;             // 5 min
}

class MediaValidationResult {
  final bool valid;
  final String? error;
  const MediaValidationResult({required this.valid, this.error});
}

class SignalementMediaProcessor {
  /// Validate limits before submission
  static MediaValidationResult validateLimits(List<PendingMediaFile> files) {
    final photos = files.where((f) => f.type == 'image').length;
    final videos = files.where((f) => f.type == 'video').length;
    final audios = files.where((f) => f.type == 'audio').length;

    if (photos > MediaLimits.maxPhotos) {
      return MediaValidationResult(valid: false, error: 'signalement.limit_photos_exceeded'.tr(namedArgs: {'max': '${MediaLimits.maxPhotos}'}));
    }
    if (videos > MediaLimits.maxVideos) {
      return MediaValidationResult(valid: false, error: 'signalement.limit_videos_exceeded'.tr(namedArgs: {'max': '${MediaLimits.maxVideos}'}));
    }
    if (audios > MediaLimits.maxAudios) {
      return MediaValidationResult(valid: false, error: 'signalement.limit_audios'.tr(namedArgs: {'max': '${MediaLimits.maxAudios}'}));
    }

    for (final f in files) {
      if (f.type == 'video' && f.durationSeconds != null && f.durationSeconds! > MediaLimits.maxVideoDuration) {
        return MediaValidationResult(valid: false, error: 'signalement.limit_video_duration'.tr(namedArgs: {'max': '${MediaLimits.maxVideoDuration}'}));
      }
      if (f.type == 'audio' && f.durationSeconds != null && f.durationSeconds! > MediaLimits.maxAudioDuration) {
        return MediaValidationResult(valid: false, error: 'signalement.limit_audio_duration'.tr(namedArgs: {'max': '${MediaLimits.maxAudioDuration ~/ 60}'}));
      }
    }

    return const MediaValidationResult(valid: true);
  }

  // ─── COMPRESSION ────────────────────────────────────────────────────────────

  static Future<Uint8List> compressImage(File file) async {
    final result = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: 1920,
      minHeight: 1080,
      quality: 75,
      format: CompressFormat.jpeg,
    );
    if (result == null) throw Exception('Compression image échouée');

    if (result.length > MediaLimits.maxImageBytes) {
      final retry = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 1280,
        minHeight: 720,
        quality: 50,
        format: CompressFormat.jpeg,
      );
      return retry ?? result;
    }
    return result;
  }

  static Future<Uint8List> compressVideo(File file) async {
    final info = await VideoCompress.compressVideo(
      file.path,
      quality: VideoQuality.MediumQuality,
      deleteOrigin: false,
      includeAudio: true,
    );
    if (info?.file == null) throw Exception('Compression vidéo échouée');

    final bytes = await info!.file!.readAsBytes();
    if (bytes.length > MediaLimits.maxVideoBytes) {
      final retry = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.LowQuality,
        deleteOrigin: false,
        includeAudio: true,
      );
      if (retry?.file != null) return retry!.file!.readAsBytes();
    }
    return bytes;
  }

  static Future<Uint8List> compressAudio(File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length <= MediaLimits.maxAudioBytes) return bytes;
    // AAC is already compressed at recording time (64kbps).
    // Truncating produces an invalid m4a container — reject instead.
    debugPrint('[MediaProcessor] Audio exceeds ${MediaLimits.maxAudioBytes ~/ (1024 * 1024)}MB, rejecting');
    throw Exception('signalement.limit_audio_duration'.tr(namedArgs: {'max': '${MediaLimits.maxAudioDuration ~/ 60}'}));
  }

  static Future<Uint8List> compressMedia(PendingMediaFile media) async {
    switch (media.type) {
      case 'image':
        return compressImage(media.file);
      case 'video':
        return compressVideo(media.file);
      case 'audio':
        return compressAudio(media.file);
      default:
        return media.file.readAsBytes();
    }
  }

  // ─── THUMBNAILS ─────────────────────────────────────────────────────────────

  static Future<Uint8List?> generateThumbnail(PendingMediaFile media) async {
    try {
      if (media.type == 'video') {
        return await VideoCompress.getByteThumbnail(
          media.file.path,
          quality: 60,
          position: 1,
        );
      }
      if (media.type == 'image') {
        return await FlutterImageCompress.compressWithFile(
          media.file.absolute.path,
          minWidth: 300,
          minHeight: 300,
          quality: 50,
          format: CompressFormat.jpeg,
        );
      }
    } catch (e) {
      debugPrint('[Signalement] Thumbnail generation failed: $e');
    }
    return null;
  }

  // ─── HELPERS ────────────────────────────────────────────────────────────────

  static String extensionForType(String type) =>
      type == 'image' ? 'jpg' : type == 'video' ? 'mp4' : 'm4a';

  static String contentTypeForType(String type) =>
      type == 'image' ? 'image/jpeg' : type == 'video' ? 'video/mp4' : 'audio/mp4';
}
