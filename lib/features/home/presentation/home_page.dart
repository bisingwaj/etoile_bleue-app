import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;
import 'package:etoile_bleue_mobile/core/theme/app_theme.dart';
import 'package:etoile_bleue_mobile/features/directory/presentation/directory_page.dart';
import 'package:etoile_bleue_mobile/features/history/presentation/history_page.dart';
import 'package:etoile_bleue_mobile/features/profile/presentation/profile_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../../core/utils/dynamic_island_toast.dart';
import 'notifications_page.dart';
import '../../training/presentation/training_page.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:etoile_bleue_mobile/core/router/app_router.dart';
import 'incident_camera_page.dart';
import 'widgets/goodsam_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/providers/user_provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/providers/notifications_provider.dart';

enum TrackingSheetState { collapsed, search, sos, found }

enum SosTrackingState { processing, handled, onTheWay, onSite }

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  String? _mapStyle;
  BitmapDescriptor? _customLocationMarker;
  late AnimationController _sosAnimationController;
  late AnimationController _radarAnimationController;
  Position? _currentPosition;
  String _currentAddress = "Recherche position...";
  
  bool _isLocationGranted = false;
  bool _isSosTriggered = false;
  StreamSubscription<Position>? _positionStreamSubscription;
  int _currentIndex = 0;
  final AudioPlayer _sosAudioPlayer = AudioPlayer();
  final GlobalKey<DirectoryPageState> _directoryKey = GlobalKey<DirectoryPageState>();

  // Tracking-related state (legacy, still used by some UI components)
  Timer? _stateSimulationTimer;
  bool _isTracking = false;
  bool _isTrackerMinimized = false;
  bool _isIslandExpanded = false;
  SosTrackingState _trackingState = SosTrackingState.processing;
  int _ambulanceEtaMinutes = 8;
  LatLng? _ambulancePos;
  String _unitCallsign = '';
  String _currentSOSCategory = '';
  RealtimeChannel? _dispatchSub;
  RealtimeChannel? _unitSub;
  
  // Exemple de position par défaut : Kinshasa Gombe
  static const LatLng _center = LatLng(-4.316, 15.311);

  @override
  void initState() {
    super.initState();
    _sosAudioPlayer.setReleaseMode(ReleaseMode.stop);
    _loadMapStyle();
    _tryExtractLocation();
    _initCustomMarker();

    _sosAnimationController = AnimationController(
       vsync: this,
       duration: const Duration(milliseconds: 1200),
    )..addStatusListener((status) {
       if (status == AnimationStatus.completed && !_isSosTriggered) {
         HapticFeedback.heavyImpact();
         _sosAnimationController.reset();
         _triggerEmergencyCall();
       }
    });

    _radarAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listen<AsyncValue<List<Map<String, dynamic>>>>(notificationsProvider, (prev, next) {
        final prevCount = prev?.valueOrNull?.length ?? 0;
        final nextList = next.valueOrNull ?? [];
        if (nextList.length > prevCount && prevCount > 0) {
          final latest = nextList.first;
          final title = latest['title']?.toString() ?? 'Nouvelle notification';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(CupertinoIcons.bell_fill, color: Colors.white, size: 18),
                    const SizedBox(width: 12),
                    Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
                  ],
                ),
                backgroundColor: AppColors.blue,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                duration: const Duration(seconds: 4),
                margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
              ),
            );
          }
        }
      });
    });

  }

  Future<void> _initCustomMarker() async {
    final int size = 80;
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    final Paint haloPaint = Paint()..color = AppColors.blue.withValues(alpha: 0.2);
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, haloPaint);

    final Paint borderPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2.5, borderPaint);

    final Paint dotPaint = Paint()..color = AppColors.blue;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 3.5, dotPaint);

    final ui.Image image = await pictureRecorder.endRecording().toImage(size, size);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      final Uint8List uint8List = byteData.buffer.asUint8List();
      if (mounted) {
        setState(() {
          _customLocationMarker = BitmapDescriptor.fromBytes(uint8List);
        });
      }
    }
  }

  Future<void> _loadMapStyle() async {
    _mapStyle = await rootBundle.loadString('assets/json/map_style_white.json');
    if (mounted) setState(() {});
  }

  void _showCancelSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Annuler l\'alerte ?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
              const SizedBox(height: 24),
              _buildCancelTuile('Fausse alerte', CupertinoIcons.xmark_circle_fill, () => _confirmCancel(ctx)),
              const SizedBox(height: 12),
              _buildCancelTuile('Alerte non vitale', CupertinoIcons.info_circle_fill, () => _confirmCancel(ctx)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Retour au suivi', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCancelTuile(String title, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.black87, size: 28),
            const SizedBox(width: 16),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.black87)),
            const Spacer(),
            const Icon(CupertinoIcons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  void _confirmCancel(BuildContext context) {
    Navigator.pop(context); // fermer BottomSheet d'annulation
    _stateSimulationTimer?.cancel();
    _sosAnimationController.reset();
    setState(() {
      _isTracking = false;
      _isTrackerMinimized = false;
    });
    DynamicIslandToast.showInfo(this.context, 'home.alert_canceled'.tr());
  }

  ({Color color, IconData icon, String title, String subtitle}) _getTrackingStyle() {
    switch (_trackingState) {
      case SosTrackingState.processing:
        return (color: Colors.orange, icon: CupertinoIcons.hourglass, title: 'home.track_processing_title'.tr(), subtitle: 'home.track_processing_sub'.tr());
      case SosTrackingState.handled:
        return (color: AppColors.blue, icon: CupertinoIcons.star_fill, title: 'home.track_handled_title'.tr(), subtitle: 'home.track_handled_sub'.tr());
      case SosTrackingState.onTheWay:
        return (color: const Color(0xFF10B981), icon: CupertinoIcons.car_detailed, title: 'home.track_on_way_title'.tr(), subtitle: 'home.track_on_way_sub'.tr(args: [_ambulanceEtaMinutes.toString()]));
      case SosTrackingState.onSite:
        return (color: Colors.deepPurple, icon: CupertinoIcons.location_solid, title: 'home.track_on_site_title'.tr(), subtitle: 'home.track_on_site_sub'.tr());
    }
  }

  Widget _buildDynamicIslandTracker() {
    final style = _getTrackingStyle();
    
    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (details.primaryDelta! > 5) {
          setState(() => _isIslandExpanded = true); // swipe down expands
        } else if (details.primaryDelta! < -5) {
          setState(() => _isIslandExpanded = false); // swipe up reduces
        }
      },
      onTap: () {
        setState(() => _isIslandExpanded = !_isIslandExpanded);
      },
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.fastOutSlowIn,
            margin: EdgeInsets.only(left: 16, right: 16, top: MediaQuery.of(context).padding.top + 50, bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(_isIslandExpanded ? 28 : 32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
              border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Row (Always visible)
                Row(
                  children: [
                    if (_trackingState == SosTrackingState.onTheWay)
                      Container(
                        width: 64,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: AnimatedAlign(
                          duration: const Duration(seconds: 1),
                          curve: Curves.linear,
                          alignment: Alignment(-1.0 + (((12 - _ambulanceEtaMinutes) / 12) * 2.0), 0),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: style.color, shape: BoxShape.circle),
                            child: const Icon(CupertinoIcons.car_detailed, color: Colors.white, size: 14),
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: style.color.withValues(alpha: 0.2), shape: BoxShape.circle),
                        child: Icon(style.icon, color: style.color, size: 16),
                      ).animate(onPlay: (c) => c.repeat()).shake(hz: 3, duration: 1.seconds),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(style.title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Marianne')),
                          Text(style.subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'Marianne')),
                        ],
                      ),
                    ),
                    Icon(_isIslandExpanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down, color: Colors.white54, size: 20),
                  ],
                ),
                
                // Expanded Content
                if (_isIslandExpanded) ...[
                  const SizedBox(height: 16),
                  // Mini Map Animée
                  Container(
                    height: 150,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.grey[800],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _AmbulanceMapWidget(userPosition: _currentPosition, ambulancePosition: _ambulancePos),
                  ),
                  const SizedBox(height: 16),
                  
                  // Vehicle Info & Call Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                            child: const Icon(CupertinoIcons.car_detailed, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_unitCallsign, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              Text('home.license_plate'.tr(), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          elevation: 0,
                        ),
                        onPressed: () async {
                          final uri = Uri.parse('tel:112');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri);
                          }
                        },
                        icon: const Icon(CupertinoIcons.phone_fill, size: 16),
                        label: Text('home.call_btn'.tr(), style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Button to restore Full Tracker BottomSheet
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => setState(() {
                          _isTrackerMinimized = false;
                          _isIslandExpanded = false;
                        }),
                        icon: const Icon(CupertinoIcons.chevron_down, size: 14, color: Colors.white),
                        label: Text('home.view_details'.tr(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildTimelineStep(String title, String subtitle, String time, String subtime, bool isActive, bool isLast) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? AppColors.blue : Colors.transparent,
                border: Border.all(
                  color: isActive ? AppColors.blue.withValues(alpha: 0.2) : Colors.grey[300]!,
                  width: isActive ? 4 : 2,
                ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 40,
                color: isActive ? AppColors.blue.withValues(alpha: 0.3) : Colors.grey[200],
              ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title, 
                style: TextStyle(fontWeight: isActive ? FontWeight.bold : FontWeight.normal, color: isActive ? Colors.black87 : Colors.grey[600], fontSize: 15)
              ),
              if (subtitle.isNotEmpty)
                Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey[500])),
              if (!isLast) const SizedBox(height: 16),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(time, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            if (subtime.isNotEmpty)
              Text(subtime, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        )
      ],
    );
  }

  Widget _buildSOSTrackerSheetInline() {
    final now = DateTime.now();
    final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, -5))
        ]
      ),
      padding: const EdgeInsets.only(top: 12, left: 24, right: 24, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          GestureDetector(
            onVerticalDragUpdate: (details) {
              if (details.primaryDelta! > 5) {
                setState(() => _isTrackerMinimized = true);
              }
            },
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(CupertinoIcons.heart_circle_fill, color: AppColors.red, size: 28),
                  const SizedBox(width: 8),
                  Text('Étoile Bleue', style: AppTextStyles.headlineLarge.copyWith(fontWeight: FontWeight.bold, fontSize: 22)),
                ],
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.chevron_down, color: Colors.black54, size: 28),
                onPressed: () => setState(() => _isTrackerMinimized = true), // Réduire au lieu de pop
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Driver Profile equivalent
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.blue[50],
                        child: const Icon(CupertinoIcons.person_3_fill, color: AppColors.blue),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('home.rescue_unit'.tr(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Row(
                              children: [
                                const Icon(Icons.verified_user, color: Colors.amber, size: 14),
                                const SizedBox(width: 4),
                                Text('home.red_cross'.tr(), style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('home.est_delay'.tr(), style: TextStyle(color: Colors.grey, fontSize: 12)),
                          Text('7 min', style: TextStyle(color: Colors.grey[800], fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Badges Premium
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(16)),
                          child: Row(
                            children: [
                              const Icon(CupertinoIcons.location_solid, color: AppColors.blue, size: 14),
                              const SizedBox(width: 4),
                              Text('home.gps_vehicle'.tr(), style: const TextStyle(color: AppColors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(16)),
                          child: Row(
                            children: [
                              const Icon(CupertinoIcons.waveform_path_ecg, color: Colors.green, size: 14),
                              const SizedBox(width: 4),
                              Text('home.med_connection'.tr(), style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Trip Info equivalent (Timeline)
                  Text('home.track_timeline'.tr(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 20),
                  _buildTimelineStep('home.step_sos'.tr(), _currentAddress, timeStr, 'home.step_validated'.tr(), true, false),
                  _buildTimelineStep('home.track_handled_title'.tr(), 'home.step_triage'.tr(), '--:--', 'home.step_wait'.tr(), _trackingState.index >= SosTrackingState.handled.index, false),
                  _buildTimelineStep('home.step_en_route'.tr(), 'home.step_assigned'.tr(), '--:--', '', _trackingState.index >= SosTrackingState.onTheWay.index, false),
                  _buildTimelineStep('home.step_arrive'.tr(), 'home.step_calm'.tr(), '--:--', 'home.step_est'.tr(), _trackingState.index >= SosTrackingState.onSite.index, true),
                  
                  const SizedBox(height: 24),
                  
                  // Animated Radar Status Box
                  AnimatedBuilder(
                    animation: _radarAnimationController,
                    builder: (context, child) {
                      final style = _getTrackingStyle();
                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [style.color.withValues(alpha: 0.1), Colors.white.withValues(alpha: 0.5)], 
                            begin: Alignment.topCenter, 
                            end: Alignment.bottomCenter
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: style.color.withValues(alpha: 0.2)),
                          boxShadow: [
                            BoxShadow(
                              color: style.color.withValues(alpha: 0.15 * _radarAnimationController.value),
                              blurRadius: 30 * _radarAnimationController.value,
                              spreadRadius: 10 * _radarAnimationController.value,
                            )
                          ],
                        ),
                        child: Column(
                          children: [
                            Text('home.sos_qualified'.tr(args: [_currentSOSCategory]), style: TextStyle(color: style.color, fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Text('home.current_status'.tr(), style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Text(style.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.black87), textAlign: TextAlign.center),
                          ],
                        ),
                      );
                    }
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          
          // Actions: SMS Offline, Red Call Button & Hold-to-Cancel
          GestureDetector(
            onTap: () async {
              HapticFeedback.heavyImpact();
              final userOpt = ref.read(userProvider).value;
              String userName = "Citoyen(ne)";
              if (userOpt != null) {
                final String first = userOpt['first_name'] ?? '';
                final String last = userOpt['last_name'] ?? '';
                final String full = "$first $last".trim();
                if (full.isNotEmpty) userName = full;
              }
              
              String time = "${DateTime.now().hour}h${DateTime.now().minute.toString().padLeft(2, '0')}";
              String body = '🔴 ALERTE URGENCE ETOILE BLEUE 🔴\n'
                  'Mme/M. $userName signale un cas de : ${_currentSOSCategory.toUpperCase()}.\n'
                  '📍 Position : ${_currentAddress.isNotEmpty ? _currentAddress : "Inconnue"} (Lat: ${_currentPosition?.latitude}, Lng: ${_currentPosition?.longitude})\n'
                  '⏰ Heure : $time\n'
                  '🩺 \n\n'
                  'Veuillez intervenir immédiatement.';
              final uri = Uri.parse('sms:112?body=${Uri.encodeComponent(body)}');
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              try {
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                } else {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              } catch (e) {
                scaffoldMessenger.showSnackBar(SnackBar(content: Text('home.error_sms'.tr())));
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   const Icon(CupertinoIcons.chat_bubble_text_fill, color: Colors.orange),
                   const SizedBox(width: 8),
                   Text('home.sms_fallback'.tr(), style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.red, 
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                     BoxShadow(color: AppColors.red.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(CupertinoIcons.phone_fill, color: Colors.white),
                  onPressed: () async {
                    HapticFeedback.heavyImpact();
                    final uri = Uri.parse('tel:112');
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    try {
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      } else {
                        // Fallback force launch
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    } catch (e) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(content: Text('home.error_phone'.tr())),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _HoldToCancelButton(onComplete: _showCancelSheet, accentColor: _getTrackingStyle().color),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _stateSimulationTimer?.cancel();
    _vibrationTimer?.cancel();
    _dispatchSub?.unsubscribe();
    _unitSub?.unsubscribe();
    _positionStreamSubscription?.cancel();
    _mapController?.dispose();
    _sosAnimationController.dispose();
    _sosAudioPlayer.dispose();
    _radarAnimationController.dispose();
    super.dispose();
  }

  Future<void> _tryExtractLocation() async {
    debugPrint("=== GPS: Starting _tryExtractLocation ===");
    bool serviceEnabled;
    LocationPermission permission;

    debugPrint("=== GPS: Checking isLocationServiceEnabled ===");
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    debugPrint("=== GPS: serviceEnabled: $serviceEnabled ===");
    
    if (!serviceEnabled) {
      if (mounted) setState(() => _currentAddress = 'home.gps_disabled'.tr());
      return;
    }

    debugPrint("=== GPS: Checking checkPermission ===");
    permission = await Geolocator.checkPermission();
    debugPrint("=== GPS: checkPermission: $permission ===");
    
    if (permission == LocationPermission.denied) {
      debugPrint("=== GPS: Requesting Permission ===");
      permission = await Geolocator.requestPermission();
      debugPrint("=== GPS: requestPermission result: $permission ===");
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _currentAddress = 'home.gps_denied'.tr());
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _currentAddress = 'home.gps_denied_perm'.tr());
      return;
    } 

    if (mounted) setState(() => _isLocationGranted = true);

    try {
      debugPrint("=== GPS: Calling getLastKnownPosition ===");
      // 1. Affichage Instantané via le cache (anti-blocage)
      Position? currentPos = await Geolocator.getLastKnownPosition().timeout(const Duration(seconds: 2), onTimeout: () {
        debugPrint("=== GPS: getLastKnownPosition Timeout! ===");
        return null; // Return null on timeout
      });
      debugPrint("=== GPS: getLastKnownPosition returned: $currentPos ===");
      
      if (currentPos != null && mounted) {
        _updatePosition(currentPos, isInstant: true);
      }

      debugPrint("=== GPS: Calling getCurrentPosition (4s timeout) ===");
      // 2. Affinement en arrière-plan avec Timeout (évite de bloquer sur une absence de satellite)
      try {
        Position newPos = await Geolocator.getCurrentPosition(
          locationSettings: Platform.isAndroid
              ? AndroidSettings(
                  accuracy: LocationAccuracy.high,
                  timeLimit: const Duration(seconds: 4),
                  forceLocationManager: true,
                )
              : const LocationSettings(
                  accuracy: LocationAccuracy.high,
                  timeLimit: Duration(seconds: 4),
                ),
        ).timeout(const Duration(seconds: 5), onTimeout: () {
          debugPrint("=== GPS: Dart-level timeout hit for getCurrentPosition! ===");
          throw TimeoutException("Dart-level timeout for getCurrentPosition");
        });
        debugPrint("=== GPS: getCurrentPosition returned: $newPos ===");
        currentPos = newPos;
      } catch (e) {
        debugPrint("=== GPS: getCurrentPosition caught error: $e ===");
        // En cas de timeout, currentPos reste la position en cache (s'il y en a une)
      }
      
      if (currentPos != null && mounted) {
        _updatePosition(currentPos, isInstant: false);
      } else if (currentPos == null && mounted) {
        debugPrint("=== GPS: Fallback: No pos found. Switching to fake Kinshasa position for UI testing ===");
        // HARD FALLBACK FOR EMULATOR IF EVERYTHING FAILS:
        currentPos = Position(
          latitude: -4.316, 
          longitude: 15.311,
          timestamp: DateTime.now(),
          accuracy: 0, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
        );
        _updatePosition(currentPos, isInstant: false);
      }

      debugPrint("=== GPS: Setting up getPositionStream ===");
      // 3. Listener continu pour suivre le mouvement de l'utilisateur
      final LocationSettings locationSettings = Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
              forceLocationManager: true,
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            );

      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen((Position position) {
        _updatePosition(position, isInstant: false);
      });
    } catch (e) {
      if (mounted) setState(() => _currentAddress = 'home.gps_error'.tr());
    }
  }

  Future<void> _updatePosition(Position position, {bool isInstant = false}) async {
    if (!mounted) return;
    
    setState(() {
      _currentPosition = position;
      if (isInstant && _currentAddress == "Recherche position...") {
        _currentAddress = "${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)} (Affinement...)";
      } else if (!isInstant) {
        _currentAddress = "${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)} (Recherche de rue...)";
      }
    });
    
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(position.latitude, position.longitude),
          zoom: 18.0,
        ),
      ),
    );

    // Sauvegarde silencieuse (Bypassée vers Supabase si besoin)
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      try {
        Supabase.instance.client.from('users_directory').update({
          // 'last_lat': position.latitude,
          // 'last_lng': position.longitude,
        }).eq('auth_user_id', userId);
      } catch (_) {}
    }
    
    try {
      // Course de Géocodage Parallèle (Natif vs Mapbox)
      // Démarrage simultané des deux requêtes pour une réponse ultra-rapide
      final nativeFuture = placemarkFromCoordinates(position.latitude, position.longitude).timeout(const Duration(seconds: 3));
      
      final mapboxUrl = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/${position.longitude},${position.latitude}.json?access_token=pk.eyJ1Ijoic2hha2FkZXVtIiwiYSI6ImNtbjJoc3V0cTB6MDYycnNqazB6NjdzY3gifQ.2u3kJoor4SKro73-0ZJfWA&types=address,poi'
      );
      final mapboxFuture = http.get(mapboxUrl).timeout(const Duration(seconds: 4));

      // On donne priorité au natif
      try {
        List<Placemark> placemarks = await nativeFuture;
        if (placemarks.isNotEmpty && mounted) {
          Placemark place = placemarks[0];
          // Prioriser le 'name' qui contient souvent "N° Nom de la rue"
          String name = place.name ?? '';
          String street = place.thoroughfare ?? place.street ?? ''; 
          String district = place.subLocality ?? place.subAdministrativeArea ?? ''; 
          String city = place.locality ?? ''; 
          
          List<String> parts = [];
          
          // Si le 'name' contient la rue ou ressemble à une adresse précise, on l'utilise
          if (name.isNotEmpty && !name.contains('+') && name.length > 2) {
            parts.add(name);
            if (street.isNotEmpty && !name.contains(street) && !street.contains(name)) {
              parts.add(street);
            }
          } else if (street.isNotEmpty) {
            parts.add(street);
          }

          if (district.isNotEmpty && !parts.contains(district) && district != city) {
            parts.add(district);
          }
          if (city.isNotEmpty && !parts.contains(city)) {
            parts.add(city);
          }
          
          String address = parts.join(', ');
          if (address.isNotEmpty) {
            setState(() => _currentAddress = address);
            return;
          }
        }
      } catch (_) {
        // Le natif a échoué ou timeout, on passe à Mapbox
      }

      // Fallback API Mapbox
      try {
        final response = await mapboxFuture;
        if (response.statusCode == 200 && mounted) {
          final data = json.decode(response.body);
          if (data['features'] != null && (data['features'] as List).isNotEmpty) {
             final features = data['features'] as List;
             // Chercher le texte court d'abord (nom de la rue) au lieu de l'adresse complète (place_name) trop longue
             String placeName = features[0]['text'] ?? features[0]['place_name'] ?? 'Position trouvée';
             setState(() => _currentAddress = placeName);
          }
        }
      } catch (_) {}

    } catch (e) {
      // Ignorer
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Index 0: Carte
          Stack(
            children: [
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAppBar(),
                    if (!_isTracking || _isTrackerMinimized) const SizedBox(height: 24),
                    if (!_isTracking || _isTrackerMinimized) _buildGreeting(),
                    if (!_isTracking || _isTrackerMinimized) const SizedBox(height: AppSpacing.sm),
                    _buildMapSection(),
                    if (!_isTracking || _isTrackerMinimized) const SizedBox(height: 130),
                    if (!_isTracking || _isTrackerMinimized) _buildQuickActions(),
                    if (!_isTracking || _isTrackerMinimized) const SizedBox(height: 32),
                  ],
                ),
              ),
              
              // Dynamic Island removed, logic moved to overlay.
            ],
          ),
          // Index 1: Annuaire
          DirectoryPage(key: _directoryKey),
          // Index 2: Historique
          const HistoryPage(),
          // Index 3: Profil
          const ProfilePage(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, left: AppSpacing.md, right: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo Icon (Blue square with star)
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.blue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(CupertinoIcons.star_fill, color: Colors.white, size: 28),
          ),
          
          // Right action icons
          Row(
            children: [
              Consumer(
                builder: (context, ref, _) {
                  final unreadCount = ref.watch(unreadNotificationsCountProvider);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _buildCircleIcon(
                        CupertinoIcons.bell,
                        onTap: () {
                          context.push(AppRoutes.notifications);
                        },
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppColors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                            child: Center(
                              child: Text(
                                unreadCount > 9 ? '9+' : '$unreadCount',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(width: AppSpacing.sm),
              _buildCircleIcon(
                CupertinoIcons.ellipsis,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const TrainingPage()));
                },
              ),
              const SizedBox(width: AppSpacing.sm),
              // Profile Picture 
              Consumer(
                builder: (context, ref, _) {
                  final profileImage = ref.watch(profileImageProvider);
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilePage()));
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.navyDeep, 
                        image: DecorationImage(
                          image: profileImage != null 
                              ? FileImage(profileImage) as ImageProvider
                              : const NetworkImage('https://api.dicebear.com/7.x/notionists/png?seed=David&backgroundColor=e6f0fa'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  );
                }
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCircleIcon(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.navy, size: 20),
      ),
    );
  }

  Widget _buildGreeting() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Consumer(
            builder: (context, ref, _) {
              final userAsync = ref.watch(userProvider);
              final userName = userAsync.when(
                data: (data) => data?['first_name'] ?? 'David',
                loading: () => '...',
                error: (_, __) => 'David',
              );
              return Text(
                'home.greeting'.tr().replaceAll('David', userName),
                style: AppTextStyles.headlineLarge.copyWith(fontSize: 28),
              );
            }
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(CupertinoIcons.location_solid, color: AppColors.blue, size: 16),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'home.you_are_here'.tr(),
                    style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    _currentAddress,
                    style: AppTextStyles.bodyLarge.copyWith(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMapSection() {
    return Expanded(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          // The Map Container
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.grey[200],
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: constraints.maxHeight + 35, // Pousse le logo hors du cadre
                      child: GoogleMap(
                        onMapCreated: (GoogleMapController controller) {
                          _mapController = controller;
                          if (_mapStyle != null) {
                            _mapController?.setMapStyle(_mapStyle);
                          }
                          if (_currentPosition != null) {
                            _mapController?.animateCamera(
                              CameraUpdate.newCameraPosition(
                                CameraPosition(
                                  target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                                  zoom: 18.0,
                                ),
                              ),
                            );
                          }
                        },
                        initialCameraPosition: const CameraPosition(
                          target: _center,
                          zoom: 18.0,
                        ),
                        markers: _currentPosition != null && _customLocationMarker != null ? {
                          Marker(
                            markerId: const MarkerId('current_location'),
                            position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                            icon: _customLocationMarker!,
                            anchor: const Offset(0.5, 0.5),
                            infoWindow: const InfoWindow(title: 'Vous êtes ici'),
                          )
                        } : {},
                        zoomControlsEnabled: false,
                        myLocationEnabled: _isLocationGranted,
                        myLocationButtonEnabled: _isLocationGranted,
                        mapToolbarEnabled: false,
                        compassEnabled: false,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          
          // Gradient fade on top of map to make it blend into white
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 60,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.white,
                    AppColors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          
          // SOS Button
          Positioned(
            bottom: -70,
            child: _buildSOSButton(),
          ),
        ],
      ),
    );
  }

  Timer? _vibrationTimer;

  Widget _buildTrackingShazamWave() {
    final style = _getTrackingStyle();
    Color waveColor = style.color;
    IconData centerIcon = style.icon;

    return GestureDetector(
      onTap: () {
        setState(() => _isTrackerMinimized = false); // Open full sheet again
        HapticFeedback.lightImpact();
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Wave Rings
          ...List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _radarAnimationController,
              builder: (context, child) {
                double value = (_radarAnimationController.value - (index * 0.3)).clamp(0.0, 1.0);
                return Transform.scale(
                  scale: 1.0 + (value * 2.5),
                  child: Opacity(
                    opacity: 1.0 - value,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: waveColor.withOpacity(0.3),
                      ),
                    ),
                  ),
                );
              },
            );
          }),
          // Center Icon
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: waveColor,
              boxShadow: [
                BoxShadow(
                  color: waveColor.withOpacity(0.5),
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Icon(centerIcon, color: Colors.white, size: 40),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSOSButton() {
    if (_isTracking) {
      return _buildTrackingShazamWave();
    }
  
    return Listener(
      onPointerDown: (_) {
        HapticFeedback.heavyImpact();
        _sosAudioPlayer.play(AssetSource('audio/sos_sound.wav'));
        _sosAnimationController.forward();
        _vibrationTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
          HapticFeedback.mediumImpact();
        });
      },
      onPointerUp: (_) {
        _vibrationTimer?.cancel();
        _sosAudioPlayer.stop();
        if (_sosAnimationController.status != AnimationStatus.completed) {
          _sosAnimationController.reverse();
        }
      },
      onPointerCancel: (_) {
        _vibrationTimer?.cancel();
        _sosAudioPlayer.stop();
        if (_sosAnimationController.status != AnimationStatus.completed) {
          _sosAnimationController.reverse();
        }
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 170,
            height: 170,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.red.withValues(alpha: 0.08),
            ),
          ),
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.red.withValues(alpha: 0.15),
            ),
          ),
          AnimatedBuilder(
            animation: _sosAnimationController,
            builder: (context, child) {
              if (_sosAnimationController.value == 0) return const SizedBox();
              return SizedBox(
                width: 146,
                height: 146,
                child: CircularProgressIndicator(
                  value: _sosAnimationController.value,
                  strokeWidth: 6,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                  backgroundColor: Colors.transparent,
                ),
              );
            },
          ),
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE53935),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE53935).withValues(alpha: 0.4),
                  blurRadius: 16,
                  spreadRadius: 4,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Text(
              'SOS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                fontFamily: 'Marianne',
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'home.quick_actions'.tr(),
            style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildActionCard(
                'home.report'.tr(),
                CupertinoIcons.camera_fill,
                const Color(0xFFEBF8EE),
                const Color(0xFF004D1B),
                () => _showIncidentSheet(),
              ),
              _buildActionCard(
                'home.goodsam'.tr(),
                CupertinoIcons.heart_fill,
                const Color(0xFFFCEAE9),
                const Color(0xFF8B1212),
                () => _showGoodSamSheet(),
              ),
              _buildActionCard(
                'Suivi\nSOS',
                CupertinoIcons.heart_circle_fill,
                const Color(0xFFF0F4FF),
                const Color(0xFF003580),
                () {
                  context.push('/active_tracking');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _startEmergencyCall() async {
    HapticFeedback.heavyImpact();
    if (_isSosTriggered) return;
    setState(() => _isSosTriggered = true);
    try {
      await ref.read(callStateProvider.notifier).startSosCall(
        lat: _currentPosition?.latitude,
        lng: _currentPosition?.longitude,
      );
      if (mounted) context.go('/call/active');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSosTriggered = false);
    }
  }

  /// Déclenché par le bouton SOS après maintien complet (1.2 s).
  Future<void> _triggerEmergencyCall() async {
    if (_isSosTriggered) return;
    setState(() => _isSosTriggered = true);
    try {
      await ref.read(callStateProvider.notifier).startSosCall(
        lat: _currentPosition?.latitude,
        lng: _currentPosition?.longitude,
      );
      
      if (!mounted) return;
      
      final callState = ref.read(callStateProvider);
      if (callState.status == ActiveCallStatus.blocked) {
        context.go('/blocked', extra: {
          'expires_at': callState.blockedExpiresAt,
          'reason': callState.blockedReason,
        });
      } else {
        context.go('/call/active');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur SOS: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSosTriggered = false);
    }
  }

  void _showIncidentSheet() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const IncidentCameraPage(),
        fullscreenDialog: true,
      ),
    );
  }

  void _showGoodSamSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GoodSamSheet(
        onCancel: () {
          DynamicIslandToast.showInfo(this.context, 'home.toast_goodsam_cancel'.tr());
        },
      ),
    );
  }

  Widget _buildActionCard(String title, IconData icon, Color bgColor, Color iconColor, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 8.0),
          height: 110,
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: iconColor, size: 28),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Marianne',
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E5EA), width: 1)),
      ),
      child: BottomNavigationBar(
        elevation: 0,
        backgroundColor: AppColors.white,
        selectedItemColor: AppColors.navyDeep,
        unselectedItemColor: const Color(0xFF86868B),
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, fontFamily: 'Marianne'),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12, fontFamily: 'Marianne'),
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
          if (index == 1) {
            _directoryKey.currentState?.refreshLocation();
          }
        },
        items: [
          BottomNavigationBarItem(
            icon: const Padding(padding: EdgeInsets.only(bottom: 4.0), child: Icon(CupertinoIcons.house)),
            activeIcon: const Padding(padding: EdgeInsets.only(bottom: 4.0), child: Icon(CupertinoIcons.house_fill))
                .animate()
                .scaleXY(begin: 0.5, end: 1.0, duration: 400.ms, curve: Curves.elasticOut),
            label: 'home.nav_home'.tr(),
          ),
          BottomNavigationBarItem(
            icon: const Padding(padding: EdgeInsets.only(bottom: 4.0), child: Icon(CupertinoIcons.book)),
            activeIcon: const Padding(padding: EdgeInsets.only(bottom: 4.0), child: Icon(CupertinoIcons.book_fill))
                .animate()
                .flipV(begin: -0.5, end: 0, duration: 400.ms, curve: Curves.easeOut),
            label: 'home.nav_directory'.tr(),
          ),
          BottomNavigationBarItem(
            icon: const Padding(padding: EdgeInsets.only(bottom: 4.0), child: Icon(CupertinoIcons.clock)),
            activeIcon: const Padding(padding: EdgeInsets.only(bottom: 4.0), child: Icon(CupertinoIcons.clock_fill))
                .animate()
                .rotate(begin: -0.2, end: 0, duration: 400.ms, curve: Curves.elasticOut)
                .scaleXY(begin: 0.8, end: 1.0),
            label: 'home.nav_history'.tr(),
          ),
          BottomNavigationBarItem(
            icon: const Padding(padding: EdgeInsets.only(bottom: 4.0), child: Icon(CupertinoIcons.person_crop_circle)),
            activeIcon: const Padding(padding: EdgeInsets.only(bottom: 4.0), child: Icon(CupertinoIcons.person_crop_circle_fill))
                .animate()
                .slideY(begin: 0.5, end: 0, duration: 300.ms, curve: Curves.easeOut)
                .fadeIn(),
            label: 'home.nav_profile'.tr(),
          ),
        ],
      ),
    );
  }
}

class _TriageSheetWidget extends StatefulWidget {
  final VoidCallback onCancel;
  final ValueChanged<String> onConfirm;

  const _TriageSheetWidget({required this.onCancel, required this.onConfirm});

  @override
  State<_TriageSheetWidget> createState() => _TriageSheetWidgetState();
}

class _TriageSheetWidgetState extends State<_TriageSheetWidget> {
  int _step = 0;
  String _selectedCategory = '';
  String _selectedVictim = '';

  Widget _buildMammothTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                title, 
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87, height: 1.1),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                subtitle, 
                textAlign: TextAlign.center, 
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Colors.grey[600], height: 1.1),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String title = '';
    String subtitle = '';
    List<Widget> tiles = [];
    VoidCallback onBack = widget.onCancel;

    if (_step == 0) {
      title = 'Que se passe-t-il ?';
      subtitle = 'Précisez la nature du danger immédiat';
      tiles = [
        _buildMammothTile(title: 'Malaise / Accident', subtitle: "Problème de santé", icon: CupertinoIcons.heart_fill, color: AppColors.red, onTap: () => setState(() { _selectedCategory = 'Malaise/Accident'; _step = 1; })),
        _buildMammothTile(title: 'Agression / Danger', subtitle: "Menace humaine", icon: CupertinoIcons.shield_fill, color: AppColors.navyDeep, onTap: () => setState(() { _selectedCategory = 'Agression/Danger'; _step = 1; })),
        _buildMammothTile(title: 'Feu / Fumée', subtitle: "Incendie, explosion", icon: CupertinoIcons.flame_fill, color: Colors.orange, onTap: () => setState(() { _selectedCategory = 'Feu/Fumée'; _step = 1; })),
        _buildMammothTile(title: 'Autre Problème', subtitle: "Autre urgence", icon: CupertinoIcons.exclamationmark_triangle_fill, color: Colors.grey[800]!, onTap: () => setState(() { _selectedCategory = 'Autre'; _step = 1; })),
      ];
    } else if (_step == 1) {
      title = 'Qui est en danger ?';
      subtitle = 'Qui a besoin des secours en urgence ?';
      onBack = () => setState(() => _step = 0);
      tiles = [
        _buildMammothTile(title: "C'est pour moi", subtitle: "Je suis la victime", icon: CupertinoIcons.person_fill, color: AppColors.blue, onTap: () => setState(() { _selectedVictim = 'C\'est moi'; _step = 2; })),
        _buildMammothTile(title: 'Quelqu\'un avec moi', subtitle: "Je peux l'aider", icon: CupertinoIcons.person_2_fill, color: Colors.blueAccent, onTap: () => setState(() { _selectedVictim = 'Avec moi'; _step = 2; })),
        _buildMammothTile(title: 'Je suis témoin', subtitle: "J'observe de loin", icon: CupertinoIcons.eye_fill, color: Colors.purple, onTap: () => setState(() { _selectedVictim = 'Témoin'; _step = 2; })),
        _buildMammothTile(title: 'Plusieurs personnes', subtitle: "Multiples victimes", icon: CupertinoIcons.person_3_fill, color: AppColors.red, onTap: () => setState(() { _selectedVictim = 'Groupe'; _step = 2; })),
      ];
    } else if (_step == 2) {
      title = 'L\'état de la personne ?';
      subtitle = 'Symptôme visible majeur';
      onBack = () => setState(() => _step = 1);
      tiles = [
        _buildMammothTile(title: 'Inconscient', subtitle: "Ne respire plus", icon: CupertinoIcons.waveform_path_ecg, color: AppColors.red, onTap: () => widget.onConfirm('$_selectedCategory - $_selectedVictim - Inconscient')),
        _buildMammothTile(title: 'Saigne beaucoup', subtitle: "Très douloureux", icon: CupertinoIcons.bandage_fill, color: Colors.orange, onTap: () => widget.onConfirm('$_selectedCategory - $_selectedVictim - Saigne beaucoup')),
        _buildMammothTile(title: 'Conscient', subtitle: "Dégât léger", icon: CupertinoIcons.checkmark_seal_fill, color: Colors.green, onTap: () => widget.onConfirm('$_selectedCategory - $_selectedVictim - Conscient')),
        _buildMammothTile(title: 'Je fuis', subtitle: "Je ne vois pas bien", icon: CupertinoIcons.bolt_horizontal_fill, color: Colors.grey[800]!, onTap: () => widget.onConfirm('$_selectedCategory - $_selectedVictim - Je fuis')),
      ];
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      padding: const EdgeInsets.only(top: 12, left: 24, right: 24, bottom: 40),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 48, height: 6, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 24),
            
            Text(title, textAlign: TextAlign.center, style: AppTextStyles.headlineLarge.copyWith(fontWeight: FontWeight.w900, fontSize: 24)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600], fontSize: 15)),
            const SizedBox(height: 32),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return SlideTransition(
                  position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(animation),
                  child: child,
                );
              },
              child: GridView.count(
                key: ValueKey<int>(_step),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.85,
                children: tiles,
              ),
            ),

            const SizedBox(height: 32),
            TextButton(
              onPressed: onBack,
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: Text('home.triage_back'.tr(), style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoldToCancelButton extends StatefulWidget {
  final VoidCallback onComplete;
  final Color accentColor;
  const _HoldToCancelButton({required this.onComplete, this.accentColor = AppColors.red});

  @override
  State<_HoldToCancelButton> createState() => _HoldToCancelButtonState();
}

class _HoldToCancelButtonState extends State<_HoldToCancelButton> with SingleTickerProviderStateMixin {
  late AnimationController _holdController;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        widget.onComplete();
        _holdController.reset();
      }
    });
  }

  @override
  void dispose() {
    // Subscriptions cleared
    _holdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        _holdController.forward();
      },
      onTapUp: (_) {
        _holdController.reverse();
      },
      onTapCancel: () {
        _holdController.reverse();
      },
      child: AnimatedBuilder(
        animation: _holdController,
        builder: (context, child) {
          return Container(
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Stack(
              children: [
                // Filled progress background
                if (_holdController.value > 0)
                  Container(
                    width: MediaQuery.of(context).size.width * _holdController.value,
                    decoration: BoxDecoration(
                      color: widget.accentColor.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                const Center(
                  child: Text(
                    'Maintenir pour annuler',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }
}

class _AmbulanceMapWidget extends StatefulWidget {
  final Position? userPosition;
  final LatLng? ambulancePosition;
  const _AmbulanceMapWidget({this.userPosition, this.ambulancePosition});

  @override
  State<_AmbulanceMapWidget> createState() => _AmbulanceMapWidgetState();
}

class _AmbulanceMapWidgetState extends State<_AmbulanceMapWidget> {
  late LatLng _targetPos;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    double lat = widget.userPosition?.latitude ?? -4.321;
    double lng = widget.userPosition?.longitude ?? 15.312;
    _targetPos = LatLng(lat, lng);
  }

  @override
  void didUpdateWidget(_AmbulanceMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ambulancePosition != null && oldWidget.ambulancePosition != widget.ambulancePosition) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: widget.ambulancePosition!, zoom: 16.5, tilt: 45),
        ),
      );
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ambPos = widget.ambulancePosition ?? LatLng(_targetPos.latitude + 0.005, _targetPos.longitude + 0.005);
    
    return GoogleMap(
      liteModeEnabled: false,
      initialCameraPosition: CameraPosition(
        target: ambPos,
        zoom: 16.0,
      ),
      onMapCreated: (ctrl) => _mapController = ctrl,
      mapType: MapType.normal,
      zoomControlsEnabled: false,
      myLocationButtonEnabled: false,
      compassEnabled: false,
      myLocationEnabled: true,
      markers: {
        Marker(
          markerId: const MarkerId('ambulance'),
          position: ambPos,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      },
      polylines: {
        Polyline(
          polylineId: const PolylineId('route'),
          points: [ambPos, _targetPos],
          color: AppColors.blue.withValues(alpha: 0.5),
          width: 4,
          patterns: [PatternItem.dash(10), PatternItem.gap(10)],
        )
      },
    );
  }
}

