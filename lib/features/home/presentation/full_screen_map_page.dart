import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:etoile_bleue_mobile/core/providers/active_intervention_provider.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'package:etoile_bleue_mobile/core/utils/tracking_utils.dart';
import 'package:go_router/go_router.dart';
import 'package:etoile_bleue_mobile/core/router/app_router.dart';
import 'package:etoile_bleue_mobile/features/directory/presentation/directory_page.dart';
import 'package:etoile_bleue_mobile/features/directory/data/health_structures_repository.dart';
import 'dart:math' as math;

class FullScreenMapPage extends ConsumerStatefulWidget {
  final Position? initialUserPosition;

  const FullScreenMapPage({
    super.key,
    this.initialUserPosition,
  });

  @override
  ConsumerState<FullScreenMapPage> createState() => _FullScreenMapPageState();
}

class _FullScreenMapPageState extends ConsumerState<FullScreenMapPage>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();

  // Timer pour rafraîchir le "il y a X s" chaque seconde
  Timer? _freshnessTicker;

  // Animation de la carte au premier rendu
  bool _hasFittedBounds = false;

  // Route réelle (Mapbox Directions)
  List<RouteSegment> _routeSegments = [];
  LatLng? _lastRouteRescuerPos;
  Timer? _routeThrottle;

  // Structures de référence
  List<Institution> _referenceInstitutions = [];
  bool _isLoadingStructures = false;

  @override
  void initState() {
    super.initState();

    // Timer de fraîcheur : force un setState toutes les secondes
    _freshnessTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // Fetch la route initiale et les structures après le premier frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchRouteIfNeeded();
      _fetchReferenceStructures();
    });
  }

  Future<void> _fetchReferenceStructures() async {
    if (_isLoadingStructures) return;
    setState(() => _isLoadingStructures = true);
    try {
      final repo = HealthStructuresRepository();
      final rows = await repo.fetchAllOpenStructures();
      final institutions = rows.map(Institution.fromApiRow).where((i) => i.hasValidCoords).toList();
      
      // On garde les 20 plus proches de l'utilisateur pour servir de repères
      final userPos = widget.initialUserPosition;
      if (userPos != null) {
        institutions.sort((a, b) {
          final distA = Geolocator.distanceBetween(userPos.latitude, userPos.longitude, a.lat!, a.lng!);
          final distB = Geolocator.distanceBetween(userPos.latitude, userPos.longitude, b.lat!, b.lng!);
          return distA.compareTo(distB);
        });
      }
      
      if (mounted) {
        setState(() {
          _referenceInstitutions = institutions.take(20).toList();
          _isLoadingStructures = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching reference structures: $e');
      if (mounted) setState(() => _isLoadingStructures = false);
    }
  }

  @override
  void dispose() {
    _freshnessTicker?.cancel();
    _routeThrottle?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  /// Fetch la route Mapbox si la position du secouriste a suffisamment changé (> 100m).
  void _fetchRouteIfNeeded() {
    final intervention = ref.read(activeInterventionProvider);
    final userPos = widget.initialUserPosition;
    if (userPos == null) return;
    if (intervention.rescuerLat == null || intervention.rescuerLng == null) return;

    final rescuerPos = LatLng(intervention.rescuerLat!, intervention.rescuerLng!);

    // Skip si la position n'a pas assez bougé
    if (_lastRouteRescuerPos != null) {
      final movedKm = haversineKm(
        _lastRouteRescuerPos!.latitude, _lastRouteRescuerPos!.longitude,
        rescuerPos.latitude, rescuerPos.longitude,
      );
      if (movedKm < 0.1) return; // Moins de 100m, pas de re-fetch
    }

    _lastRouteRescuerPos = rescuerPos;

    // Throttle : max 1 appel toutes les 20s
    _routeThrottle?.cancel();
    _routeThrottle = Timer(const Duration(seconds: 1), () async {
      final segments = await fetchRouteSegments(
        originLat: rescuerPos.latitude,
        originLng: rescuerPos.longitude,
        destLat: userPos.latitude,
        destLng: userPos.longitude,
      );
      if (mounted && segments.isNotEmpty) {
        setState(() => _routeSegments = segments);
      }
    });
  }

  void _fitBoundsToMarkers(Position userPos, ActiveInterventionState intervention) {
    if (intervention.rescuerLat == null || intervention.rescuerLng == null) return;

    final bounds = LatLngBounds(
      LatLng(userPos.latitude, userPos.longitude),
      LatLng(intervention.rescuerLat!, intervention.rescuerLng!),
    );
    
    try {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        _mapController.fitCamera(CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.only(top: 150.0, bottom: 280.0, left: 60.0, right: 60.0),
        ));
      });
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    final intervention = ref.watch(activeInterventionProvider);
    final hasRescuer = intervention.shouldShowRescuer &&
        intervention.rescuerLat != null &&
        intervention.rescuerLng != null;
    final userPos = widget.initialUserPosition;

    // Fetch route si nécessaire
    if (hasRescuer) {
      _fetchRouteIfNeeded();
    }

    // Auto-fit au premier rendu
    if (hasRescuer && userPos != null && !_hasFittedBounds) {
      _hasFittedBounds = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitBoundsToMarkers(userPos, intervention);
      });
    }

    final initialCenter = userPos != null
        ? LatLng(userPos.latitude, userPos.longitude)
        : const LatLng(-4.316, 15.311);

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ═══════════════════════════════════════════════════════
          // 1. CARTE FLUTTER MAP (MAPBOX)
          // ═══════════════════════════════════════════════════════
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 16.0,
              onMapReady: () {
                if (hasRescuer && userPos != null) {
                  _fitBoundsToMarkers(userPos, intervention);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=$mapboxToken',
                userAgentPackageName: 'com.shakadeum.etoile_bleue_mobile',
                maxZoom: 22,
                maxNativeZoom: 18,
              ),
              // Structures de référence (Repères visuels)
              MarkerLayer(
                markers: _referenceInstitutions.map<Marker>((inst) {
                  return Marker(
                    point: LatLng(inst.lat!, inst.lng!),
                    width: 30,
                    height: 30,
                    child: Opacity(
                      opacity: 0.6,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)
                          ],
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Icon(inst.icon, color: inst.color.withValues(alpha: 0.7), size: 16),
                      ),
                    ),
                  );
                }).toList(),
              ),
              // Route (Polyline avec trafic)
              if (hasRescuer && userPos != null)
                PolylineLayer(
                  polylines: _routeSegments.isNotEmpty
                      ? _routeSegments.map((segment) {
                          return Polyline(
                            points: segment.points,
                            color: segment.color,
                            strokeWidth: 5.0,
                            pattern: const StrokePattern.solid(),
                          );
                        }).toList()
                      : [
                          Polyline(
                            points: [
                              LatLng(intervention.rescuerLat!, intervention.rescuerLng!),
                              LatLng(userPos.latitude, userPos.longitude)
                            ],
                            color: AppColors.blue,
                            strokeWidth: 5.0,
                            pattern: StrokePattern.dashed(segments: const [20, 10]),
                          ),
                        ],
                ),
              // Markers principaux
              MarkerLayer(
                markers: [
                  if (userPos != null)
                    Marker(
                      point: LatLng(userPos.latitude, userPos.longitude),
                      width: 32,
                      height: 32,
                      child: const CitizenMapMarker(),
                    ),
                  if (hasRescuer)
                    Marker(
                      point: LatLng(intervention.rescuerLat!, intervention.rescuerLng!),
                      width: 44,
                      height: 44,
                      child: RescuerMapMarker(
                        heading: intervention.rescuerHeading ?? 0,
                        isStale: intervention.isRescuerStale,
                        isOffline: intervention.isRescuerOffline,
                        isLowBattery: intervention.isLowBattery,
                      ),
                    ),
                ],
              ),
            ],
          ),

          // ═══════════════════════════════════════════════════════
          // 2. TOP BAR : Back + Title
          // ═══════════════════════════════════════════════════════
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                _buildCircleButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(width: 12),
                // Title pill
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (hasRescuer) ...[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: intervention.isRescuerDegraded
                                  ? Colors.grey
                                  : const Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          hasRescuer ? 'Suivi en direct' : 'Ma position',
                          style: const TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            fontFamily: 'Marianne',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Re-center button
                _buildCircleButton(
                  icon: CupertinoIcons.location_fill,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (hasRescuer && userPos != null) {
                      _fitBoundsToMarkers(userPos, intervention);
                    } else if (userPos != null) {
                      _mapController.move(LatLng(userPos.latitude, userPos.longitude), 16.0);
                    }
                  },
                ),
              ],
            ),
          ),

          // ═══════════════════════════════════════════════════════
          // 3. DEGRADED STATE BANNER (stale / offline)
          // ═══════════════════════════════════════════════════════
          if (hasRescuer && intervention.isRescuerDegraded)
            Positioned(
              top: MediaQuery.of(context).padding.top + 72,
              left: 24,
              right: 24,
              child: _buildDegradedBanner(intervention),
            ),

          // ═══════════════════════════════════════════════════════
          // 4. TRAVEL INFO CARD (bottom)
          // ═══════════════════════════════════════════════════════
          if (hasRescuer && userPos != null)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 24,
              left: 16,
              right: 16,
              child: _buildTravelInfoCard(intervention, userPos),
            ),
        ],
      ),
    );
  }

  // ─── Circle Button ───────────────────────────────────────────────────────
  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.black87, size: 20),
      ),
    );
  }

  // ─── Degraded Banner ─────────────────────────────────────────────────────
  Widget _buildDegradedBanner(ActiveInterventionState intervention) {
    final isOffline = intervention.isRescuerOffline;
    final message = isOffline
        ? 'Secouriste hors ligne'
        : 'Position non mise à jour';
    final subMessage = isOffline
        ? 'La connexion sera rétablie automatiquement'
        : timeAgoString(intervention.rescuerUpdatedAt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            isOffline
                ? CupertinoIcons.wifi_slash
                : CupertinoIcons.exclamationmark_triangle_fill,
            color: Colors.orange[700],
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Colors.orange[900],
                    fontFamily: 'Marianne',
                  ),
                ),
                if (subMessage.isNotEmpty)
                  Text(
                    subMessage,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange[700],
                      fontFamily: 'Marianne',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Travel Info Card (Premium Glassmorphism) ─────────────────────────────
  Widget _buildTravelInfoCard(
      ActiveInterventionState intervention, Position userPos) {
    final double distKm = haversineKm(
      userPos.latitude,
      userPos.longitude,
      intervention.rescuerLat!,
      intervention.rescuerLng!,
    );
    final int eta = estimateEtaMinutes(distKm);
    final String freshness = timeAgoString(intervention.rescuerUpdatedAt);
    final String statusLabel = dispatchStatusLabel(intervention.dispatchStatus);
    final Color statusColor = dispatchStatusColor(intervention.dispatchStatus);
    final IconData statusIcon = dispatchStatusIcon(intervention.dispatchStatus);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 30,
            spreadRadius: 2,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: statusColor.withValues(alpha: 0.08),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header : statut + nom secouriste
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                // Status dot + icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(statusIcon, color: statusColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        intervention.rescuerName ?? 'Secouriste',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.navyDeep,
                          fontFamily: 'Marianne',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: intervention.isRescuerDegraded
                                  ? Colors.grey
                                  : statusColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            statusLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: statusColor,
                              fontFamily: 'Marianne',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // ETA badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.clock,
                          size: 14, color: AppColors.blue),
                      const SizedBox(width: 6),
                      Text(
                        '~$eta min',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: AppColors.blue,
                          fontFamily: 'Marianne',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(height: 1, color: Colors.grey[100]),
          ),

          // ── Stats row : Distance + ETA + Freshness
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                _buildStatItem(
                  icon: CupertinoIcons.map_pin_ellipse,
                  value: formatDistance(distKm),
                  label: 'Distance',
                ),
                _buildStatDivider(),
                _buildStatItem(
                  icon: CupertinoIcons.speedometer,
                  value: '$eta min',
                  label: 'Temps estimé',
                ),
                _buildStatDivider(),
                _buildStatItem(
                  icon: CupertinoIcons.antenna_radiowaves_left_right,
                  value: freshness.isEmpty ? '–' : freshness,
                  label: 'Mise à jour',
                  valueColor: intervention.isRescuerStale
                      ? Colors.orange
                      : const Color(0xFF10B981),
                ),
              ],
            ),
          ),

          // ── Battery warning
          if (intervention.isLowBattery)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.battery_25, size: 16,
                        color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    Text(
                      'Batterie du secouriste faible (${intervention.rescuerBattery}%)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange[800],
                        fontFamily: 'Marianne',
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Details Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  if (intervention.incidentId != null) {
                    context.push(
                      AppRoutes.incidentDetail.replaceAll(':id', intervention.incidentId!),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Voir détails',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Marianne',
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    Color? valueColor,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.grey[400], size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: valueColor ?? AppColors.navyDeep,
              fontFamily: 'Marianne',
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
              fontWeight: FontWeight.w500,
              fontFamily: 'Marianne',
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      height: 36,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.grey[100],
    );
  }
}
