import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Service de premier plan Android pour maintenir l'appel Agora actif
/// en arrière-plan (requis sur Android 12+, sinon le processus audio est tué).
class CallForegroundService {
  /// Configuration initiale — appeler dans main() avant runApp()
  static void initTaskHandler() {
    // Initialise le canal de communication entre TaskHandler et l'UI
    FlutterForegroundTask.initCommunicationPort();

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'agora_call_channel',
        channelName: 'Appel SOS en cours',
        channelDescription: 'Maintient votre appel d\'urgence actif en arrière-plan',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Démarre le service de premier plan quand un appel commence
  static Future<void> start({
    required String channelId,
    required String role,
  }) async {
    // Vérifier et demander les permissions si nécessaire
    if (!await FlutterForegroundTask.isRunningService) {
      final result = await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: _titleForRole(role),
        notificationText: 'Canal actif : $channelId',
        notificationIcon: null,
        notificationButtons: [
          const NotificationButton(id: 'btn_end_call', text: 'Raccrocher'),
        ],
        callback: startCallback,
      );
      debugPrint('[ForegroundService] Démarré : $result pour le canal $channelId');
    } else {
      await FlutterForegroundTask.updateService(
        notificationTitle: _titleForRole(role),
        notificationText: 'Canal actif : $channelId',
      );
    }

    // Écouter les données envoyées par le TaskHandler (bouton raccrocher)
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }

  /// Arrête le service quand l'appel se termine
  static Future<void> stop() async {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    if (await FlutterForegroundTask.isRunningService) {
      final result = await FlutterForegroundTask.stopService();
      debugPrint('[ForegroundService] Arrêté : $result');
    }
  }

  static void _onReceiveTaskData(Object data) {
    if (data is String && data == 'btn_end_call') {
      debugPrint('[ForegroundService] Bouton raccrocher appuyé depuis la notification');
      // Le signal est reçu dans l'UI via addTaskDataCallback dans LiveCallScreen
    }
  }

  static String _titleForRole(String role) {
    switch (role) {
      case 'Rescuer':
        return '🚑 Appel SOS en cours — Secouriste';
      case 'Dispatcher':
        return '🖥️ Supervision SOS — Dispatcher';
      default:
        return '🚨 Appel SOS en cours';
    }
  }
}

/// Callback de démarrage du TaskHandler (doit être top-level @pragma)
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(CallTaskHandler());
}

/// Handler du service foreground — s'exécute dans un isolate séparé
class CallTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[ForegroundService] Handler démarré — starter: ${starter.name}');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Keepalive : envoie un ping au thread principal toutes les 5 secondes
    FlutterForegroundTask.sendDataToMain({
      'event': 'keepalive',
      'timestampMillis': timestamp.millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[ForegroundService] Handler détruit (timeout: $isTimeout)');
  }

  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('[ForegroundService] Bouton notif: $id');
    // Envoie l'action de raccrocher au thread principal
    FlutterForegroundTask.sendDataToMain(id);
  }

  @override
  void onNotificationPressed() {
    debugPrint('[ForegroundService] Notification tapée');
  }
}
