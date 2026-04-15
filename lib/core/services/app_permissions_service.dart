import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// État agrégé des autorisations nécessaires au fonctionnement de l’app (voir écran gate).
class AppPermissionsSnapshot {
  final bool locationServiceEnabled;
  final LocationPermission locationPermission;
  final PermissionStatus microphone;
  final PermissionStatus camera;
  final PermissionStatus notification;

  const AppPermissionsSnapshot({
    required this.locationServiceEnabled,
    required this.locationPermission,
    required this.microphone,
    required this.camera,
    required this.notification,
  });

  bool get locationGranted =>
      locationServiceEnabled &&
      (locationPermission == LocationPermission.whileInUse ||
          locationPermission == LocationPermission.always);

  bool get allGranted =>
      locationGranted &&
      microphone == PermissionStatus.granted &&
      camera == PermissionStatus.granted &&
      notification == PermissionStatus.granted;
}

/// Lecture et demandes d’autorisations (localisation via Geolocator, le reste via permission_handler).
class AppPermissionsService {
  AppPermissionsService._();

  static Future<AppPermissionsSnapshot> checkAll() async {
    final locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    final locationPermission = await Geolocator.checkPermission();
    final microphone = await Permission.microphone.status;
    final camera = await Permission.camera.status;
    final notification = await Permission.notification.status;

    return AppPermissionsSnapshot(
      locationServiceEnabled: locationServiceEnabled,
      locationPermission: locationPermission,
      microphone: microphone,
      camera: camera,
      notification: notification,
    );
  }

  /// Demande la localisation (service + permission).
  static Future<AppPermissionsSnapshot> requestLocation() async {
    var serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return checkAll();
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      await openAppSettings();
    }
    return checkAll();
  }

  static Future<AppPermissionsSnapshot> requestMicrophone() async {
    final status = await Permission.microphone.request();
    if (status == PermissionStatus.permanentlyDenied) {
      await openAppSettings();
    }
    return checkAll();
  }

  static Future<AppPermissionsSnapshot> requestCamera() async {
    final status = await Permission.camera.request();
    if (status == PermissionStatus.permanentlyDenied) {
      await openAppSettings();
    }
    return checkAll();
  }

  static Future<AppPermissionsSnapshot> requestNotification() async {
    final status = await Permission.notification.request();
    if (status == PermissionStatus.permanentlyDenied) {
      await openAppSettings();
    }
    return checkAll();
  }

  static Future<void> openSystemSettings() async {
    await openAppSettings();
  }
}
