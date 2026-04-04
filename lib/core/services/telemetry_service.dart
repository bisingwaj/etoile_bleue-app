import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class TelemetryService {
  static final Battery _battery = Battery();
  static final Connectivity _connectivity = Connectivity();
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  static Future<Map<String, String>> getDeviceTelemetry() async {
    String batteryLevel = 'Unknown';
    String networkState = 'Unknown';
    String deviceModel = 'Unknown';

    // 1. Batterie
    try {
      final level = await _battery.batteryLevel;
      batteryLevel = '$level%';
    } catch (e) {
      debugPrint('[Telemetry] Battery error: $e');
    }

    // 2. Réseau
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      // connectivityResult is a List in newer versions
      if (connectivityResult.isNotEmpty) {
        final result = connectivityResult.first;
        if (result == ConnectivityResult.mobile) {
          networkState = 'Cellulaire (3G/4G)';
        } else if (result == ConnectivityResult.wifi) {
          networkState = 'Wi-Fi';
        } else if (result == ConnectivityResult.none) {
          networkState = 'Hors-ligne';
        } else {
          networkState = result.name;
        }
      }
    } catch (e) {
      debugPrint('[Telemetry] Network error: $e');
    }

    // 3. Modèle de l'appareil
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        deviceModel = '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        deviceModel = iosInfo.utsname.machine;
      }
    } catch (e) {
      debugPrint('[Telemetry] Device info error: $e');
    }

    return {
      'battery_level': batteryLevel,
      'network_state': networkState,
      'device_model': deviceModel,
    };
  }
}
