/// rescuer_gps_provider.dart — Envoi GPS temps réel vers active_rescuers
/// Upsert la position toutes les 10 secondes via Supabase

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RescuerGpsNotifier extends StateNotifier<bool> {
  final SupabaseClient _supabase;
  StreamSubscription<Position>? _positionSub;
  Timer? _heartbeatTimer;

  RescuerGpsNotifier(this._supabase) : super(false);

  String? get _userId => _supabase.auth.currentUser?.id;

  /// Démarre le suivi GPS
  Future<void> startTracking() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    state = true;

    // Stream de position haute fréquence
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Minimum 5m de mouvement
      ),
    ).listen(_onPosition);

    // Heartbeat toutes les 10s même sans mouvement
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition();
        await _upsertPosition(pos);
      } catch (_) {}
    });
  }

  void _onPosition(Position pos) => _upsertPosition(pos);

  Future<void> _upsertPosition(Position pos) async {
    final uid = _userId;
    if (uid == null) return;
    try {
      await _supabase.from('active_rescuers').upsert(
        {
          'user_id': uid,
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracy': pos.accuracy,
          'heading': pos.heading,
          'speed': pos.speed,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id',
      );
    } catch (e) {
      // Silently fail — will retry next cycle
    }
  }

  /// Arrête le suivi et supprime la position
  Future<void> stopTracking() async {
    _positionSub?.cancel();
    _heartbeatTimer?.cancel();
    state = false;

    final uid = _userId;
    if (uid == null) return;
    try {
      await _supabase
          .from('active_rescuers')
          .delete()
          .eq('user_id', uid);
    } catch (_) {}
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }
}

final rescuerGpsProvider = StateNotifierProvider<RescuerGpsNotifier, bool>((ref) {
  return RescuerGpsNotifier(Supabase.instance.client);
});
