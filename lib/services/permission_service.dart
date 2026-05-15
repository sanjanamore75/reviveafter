import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<void> requestAllPermissions() async {
    // Standard permissions
    await [
      Permission.camera,
      Permission.microphone,
      Permission.notification,
    ].request();

    // Special permissions (System Alert Window / Appear on top)
    if (!await Permission.systemAlertWindow.isGranted) {
      await Permission.systemAlertWindow.request();
    }

    // Battery Optimization
    if (!await Permission.ignoreBatteryOptimizations.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  static Future<bool> checkAllPermissions() async {
    final camera = await Permission.camera.isGranted;
    final mic = await Permission.microphone.isGranted;
    final notifications = await Permission.notification.isGranted;
    
    return camera && mic && notifications;
  }
}
