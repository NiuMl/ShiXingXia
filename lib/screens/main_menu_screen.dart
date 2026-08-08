import 'dart:async';
import 'package:flutter/material.dart';
import '../models/exercise_config.dart';
import '../services/time_tracking_service.dart';
import '../widgets/time_circle_widget.dart';
import 'exercise_screen.dart';
import 'settings_menu_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  final TimeTrackingService _timeService = TimeTrackingService();
  int _earnedMinutes = 0;
  int _spentMinutes = 0;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadTimeData();
    // Refresh time data every second to show real-time updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _loadTimeData();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTimeData() async {
    final earned = await _timeService.getEarnedMinutes();
    final spent = await _timeService.getSpentMinutes();
    if (mounted) {
      setState(() {
        _earnedMinutes = earned;
        _spentMinutes = spent;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('健身打卡'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SettingsMenuScreen(),
                ),
              );
              // Reload data when returning from settings
              _loadTimeData();
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
          child: CustomScrollView(
            slivers: [
              // Time Circle Widget
              SliverToBoxAdapter(
                child: TimeCircleWidget(
                  earnedMinutes: _earnedMinutes,
                  spentMinutes: _spentMinutes,
                ),
              ),
              // Divider
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  child: Divider(color: Colors.white24),
                ),
              ),
              // Exercise Cards
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final exercise = ExerciseConfig.allExercises[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: _ExerciseCard(
                          config: exercise,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ExerciseScreen(
                                  exerciseConfig: exercise,
                                ),
                              ),
                            );
                            // Reload time data when returning from exercise
                            _loadTimeData();
                          },
                        ),
                      );
                    },
                    childCount: ExerciseConfig.allExercises.length,
                  ),
                ),
              ),
              // Bottom padding
              const SliverToBoxAdapter(
                child: SizedBox(height: 16),
              ),
            ],
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
