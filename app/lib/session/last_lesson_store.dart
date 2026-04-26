// LastLessonStore — in-memory cross-screen holder for the most recent
// completed lesson result. Read by HomeScreen so the "Last lesson report"
// block on the Study Desk dashboard stays visible across navigation.
//
// Persistence is intentionally NOT implemented in this wave: the spec
// (`docs/plans/dashboard-study-desk.md` §7) requires the report to be
// "always visible after the learner has completed at least one lesson",
// which strictly needs a persisted snapshot. The persisted backing was
// flagged as tech debt — see `docs/plans/roadmap.md`. For now the block
// is visible only inside the runtime session that completed the lesson.
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

  const LastLessonRecord({
    required this.lessonId,
    required this.lessonTitle,
    required this.completedAt,
    required this.totalExercises,
    required this.correctCount,
    this.debrief,
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
