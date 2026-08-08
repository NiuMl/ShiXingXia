import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
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
  bool _notificationGranted = false;
  bool _isCheckingPermissions = false;

  @override
  void initState() {
    super.initState();
    _checkAllPermissions();
  }

  Future<void> _checkAllPermissions({bool autoNavigate = true}) async {
    setState(() => _isCheckingPermissions = true);

    final accessibility = await _appBlockerService.isAccessibilityServiceEnabled();
    final usageStats = await _checkUsageStatsPermission();
    final battery = await _checkBatteryOptimization();
    final notification = await _checkNotificationPermission();

    setState(() {
      _accessibilityGranted = accessibility;
      _usageStatsGranted = usageStats;
      _batteryOptimizationDisabled = battery;
      _notificationGranted = notification;
      _isCheckingPermissions = false;
    });

    // Auto-navigate if all permissions granted (only on initial load or manual check)
    if (autoNavigate && _accessibilityGranted && _usageStatsGranted && _batteryOptimizationDisabled && _notificationGranted) {
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
      await _checkAllPermissions(autoNavigate: false);
    } catch (e) {
      print("Error requesting usage stats permission: $e");
    }
  }

  Future<void> _requestBatteryOptimization() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
      await Future.delayed(const Duration(seconds: 1));
      await _checkAllPermissions(autoNavigate: false);
    } catch (e) {
      print("Error requesting battery optimization: $e");
    }
  }

  Future<bool> _checkNotificationPermission() async {
    try {
      final status = await Permission.notification.status;
      return status.isGranted;
    } catch (e) {
      print("Error checking notification permission: $e");
      return true; // On older Android, notifications are granted by default
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final status = await Permission.notification.request();
      await _checkAllPermissions(autoNavigate: false);
    } catch (e) {
      print("Error requesting notification permission: $e");
    }
  }

  Future<void> _saveSetupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setup_complete', true);
  }

  void _showAccessibilityDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('开启无障碍服务'),
        content: const Text(
          '为了让健身打卡能检测并拦截应用：\n\n'
          '1. 点击下方“打开设置”\n'
          '2. 在列表中找到“健身打卡”\n'
          '3. 将开关切换为开启\n'
          '4. 点击确定确认\n'
          '5. 返回此页面',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _appBlockerService.openAccessibilitySettings();
              await Future.delayed(const Duration(seconds: 1));
              if (context.mounted) await _checkAllPermissions(autoNavigate: false);
            },
            child: const Text('打开设置'),
          ),
        ],
      ),
    );
  }

  void _showUsageStatsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('开启使用情况访问权限'),
        content: const Text(
          '为了追踪正在使用的应用：\n\n'
          '1. 点击下方“打开设置”\n'
          '2. 在列表中找到“健身打卡”\n'
          '3. 将开关切换为开启\n'
          '4. 返回此页面',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _requestUsageStatsPermission();
            },
            child: const Text('打开设置'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('需要完成设置'),
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
                  '健身打卡需要特殊权限',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  '这些权限允许应用拦截选定的应用并追踪你的进度。',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Accessibility Permission
                _PermissionCard(
                  title: '无障碍服务',
                  description: '用于检测被拦截应用被打开时显示拦截界面。',
                  icon: Icons.accessibility_new,
                  isGranted: _accessibilityGranted,
                  onTap: () => _showAccessibilityDialog(context),
                ),

                const SizedBox(height: 16),

                // Usage Stats Permission
                _PermissionCard(
                  title: '使用情况访问',
                  description: '用于可靠检测当前处于前台的应用。',
                  icon: Icons.bar_chart,
                  isGranted: _usageStatsGranted,
                  onTap: () => _showUsageStatsDialog(context),
                ),

                const SizedBox(height: 16),

                // Battery Optimization
                _PermissionCard(
                  title: '电池优化',
                  description: '用于保持拦截服务在后台运行。',
                  icon: Icons.battery_full,
                  isGranted: _batteryOptimizationDisabled,
                  onTap: _requestBatteryOptimization,
                ),

                const SizedBox(height: 16),

                // Notification Permission
                _PermissionCard(
                  title: '通知',
                  description: '用于显示使用时长追踪通知。',
                  icon: Icons.notifications,
                  isGranted: _notificationGranted,
                  onTap: _requestNotificationPermission,
                ),

                const SizedBox(height: 32),

                // Continue button
                if (_accessibilityGranted && _usageStatsGranted && _batteryOptimizationDisabled && _notificationGranted)
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
                      '继续使用应用',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),

                const SizedBox(height: 16),

                // Refresh button
                OutlinedButton.icon(
                  onPressed: _checkAllPermissions,
                  icon: const Icon(Icons.refresh),
                  label: const Text('检查权限'),
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
