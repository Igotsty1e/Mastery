import 'package:shared_preferences/shared_preferences.dart';

class LocalProgressStore {
  static const _lessonPrefix = 'lesson_progress_';

  static Future<int> getCompletedExercises(String lessonId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('$_lessonPrefix$lessonId') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> recordCompletedExercises(
      String lessonId, int completedCount) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_lessonPrefix$lessonId';
      final existing = prefs.getInt(key) ?? 0;
      final next = completedCount > existing ? completedCount : existing;
      await prefs.setInt(key, next);
    } catch (_) {
      // Ignore local persistence failures; lesson flow must keep working.
    }
  }
}
