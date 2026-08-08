import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/main_menu_screen.dart';
import 'screens/setup_permissions_screen.dart';
import 'screens/splash_screen.dart';
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

class MyApp extends StatefulWidget {
  final bool setupComplete;

  const MyApp({super.key, required this.setupComplete});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _showSplash = true;

  void _onSplashComplete() {
    setState(() {
      _showSplash = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '健身打卡 - 运动追踪',
      theme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: _showSplash
          ? SplashScreen(onComplete: _onSplashComplete)
          : (widget.setupComplete
              ? const MainMenuScreen()
              : const SetupPermissionsScreen()),
    );
  }
}
