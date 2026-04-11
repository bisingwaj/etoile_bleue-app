import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Service de géolocalisation temps réel pour les secouristes.
///
/// ─── Edge Cases couverts ──────────────────────────────────────────────────────
/// ✅ EC-7  : UID capturé au runtime (pas à l'init) — corrige le bug si service créé avant login
/// ✅ EC-8  : startTracking() appelé deux fois — guard _isTracking empêche un double stream
/// ✅ EC-9  : stopTracking() si uid nul — skip silencieux du delete Supabase
/// ✅ EC-10 : GPS service désactivé sur l'appareil — log explicite + return false
/// ✅ EC-11 : Permission refusée définitivement — badge "Paramètres" à afficher dans l'UI
/// ✅ EC-12 : Erreur Supabase transitoire → retry automatique via le prochain événement stream
class LocationService {
  final SupabaseClient _supabase;
  bool _isTracking = false; // EC-8 : Guard anti-double stream

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<Position>? _citizenPositionSub; // Flux pour le citoyen en SOS
  DateTime? _lastUpdate;

  static const int _throttleSeconds = 5;
  static const LocationSettings _locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10,
  );

  LocationService({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  // EC-7 : UID résolu à chaque appel (pas à l'init) pour supporter le cycle login/logout
  String? get _uid => _supabase.auth.currentUser?.id;

  // ─── PERMISSIONS ─────────────────────────────────────────────────────────────

  /// Vérifie et demande les permissions GPS.
  /// Retourne le statut pour que l'UI puisse réagir (ex: badge "Activer GPS").
  Future<LocationPermission> requestPermission() async {
    // EC-10 : GPS désactivé sur l'appareil
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('[LocationService] GPS désactivé sur l\'appareil.');
      return LocationPermission.denied;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // EC-11 : Permission refusée définitivement — ne pas reboucler en boucle
    if (permission == LocationPermission.deniedForever) {
      debugPrint('[LocationService] Permission refusée définitivement — ouvrir les Paramètres.');
    }

    return permission;
  }

  // ─── POSITION UNIQUE ─────────────────────────────────────────────────────────

  /// Obtenir une position GPS ponctuelle (pour le SOS).
  Future<Map<String, double>?> getCurrentPosition() async {
    final permission = await requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 10));
      return {'lat': position.latitude, 'lng': position.longitude};
    } catch (e) {
      debugPrint('[LocationService] Position courante échouée, tentative dernière position connue: $e');
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          debugPrint('[LocationService] Dernière position connue utilisée');
          return {'lat': last.latitude, 'lng': last.longitude};
        }
      } catch (e2) {
        debugPrint('[LocationService] Dernière position échouée: $e2');
      }
      return null;
    }
  }

  // ─── STREAM TEMPS RÉEL (Citoyens) ─────────────────────────────────────────

  /// Démarrer le flux GPS temps réel → update `incidents`
  Future<void> startCitizenTracking(String incidentReference) async {
    final permission = await requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    await _citizenPositionSub?.cancel();
    _citizenPositionSub = Geolocator.getPositionStream(
      locationSettings: _locationSettings,
    ).listen(
      (Position position) async {
        try {
          await _supabase.from('incidents').update({
            'caller_realtime_lat': position.latitude,
            'caller_realtime_lng': position.longitude,
            'caller_realtime_updated_at': DateTime.now().toUtc().toIso8601String(),
          }).eq('reference', incidentReference);
        } catch (e) {
          debugPrint('[LocationService] Erreur mise à jour GPS citoyen: $e');
        }
      },
    );
    debugPrint('[LocationService] Suivi GPS citoyen démarré pour l\'incident \$incidentReference');
  }

  /// Arrêter le flux GPS du citoyen
  Future<void> stopCitizenTracking() async {
    await _citizenPositionSub?.cancel();
    _citizenPositionSub = null;
    debugPrint('[LocationService] Suivi GPS citoyen arrêté');
  }

  // ─── STREAM TEMPS RÉEL (Secouristes) ─────────────────────────────────────────

  /// Démarrer le flux GPS temps réel → Supabase `active_rescuers`
  Future<void> startTracking() async {
    // EC-7 : UID résolu au runtime
    final uid = _uid;
    if (uid == null) {
      debugPrint('[LocationService] Utilisateur non connecté — tracking ignoré.');
      return;
    }

    // EC-8 : Guard anti-double stream
    if (_isTracking) {
      debugPrint('[LocationService] Tracking déjà actif.');
      return;
    }

    final permission = await requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    _isTracking = true;
    _positionSub = Geolocator.getPositionStream(
      locationSettings: _locationSettings,
    ).listen(
      (Position position) => _publishPosition(position, uid),
      onError: (e) {
        // EC-12 : Erreur stream GPS — log mais ne pas crasher
        debugPrint('[LocationService] Erreur stream GPS: $e');
      },
    );

    debugPrint('[LocationService] Suivi GPS démarré pour $uid');
  }

  Future<void> _publishPosition(Position position, String uid) async {
    // Throttle : max une mise à jour toutes les _throttleSeconds secondes
    final now = DateTime.now();
    if (_lastUpdate != null &&
        now.difference(_lastUpdate!).inSeconds < _throttleSeconds) {
      return;
    }
    _lastUpdate = now;

    try {
      await _supabase.from('active_rescuers').upsert({
        'uid': uid,
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracy': position.accuracy,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // EC-12 : Erreur Supabase transitoire — le prochain événement GPS retentera
      debugPrint('[LocationService] Erreur écriture Supabase: $e');
    }
  }

  /// Arrêter le flux GPS et supprimer la présence du secouriste.
  Future<void> stopTracking() async {
    _isTracking = false;
    await _positionSub?.cancel();
    _positionSub = null;
    _lastUpdate = null;

    // EC-9 : uid nul → skip le delete (déjà non-présent dans Supabase)
    final uid = _uid;
    if (uid != null) {
      try {
        await _supabase.from('active_rescuers').delete().eq('uid', uid);
        debugPrint('[LocationService] ✅ Secouriste retiré de active_rescuers');
      } catch (e) {
        debugPrint('[LocationService] Erreur suppression: $e');
      }
    }
  }

  /// Écouter les positions de tous les secouristes actifs (pour la carte).
  Stream<List<Map<String, dynamic>>> watchActiveRescuers() {
    return _supabase
        .from('active_rescuers')
        .stream(primaryKey: ['uid'])
        .map((docs) => docs);
  }

  void dispose() {
    _positionSub?.cancel();
    _citizenPositionSub?.cancel();
    _isTracking = false;
  }
}

/// Provider Riverpod pour le LocationService
final locationServiceProvider = Provider<LocationService>((ref) {
  final service = LocationService();
  ref.onDispose(service.dispose);
  return service;
});
