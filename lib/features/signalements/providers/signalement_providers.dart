import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/services/location_service.dart';
import 'package:etoile_bleue_mobile/core/services/cache_service.dart';
import 'package:etoile_bleue_mobile/core/services/connectivity_service.dart';
import '../data/signalement_repository.dart';
import '../domain/signalement_submit_service.dart';
import '../models/signalement_models.dart';

// ─── LIST PROVIDER (curseur paginé) ───────────────────────────────────────────

class SignalementsListNotifier extends StateNotifier<AsyncValue<List<Signalement>>> {
  final SignalementRepository _repo;
  String? _cursor;
  bool _hasMore = true;
  bool _loading = false;

  SignalementsListNotifier(this._repo) : super(const AsyncValue.loading()) {
    loadInitial();
  }

  Future<void> loadInitial() async {
    state = const AsyncValue.loading();
    _cursor = null;
    _hasMore = true;

    // Serve cache instantly
    final cached = CacheService.getCachedSignalements();
    if (cached != null && cached.isNotEmpty) {
      final cachedItems = cached.map((m) => Signalement.fromMap(m)).toList();
      state = AsyncValue.data(cachedItems);
      _cursor = cachedItems.isNotEmpty ? cachedItems.last.createdAt.toUtc().toIso8601String() : null;
    }

    try {
      final items = await _repo.listMySignalements(limit: 30);
      _cursor = items.isNotEmpty ? items.last.createdAt.toUtc().toIso8601String() : null;
      _hasMore = items.length >= 30;
      state = AsyncValue.data(items);
      CacheService.cacheSignalements(items.map((s) => s.toMap()).toList());
    } catch (e, st) {
      debugPrint('[Signalement] List error: $e');
      if (cached == null || cached.isEmpty) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || _loading) return;
    _loading = true;
    try {
      final items = await _repo.listMySignalements(cursor: _cursor, limit: 30);
      if (items.isEmpty) {
        _hasMore = false;
      } else {
        _cursor = items.last.createdAt.toUtc().toIso8601String();
        _hasMore = items.length >= 30;
        final current = state.valueOrNull ?? [];
        state = AsyncValue.data([...current, ...items]);
      }
    } catch (e) {
      debugPrint('[Signalement] Load more error: $e');
    }
    _loading = false;
  }

  void prepend(Signalement item) {
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data([item, ...current]);
  }

  bool get hasMore => _hasMore;
}

final signalementsListProvider =
    StateNotifierProvider<SignalementsListNotifier, AsyncValue<List<Signalement>>>((ref) {
  final repo = ref.watch(signalementRepositoryProvider);
  return SignalementsListNotifier(repo);
});

// ─── SUBMIT PROVIDER ──────────────────────────────────────────────────────────

enum SubmitState { idle, submitting, success, error }

class SignalementSubmitState {
  final SubmitState status;
  final double progress;
  final String? progressDetail;
  final SubmitResult? result;
  final String? errorMessage;

  const SignalementSubmitState({
    this.status = SubmitState.idle,
    this.progress = 0.0,
    this.progressDetail,
    this.result,
    this.errorMessage,
  });

  SignalementSubmitState copyWith({
    SubmitState? status,
    double? progress,
    String? progressDetail,
    SubmitResult? result,
    String? errorMessage,
  }) {
    return SignalementSubmitState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      progressDetail: progressDetail ?? this.progressDetail,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class SignalementSubmitNotifier extends StateNotifier<SignalementSubmitState> {
  final SignalementSubmitService _service;

  SignalementSubmitNotifier(this._service) : super(const SignalementSubmitState());

  Future<SubmitResult?> submit({
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
  }) async {
    state = const SignalementSubmitState(status: SubmitState.submitting, progress: 0.0);

    try {
      final result = await _service.submit(
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
        onProgress: (p) {
          if (mounted) {
            state = state.copyWith(
              progress: p.progress,
              progressDetail: p.detail,
            );
          }
        },
      );

      state = SignalementSubmitState(
        status: SubmitState.success,
        progress: 1.0,
        result: result,
      );
      debugPrint('[Signalement] Submit success: ${result.signalementId}');
      return result;
    } catch (e) {
      debugPrint('[Signalement] Submit error: $e');
      state = SignalementSubmitState(
        status: SubmitState.error,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
      return null;
    }
  }

  void reset() => state = const SignalementSubmitState();
}

final signalementSubmitProvider =
    StateNotifierProvider<SignalementSubmitNotifier, SignalementSubmitState>((ref) {
  final repo = ref.watch(signalementRepositoryProvider);
  final location = ref.watch(locationServiceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final service = SignalementSubmitService(repo, location, connectivity);
  return SignalementSubmitNotifier(service);
});

// ─── REALTIME PROVIDER ────────────────────────────────────────────────────────

final signalementRealtimeProvider = Provider.autoDispose<void>((ref) {
  final db = Supabase.instance.client;
  final repo = ref.watch(signalementRepositoryProvider);

  Future<void> setupRealtime() async {
    final profile = await repo.getCitizenProfile();
    final phone = profile.phone;
    if (phone == null) {
      debugPrint('[Signalement] Realtime: pas de téléphone trouvé dans users_directory');
      return;
    }

    final channel = db
        .channel('my-signalements-${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'signalements',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'citizen_phone',
            value: phone,
          ),
          callback: (payload) {
            debugPrint('[Signalement] Realtime update: ${payload.newRecord['reference']} → ${payload.newRecord['status']}');
            ref.invalidate(signalementsListProvider);
          },
        )
        .subscribe();

    ref.onDispose(() {
      db.removeChannel(channel);
      debugPrint('[Signalement] Realtime unsubscribed');
    });
  }

  setupRealtime();
});

// ─── DETAIL PROVIDER ──────────────────────────────────────────────────────────

final signalementDetailProvider =
    FutureProvider.autoDispose.family<Signalement?, String>((ref, id) async {
  final repo = ref.watch(signalementRepositoryProvider);
  return repo.getSignalement(id);
});

// ─── STRUCTURE SEARCH ─────────────────────────────────────────────────────────

final structureSearchProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, query) async {
  final repo = ref.watch(signalementRepositoryProvider);
  return repo.searchStructures(query);
});
