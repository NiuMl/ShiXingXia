import 'package:flutter/material.dart';
import 'screens/main_menu_screen.dart';

void main() => runApp(const MyApp());

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