import '../models/evaluation.dart';
import '../models/lesson.dart';

enum SessionPhase { loading, ready, evaluating, result, summary, error }

class SessionState {
  final Lesson? lesson;
  final int currentIndex;
  final SessionPhase phase;
  final EvaluateResponse? lastResult;
  final List<bool> results;
  final String? errorMessage;
  final LessonResultResponse? summary;

  /// Ordered queue of remaining exercise indices (head = current). Wave 3
  /// `DecisionEngine` re-orders this queue in response to in-session
  /// mistakes per `LEARNING_ENGINE.md §9.1`. With Wave 1/Wave 2 fixtures
  /// only (no Wave 3 decision yet fired) the queue is the linear
  /// `[0..exercises.length-1]`.
  final List<int> remainingIndices;

  /// One-line learner-facing reason from the most recent `DecisionEngine`
  /// decision per `LEARNING_ENGINE.md §11.3`. Wave 3 stores it on state;
  /// Wave 4 (Transparency Layer) renders it.
  final String? lastDecisionReason;

  /// Wave 12.5 hot-fix — declared session length for the dynamic flow.
  /// `loadDynamicSession` reads `start.exerciseCount` from
  /// `POST /sessions/start` and stores it here; the lazy queue
  /// (`lesson.exercises`) starts at length 1 and grows as `/next`
  /// returns subsequent items, so it is NOT a meaningful denominator
  /// for the progress counter. Null on the lesson-bound flow, where
  /// `lesson.exercises.length` is the correct total.
  final int? sessionTargetLength;

  const SessionState({
    this.lesson,
    this.currentIndex = 0,
    this.phase = SessionPhase.loading,
    this.lastResult,
    this.results = const [],
    this.errorMessage,
    this.summary,
    this.remainingIndices = const [],
    this.lastDecisionReason,
    this.sessionTargetLength,
  });

  Exercise? get currentExercise =>
      lesson != null && currentIndex < lesson!.exercises.length
          ? lesson!.exercises[currentIndex]
          : null;

  /// True when the just-answered item is the last in the session.
  /// Used to label the post-submit button as "Finish" instead of
  /// "Next" and as a fallback in `advance()` when `_pendingDecision`
  /// is null.
  ///
  /// Wave 12.5b — dynamic mode no longer fakes the queue. The
  /// remaining-indices queue starts as `[0]` and grows lazily as
  /// `/next` returns picks, so `remainingIndices.length <= 1` was
  /// effectively ALWAYS true on the dynamic path — surfacing
  /// "Finish" after the first attempt and (combined with a stale
  /// `_pendingDecision = endSession()` from the local engine) ending
  /// every dynamic session at Q1. The dynamic path now anchors on
  /// the server-declared session size: this is the last item iff
  /// we've answered the full target count.
  bool get isLastExercise {
    if (sessionTargetLength != null) {
      return results.length >= sessionTargetLength!;
    }
    return lesson != null && remainingIndices.length <= 1;
  }

  /// Total denominator for the progress counter. For the dynamic flow
  /// returns `sessionTargetLength` (the server-declared session size,
  /// typically 10) so the counter renders `1/10`, not `1/1` while the
  /// lazy queue is still being filled. For the legacy lesson-bound
  /// flow returns `lesson.exercises.length`.
  int get totalCount => sessionTargetLength ?? lesson?.exercises.length ?? 0;
  int get correctCount => results.where((r) => r).length;

  SessionState copyWith({
    Lesson? lesson,
    int? currentIndex,
    SessionPhase? phase,
    EvaluateResponse? lastResult,
    bool clearLastResult = false,
    List<bool>? results,
    String? errorMessage,
    LessonResultResponse? summary,
    List<int>? remainingIndices,
    String? lastDecisionReason,
    bool clearLastDecisionReason = false,
    int? sessionTargetLength,
    bool clearSessionTargetLength = false,
  }) =>
      SessionState(
        lesson: lesson ?? this.lesson,
        currentIndex: currentIndex ?? this.currentIndex,
        phase: phase ?? this.phase,
        lastResult: clearLastResult ? null : (lastResult ?? this.lastResult),
        results: results ?? this.results,
        errorMessage: errorMessage ?? this.errorMessage,
        summary: summary ?? this.summary,
        remainingIndices: remainingIndices ?? this.remainingIndices,
        lastDecisionReason: clearLastDecisionReason
            ? null
            : (lastDecisionReason ?? this.lastDecisionReason),
        sessionTargetLength: clearSessionTargetLength
            ? null
            : (sessionTargetLength ?? this.sessionTargetLength),
      );
}
