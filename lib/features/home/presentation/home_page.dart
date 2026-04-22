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
import 'package:flutter_animate/flutter_animate.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../../core/utils/dynamic_island_toast.dart';
import '../../training/presentation/training_page.dart';
import 'full_screen_map_page.dart';
import 'package:etoile_bleue_mobile/core/providers/call_state_provider.dart';
import 'package:etoile_bleue_mobile/core/services/emergency_call_service.dart';
import 'package:etoile_bleue_mobile/core/providers/active_intervention_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:etoile_bleue_mobile/core/router/app_router.dart';
import 'widgets/goodsam_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/profile_provider.dart';
import '../../../core/providers/user_provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:etoile_bleue_mobile/core/providers/notifications_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

enum SosTrackingState { processing, handled, onTheWay, onSite }

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> with TickerProviderStateMixin, WidgetsBindingObserver {
  GoogleMapController? _mapController;
  String? _mapStyle;
  BitmapDescriptor? _customLocationMarker;
  BitmapDescriptor? _rescuerMarkerIcon;
  late AnimationController _sosAnimationController;
  late AnimationController _radarAnimationController;
  Position? _currentPosition;
  String _currentAddress = "Recherche position...";
  
  bool _isLocationGranted = false;
  bool _isSosTriggered = false;
  bool _isMapLoaded = false;
  StreamSubscription<Position>? _positionStreamSubscription;
  int _currentIndex = 0;
  final Set<int> _loadedTabs = {0};
  final AudioPlayer _sosAudioPlayer = AudioPlayer();
  final GlobalKey<DirectoryPageState> _directoryKey = GlobalKey<DirectoryPageState>();

  // Tracking-related state (kept for _buildSOSButton and _buildTrackingShazamWave)
  bool _isTrackerMinimized = false;
  final SosTrackingState _trackingState = SosTrackingState.processing;
  final int _ambulanceEtaMinutes = 8;
  
  // Exemple de position par défaut : Kinshasa Gombe
  static const LatLng _center = LatLng(-4.316, 15.311);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      if (!mounted) return;
      ref.read(activeInterventionProvider.notifier).refreshInterventionTracking();
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

    // Initialize Rescuer Marker Icon (Ambulance style: Square with cross or distinct shape)
    final ui.PictureRecorder rescuerRecorder = ui.PictureRecorder();
    final Canvas rescuerCanvas = Canvas(rescuerRecorder);
    
    // Draw a square-ish base for ambulance (Red/Orange body)
    final Paint bodyPaint = Paint()..color = Colors.redAccent;
    final RRect bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(size / 2, size / 2), width: size * 0.9, height: size * 0.7),
      const Radius.circular(8),
    );
    rescuerCanvas.drawRRect(bodyRect, bodyPaint);

    // Draw a white cross
    final Paint crossPaint = Paint()..color = Colors.white;
    rescuerCanvas.drawRect(
      Rect.fromCenter(center: Offset(size / 2, size / 2), width: size * 0.15, height: size * 0.5),
      crossPaint,
    );
    rescuerCanvas.drawRect(
      Rect.fromCenter(center: Offset(size / 2, size / 2), width: size * 0.5, height: size * 0.15),
      crossPaint,
    );
    
    // Add a blue siren on top
    final Paint lightPaint = Paint()..color = Colors.blue;
    rescuerCanvas.drawCircle(Offset(size * 0.7, size * 0.2), size * 0.12, lightPaint);

    final ui.Image rescuerImage = await rescuerRecorder.endRecording().toImage(size, size);
    final ByteData? rescuerByteData = await rescuerImage.toByteData(format: ui.ImageByteFormat.png);
    if (rescuerByteData != null) {
      final Uint8List uint8List = rescuerByteData.buffer.asUint8List();
      if (mounted) {
        setState(() {
          _rescuerMarkerIcon = BitmapDescriptor.fromBytes(uint8List);
          debugPrint('[Map] Rescuer marker icon initialized');
        });
      }
    }
  }

  Future<void> _loadMapStyle() async {
    _mapStyle = await rootBundle.loadString('assets/json/map_style_white.json');
    if (mounted) setState(() {});
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vibrationTimer?.cancel();
    _positionStreamSubscription?.cancel();
    _mapController?.dispose();
    _sosAnimationController.dispose();
    _sosAudioPlayer.dispose();
    _radarAnimationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _tryExtractLocation();
    }
  }

  Future<void> _tryExtractLocation() async {
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;

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


  Widget _buildHomeTab() {
    final interventionState = ref.watch(activeInterventionProvider);
    final showBanner = interventionState.isVisible;

    return Stack(
      children: [
        SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAppBar(),
              const SizedBox(height: 24),
              _buildGreeting(),
              const SizedBox(height: AppSpacing.sm),
              Expanded(child: RepaintBoundary(child: _buildMapSection(interventionState))),
              _buildQuickActions(),
              const SizedBox(height: 32),
            ],
          ),
        ),

        // Dynamic Island - Intervention en cours
        if (showBanner)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 0,
            right: 0,
            child: Center(
              child: _buildDynamicIsland(interventionState),
            ),
          ),
      ],
    );
  }

  Widget _buildDynamicIsland(ActiveInterventionState intervention) {
    final status = intervention.dispatchStatus;
    final IconData icon;
    final String label;
    final Color accentColor;

    switch (status) {
      case 'en_route':
        icon = CupertinoIcons.location_fill;
        label = 'En route';
        accentColor = Colors.greenAccent;
        break;
      case 'dispatched':
        icon = CupertinoIcons.car_detailed;
        label = 'Assigné';
        accentColor = Colors.orangeAccent;
        break;
      case 'arrived':
        icon = CupertinoIcons.location_solid;
        label = 'Sur place';
        accentColor = Colors.deepPurpleAccent;
        break;
      case 'processing':
        icon = CupertinoIcons.hourglass;
        label = 'Traitement';
        accentColor = AppColors.blue;
        break;
      default:
        icon = CupertinoIcons.info_circle_fill;
        label = 'Intervention';
        accentColor = Colors.blueAccent;
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        final incidentId = intervention.incidentId;
        if (incidentId != null) {
          context.push(
            AppRoutes.incidentDetail.replaceAll(':id', incidentId),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        constraints: const BoxConstraints(minWidth: 240),
        decoration: BoxDecoration(
          color: Colors.black, // True Dynamic Island black
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: accentColor.withOpacity(0.2),
              blurRadius: 2,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Status Icon with Pulse-like glow
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 16),
            ),
            const SizedBox(width: 12),
            // Text Info
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '🚨 Mission active',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            // Minimalist chevron
            Icon(
              CupertinoIcons.chevron_right,
              color: Colors.white.withOpacity(0.4),
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ActiveInterventionState>(activeInterventionProvider, (prev, next) {
      if (!next.isVisible) return;
      debugPrint(
        '[Intervention][Popup] Alerte affichée — '
        'incidentId=${next.incidentId}, '
        'incidentStatus=${next.incidentStatus}, '
        'archivedAt=${next.incidentArchivedAt}, '
        'resolvedAt=${next.incidentResolvedAt}, '
        'dispatchStatus=${next.dispatchStatus}, '
        'rescuerName=${next.rescuerName}',
      );
    });

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

    return Scaffold(
      backgroundColor: AppColors.white,
      body: IndexedStack(
        key: ValueKey(context.locale.toString()),
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          _loadedTabs.contains(1) ? DirectoryPage(key: _directoryKey) : const SizedBox.shrink(),
          _loadedTabs.contains(2) ? const HistoryPage() : const SizedBox.shrink(),
          _loadedTabs.contains(3) ? const ProfilePage() : const SizedBox.shrink(),
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
                              : const CachedNetworkImageProvider('https://api.dicebear.com/7.x/notionists/png?seed=David&backgroundColor=e6f0fa'),
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
                error: (err, stack) => 'David',
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'home.you_are_here'.tr(),
                      style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      _currentAddress,
                      style: AppTextStyles.bodyLarge.copyWith(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMapSection(ActiveInterventionState interventionState) {
    final hasRescuer = interventionState.isVisible && interventionState.rescuerLat != null && interventionState.rescuerLng != null;
    
    if (hasRescuer) {
      debugPrint('[TRACKING_DEBUG] Rendering map with Rescuer at: ${interventionState.rescuerLat}, ${interventionState.rescuerLng}');
    } else {
      debugPrint('[TRACKING_DEBUG] Rendering map WITHOUT Rescuer (lat/lng is null)');
    }
    
    // Polyline for tracking
    final Set<Polyline> polylines = {};
    if (hasRescuer && _currentPosition != null) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('tracking_route'),
          points: [
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            LatLng(interventionState.rescuerLat!, interventionState.rescuerLng!),
          ],
          color: AppColors.blue,
          width: 5,
          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
        ),
      );

      // Fit bounds to show both user and rescuer
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_mapController != null) {
          final bounds = LatLngBounds(
            southwest: LatLng(
              _currentPosition!.latitude < interventionState.rescuerLat! ? _currentPosition!.latitude : interventionState.rescuerLat!,
              _currentPosition!.longitude < interventionState.rescuerLng! ? _currentPosition!.longitude : interventionState.rescuerLng!,
            ),
            northeast: LatLng(
              _currentPosition!.latitude > interventionState.rescuerLat! ? _currentPosition!.latitude : interventionState.rescuerLat!,
              _currentPosition!.longitude > interventionState.rescuerLng! ? _currentPosition!.longitude : interventionState.rescuerLng!,
            ),
          );
          _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
        }
      });
    }

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        // 1. The Map Container
        Padding(
          padding: const EdgeInsets.only(bottom: 130),
          child: Container(
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
                      height: constraints.maxHeight + 35,
                      child: GoogleMap(
                        onMapCreated: (GoogleMapController controller) {
                          _mapController = controller;
                          if (_mapStyle != null) {
                            _mapController?.setMapStyle(_mapStyle);
                          }
                          if (_currentPosition != null && !hasRescuer) {
                            _mapController?.animateCamera(
                              CameraUpdate.newCameraPosition(
                                CameraPosition(
                                  target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                                  zoom: 18.0,
                                ),
                              ),
                            );
                          }
                          if (mounted) setState(() => _isMapLoaded = true);
                        },
                        initialCameraPosition: const CameraPosition(
                          target: _center,
                          zoom: 18.0,
                        ),
                        markers: {
                          if (_currentPosition != null && _customLocationMarker != null)
                            Marker(
                              markerId: const MarkerId('current_location'),
                              position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                              icon: _customLocationMarker!,
                              anchor: const Offset(0.5, 0.5),
                              infoWindow: const InfoWindow(title: 'Vous êtes ici'),
                            ),
                          if (hasRescuer && _rescuerMarkerIcon != null)
                            Marker(
                              markerId: const MarkerId('rescuer_location'),
                              position: LatLng(interventionState.rescuerLat!, interventionState.rescuerLng!),
                              icon: _rescuerMarkerIcon!,
                              anchor: const Offset(0.5, 0.5),
                              infoWindow: InfoWindow(title: interventionState.rescuerName ?? 'Secouriste'),
                            ),
                        },
                        polylines: polylines,
                        zoomControlsEnabled: false,
                        myLocationEnabled: false,
                        myLocationButtonEnabled: false,
                        mapToolbarEnabled: false,
                        compassEnabled: false,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        // 2. Shimmer de chargement
        if (!_isMapLoaded)
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(bottom: (!interventionState.isVisible || _isTrackerMinimized) ? 130 : 0),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: Colors.grey[200],
                ),
                child: const _MapShimmer(),
              ),
            ),
          ),

        // 3. Gradient fade on top of map
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 60,
          child: IgnorePointer(
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
        ),

        // 4. SOS Button
        Positioned(
          bottom: 60,
          left: 0,
          right: 0,
          child: Center(child: _buildSOSButton(interventionState)),
        ),

        // 5. Full Screen Toggle Icon (Top Layer)
        Positioned(
          top: 12,
          right: AppSpacing.md + 12,
          child: Material(
            color: Colors.white,
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                debugPrint('[NAVIGATION] Fullscreen button clicked (Top Layer)!');
                HapticFeedback.mediumImpact();
                context.push(
                  AppRoutes.fullScreenMap,
                  extra: {'position': _currentPosition},
                );
              },
              child: const SizedBox(
                width: 50,
                height: 50,
                child: Center(
                  child: Icon(
                    Icons.fullscreen,
                    color: AppColors.blue,
                    size: 30,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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
                        color: waveColor.withValues(alpha: 0.3),
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
                  color: waveColor.withValues(alpha: 0.5),
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

  Widget _buildSOSButton(ActiveInterventionState interventionState) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        final callState = ref.read(callStateProvider);
        if (callState.isInCall) {
          DynamicIslandToast.showError(context, "Un appel d'urgence est déjà en cours");
          return;
        }
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
          final callState = ref.read(callStateProvider);
          if (!callState.isInCall && !_isSosTriggered) {
            DynamicIslandToast.showInfo(context, "Maintenez le bouton enfoncé pour lancer l'appel");
          }
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

  /// Déclenché par le bouton SOS après maintien complet (1.2 s).
  /// Point d'entrée unique pour tout déclenchement d'appel SOS.
  Future<void> _triggerEmergencyCall() async {
    if (_isSosTriggered) return;
    if (!mounted) return;

    // Bloquer si un appel est déjà en cours
    final callState = ref.read(callStateProvider);
    if (callState.isInCall || callState.status == ActiveCallStatus.connecting) {
      debugPrint('[SOS] Appel déjà en cours, redirection vers l\'écran actif');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('calls.call_already_active'.tr()),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      // Redirige vers l'écran de l'appel en cours
      if (mounted) {
        ref.read(isCallMinimizedProvider.notifier).state = false;
        context.push('/call/active');
      }
      return;
    }
    
    setState(() => _isSosTriggered = true);
    
    // 1. Lancement de la logique backend (met le status à 'connecting' immédiatement)
    _executeEmergencyCallBackground();

    // 2. Navigation IMMÉDIATE après que le statut est 'connecting' pour que GoRouter l'accepte
    if (mounted) {
      context.push('/call/active');
    }
  }

  void _executeEmergencyCallBackground() async {
    try {
      await ref.read(callStateProvider.notifier).startSosCall(
        lat: _currentPosition?.latitude,
        lng: _currentPosition?.longitude,
      );
      // La gestion de compte bloqué ou des erreurs terminales sera dorénavant captée
      // par les listeners à l'intérieur de EmergencyCallScreen.
    } catch (e) {
      // Unmounted est possible si on est revenu à l'accueil très vite, 
      // ou bien on utilise context qui est toujours valide via GoRouter
      if (mounted) {
        // En cas d'échec critique, la page d'appel verra son statut passer à `ended`
        // et pop(), la SnackBar affichera la raison sur le Home.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('home.emergency_connection_error'.tr(namedArgs: {'error': e.toString()})),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSosTriggered = false);
    }
  }

  void _showIncidentSheet() {
    context.push('/signalement-form');
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
            _loadedTabs.add(index);
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


class _MapShimmer extends StatefulWidget {
  const _MapShimmer();

  @override
  State<_MapShimmer> createState() => _MapShimmerState();
}

class _MapShimmerState extends State<_MapShimmer> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.grey[200]!,
                Colors.grey[100]!,
                Colors.grey[200]!,
              ],
              stops: [0.0, _anim.value, 1.0],
            ),
          ),
        );
      },
    );
  }
}
