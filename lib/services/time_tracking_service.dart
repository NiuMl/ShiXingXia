import 'package:shared_preferences/shared_preferences.dart';

class TimeTrackingService {
  // SharedPreferences keys (Flutter automatically adds 'flutter.' prefix internally)
  static const String _keyEarnedSeconds = 'earned_seconds';
  static const String _keySpentSeconds = 'spent_seconds';
  static const String _keyLastDeductionAt = 'last_deduction_at';

  /// 按运动记录当天时长：key = 'exercise_duration_$dateKey_$exerciseName' (单位秒)
  static String _exerciseDurationKey(String dateKey, String exerciseName) =>
      'exercise_duration_${dateKey}_$exerciseName';

  /// 获取当天日期key（格式 yyyy-MM-dd）
  static String get todayKey {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Get earned seconds
  Future<int> getEarnedSeconds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs.getInt(_keyEarnedSeconds) ?? 0;
    } catch (e) {
      print("Error loading earned seconds: $e");
      return 0;
    }
  }

  /// Get spent seconds
  Future<int> getSpentSeconds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs.getInt(_keySpentSeconds) ?? 0;
    } catch (e) {
      print("Error loading spent seconds: $e");
      return 0;
    }
  }

  /// Get earned minutes (for display)
  Future<int> getEarnedMinutes() async {
    final seconds = await getEarnedSeconds();
    return seconds ~/ 60;
  }

  /// Get spent minutes (for display)
  Future<int> getSpentMinutes() async {
    final seconds = await getSpentSeconds();
    return seconds ~/ 60;
  }

  /// Add earned minutes (from completing reps)
  Future<void> addEarnedMinutes(int minutes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentSeconds = prefs.getInt(_keyEarnedSeconds) ?? 0;
      final secondsToAdd = minutes * 60;
      await prefs.setInt(_keyEarnedSeconds, currentSeconds + secondsToAdd);
    } catch (e) {
      print("Error adding earned minutes: $e");
    }
  }

  /// Get available minutes (earned - spent)
  Future<int> getAvailableMinutes() async {
    final earnedSeconds = await getEarnedSeconds();
    final spentSeconds = await getSpentSeconds();
    return (earnedSeconds - spentSeconds) ~/ 60;
  }

  /// Get available seconds (for precise tracking)
  Future<int> getAvailableSeconds() async {
    final earnedSeconds = await getEarnedSeconds();
    final spentSeconds = await getSpentSeconds();
    return earnedSeconds - spentSeconds;
  }

  // ============== 按运动类型记录当天时长 ==============

  /// 为指定运动追加时长（秒），默认记录到今天
  Future<void> addExerciseDuration(String exerciseName, int seconds, {String? dateKey}) async {
    if (seconds <= 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _exerciseDurationKey(dateKey ?? todayKey, exerciseName);
      final current = prefs.getInt(key) ?? 0;
      await prefs.setInt(key, current + seconds);
    } catch (e) {
      print("Error adding exercise duration: $e");
    }
  }

  /// 获取指定运动当天时长（秒）
  Future<int> getExerciseDurationSeconds(String exerciseName, {String? dateKey}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final key = _exerciseDurationKey(dateKey ?? todayKey, exerciseName);
      return prefs.getInt(key) ?? 0;
    } catch (e) {
      print("Error loading exercise duration: $e");
      return 0;
    }
  }

  /// 获取指定运动当天时长（分钟，向下取整）
  Future<int> getExerciseDurationMinutes(String exerciseName, {String? dateKey}) async {
    final sec = await getExerciseDurationSeconds(exerciseName, dateKey: dateKey);
    return sec ~/ 60;
  }

  /// 获取当天总运动时长（秒）：遍历 allExercises 中每一项并累加
  Future<int> getTodayTotalDurationSeconds(List<String> exerciseNames) async {
    int total = 0;
    for (final name in exerciseNames) {
      total += await getExerciseDurationSeconds(name);
    }
    return total;
  }

  /// 获取当天总运动时长（分钟，向下取整）
  Future<int> getTodayTotalDurationMinutes(List<String> exerciseNames) async {
    final sec = await getTodayTotalDurationSeconds(exerciseNames);
    return sec ~/ 60;
  }

  /// 获取当天每个运动的时长（秒），只返回时长 > 0 的项
  /// 返回 Map：key = exerciseName, value = seconds
  Future<Map<String, int>> getTodayExerciseDurations(List<String> exerciseNames) async {
    final Map<String, int> result = {};
    for (final name in exerciseNames) {
      final sec = await getExerciseDurationSeconds(name);
      if (sec > 0) {
        result[name] = sec;
      }
    }
    return result;
  }

  /// Reset all time tracking
  Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyEarnedSeconds, 0);
      await prefs.setInt(_keySpentSeconds, 0);
      await prefs.setInt(_keyLastDeductionAt, 0);
    } catch (e) {
      print("Error resetting time tracking: $e");
    }
  }
}
