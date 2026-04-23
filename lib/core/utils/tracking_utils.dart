// tracking_utils.dart — Utilitaires partagés pour le tracking temps réel
// Haversine, ETA, time-ago, widgets de marqueurs (flutter_map), route Mapbox

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:http/http.dart' as http;

// ─── Mapbox token ───────────────────────────────────────────────────────────

const String mapboxToken =
    'pk.eyJ1Ijoic2hha2FkZXVtIiwiYSI6ImNtbjJoc3V0cTB6MDYycnNqazB6NjdzY3gifQ.2u3kJoor4SKro73-0ZJfWA';

// ─── Distance Haversine ─────────────────────────────────────────────────────

/// Calcule la distance à vol d'oiseau en km entre deux coordonnées GPS.
double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const R = 6371.0; // Rayon terrestre en km
  final dLat = _deg2rad(lat2 - lat1);
  final dLng = _deg2rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_deg2rad(lat1)) *
          math.cos(_deg2rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _deg2rad(double deg) => deg * math.pi / 180;

// ─── Estimation ETA ─────────────────────────────────────────────────────────

/// Estime le temps d'arrivée en minutes pour une distance donnée.
/// Vitesse moyenne urbaine : 25 km/h (ambulance en ville africaine).
int estimateEtaMinutes(double distanceKm, {double speedKmh = 25.0}) {
  if (distanceKm <= 0) return 0;
  return (distanceKm / speedKmh * 60).round().clamp(1, 120);
}

/// Formate la distance pour l'affichage.
String formatDistance(double distanceKm) {
  if (distanceKm < 1) {
    return '${(distanceKm * 1000).round()} m';
  }
  return '${distanceKm.toStringAsFixed(1)} km';
}

// ─── Time Ago ───────────────────────────────────────────────────────────────

/// Retourne une chaîne lisible "il y a X s/min/h" pour un timestamp donné.
String timeAgoString(DateTime? updatedAt) {
  if (updatedAt == null) return '';
  final diff = DateTime.now().toUtc().difference(updatedAt.toUtc());
  if (diff.inSeconds < 5) return 'à l\'instant';
  if (diff.inSeconds < 60) return 'il y a ${diff.inSeconds} s';
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  return 'il y a ${diff.inHours} h';
}

/// La position est-elle périmée ? (> 5 minutes)
bool isPositionStale(DateTime? updatedAt) {
  if (updatedAt == null) return true;
  return DateTime.now().toUtc().difference(updatedAt.toUtc()).inMinutes >= 5;
}

// ─── Route Mapbox Directions ────────────────────────────────────────────────

class RouteSegment {
  final List<LatLng> points;
  final Color color;

  RouteSegment({required this.points, required this.color});
}

Color _congestionToColor(String? congestion) {
  switch (congestion) {
    case 'severe':
      return Colors.red[700]!;
    case 'heavy':
      return Colors.orange;
    case 'moderate':
      return Colors.yellow[700]!;
    case 'low':
    default:
      return const Color(0xFF1565C0); // Blue
  }
}

/// Récupère la route réelle (polyline) entre deux points via Mapbox Directions API avec trafic.
/// Retourne une liste de RouteSegment (polylines découpées par couleur de trafic).
Future<List<RouteSegment>> fetchRouteSegments({
  required double originLat,
  required double originLng,
  required double destLat,
  required double destLng,
}) async {
  final fallbackPoints = [LatLng(originLat, originLng), LatLng(destLat, destLng)];
  final fallbackSegment = [RouteSegment(points: fallbackPoints, color: _congestionToColor('low'))];
  
  try {
    final url = Uri.parse(
      'https://api.mapbox.com/directions/v5/mapbox/driving-traffic/'
      '$originLng,$originLat;$destLng,$destLat'
      '?geometries=polyline6&overview=full&annotations=congestion&access_token=$mapboxToken',
    );
    final response = await http.get(url).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      debugPrint('[Route] Mapbox error: ${response.statusCode}');
      return fallbackSegment;
    }

    final data = json.decode(response.body);
    final routes = data['routes'] as List?;
    if (routes == null || routes.isEmpty) return fallbackSegment;

    final route = routes[0];
    final geometry = route['geometry'] as String?;
    if (geometry == null || geometry.isEmpty) return fallbackSegment;

    // Decode polyline6 (precision = 6)
    final points = _decodePolyline(geometry, precision: 6);
    if (points.length < 2) return fallbackSegment;

    // Récupérer la congestion (traffic)
    List<dynamic>? congestionList;
    if (route['legs'] != null && (route['legs'] as List).isNotEmpty) {
      final annotation = route['legs'][0]['annotation'];
      if (annotation != null && annotation['congestion'] != null) {
        congestionList = annotation['congestion'];
      }
    }

    if (congestionList == null || congestionList.isEmpty) {
      return [RouteSegment(points: points, color: _congestionToColor('low'))];
    }

    // Regrouper les segments par niveau de congestion pour limiter le nombre de Polylines
    final List<RouteSegment> segments = [];
    List<LatLng> currentPoints = [points[0]];
    String currentCongestion = congestionList[0].toString();

    for (int i = 0; i < points.length - 1; i++) {
      final String c = i < congestionList.length ? congestionList[i].toString() : 'low';
      
      if (c != currentCongestion) {
        // Clôturer le groupe précédent
        segments.add(RouteSegment(points: currentPoints, color: _congestionToColor(currentCongestion)));
        // Commencer un nouveau groupe (doit inclure le dernier point pour connecter la ligne)
        currentPoints = [points[i]];
        currentCongestion = c;
      }
      currentPoints.add(points[i + 1]);
    }
    
    // Ajouter le dernier groupe
    if (currentPoints.length > 1) {
      segments.add(RouteSegment(points: currentPoints, color: _congestionToColor(currentCongestion)));
    }

    return segments;
  } catch (e) {
    debugPrint('[Route] fetchRouteSegments error: $e');
    return fallbackSegment;
  }
}

/// Décode une polyline encodée (Google Encoded Polyline Algorithm).
/// [precision] : 5 pour polyline5 standard, 6 pour Mapbox polyline6.
List<LatLng> _decodePolyline(String encoded, {int precision = 6}) {
  final List<LatLng> points = [];
  int index = 0;
  int lat = 0;
  int lng = 0;
  final double factor = math.pow(10, precision).toDouble();

  while (index < encoded.length) {
    // Latitude
    int shift = 0;
    int result = 0;
    int byte;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1F) << shift;
      shift += 5;
    } while (byte >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    // Longitude
    shift = 0;
    result = 0;
    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1F) << shift;
      shift += 5;
    } while (byte >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    points.add(LatLng(lat / factor, lng / factor));
  }
  return points;
}

// ─── Marqueurs Flutter natifs ─────────────────────────────────────────────────

/// Widget de marqueur pour le secouriste (tourne avec le heading).
class RescuerMapMarker extends StatelessWidget {
  final double heading;
  final bool isStale;
  final bool isOffline;
  final bool isLowBattery;

  const RescuerMapMarker({
    super.key,
    this.heading = 0,
    this.isStale = false,
    this.isOffline = false,
    this.isLowBattery = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDegraded = isStale || isOffline;
    final Color primaryColor =
        isDegraded ? Colors.grey[500]! : const Color(0xFFE53935);
    final Color accentColor =
        isDegraded ? Colors.grey[400]! : const Color(0xFF1565C0);
    final Color glowColor = isDegraded
        ? Colors.grey.withValues(alpha: 0.2)
        : primaryColor.withValues(alpha: 0.3);

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // Halo pulsant
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: glowColor,
          ),
        ),
        // Cercle principal
        Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 3,
                offset: Offset(0, 1),
              )
            ],
          ),
          alignment: Alignment.center,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primaryColor,
            ),
            alignment: Alignment.center,
            // Croix blanche
            child: const Icon(Icons.add, color: Colors.white, size: 10),
          ),
        ),
        // Flèche directionnelle rotative
        Transform.rotate(
          angle: heading * math.pi / 180,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: CustomPaint(
                size: const Size(8, 8),
                painter: _ArrowPainter(color: accentColor),
              ),
            ),
          ),
        ),
        // Badge batterie faible
        if (isLowBattery && !isDegraded)
          Positioned(
            top: 2,
            right: 2,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.orange,
              ),
              child: const Icon(Icons.bolt, color: Colors.white, size: 8),
            ),
          ),
      ],
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final Color color;
  _ArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path();
    path.moveTo(size.width / 2, 0);
    path.lineTo(0, size.height);
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Widget de marqueur pour le citoyen (point bleu).
class CitizenMapMarker extends StatelessWidget {
  const CitizenMapMarker({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF1565C0).withValues(alpha: 0.2),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 12,
        height: 12,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 3,
              offset: Offset(0, 1),
            )
          ],
        ),
        alignment: Alignment.center,
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF1565C0),
          ),
        ),
      ),
    );
  }
}

// ─── Statut dispatch → label FR ─────────────────────────────────────────────

String dispatchStatusLabel(String status) {
  switch (status) {
    case 'processing':
      return 'Prise en charge';
    case 'dispatched':
      return 'Assigné';
    case 'en_route':
      return 'En route';
    case 'arrived':
      return 'Sur place';
    case 'en_route_hospital':
      return 'Vers l\'hôpital';
    case 'arrived_hospital':
      return 'À l\'hôpital';
    case 'transferring':
      return 'Transfert';
    case 'at_hospital':
      return 'À l\'hôpital';
    case 'completed':
      return 'Terminé';
    case 'cancelled':
      return 'Annulé';
    default:
      return 'Intervention';
  }
}

/// Icône associée au statut dispatch.
IconData dispatchStatusIcon(String status) {
  switch (status) {
    case 'processing':
      return Icons.hourglass_top_rounded;
    case 'dispatched':
      return Icons.person_pin_circle_rounded;
    case 'en_route':
      return Icons.airport_shuttle_rounded;
    case 'arrived':
      return Icons.location_on_rounded;
    case 'en_route_hospital':
      return Icons.local_hospital_rounded;
    case 'arrived_hospital':
      return Icons.local_hospital_rounded;
    case 'completed':
      return Icons.check_circle_rounded;
    default:
      return Icons.info_outline_rounded;
  }
}

/// Couleur associée au statut dispatch.
Color dispatchStatusColor(String status) {
  switch (status) {
    case 'processing':
      return Colors.orange;
    case 'dispatched':
      return const Color(0xFF1565C0);
    case 'en_route':
      return const Color(0xFF10B981);
    case 'arrived':
      return Colors.deepPurple;
    case 'en_route_hospital':
      return const Color(0xFF1565C0);
    case 'arrived_hospital':
      return const Color(0xFF1565C0);
    case 'completed':
      return Colors.green;
    default:
      return Colors.blueAccent;
  }
}
