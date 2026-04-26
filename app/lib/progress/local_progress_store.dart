import 'package:shared_preferences/shared_preferences.dart';

class LocalProgressStore {
  static const _lessonPrefix = 'lesson_progress_';
  static const _onboardingSeenKey = 'onboarding_arrival_ritual_seen_v1';

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

  /// Returns true if the learner has already completed the Arrival Ritual
  /// onboarding (`docs/plans/arrival-ritual.md`). Defaults to `false` on any
  /// storage failure so the user sees onboarding rather than being silently
  /// dropped into the dashboard.
  static Future<bool> hasSeenOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_onboardingSeenKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Records that the Arrival Ritual onboarding finished. Called at the
  /// final Handoff step CTA, before routing into the lesson intro.
  static Future<void> markOnboardingSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onboardingSeenKey, true);
    } catch (_) {
      // Tolerate persistence failure: worst case, the user sees onboarding
      // again next launch — not a correctness bug, just a soft regression.
    }
  }
}
