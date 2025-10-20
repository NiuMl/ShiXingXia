import 'package:shared_preferences/shared_preferences.dart';

class TimeTrackingService {
  // SharedPreferences keys (Flutter automatically adds 'flutter.' prefix internally)
  static const String _keyEarnedSeconds = 'earned_seconds';
  static const String _keySpentSeconds = 'spent_seconds';
  static const String _keyLastDeductionAt = 'last_deduction_at';

  /// Get earned seconds
  Future<int> getEarnedSeconds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Reload to get latest values from disk (updated by native code)
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
      // Reload to get latest values from disk (updated by native code)
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
  /// Converts minutes to seconds for storage
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
