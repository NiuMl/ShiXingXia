import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/main_menu_screen.dart';
import 'screens/setup_permissions_screen.dart';
import 'services/app_blocker_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restore saved app blocker settings to the native service
  final appBlockerService = AppBlockerService();
  await appBlockerService.restoreSavedSettings();

  // Check if setup is complete
  final prefs = await SharedPreferences.getInstance();
  final setupComplete = prefs.getBool('setup_complete') ?? false;

  runApp(MyApp(setupComplete: setupComplete));
}

class MyApp extends StatelessWidget {
  final bool setupComplete;

  const MyApp({super.key, required this.setupComplete});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GetFit - Exercise Tracker',
      theme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: setupComplete ? const MainMenuScreen() : const SetupPermissionsScreen(),
    );
  }
}