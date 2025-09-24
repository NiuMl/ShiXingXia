import 'package:flutter/material.dart';
import 'pose_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ML-Kit Pose',
      theme: ThemeData.dark(),
      home: const MainMenuScreen(),
    );
  }
}

/* ---------------- Main Menu ---------------- */
class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ML-Kit Pose Demo')),
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.camera_alt),
          label: const Text('Start Pose Tracking'),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PoseScreen()),
          ),
        ),
      ),
    );
  }
}