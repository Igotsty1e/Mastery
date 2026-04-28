// LastLessonStore — in-memory cross-screen holder for the most recent
// completed lesson result. Read by HomeScreen so the "Last lesson report"
// block on the Study Desk dashboard stays visible across navigation.
//
// Persistence is intentionally NOT implemented in this wave: the spec
// (`docs/plans/dashboard-study-desk.md` §7) requires the report to be
// "always visible after the learner has completed at least one lesson",
// which strictly needs a persisted snapshot. The persisted backing is
// the planned `/dashboard.last_lesson_report` rebind in
// `docs/plans/auth-foundation.md` Wave 3. For now the block is visible
// only inside the runtime session that completed the lesson.
//
// Wave 14.9 (2026-04-28) — the record now carries the full
// `LessonResultResponse` so the dashboard's `Review mistakes` and
// `See full report` CTAs can render the per-exercise mistake list,
// not just a thin headline. Before 14.9 the store dropped the
// answers list, which made `Review mistakes` open a SummaryScreen
// with no mistakes to review and `initialScrollToMistakes` had no
// scroll target.
//
// Singleton lifetime = app lifetime. Writers: SessionController on
// successful summary fetch. Readers: HomeScreen.

import 'package:flutter/foundation.dart';

import '../models/evaluation.dart';

class LastLessonRecord {
  final String lessonId;
  final String lessonTitle;
  final DateTime completedAt;
  final int totalExercises;
  final int correctCount;
  final LessonDebrief? debrief;

  /// Wave 14.9 — full server response carrying per-exercise answers,
  /// canonical answers, explanations, and the mistake list. The
  /// dashboard CTAs (`Review mistakes`, `See full report`) re-render
  /// SummaryScreen against this so the learner sees the same content
  /// they saw immediately after the lesson, without a re-fetch.
  ///
  /// Nullable because the legacy fallback in `SessionController` may
  /// have to enter the summary phase with local counts only when the
  /// `/result` fetch fails (e.g. transient network). UI must degrade
  /// gracefully — see `_LastLessonReport` in `home_screen.dart`.
  final LessonResultResponse? summary;

  const LastLessonRecord({
    required this.lessonId,
    required this.lessonTitle,
    required this.completedAt,
    required this.totalExercises,
    required this.correctCount,
    this.debrief,
    this.summary,
  });

  int get mistakesCount => totalExercises - correctCount;
}

class LastLessonStore extends ChangeNotifier {
  LastLessonStore._();
  static final LastLessonStore instance = LastLessonStore._();

  LastLessonRecord? _record;
  LastLessonRecord? get record => _record;

  void recordLesson(LastLessonRecord record) {
    _record = record;
    notifyListeners();
  }

  /// Test-only reset hook.
  @visibleForTesting
  void reset() {
    _record = null;
    notifyListeners();
  }
}
