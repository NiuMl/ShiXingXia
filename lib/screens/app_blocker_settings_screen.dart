import 'package:flutter/material.dart';
import '../services/app_blocker_service.dart';

class AppBlockerSettingsScreen extends StatefulWidget {
  const AppBlockerSettingsScreen({super.key});

  @override
  State<AppBlockerSettingsScreen> createState() => _AppBlockerSettingsScreenState();
}

class _AppBlockerSettingsScreenState extends State<AppBlockerSettingsScreen> {
  final AppBlockerService _appBlockerService = AppBlockerService();
  List<AppInfo> _installedApps = [];
  Set<String> _blockedPackages = {};
  bool _isLoading = true;
  bool _blockingEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final apps = await _appBlockerService.getInstalledApps();

    // Load saved settings
    final savedBlockedApps = await _appBlockerService.getSavedBlockedApps();
    final savedBlockingEnabled = await _appBlockerService.getSavedBlockingEnabled();

    setState(() {
      _installedApps = apps;
      _blockedPackages = savedBlockedApps.toSet();
      _blockingEnabled = savedBlockingEnabled;
      _isLoading = false;
    });
  }

  Future<void> _toggleBlockingEnabled(bool value) async {
    setState(() => _blockingEnabled = value);
    await _appBlockerService.setBlockingEnabled(value);
  }

  Future<void> _toggleAppBlocked(String packageName, bool isBlocked) async {
    setState(() {
      if (isBlocked) {
        _blockedPackages.add(packageName);
      } else {
        _blockedPackages.remove(packageName);
      }
    });

    await _appBlockerService.setBlockedApps(_blockedPackages.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Blocker Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Blocking Toggle
                Card(
                  margin: const EdgeInsets.all(16),
                  child: SwitchListTile(
                    title: const Text('Enable App Blocking'),
                    subtitle: const Text('Block selected apps when enabled'),
                    value: _blockingEnabled,
                    onChanged: _toggleBlockingEnabled,
                    secondary: Icon(
                      _blockingEnabled ? Icons.block : Icons.check_circle_outline,
                      color: _blockingEnabled ? Colors.red : Colors.grey,
                    ),
                  ),
                ),

                // App List
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        'Select Apps to Block (${_blockedPackages.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                Expanded(
                  child: _installedApps.isEmpty
                      ? const Center(child: Text('No apps found'))
                      : ListView.builder(
                          itemCount: _installedApps.length,
                          itemBuilder: (context, index) {
                            final app = _installedApps[index];
                            final isBlocked = _blockedPackages.contains(app.packageName);

                            return CheckboxListTile(
                              title: Text(app.appName),
                              subtitle: Text(
                                app.packageName,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              value: isBlocked,
                              onChanged: (value) {
                                _toggleAppBlocked(app.packageName, value ?? false);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
