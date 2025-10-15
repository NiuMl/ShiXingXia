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
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('App Blocker'),
            subtitle: const Text('Select which apps to block'),
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
            title: const Text('Permissions'),
            subtitle: const Text('Review and grant required permissions'),
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
              'GetFit - Exercise & App Control',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
