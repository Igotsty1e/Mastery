import 'package:shared_preferences/shared_preferences.dart';

class LocalProgressStore {
  static const _lessonPrefix = 'lesson_progress_';
  static const _onboardingSeenKey = 'onboarding_arrival_ritual_seen_v2';
  static const _diagnosticSkippedKey = 'diagnostic_skipped_v1';

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

  /// Wave 12.3 — diagnostic-mode skip flag. Set when the learner taps
  /// "Skip for now" on the diagnostic welcome step. The HomeScreen
  /// routing gate reads this so a skipper does not see the prompt
  /// again on the same device. Cleared by the future Wave 12.4
  /// settings re-take affordance.
  ///
  /// Defaults to `false` on storage failure so a true intent (skip)
  /// is never silently turned into a re-prompt; the user is no worse
  /// off than seeing the diagnostic again.
  static Future<bool> hasSkippedDiagnostic() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_diagnosticSkippedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markDiagnosticSkipped() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_diagnosticSkippedKey, true);
    } catch (_) {
      // Tolerate persistence failure — the server-side audit event
      // still fires, and the worst case is a re-prompt on next launch.
    }
  }

  static Future<void> clearDiagnosticSkipped() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_diagnosticSkippedKey);
    } catch (_) {
      // Soft failure.
    }
  }

  /// Wave G9 — first-session bridge gate. Set when the brand-new
  /// learner has been pushed straight from onboarding/diagnostic
  /// into their very first dynamic session, so the HomeScreen
  /// "first-session bridge" view never re-fires (and the dashboard
  /// renders normally on the way back from the SummaryScreen).
  /// The semantics are "started", not "completed" — once we have
  /// pushed the LessonIntroScreen we commit, even if the learner
  /// closes the tab before submitting an answer.
  static const _firstSessionStartedKey = 'first_session_started_v1';

  static Future<bool> hasStartedFirstSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_firstSessionStartedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markFirstSessionStarted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_firstSessionStartedKey, true);
    } catch (_) {
      // Soft failure — worst case the bridge fires again on next
      // launch, which still ends in a session (just one extra
      // loading frame).
    }
  }
}
