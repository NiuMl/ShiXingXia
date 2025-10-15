import 'package:shared_preferences/shared_preferences.dart';

class TimeTrackingService {
  // SharedPreferences keys (Flutter automatically adds 'flutter.' prefix internally)
  static const String _keyEarnedMinutes = 'earned_minutes';
  static const String _keySpentMinutes = 'spent_minutes';

  /// Get earned minutes
  Future<int> getEarnedMinutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Reload to get latest values from disk (updated by native code)
      await prefs.reload();
      return prefs.getInt(_keyEarnedMinutes) ?? 0;
    } catch (e) {
      print("Error loading earned minutes: $e");
      return 0;
    }
  }

  /// Get spent minutes
  Future<int> getSpentMinutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Reload to get latest values from disk (updated by native code)
      await prefs.reload();
      return prefs.getInt(_keySpentMinutes) ?? 0;
    } catch (e) {
      print("Error loading spent minutes: $e");
      return 0;
    }
  }

  /// Add earned minutes (from completing reps)
  Future<void> addEarnedMinutes(int minutes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_keyEarnedMinutes) ?? 0;
      await prefs.setInt(_keyEarnedMinutes, current + minutes);
    } catch (e) {
      print("Error adding earned minutes: $e");
    }
  }

  /// Add spent minutes (when using apps)
  Future<void> addSpentMinutes(int minutes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_keySpentMinutes) ?? 0;
      await prefs.setInt(_keySpentMinutes, current + minutes);
    } catch (e) {
      print("Error adding spent minutes: $e");
    }
  }

  /// Get available minutes (earned - spent)
  Future<int> getAvailableMinutes() async {
    final earned = await getEarnedMinutes();
    final spent = await getSpentMinutes();
    return earned - spent;
  }

  /// Reset all time tracking
  Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyEarnedMinutes, 0);
      await prefs.setInt(_keySpentMinutes, 0);
    } catch (e) {
      print("Error resetting time tracking: $e");
    }
  }
}
