import 'package:flutter/material.dart';
import 'screens/main_menu_screen.dart';
import 'services/app_blocker_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Restore saved app blocker settings to the native service
  final appBlockerService = AppBlockerService();
  await appBlockerService.restoreSavedSettings();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GetFit - Exercise Tracker',
      theme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: const MainMenuScreen(),
    );
  }
}