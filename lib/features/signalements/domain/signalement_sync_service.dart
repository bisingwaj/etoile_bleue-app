import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:etoile_bleue_mobile/core/services/connectivity_service.dart';
import '../data/signalement_offline_queue.dart';
import '../data/signalement_repository.dart';
import '../data/signalement_media_processor.dart';
import '../models/signalement_models.dart';
import 'package:etoile_bleue_mobile/core/services/location_service.dart';

class SignalementSyncService {
  final SignalementRepository _repo;
  final LocationService _location;
  final ConnectivityService _connectivity;
  StreamSubscription<void>? _onBackOnlineSub;
  bool _syncing = false;

  final ValueNotifier<int> pendingCount = ValueNotifier(0);

  SignalementSyncService(this._repo, this._location, this._connectivity) {
    _onBackOnlineSub = _connectivity.onBackOnline.listen((_) => syncAll());
    _refreshCount();
  }

  Future<void> _refreshCount() async {
    pendingCount.value = await SignalementOfflineQueue.pendingCount;
  }

  Future<void> syncAll() async {
    if (_syncing) return;
    if (!_connectivity.isOnline.value) return;
    _syncing = true;
    debugPrint('[Sync] Starting offline signalement sync...');

    try {
      final pending = await SignalementOfflineQueue.getPending();
      if (pending.isNotEmpty) {
        for (final item in pending) {
          if (!_connectivity.isOnline.value) break;

          try {
            await _submitOfflineItem(item);
            await SignalementOfflineQueue.remove(item.localId);
            debugPrint('[Sync] Successfully synced: ${item.localId}');
          } catch (e) {
            debugPrint('[Sync] Failed to sync ${item.localId}: $e');
            final newCount = item.retryCount + 1;
            if (newCount >= 10) {
              debugPrint('[Sync] Max retries reached for ${item.localId}, removing');
              await SignalementOfflineQueue.remove(item.localId);
            } else {
              await SignalementOfflineQueue.updateRetryCount(item.localId, newCount);
              // Exponential backoff before next item
              await Future.delayed(Duration(seconds: newCount * 2));
            }
          }
        }
      }

      final pendingOrphans = await SignalementOfflineQueue.getPendingOrphans();
      if (pendingOrphans.isNotEmpty) {
        for (final item in pendingOrphans) {
          if (!_connectivity.isOnline.value) break;

          try {
            await _submitOrphanItem(item);
            await SignalementOfflineQueue.removeOrphan(item.id);
            debugPrint('[Sync] Successfully synced orphan: ${item.id}');
          } catch (e) {
            debugPrint('[Sync] Failed to sync orphan ${item.id}: $e');
            final newCount = item.retryCount + 1;
            if (newCount >= 10) {
              debugPrint('[Sync] Max retries reached for orphan ${item.id}, removing');
              await SignalementOfflineQueue.removeOrphan(item.id);
            } else {
              await SignalementOfflineQueue.updateOrphanRetryCount(item.id, newCount);
              await Future.delayed(Duration(seconds: newCount * 2));
            }
          }
        }
      }

    } finally {
      _syncing = false;
      await _refreshCount();
    }
  }

  Future<void> _submitOfflineItem(OfflineSignalement item) async {
    double? lat;
    double? lng;
    try {
      final pos = await _location.getCurrentPosition();
      lat = pos?['lat'];
      lng = pos?['lng'];
    } catch (_) {}

    final signalementId = await _repo.createSignalement(
      title: item.title,
      category: item.category,
      description: item.description,
      province: item.province,
      ville: item.ville,
      commune: item.commune,
      lat: lat,
      lng: lng,
      structureName: item.structureName,
      structureId: item.structureId,
      priority: item.priority,
      isAnonymous: item.isAnonymous,
    );

    for (final media in item.mediaRefs) {
      bool uploaded = false;
      try {
        final file = File(media.localPath);
        if (!await file.exists()) {
          // File already gone — skip cleanup too
          uploaded = true;
          continue;
        }

        final pending = PendingMediaFile(
          file: file,
          type: media.type,
          originalFilename: media.originalFilename,
          durationSeconds: media.durationSeconds,
        );

        final compressed = await SignalementMediaProcessor.compressMedia(pending);
        final thumbnail = await SignalementMediaProcessor.generateThumbnail(pending);

        final ext = SignalementMediaProcessor.extensionForType(media.type);
        final ts = DateTime.now().millisecondsSinceEpoch;
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
          } catch (_) {}
        }

        await _repo.insertMediaRow(
          signalementId: signalementId,
          type: media.type,
          url: url,
          thumbnail: thumbUrl,
          duration: media.durationSeconds,
          filename: media.originalFilename,
        );
        uploaded = true;
      } catch (e) {
        debugPrint('[Sync] Media upload failed, saving as orphan: $e');
        // Save as orphan so it can be retried later — do NOT delete the local file
        try {
          await SignalementOfflineQueue.enqueueOrphan(OrphanMedia(
            id: 'orphan_sync_${DateTime.now().millisecondsSinceEpoch}_${media.localPath.hashCode}',
            signalementId: signalementId,
            mediaRef: media,
            createdAt: DateTime.now(),
          ));
        } catch (orphanErr) {
          debugPrint('[Sync] Failed to enqueue orphan: $orphanErr');
        }
      }

      // Only delete local file if upload succeeded
      if (uploaded) {
        try {
          final file = File(media.localPath);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _submitOrphanItem(OrphanMedia item) async {
    final media = item.mediaRef;
    final file = File(media.localPath);
    if (!await file.exists()) return; // File already gone

    final pending = PendingMediaFile(
      file: file,
      type: media.type,
      originalFilename: media.originalFilename,
      durationSeconds: media.durationSeconds,
    );

    final compressed = await SignalementMediaProcessor.compressMedia(pending);
    final thumbnail = await SignalementMediaProcessor.generateThumbnail(pending);

    final ext = SignalementMediaProcessor.extensionForType(media.type);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final storagePath = 'signalements/${item.signalementId}/${media.type}_$ts.$ext';

    final url = await _repo.uploadBytes(
      storagePath: storagePath,
      bytes: compressed,
      contentType: SignalementMediaProcessor.contentTypeForType(media.type),
    );

    String? thumbUrl;
    if (thumbnail != null) {
      try {
        final thumbPath = 'signalements/${item.signalementId}/thumb_${media.type}_$ts.jpg';
        thumbUrl = await _repo.uploadBytes(
          storagePath: thumbPath,
          bytes: thumbnail,
          contentType: 'image/jpeg',
        );
      } catch (_) {}
    }

    await _repo.insertMediaRow(
      signalementId: item.signalementId,
      type: media.type,
      url: url,
      thumbnail: thumbUrl,
      duration: media.durationSeconds,
      filename: media.originalFilename,
    );

    // Cleanup local file after successful sync
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  void dispose() {
    _onBackOnlineSub?.cancel();
    pendingCount.dispose();
  }
}

final signalementSyncServiceProvider = Provider<SignalementSyncService>((ref) {
  final repo = ref.watch(signalementRepositoryProvider);
  final location = ref.watch(locationServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final service = SignalementSyncService(repo, location, connectivity);
  ref.onDispose(() => service.dispose());
  return service;
});

final pendingSyncCountProvider = Provider<int>((ref) {
  final service = ref.watch(signalementSyncServiceProvider);
  final notifier = service.pendingCount;

  void listener() => ref.invalidateSelf();
  notifier.addListener(listener);
  ref.onDispose(() => notifier.removeListener(listener));

  return notifier.value;
});
