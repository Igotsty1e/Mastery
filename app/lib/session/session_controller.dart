import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../api/api_client.dart';
import '../learner/learner_skill_store.dart';
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

  SessionController(this._api) : _state = const SessionState() {
    _sessionId = _uuid.v4();
  }

  Future<void> loadLesson(String lessonId) async {
    _lastLessonId = lessonId;
    _lastAnswer = null;
    _sessionId = _uuid.v4();
    _emit(_state.copyWith(phase: SessionPhase.loading));
    try {
      final lesson = await _api.getLesson(lessonId);
      _emit(_state.copyWith(
        lesson: lesson,
        phase: SessionPhase.ready,
        currentIndex: 0,
        results: [],
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
      _emit(_state.copyWith(
        phase: SessionPhase.result,
        lastResult: response,
        results: [..._state.results, response.correct],
      ));
      await LocalProgressStore.recordCompletedExercises(
        _state.lesson!.lessonId,
        _state.results.length,
      );
      // LEARNING_ENGINE.md §6 + §7: record per-skill mastery state. Wave 2
      // is device-scoped; the store is no-op when the exercise lacks the
      // Wave 1 metadata trio (older fixtures or item types not yet tagged).
      if (exercise.skillId != null && exercise.evidenceTier != null) {
        await LearnerSkillStore.recordAttempt(
          skillId: exercise.skillId!,
          evidenceTier: exercise.evidenceTier!,
          correct: response.correct,
          primaryTargetError: exercise.primaryTargetError,
          meaningFrame: exercise.meaningFrame,
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
    if (_state.isLastExercise) {
      _emit(_state.copyWith(phase: SessionPhase.evaluating, clearLastResult: true));
      _fetchSummary();
    } else {
      _emit(_state.copyWith(
        currentIndex: _state.currentIndex + 1,
        phase: SessionPhase.ready,
        clearLastResult: true,
      ));
    }
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
  }

  void _emit(SessionState next) {
    _state = next;
    notifyListeners();
  }
}
