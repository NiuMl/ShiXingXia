import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_blocker_service.dart';
import 'main_menu_screen.dart';

class SetupPermissionsScreen extends StatefulWidget {
  const SetupPermissionsScreen({super.key});

  @override
  State<SetupPermissionsScreen> createState() => _SetupPermissionsScreenState();
}

class _SetupPermissionsScreenState extends State<SetupPermissionsScreen> {
  static const MethodChannel _channel = MethodChannel('com.example.getfit/app_blocker');
  final AppBlockerService _appBlockerService = AppBlockerService();

  bool _accessibilityGranted = false;
  bool _usageStatsGranted = false;
  bool _batteryOptimizationDisabled = false;
  bool _isCheckingPermissions = false;

  @override
  void initState() {
    super.initState();
    _checkAllPermissions();
  }

  Future<void> _checkAllPermissions() async {
    setState(() => _isCheckingPermissions = true);

    final accessibility = await _appBlockerService.isAccessibilityServiceEnabled();
    final usageStats = await _checkUsageStatsPermission();
    final battery = await _checkBatteryOptimization();

    setState(() {
      _accessibilityGranted = accessibility;
      _usageStatsGranted = usageStats;
      _batteryOptimizationDisabled = battery;
      _isCheckingPermissions = false;
    });

    // Auto-navigate if all permissions granted
    if (_accessibilityGranted && _usageStatsGranted && _batteryOptimizationDisabled) {
      await _saveSetupComplete();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainMenuScreen()),
        );
      }
    }
  }

  Future<bool> _checkUsageStatsPermission() async {
    try {
      final bool hasPermission = await _channel.invokeMethod('hasUsageStatsPermission');
      return hasPermission;
    } catch (e) {
      print("Error checking usage stats permission: $e");
      return false;
    }
  }

  Future<bool> _checkBatteryOptimization() async {
    try {
      final bool isIgnoring = await _channel.invokeMethod('isIgnoringBatteryOptimizations');
      return isIgnoring;
    } catch (e) {
      print("Error checking battery optimization: $e");
      return false;
    }
  }

  Future<void> _requestUsageStatsPermission() async {
    try {
      await _channel.invokeMethod('requestUsageStatsPermission');
      await Future.delayed(const Duration(seconds: 1));
      await _checkAllPermissions();
    } catch (e) {
      print("Error requesting usage stats permission: $e");
    }
  }

  Future<void> _requestBatteryOptimization() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
      await Future.delayed(const Duration(seconds: 1));
      await _checkAllPermissions();
    } catch (e) {
      print("Error requesting battery optimization: $e");
    }
  }

  Future<void> _saveSetupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setup_complete', true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Required'),
        automaticallyImplyLeading: false,
      ),
      body: _isCheckingPermissions
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Icon(
                  Icons.security,
                  size: 80,
                  color: Colors.blue,
                ),
                const SizedBox(height: 24),
                const Text(
                  'GetFit needs special permissions',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'These permissions allow the app to block selected apps and track your progress.',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Accessibility Permission
                _PermissionCard(
                  title: 'Accessibility Service',
                  description: 'Required to detect when blocked apps are opened and show blocking overlay.',
                  icon: Icons.accessibility_new,
                  isGranted: _accessibilityGranted,
                  onTap: () async {
                    await _appBlockerService.openAccessibilitySettings();
                    await Future.delayed(const Duration(seconds: 1));
                    await _checkAllPermissions();
                  },
                ),

                const SizedBox(height: 16),

                // Usage Stats Permission
                _PermissionCard(
                  title: 'Usage Access',
                  description: 'Required to reliably detect which app is in the foreground.',
                  icon: Icons.bar_chart,
                  isGranted: _usageStatsGranted,
                  onTap: _requestUsageStatsPermission,
                ),

                const SizedBox(height: 16),

                // Battery Optimization
                _PermissionCard(
                  title: 'Battery Optimization',
                  description: 'Required to keep the blocking service running in the background.',
                  icon: Icons.battery_full,
                  isGranted: _batteryOptimizationDisabled,
                  onTap: _requestBatteryOptimization,
                ),

                const SizedBox(height: 32),

                // Continue button
                if (_accessibilityGranted && _usageStatsGranted && _batteryOptimizationDisabled)
                  ElevatedButton(
                    onPressed: () async {
                      await _saveSetupComplete();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const MainMenuScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      'Continue to App',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),

                const SizedBox(height: 16),

                // Refresh button
                OutlinedButton.icon(
                  onPressed: _checkAllPermissions,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check Permissions'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final bool isGranted;
  final VoidCallback onTap;

  const _PermissionCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.isGranted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: isGranted ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isGranted ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: isGranted ? Colors.green : Colors.orange,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Icon(
                          isGranted ? Icons.check_circle : Icons.error_outline,
                          color: isGranted ? Colors.green : Colors.orange,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
