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

  const SessionState({
    this.lesson,
    this.currentIndex = 0,
    this.phase = SessionPhase.loading,
    this.lastResult,
    this.results = const [],
    this.errorMessage,
    this.summary,
  });

  Exercise? get currentExercise =>
      lesson != null && currentIndex < lesson!.exercises.length
          ? lesson!.exercises[currentIndex]
          : null;

  bool get isLastExercise =>
      lesson != null && currentIndex >= lesson!.exercises.length - 1;

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
  }) =>
      SessionState(
        lesson: lesson ?? this.lesson,
        currentIndex: currentIndex ?? this.currentIndex,
        phase: phase ?? this.phase,
        lastResult: clearLastResult ? null : (lastResult ?? this.lastResult),
        results: results ?? this.results,
        errorMessage: errorMessage ?? this.errorMessage,
        summary: summary ?? this.summary,
      );
}
