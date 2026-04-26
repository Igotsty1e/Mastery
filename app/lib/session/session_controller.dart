import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../api/api_client.dart';
import '../learner/decision_engine.dart';
import '../learner/learner_skill_store.dart';
import '../learner/review_scheduler.dart';
import '../models/evaluation.dart';
import '../models/lesson.dart';
import '../progress/local_progress_store.dart';
import 'last_lesson_store.dart';
import 'session_state.dart';

class SessionController extends ChangeNotifier {
  final ApiClient _api;
  final _uuid = const Uuid();

  SessionState _state;
  SessionState get state => _state;

  String? _lastLessonId;
  String? _lastAnswer;
  late String _sessionId;

  /// Wave 3 §9.1 in-session mistake counter, per skill, reset on
  /// `loadLesson`. The `DecisionEngine` reads this to decide the 1/2/3
  /// loop; the `ReviewScheduler` reads it on session end to compute the
  /// next cadence step per §9.3.
  Map<String, int> _sessionMistakesBySkill = {};

  /// Pending decision computed in `submitAnswer` and applied on
  /// `advance()`. Stored so we don't recompute when `advance()` runs.
  DecisionResult? _pendingDecision;

  SessionController(this._api) : _state = const SessionState() {
    _sessionId = _uuid.v4();
  }

  Future<void> loadLesson(String lessonId) async {
    _lastLessonId = lessonId;
    _lastAnswer = null;
    _sessionId = _uuid.v4();
    _sessionMistakesBySkill = {};
    _pendingDecision = null;
    _emit(_state.copyWith(phase: SessionPhase.loading));
    try {
      final lesson = await _api.getLesson(lessonId);
      _emit(_state.copyWith(
        lesson: lesson,
        phase: SessionPhase.ready,
        currentIndex: 0,
        results: [],
        remainingIndices:
            List<int>.generate(lesson.exercises.length, (i) => i),
        clearLastDecisionReason: true,
      ));
    } catch (e) {
      _emit(_state.copyWith(
        phase: SessionPhase.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> submitAnswer(String userAnswer) async {
    final exercise = _state.currentExercise;
    if (exercise == null) return;

    _lastAnswer = userAnswer;
    _emit(_state.copyWith(phase: SessionPhase.evaluating));
    try {
      final response = await _api.submitAnswer(_state.lesson!.lessonId, EvaluateRequest(
        sessionId: _sessionId,
        attemptId: _uuid.v4(),
        exerciseId: exercise.exerciseId,
        exerciseType: exerciseTypeToString(exercise.type),
        userAnswer: userAnswer,
        submittedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      // Track per-skill in-session mistake count (§9.1 1/2/3 loop input).
      if (!response.correct && exercise.skillId != null) {
        final sid = exercise.skillId!;
        _sessionMistakesBySkill[sid] = (_sessionMistakesBySkill[sid] ?? 0) + 1;
      }

      // Compute the next-item decision now so `advance()` is a pure state
      // transition with no async logic. With Wave 1 metadata absent on
      // older fixtures, the engine returns the linear default.
      _pendingDecision = DecisionEngine.decideAfterAttempt(
        lesson: _state.lesson!,
        remainingQueue: _state.remainingIndices,
        mistakesBySkill: _sessionMistakesBySkill,
        justAttempted: exercise,
        justCorrect: response.correct,
      );

      _emit(_state.copyWith(
        phase: SessionPhase.result,
        lastResult: response,
        results: [..._state.results, response.correct],
        lastDecisionReason: _pendingDecision?.reason,
        clearLastDecisionReason: _pendingDecision?.reason == null,
      ));
      await LocalProgressStore.recordCompletedExercises(
        _state.lesson!.lessonId,
        _state.results.length,
      );
      // LEARNING_ENGINE.md §6 + §7: record per-skill mastery state. Wave 2
      // is device-scoped; the store is no-op when the exercise lacks the
      // Wave 1 metadata trio (older fixtures or item types not yet tagged).
      // Wave 5 evaluator version is forwarded so the store can invalidate
      // the §6.4 production gate per §12.3 when the evaluator semantics
      // change under a previously-cleared learner.
      if (exercise.skillId != null && exercise.evidenceTier != null) {
        await LearnerSkillStore.recordAttempt(
          skillId: exercise.skillId!,
          evidenceTier: exercise.evidenceTier!,
          correct: response.correct,
          primaryTargetError: exercise.primaryTargetError,
          meaningFrame: exercise.meaningFrame,
          evaluationVersion: response.evaluationVersion,
        );
      }
    } catch (e) {
      _emit(_state.copyWith(
        phase: SessionPhase.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> retry() async {
    if (_lastAnswer != null) {
      await submitAnswer(_lastAnswer!);
    } else if (_lastLessonId != null) {
      await loadLesson(_lastLessonId!);
    }
  }

  void advance() {
    final decision = _pendingDecision;
    _pendingDecision = null;

    // Decision Engine signalled session end (e.g. 3rd-mistake skip emptied
    // the queue), or the queue genuinely has only the current item left.
    if (decision?.endSession ?? _state.isLastExercise) {
      _emit(_state.copyWith(
          phase: SessionPhase.evaluating, clearLastResult: true));
      _fetchSummary();
      return;
    }

    final newQueue = decision?.remainingQueue ??
        (_state.remainingIndices.isNotEmpty
            ? _state.remainingIndices.sublist(1)
            : const <int>[]);
    if (newQueue.isEmpty) {
      _emit(_state.copyWith(
          phase: SessionPhase.evaluating, clearLastResult: true));
      _fetchSummary();
      return;
    }

    _emit(_state.copyWith(
      currentIndex: newQueue.first,
      remainingIndices: newQueue,
      phase: SessionPhase.ready,
      clearLastResult: true,
      // Carry forward the decision reason so the result→ready transition
      // does not silently drop it before Wave 4 can render it.
      lastDecisionReason: decision?.reason,
      clearLastDecisionReason: decision?.reason == null,
    ));
  }

  Future<void> _fetchSummary() async {
    try {
      final summary = await _api.getResult(_state.lesson!.lessonId, _sessionId);
      _emit(_state.copyWith(phase: SessionPhase.summary, summary: summary));
      // Publish to the in-memory cross-screen store so the dashboard's
      // "Last lesson report" block can render once the user pops back.
      LastLessonStore.instance.recordLesson(LastLessonRecord(
        lessonId: _state.lesson!.lessonId,
        lessonTitle: _state.lesson!.title,
        completedAt: DateTime.now(),
        totalExercises: summary.totalExercises,
        correctCount: summary.correctCount,
        debrief: summary.debrief,
      ));
    } catch (e, st) {
      debugPrint('_fetchSummary failed – showing local counts. Error: $e\n$st');
      _emit(_state.copyWith(phase: SessionPhase.summary));
    }
    // LEARNING_ENGINE.md §9.3 cadence — record the just-finished session
    // outcome for every skill the learner touched. The scheduler decides
    // the next due time; the dashboard reads it via ReviewScheduler.dueAt.
    await _scheduleReviews();
  }

  Future<void> _scheduleReviews() async {
    final touched = <String>{};
    final lesson = _state.lesson;
    if (lesson == null) return;
    for (final ex in lesson.exercises) {
      if (ex.skillId != null) touched.add(ex.skillId!);
    }
    final now = DateTime.now().toUtc();
    for (final skillId in touched) {
      final mistakes = _sessionMistakesBySkill[skillId] ?? 0;
      await ReviewScheduler.recordSessionEnd(
        skillId: skillId,
        mistakesInSession: mistakes,
        occurredAt: now,
      );
    }
  }

  void _emit(SessionState next) {
    _state = next;
    notifyListeners();
  }
}
