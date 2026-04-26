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
  });

  Exercise? get currentExercise =>
      lesson != null && currentIndex < lesson!.exercises.length
          ? lesson!.exercises[currentIndex]
          : null;

  /// True when there is no exercise to advance to — either the queue
  /// has one item left (the current one) or the lesson is missing.
  bool get isLastExercise =>
      lesson != null && remainingIndices.length <= 1;

  int get totalCount => lesson?.exercises.length ?? 0;
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
      );
}
