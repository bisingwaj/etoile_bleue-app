import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:etoile_bleue_mobile/core/services/location_service.dart';
import 'package:etoile_bleue_mobile/core/services/connectivity_service.dart';
import '../data/signalement_repository.dart';
import '../data/signalement_media_processor.dart';
import '../data/signalement_offline_queue.dart';
import '../models/signalement_models.dart';

class SubmitResult {
  final String signalementId;
  final String reference;
  final int mediaCount;
  final int mediaUploaded;
  final bool hasLocation;
  final bool pendingSync;

  const SubmitResult({
    required this.signalementId,
    required this.reference,
    required this.mediaCount,
    required this.mediaUploaded,
    required this.hasLocation,
    this.pendingSync = false,
  });
}

class SubmitProgress {
  final String step; // 'validating', 'gps', 'creating', 'compressing', 'uploading', 'done'
  final double progress; // 0.0 to 1.0
  final String? detail;

  const SubmitProgress({required this.step, required this.progress, this.detail});
}

class SignalementSubmitService {
  final SignalementRepository _repo;
  final LocationService _location;
  final ConnectivityService _connectivity;

  SignalementSubmitService(this._repo, this._location, this._connectivity);

  /// Full submit pipeline with progress reporting.
  /// Falls back to offline queue when no network is available.
  Future<SubmitResult> submit({
    required String title,
    required String category,
    required String description,
    String province = 'Kinshasa',
    String ville = 'Kinshasa',
    String? commune,
    bool isAnonymous = false,
    String priority = 'moyenne',
    String? structureName,
    String? structureId,
    List<PendingMediaFile> mediaFiles = const [],
    void Function(SubmitProgress)? onProgress,
  }) async {
    // 1. Validate media limits
    onProgress?.call(const SubmitProgress(step: 'validating', progress: 0.0));
    final validation = SignalementMediaProcessor.validateLimits(mediaFiles);
    if (!validation.valid) {
      throw Exception(validation.error);
    }

    // 2. Check total size
    int totalSize = 0;
    for (final f in mediaFiles) {
      totalSize += await f.sizeBytes;
    }
    if (totalSize > MediaLimits.maxTotalBytes) {
      throw Exception('signalement.error_size'.tr(namedArgs: {'max': '${MediaLimits.maxTotalBytes ~/ (1024 * 1024)}'}));
    }

    // 2b. If offline, save to local queue
    if (!_connectivity.isOnline.value) {
      return _saveOffline(
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
        mediaFiles: mediaFiles,
        onProgress: onProgress,
      );
    }

    // 3. GPS
    onProgress?.call(SubmitProgress(step: 'gps', progress: 0.05, detail: 'signalement.progress_gps'.tr()));
    double? lat;
    double? lng;
    try {
      final pos = await _location.getCurrentPosition();
      lat = pos?['lat'];
      lng = pos?['lng'];
    } catch (e) {
      debugPrint('[Signalement] GPS non disponible: $e');
    }

    // 4. Deduplication check
    onProgress?.call(SubmitProgress(step: 'validating', progress: 0.1, detail: 'signalement.progress_validating'.tr()));
    if (await _repo.isDuplicate(title, isAnonymous: isAnonymous)) {
      throw Exception('signalement.error_duplicate'.tr());
    }

    // 5. INSERT signalement
    onProgress?.call(SubmitProgress(step: 'creating', progress: 0.15, detail: 'signalement.progress_creating'.tr()));
    String? signalementId;
    
    try {
      signalementId = await _repo.createSignalement(
        title: title,
        category: category,
        description: description,
        province: province,
        ville: ville,
        commune: commune,
        lat: lat,
        lng: lng,
        structureName: structureName,
        structureId: structureId,
        priority: priority,
        isAnonymous: isAnonymous,
      );
    } catch (e) {
      debugPrint('[Signalement] Failure creating signalement: $e');
      // Only fall back to offline queue for genuine network/connectivity errors.
      // Business/auth errors (RLS, auth, validation) should surface to the user.
      final isNetworkError = e is SocketException ||
          e is HttpException ||
          e.toString().contains('network') ||
          e.toString().contains('connection') ||
          e.toString().contains('timeout') ||
          e.toString().contains('unreachable');
      if (isNetworkError) {
        return _saveOffline(
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
          mediaFiles: mediaFiles,
          onProgress: onProgress,
        );
      }
      // Re-throw so the UI can display a meaningful error to the user
      rethrow;
    }

    // Read back the reference
    String reference = '';
    try {
      final sig = await _repo.getSignalement(signalementId);
      reference = sig?.reference ?? signalementId;
    } catch (_) {
      reference = signalementId;
    }

    // 6. Compress + upload media in parallel chunks of 3
    int uploaded = 0;
    final totalMedia = mediaFiles.length;
    final indexedMedia = List.generate(totalMedia, (i) => i);
    final chunks = <List<int>>[];
    for (var i = 0; i < indexedMedia.length; i += 3) {
      chunks.add(indexedMedia.sublist(i, i + 3 > indexedMedia.length ? indexedMedia.length : i + 3));
    }

    for (final chunk in chunks) {
      final futures = chunk.map((i) async {
        final media = mediaFiles[i];
        final mediaProgress = 0.2 + (0.75 * i / (totalMedia == 0 ? 1 : totalMedia));
        final label = '${media.type} ${i + 1}/$totalMedia';

        try {
          onProgress?.call(SubmitProgress(
            step: 'compressing',
            progress: mediaProgress,
            detail: 'signalement.progress_compressing'.tr(namedArgs: {'label': label}),
          ));
          final compressed = await SignalementMediaProcessor.compressMedia(media);
          final thumbnail = await SignalementMediaProcessor.generateThumbnail(media);

          onProgress?.call(SubmitProgress(
            step: 'uploading',
            progress: mediaProgress + 0.05,
            detail: 'signalement.progress_uploading'.tr(namedArgs: {'label': label}),
          ));
          final ext = SignalementMediaProcessor.extensionForType(media.type);
          final ts = DateTime.now().millisecondsSinceEpoch + i;
          final storagePath = 'signalements/$signalementId/${media.type}_$ts.$ext';

          final url = await _repo.uploadBytes(
            storagePath: storagePath,
            bytes: compressed,
            contentType: SignalementMediaProcessor.contentTypeForType(media.type),
          );

          String? thumbUrl;
          if (thumbnail != null) {
            try {
              final thumbPath = 'signalements/$signalementId/thumb_${media.type}_$ts.jpg';
              thumbUrl = await _repo.uploadBytes(
                storagePath: thumbPath,
                bytes: thumbnail,
                contentType: 'image/jpeg',
              );
            } catch (e) {
              debugPrint('[Signalement] Thumbnail upload failed (non-fatal): $e');
            }
          }

          await _repo.insertMediaRow(
            signalementId: signalementId!,
            type: media.type,
            url: url,
            thumbnail: thumbUrl,
            duration: media.durationSeconds,
            filename: media.originalFilename,
          );

          uploaded++;
          debugPrint('[Signalement] Média $label uploadé avec succès');
        } catch (e) {
          debugPrint('[Signalement] ECHEC média $label: $e');
          // Sauvegarde dans la queue des médias orphelins
          final orphan = OrphanMedia(
            id: 'orphan_${DateTime.now().millisecondsSinceEpoch}_$i',
            signalementId: signalementId!,
            mediaRef: OfflineMediaRef(
              localPath: media.file.path,
              type: media.type,
              originalFilename: media.originalFilename,
              durationSeconds: media.durationSeconds,
            ),
            createdAt: DateTime.now(),
          );
          await SignalementOfflineQueue.enqueueOrphan(orphan);
        }
      });
      await Future.wait(futures);
    }

    onProgress?.call(SubmitProgress(step: 'done', progress: 1.0, detail: 'signalement.progress_done'.tr()));
    debugPrint('[Signalement] Soumission terminée: $signalementId — $uploaded/$totalMedia médias uploadés');

    return SubmitResult(
      signalementId: signalementId,
      reference: reference,
      mediaCount: totalMedia,
      mediaUploaded: uploaded,
      hasLocation: lat != null,
    );
  }

  Future<SubmitResult> _saveOffline({
    required String title,
    required String category,
    required String description,
    required String province,
    required String ville,
    String? commune,
    required bool isAnonymous,
    required String priority,
    String? structureName,
    String? structureId,
    required List<PendingMediaFile> mediaFiles,
    void Function(SubmitProgress)? onProgress,
  }) async {
    onProgress?.call(SubmitProgress(
      step: 'creating',
      progress: 0.5,
      detail: 'common.pending_sync'.tr(),
    ));

    final localId = 'offline_${DateTime.now().millisecondsSinceEpoch}';
    final mediaRefs = mediaFiles.map((m) => OfflineMediaRef(
      localPath: m.file.path,
      type: m.type,
      originalFilename: m.originalFilename,
      durationSeconds: m.durationSeconds,
    )).toList();

    await SignalementOfflineQueue.enqueue(OfflineSignalement(
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
      createdAt: DateTime.now(),
    ));

    onProgress?.call(SubmitProgress(step: 'done', progress: 1.0, detail: 'common.pending_sync'.tr()));

    return SubmitResult(
      signalementId: localId,
      reference: 'SIG-OFFLINE-$localId',
      mediaCount: mediaFiles.length,
      mediaUploaded: 0,
      hasLocation: false,
      pendingSync: true,
    );
  }
}
