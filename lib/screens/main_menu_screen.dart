import 'package:flutter/material.dart';
import '../models/exercise_config.dart';
import 'exercise_screen.dart';
import 'app_blocker_settings_screen.dart';

class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GetFit'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AppBlockerSettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.grey.shade900,
              Colors.black,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView.builder(
              itemCount: ExerciseConfig.allExercises.length,
              itemBuilder: (context, index) {
                final exercise = ExerciseConfig.allExercises[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: _ExerciseCard(
                    config: exercise,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExerciseScreen(
                            exerciseConfig: exercise,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final ExerciseConfig config;
  final VoidCallback onTap;

  const _ExerciseCard({
    required this.config,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                config.primaryColor.withValues(alpha: 0.15),
                config.secondaryColor.withValues(alpha: 0.1),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: config.primaryColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    config.icon,
                    size: 32,
                    color: config.primaryColor,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    config.displayName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: config.secondaryColor,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
