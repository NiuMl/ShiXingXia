import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const String _keyBlockedApps = 'blocked_apps';
  static const String _keyBlockingEnabled = 'blocking_enabled';

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
      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyBlockedApps, packageNames);
    } on PlatformException catch (e) {
      print("Error setting blocked apps: ${e.message}");
    }
  }

  /// Enable or disable blocking functionality
  Future<void> setBlockingEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setBlockingEnabled', {'enabled': enabled});
      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyBlockingEnabled, enabled);
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

  /// Load saved blocked apps from storage
  Future<List<String>> getSavedBlockedApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_keyBlockedApps) ?? [];
    } catch (e) {
      print("Error loading blocked apps: $e");
      return [];
    }
  }

  /// Load saved blocking enabled state
  Future<bool> getSavedBlockingEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyBlockingEnabled) ?? false;
    } catch (e) {
      print("Error loading blocking enabled: $e");
      return false;
    }
  }

  /// Restore saved settings (call on app start)
  Future<void> restoreSavedSettings() async {
    final blockedApps = await getSavedBlockedApps();
    final blockingEnabled = await getSavedBlockingEnabled();

    if (blockedApps.isNotEmpty) {
      await _channel.invokeMethod('setBlockedApps', {'apps': blockedApps});
    }
    await _channel.invokeMethod('setBlockingEnabled', {'enabled': blockingEnabled});
  }
}
