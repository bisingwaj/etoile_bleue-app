import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:etoile_bleue_mobile/core/providers/active_intervention_provider.dart';
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'package:go_router/go_router.dart';

class FullScreenMapPage extends ConsumerStatefulWidget {
  final Position? initialUserPosition;

  const FullScreenMapPage({
    super.key,
    this.initialUserPosition,
  });

  @override
  ConsumerState<FullScreenMapPage> createState() => _FullScreenMapPageState();
}

class _FullScreenMapPageState extends ConsumerState<FullScreenMapPage> {
  GoogleMapController? _mapController;
  BitmapDescriptor? _customLocationMarker;
  BitmapDescriptor? _rescuerMarkerIcon;
  String? _mapStyle;

  @override
  void initState() {
    super.initState();
    _loadMapStyle();
    _initMarkers();
  }

  Future<void> _loadMapStyle() async {
    _mapStyle = await rootBundle.loadString('assets/json/map_style_white.json');
    if (mounted) setState(() {});
  }

  Future<void> _initMarkers() async {
    final int size = 80;
    
    // User Marker
    final ui.PictureRecorder userRecorder = ui.PictureRecorder();
    final Canvas userCanvas = Canvas(userRecorder);
    final Paint userHaloPaint = Paint()..color = AppColors.blue.withOpacity(0.2);
    userCanvas.drawCircle(Offset(size / 2, size / 2), size / 2, userHaloPaint);
    final Paint userBorderPaint = Paint()..color = Colors.white;
    userCanvas.drawCircle(Offset(size / 2, size / 2), size / 2.5, userBorderPaint);
    final Paint userDotPaint = Paint()..color = AppColors.blue;
    userCanvas.drawCircle(Offset(size / 2, size / 2), size / 3.5, userDotPaint);
    final ui.Image userImg = await userRecorder.endRecording().toImage(size, size);
    final ByteData? userByteData = await userImg.toByteData(format: ui.ImageByteFormat.png);
    
    // Rescuer Marker
    final ui.PictureRecorder rescuerRecorder = ui.PictureRecorder();
    final Canvas rescuerCanvas = Canvas(rescuerRecorder);
    final Paint bodyPaint = Paint()..color = Colors.redAccent;
    final RRect bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(size / 2, size / 2), width: size * 0.9, height: size * 0.7),
      const Radius.circular(8),
    );
    rescuerCanvas.drawRRect(bodyRect, bodyPaint);
    final Paint crossPaint = Paint()..color = Colors.white;
    rescuerCanvas.drawRect(Rect.fromCenter(center: Offset(size / 2, size / 2), width: size * 0.15, height: size * 0.5), crossPaint);
    rescuerCanvas.drawRect(Rect.fromCenter(center: Offset(size / 2, size / 2), width: size * 0.5, height: size * 0.15), crossPaint);
    final Paint lightPaint = Paint()..color = Colors.blue;
    rescuerCanvas.drawCircle(Offset(size * 0.7, size * 0.2), size * 0.12, lightPaint);
    final ui.Image rescuerImg = await rescuerRecorder.endRecording().toImage(size, size);
    final ByteData? rescuerByteData = await rescuerImg.toByteData(format: ui.ImageByteFormat.png);

    if (mounted && userByteData != null && rescuerByteData != null) {
      setState(() {
        _customLocationMarker = BitmapDescriptor.fromBytes(userByteData.buffer.asUint8List());
        _rescuerMarkerIcon = BitmapDescriptor.fromBytes(rescuerByteData.buffer.asUint8List());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final interventionState = ref.watch(activeInterventionProvider);
    final hasRescuer = interventionState.rescuerLat != null && interventionState.rescuerLng != null;
    final userPos = widget.initialUserPosition;

    // Polyline
    final Set<Polyline> polylines = {};
    if (hasRescuer && userPos != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('tracking_route_full'),
          points: [
            LatLng(userPos.latitude, userPos.longitude),
            LatLng(interventionState.rescuerLat!, interventionState.rescuerLng!),
          ],
          color: AppColors.blue,
          width: 5,
          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
        ),
      );

      // Auto-fit bounds
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_mapController != null) {
          final bounds = LatLngBounds(
            southwest: LatLng(
              userPos.latitude < interventionState.rescuerLat! ? userPos.latitude : interventionState.rescuerLat!,
              userPos.longitude < interventionState.rescuerLng! ? userPos.longitude : interventionState.rescuerLng!,
            ),
            northeast: LatLng(
              userPos.latitude > interventionState.rescuerLat! ? userPos.latitude : interventionState.rescuerLat!,
              userPos.longitude > interventionState.rescuerLng! ? userPos.longitude : interventionState.rescuerLng!,
            ),
          );
          _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
        }
      });
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: Text(
          hasRescuer ? 'Suivi en direct' : 'Ma position',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {
              _mapController = controller;
              if (_mapStyle != null) _mapController?.setMapStyle(_mapStyle);
              if (userPos != null && !hasRescuer) {
                _mapController?.animateCamera(
                  CameraUpdate.newCameraPosition(
                    CameraPosition(target: LatLng(userPos.latitude, userPos.longitude), zoom: 17),
                  ),
                );
              }
            },
            initialCameraPosition: CameraPosition(
              target: userPos != null 
                ? LatLng(userPos.latitude, userPos.longitude) 
                : const LatLng(-4.316, 15.311),
              zoom: 17,
            ),
            markers: {
              if (userPos != null && _customLocationMarker != null)
                Marker(
                  markerId: const MarkerId('me'),
                  position: LatLng(userPos.latitude, userPos.longitude),
                  icon: _customLocationMarker!,
                  anchor: const Offset(0.5, 0.5),
                ),
              if (hasRescuer && _rescuerMarkerIcon != null)
                Marker(
                  markerId: const MarkerId('rescuer'),
                  position: LatLng(interventionState.rescuerLat!, interventionState.rescuerLng!),
                  icon: _rescuerMarkerIcon!,
                  anchor: const Offset(0.5, 0.5),
                  infoWindow: InfoWindow(title: interventionState.rescuerName ?? 'Secouriste'),
                ),
            },
            polylines: polylines,
            zoomControlsEnabled: false,
            myLocationEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
          ),
          
          // Travel Info Card
          if (hasRescuer && userPos != null)
            Positioned(
              bottom: 32,
              left: 16,
              right: 16,
              child: _buildTravelInfoCard(interventionState, userPos),
            ),
        ],
      ),
    );
  }

  Widget _buildTravelInfoCard(ActiveInterventionState state, Position userPos) {
    final double distanceInMeters = Geolocator.distanceBetween(
      userPos.latitude,
      userPos.longitude,
      state.rescuerLat!,
      state.rescuerLng!,
    );
    
    final double distanceInKm = distanceInMeters / 1000;
    // Estimate ETA: 25 km/h average speed in urban traffic
    final int etaMinutes = (distanceInKm / 25 * 60).round().clamp(1, 60);
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.blue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(CupertinoIcons.location_fill, color: AppColors.blue, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.rescuerName ?? 'Secouriste en route',
                      style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Arrivée estimée dans $etaMinutes min',
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: AppColors.blue, 
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildInfoItem(
                CupertinoIcons.map_pin_ellipse,
                '${distanceInKm.toStringAsFixed(1)} km',
                'Distance',
              ),
              _buildVerticalDivider(),
              _buildInfoItem(
                CupertinoIcons.clock,
                '$etaMinutes min',
                'Temps estimé',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.grey[400], size: 20),
        const SizedBox(height: 8),
        Text(
          value,
          style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 40,
      width: 1,
      color: Colors.grey[200],
    );
  }
}
