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

  /// Server-owned session id minted by `POST /lessons/:id/sessions/start`
  /// in `loadLesson`. Wave 8 (legacy drop): the local UUID v4 from
  /// earlier waves is gone — every answer + result fetch threads this
  /// server id, the same one `lesson_progress` aggregates against.
  String? _sessionId;

  /// Wave 11.3 — true when the controller was loaded via
  /// `loadDynamicSession` (V1 dynamic flow). Drives the post-attempt
  /// `nextExercise(sessionId)` fetch and the synthetic-lesson queue
  /// growth. False for the legacy `loadLesson(lessonId)` flow.
  bool _dynamicMode = false;

  /// Wave 3 §9.1 in-session mistake counter, per skill, reset on
  /// `loadLesson`. The `DecisionEngine` reads this to decide the 1/2/3
  /// loop; the `ReviewScheduler` reads it on session end to compute the
  /// next cadence step per §9.3.
  Map<String, int> _sessionMistakesBySkill = {};

  /// Pending decision computed in `submitAnswer` and applied on
  /// `advance()`. Stored so we don't recompute when `advance()` runs.
  DecisionResult? _pendingDecision;

  SessionController(this._api) : _state = const SessionState();

  /// Wave 11.3 — V1 dynamic-session entry point. Calls `POST /sessions/start`,
  /// receives `{ session_id, first_exercise }`, and seeds a synthetic
  /// `Lesson` whose `exercises` list grows by one each time `advance()`
  /// fires. The Decision Engine on the server picks every subsequent
  /// item via `POST /lesson-sessions/:sid/next`.
  ///
  /// Sits next to the legacy `loadLesson(lessonId)` so the rewire of
  /// HomeScreen's CTA can ship in this PR while older test fixtures
  /// keep working off the lesson-bound flow.
  Future<void> loadDynamicSession() async {
    _lastLessonId = null;
    _lastAnswer = null;
    _sessionId = null;
    _sessionMistakesBySkill = {};
    _pendingDecision = null;
    _dynamicMode = true;
    _emit(_state.copyWith(phase: SessionPhase.loading));
    try {
      final start = await _api.startSession();
      _sessionId = start.sessionId;
      // Synthetic lesson — the title + level land on UI and are kept
      // stable for the duration of the session. Exercises grow as the
      // Decision Engine returns them.
      final lesson = Lesson(
        lessonId: start.sessionId,
        title: start.title,
        language: 'en',
        level: start.level,
        introRule: '',
        introExamples: const [],
        exercises: [start.firstExercise],
      );
      _emit(_state.copyWith(
        lesson: lesson,
        phase: SessionPhase.ready,
        currentIndex: 0,
        results: [],
        remainingIndices: const [0],
        clearLastDecisionReason: true,
        // Wave 12.5 — anchor the progress counter to the
        // server-declared session size. Without this the denominator
        // would be `lesson.exercises.length` which starts at 1 and
        // grows lazily, producing the prod-observed `1/1 → 2/2`
        // bug.
        sessionTargetLength: start.exerciseCount,
      ));
    } catch (e) {
      _emit(_state.copyWith(
        phase: SessionPhase.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> loadLesson(String lessonId) async {
    _lastLessonId = lessonId;
    _lastAnswer = null;
    _sessionId = null;
    _sessionMistakesBySkill = {};
    _pendingDecision = null;
    _dynamicMode = false;
    _emit(_state.copyWith(phase: SessionPhase.loading));
    try {
      // Wave 8: load lesson content (public route) + start a server-owned
      // session in parallel. `startLessonSession` requires an attached
      // AuthClient; HomeScreen wires that during `_resolveInitialView`
      // and after sign-in / Skip.
      final results = await Future.wait<Object>([
        _api.getLesson(lessonId),
        _api.startLessonSession(lessonId),
      ]);
      final lesson = results[0] as Lesson;
      final session = results[1] as LessonSessionStart;
      _sessionId = session.sessionId;
      _emit(_state.copyWith(
        lesson: lesson,
        phase: SessionPhase.ready,
        currentIndex: 0,
        results: [],
        remainingIndices:
            List<int>.generate(lesson.exercises.length, (i) => i),
        clearLastDecisionReason: true,
        // Wave 12.5 — legacy lesson-bound flow uses
        // `lesson.exercises.length` as the denominator; clear any
        // stale session target left over from a prior
        // `loadDynamicSession` on the same controller instance.
        clearSessionTargetLength: true,
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
    final sessionId = _sessionId;
    if (sessionId == null) {
      _emit(_state.copyWith(
        phase: SessionPhase.error,
        errorMessage: 'Session not started — call loadLesson first',
      ));
      return;
    }

    _lastAnswer = userAnswer;
    _emit(_state.copyWith(phase: SessionPhase.evaluating));
    try {
      final response = await _api.submitAnswer(
        sessionId,
        EvaluateRequest(
          sessionId: sessionId,
          attemptId: _uuid.v4(),
          exerciseId: exercise.exerciseId,
          exerciseType: exerciseTypeToString(exercise.type),
          userAnswer: userAnswer,
          submittedAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

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

      // Wave 11.3 — V1 dynamic flow: ask the server-side Decision
      // Engine for the next pick. Overrides the local DecisionEngine
      // result computed above; the server-side queue is authoritative
      // when the session was loaded via `loadDynamicSession`.
      if (_dynamicMode) {
        await _fetchNextDynamic();
      }
    } catch (e) {
      _emit(_state.copyWith(
        phase: SessionPhase.error,
        errorMessage: e.toString(),
      ));
    }
  }

  Future<void> _fetchNextDynamic() async {
    final sessionId = _sessionId;
    final lesson = _state.lesson;
    if (sessionId == null || lesson == null) return;
    try {
      final dynamicNext = await _api.nextExercise(sessionId);
      if (dynamicNext.next == null) {
        _pendingDecision = const DecisionResult.endSession();
        return;
      }
      // Append the freshly-picked exercise to the synthetic lesson and
      // queue its index. `advance()` consumes `_pendingDecision` and
      // transitions to that index on the next tick.
      final newExercises = [...lesson.exercises, dynamicNext.next!];
      final newIndex = newExercises.length - 1;
      final updatedLesson = lesson.copyWith(exercises: newExercises);
      _pendingDecision = DecisionResult.advance(
        [newIndex],
        reason: dynamicNext.reason,
      );
      _emit(_state.copyWith(
        lesson: updatedLesson,
        lastDecisionReason: dynamicNext.reason,
        clearLastDecisionReason: dynamicNext.reason == null,
      ));
    } catch (_) {
      // On a transient network failure, end the session so the
      // learner sees their summary instead of being stuck on the
      // result phase. The server still has the in-progress row;
      // they can resume by starting a fresh session.
      _pendingDecision = const DecisionResult.endSession();
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
    final sessionId = _sessionId;
    if (sessionId == null) {
      // Defensive: should never happen — loadLesson always seeds this
      // before any answers are submitted. Surface a summary phase with
      // local counts only.
      _emit(_state.copyWith(phase: SessionPhase.summary));
      await _scheduleReviews();
      return;
    }
    try {
      // Wave 8: complete first (idempotent server-side; builds the
      // debrief snapshot + upserts lesson_progress) then fetch the
      // result DTO.
      await _api.completeLessonSession(sessionId);
      final summary = await _api.getResult(sessionId);
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
