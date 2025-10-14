import 'package:flutter/services.dart';

class AppInfo {
  final String packageName;
  final String appName;

  AppInfo({required this.packageName, required this.appName});

  factory AppInfo.fromMap(Map<dynamic, dynamic> map) {
    return AppInfo(
      packageName: map['packageName'] as String,
      appName: map['appName'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'packageName': packageName,
      'appName': appName,
    };
  }
}

class AppBlockerService {
  static const MethodChannel _channel = MethodChannel('com.example.getfit/app_blocker');

  /// Check if the accessibility service is enabled
  Future<bool> isAccessibilityServiceEnabled() async {
    try {
      final bool isEnabled = await _channel.invokeMethod('isAccessibilityServiceEnabled');
      return isEnabled;
    } on PlatformException catch (e) {
      print("Error checking accessibility service: ${e.message}");
      return false;
    }
  }

  /// Open accessibility settings to enable the service
  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } on PlatformException catch (e) {
      print("Error opening accessibility settings: ${e.message}");
    }
  }

  /// Set the list of apps to block
  Future<void> setBlockedApps(List<String> packageNames) async {
    try {
      await _channel.invokeMethod('setBlockedApps', {'apps': packageNames});
    } on PlatformException catch (e) {
      print("Error setting blocked apps: ${e.message}");
    }
  }

  /// Enable or disable blocking functionality
  Future<void> setBlockingEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setBlockingEnabled', {'enabled': enabled});
    } on PlatformException catch (e) {
      print("Error setting blocking enabled: ${e.message}");
    }
  }

  /// Get list of installed apps
  Future<List<AppInfo>> getInstalledApps() async {
    try {
      final List<dynamic> apps = await _channel.invokeMethod('getInstalledApps');
      return apps.map((app) => AppInfo.fromMap(app as Map<dynamic, dynamic>)).toList();
    } on PlatformException catch (e) {
      print("Error getting installed apps: ${e.message}");
      return [];
    }
  }
}
