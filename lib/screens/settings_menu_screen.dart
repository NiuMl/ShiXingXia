import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_blocker_settings_screen.dart';
import 'setup_permissions_screen.dart';

class SettingsMenuScreen extends StatelessWidget {
  const SettingsMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('应用拦截'),
            subtitle: const Text('选择要拦截的应用'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AppBlockerSettingsScreen(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('权限管理'),
            subtitle: const Text('查看并授予所需权限'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              // Clear setup complete flag to show permission screen
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('setup_complete', false);

              if (context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SetupPermissionsScreen(),
                  ),
                ).then((_) async {
                  // Restore setup complete when returning
                  await prefs.setBool('setup_complete', true);
                });
              }
            },
          ),
          const Divider(),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '健身打卡 - 运动与应用管理',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
