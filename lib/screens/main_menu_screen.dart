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
  int _todayTotalMinutes = 0;

  /// 当天已使用的运动：key = exerciseName, value = 秒数
  Map<String, int> _todayExerciseSeconds = {};

  Timer? _refreshTimer;

  /// 所有运动名列表，用于查询时长
  List<String> get _allExerciseNames =>
      ExerciseConfig.allExercises.map((e) => e.name).toList();

  @override
  void initState() {
    super.initState();
    _loadTimeData();
    // 每秒刷新：运动中时长会每10秒写入，返回首页时能尽快看到最新数据
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
    final names = _allExerciseNames;
    final totalMin = await _timeService.getTodayTotalDurationMinutes(names);
    final durations = await _timeService.getTodayExerciseDurations(names);
    if (mounted) {
      setState(() {
        _todayTotalMinutes = totalMin;
        _todayExerciseSeconds = durations;
      });
    }
  }

  /// 将秒数格式化为 "X分Y秒" 或 "X分钟"（整分时）
  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    if (min == 0) return '$sec秒';
    if (sec == 0) return '$min分钟';
    return '$min分${sec}秒';
  }

  @override
  Widget build(BuildContext context) {
    // 按 allExercises 顺序过滤出当天使用过的配置
    final usedConfigs = ExerciseConfig.allExercises
        .where((c) => _todayExerciseSeconds.containsKey(c.name))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('108拜'),
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
              // Time Circle Widget：显示当天总运动分钟数
              SliverToBoxAdapter(
                child: TimeCircleWidget(
                  totalMinutes: _todayTotalMinutes,
                ),
              ),
              // 当天各运动时长列表（只显示使用过的）：图标 + 时长
              if (usedConfigs.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '今日运动',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 18,
                          runSpacing: 16,
                          children: usedConfigs.map((config) {
                            final secs =
                                _todayExerciseSeconds[config.name] ?? 0;
                            return _TodayExerciseIcon(
                              config: config,
                              durationText: _formatDuration(secs),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
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

/// 当天已使用的运动：图标 + 时长
class _TodayExerciseIcon extends StatelessWidget {
  final ExerciseConfig config;
  final String durationText;

  const _TodayExerciseIcon({
    required this.config,
    required this.durationText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: config.primaryColor.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(
              color: config.primaryColor.withOpacity(0.4),
            ),
          ),
          child: Icon(
            config.icon,
            size: 26,
            color: config.primaryColor,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          durationText,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: config.secondaryColor,
          ),
        ),
      ],
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
