// LastLessonStore — in-memory cross-screen holder for the most recent
// completed lesson result.
//
// **Wave 0 retirement (2026-05-01).** The dashboard's "Last lesson
// report" block that originally consumed this store was retired in
// the automaticity pivot — see `docs/plans/automaticity-pivot.md
// §Wave 0`. The store remains written so the data is preserved for
// potential engine-driven future use; there is currently no
// rendering consumer. The pre-pivot Wave 3 rebind tracked in
// `docs/plans/auth-foundation.md` is moot — no client surface to
// feed.
//
// Wave 14.9 (2026-04-28) — record carries the full
// `LessonResultResponse` so a future surface that wants the
// per-exercise mistake list can render it without a re-fetch. Kept
// in the schema even after Wave 0 since the writer pays the cost.
//
// Singleton lifetime = app lifetime. Writer: SessionController on
// successful summary fetch. Reader: none (Wave 0 retirement); see
// the @visibleForTesting reset hook for the test path.

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
  /// pre-Wave-0 consumers were the dashboard's `Review mistakes` /
  /// `See full report` CTAs on the now-retired `_LastLessonReport`
  /// block; both were retired in Wave 0 (automaticity pivot,
  /// 2026-05-01). The field is kept in the schema so a future
  /// engine-driven consumer can use it without a re-fetch.
  ///
  /// Nullable because the legacy fallback in `SessionController` may
  /// have to enter the summary phase with local counts only when the
  /// `/result` fetch fails (e.g. transient network).
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
