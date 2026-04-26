import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mastery/api/api_client.dart';
import 'package:mastery/session/session_controller.dart';
import 'package:mastery/session/session_state.dart';
import 'package:mastery/models/lesson.dart';
import 'package:mastery/models/evaluation.dart';
import 'package:mastery/learner/learner_skill_store.dart';
import 'package:mastery/progress/local_progress_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// ── fixture helpers ──────────────────────────────────────────────────────────

const _lessonId  = 'a1b2c3d4-0001-4000-8000-000000000001';
const _exId      = 'a1b2c3d4-0001-4000-8000-000000000011';
const _exId2     = 'a1b2c3d4-0001-4000-8000-000000000012';

Map<String, dynamic> _lessonJson() => {
  'lesson_id': _lessonId,
  'title': 'Test Lesson',
  'language': 'en',
  'level': 'B2',
  'intro_rule': 'Test rule.',
  'intro_examples': <String>[],
  'exercises': [
    {
      'exercise_id': _exId,
      'type': 'fill_blank',
      'instruction': 'Complete the gap with the correct verb form.',
      'prompt': 'She ___ working.',
    }
  ],
};

Map<String, dynamic> _evaluateJson({bool correct = true}) => {
  'attempt_id': '00000000-0000-4000-8000-000000000002',
  'exercise_id': _exId,
  'correct': correct,
  'evaluation_source': 'deterministic',
  'explanation': null,
  'canonical_answer': 'is',
};

Map<String, dynamic> _lessonJson2() => {
  'lesson_id': _lessonId,
  'title': 'Test Lesson',
  'language': 'en',
  'level': 'B2',
  'intro_rule': 'Test rule.',
  'intro_examples': <String>[],
  'exercises': [
    {
      'exercise_id': _exId,
      'type': 'fill_blank',
      'instruction': 'Complete the gap with the correct verb form.',
      'prompt': 'She ___ working.',
    },
    {
      'exercise_id': _exId2,
      'type': 'fill_blank',
      'instruction': 'Complete the gap with the correct verb form.',
      'prompt': 'They ___ students.',
    },
  ],
};

Map<String, dynamic> _evaluateJson2({bool correct = false}) => {
  'attempt_id': '00000000-0000-4000-8000-000000000003',
  'exercise_id': _exId2,
  'correct': correct,
  'evaluation_source': 'deterministic',
  'explanation': null,
  'canonical_answer': 'are',
};

Map<String, dynamic> _resultJson2() => {
  'lesson_id': _lessonId,
  'total_exercises': 2,
  'correct_count': 1,
  'answers': [
    {'exercise_id': _exId, 'correct': true},
    {'exercise_id': _exId2, 'correct': false},
  ],
};

Map<String, dynamic> _resultJson() => {
  'lesson_id': _lessonId,
  'total_exercises': 1,
  'correct_count': 1,
  'answers': [
    {'exercise_id': _exId, 'correct': true},
  ],
};

http.Response _jsonResponse(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

// ── SessionState unit tests ──────────────────────────────────────────────────

void main() {
  group('SessionState', () {
    final exercise = Exercise(
      exerciseId: _exId,
      type: ExerciseType.fillBlank,
      instruction: 'Complete the gap with the correct verb form.',
      prompt: 'test',
    );
    final lesson = Lesson(
      lessonId: _lessonId,
      title: 'T',
      language: 'en',
      level: 'B2',
      introRule: '',
      introExamples: [],
      exercises: [exercise],
    );

    test('currentExercise returns null when no lesson', () {
      const s = SessionState();
      expect(s.currentExercise, isNull);
    });

    test('currentExercise returns correct exercise', () {
      final s = SessionState(lesson: lesson, currentIndex: 0, phase: SessionPhase.ready);
      expect(s.currentExercise?.exerciseId, equals(_exId));
    });

    test('isLastExercise true when at last index', () {
      final s = SessionState(lesson: lesson, currentIndex: 0, phase: SessionPhase.ready);
      expect(s.isLastExercise, isTrue);
    });

    test('copyWith clearLastResult nulls lastResult', () {
      final result = EvaluateResponse(
        attemptId: '1',
        exerciseId: _exId,
        correct: true,
        canonicalAnswer: 'is',
      );
      final s = SessionState(lastResult: result)
          .copyWith(clearLastResult: true);
      expect(s.lastResult, isNull);
    });
  });

  // ── SessionController tests ─────────────────────────────────────────────────

  group('SessionController.loadLesson', () {
    test('success → phase becomes ready, lesson is set', () async {
      final client = MockClient((_) async => _jsonResponse(_lessonJson()));
      final api = ApiClient(baseUrl: 'http://test', client: client);
      final ctrl = SessionController(api);

      final phases = <SessionPhase>[];
      ctrl.addListener(() => phases.add(ctrl.state.phase));

      await ctrl.loadLesson(_lessonId);

      expect(phases, containsAllInOrder([SessionPhase.loading, SessionPhase.ready]));
      expect(ctrl.state.lesson?.lessonId, equals(_lessonId));
    });

    test('network failure → phase becomes error', () async {
      final client = MockClient((_) async => throw Exception('connection refused'));
      final api = ApiClient(baseUrl: 'http://test', client: client);
      final ctrl = SessionController(api);

      await ctrl.loadLesson(_lessonId);

      expect(ctrl.state.phase, equals(SessionPhase.error));
      expect(ctrl.state.errorMessage, isNotNull);
    });

    test('non-200 response → phase becomes error', () async {
      final client = MockClient((_) async => _jsonResponse({'error': 'lesson_not_found'}, status: 404));
      final api = ApiClient(baseUrl: 'http://test', client: client);
      final ctrl = SessionController(api);

      await ctrl.loadLesson(_lessonId);

      expect(ctrl.state.phase, equals(SessionPhase.error));
    });
  });

  group('SessionController.submitAnswer', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<SessionController> loadedController() async {
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) return _jsonResponse(_lessonJson());
        return _jsonResponse(_evaluateJson());
      });
      final api = ApiClient(baseUrl: 'http://test', client: client);
      final ctrl = SessionController(api);
      await ctrl.loadLesson(_lessonId);
      return ctrl;
    }

    test('success → phase becomes result, lastResult set', () async {
      final ctrl = await loadedController();
      await ctrl.submitAnswer('is');
      expect(ctrl.state.phase, equals(SessionPhase.result));
      expect(ctrl.state.lastResult?.correct, isTrue);
    });

    test('results list accumulates', () async {
      final ctrl = await loadedController();
      await ctrl.submitAnswer('is');
      expect(ctrl.state.results, equals([true]));
    });

    test('stored completed-exercise count equals 1 after one submitAnswer', () async {
      final ctrl = await loadedController();
      await ctrl.submitAnswer('is');
      final stored = await LocalProgressStore.getCompletedExercises(_lessonId);
      expect(stored, equals(1));
    });

    test('LearnerSkillStore records the attempt when Wave 1 metadata is present', () async {
      const tagged = {
        'lesson_id': _lessonId,
        'title': 'Test Lesson',
        'language': 'en',
        'level': 'B2',
        'intro_rule': 'Test rule.',
        'intro_examples': <String>[],
        'exercises': [
          {
            'exercise_id': _exId,
            'type': 'fill_blank',
            'instruction': 'Complete the gap with the correct verb form.',
            'prompt': 'She ___ working.',
            'skill_id': 'verb-ing-after-gerund-verbs',
            'primary_target_error': 'contrast_error',
            'evidence_tier': 'medium',
          }
        ],
      };

      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) return _jsonResponse(tagged);
        return _jsonResponse(_evaluateJson());
      });
      final api = ApiClient(baseUrl: 'http://test', client: client);
      final ctrl = SessionController(api);
      await ctrl.loadLesson(_lessonId);
      await ctrl.submitAnswer('is');

      final rec =
          await LearnerSkillStore.getRecord('verb-ing-after-gerund-verbs');
      expect(rec.masteryScore, 10); // medium correct → +10
      expect(rec.evidenceSummary[EvidenceTier.medium], 1);
      expect(rec.lastAttemptAt, isNotNull);
    });

    test('LearnerSkillStore is a no-op when the exercise lacks Wave 1 metadata', () async {
      // Default loadedController uses the un-tagged fixture (`_lessonJson`).
      final ctrl = await loadedController();
      await ctrl.submitAnswer('is');
      final all = await LearnerSkillStore.allRecords();
      expect(all, isEmpty);
    });

    test('network failure during submit → phase becomes error', () async {
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) return _jsonResponse(_lessonJson());
        throw Exception('timeout');
      });
      final api = ApiClient(baseUrl: 'http://test', client: client);
      final ctrl = SessionController(api);
      await ctrl.loadLesson(_lessonId);
      await ctrl.submitAnswer('is');
      expect(ctrl.state.phase, equals(SessionPhase.error));
    });
  });

  group('SessionController.retry', () {
    test('retry after submit error replays last answer', () async {
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) return _jsonResponse(_lessonJson());    // loadLesson
        if (call == 2) throw Exception('first submit fails');  // submitAnswer
        return _jsonResponse(_evaluateJson());                  // retry
      });
      final api = ApiClient(baseUrl: 'http://test', client: client);
      final ctrl = SessionController(api);

      await ctrl.loadLesson(_lessonId);
      await ctrl.submitAnswer('is');          // fails → error state, _lastAnswer = 'is'
      expect(ctrl.state.phase, equals(SessionPhase.error));

      await ctrl.retry();                     // retries with same answer

      expect(ctrl.state.phase, equals(SessionPhase.result));
      expect(ctrl.state.lastResult?.correct, isTrue);
      expect(call, equals(3));
    });

    test('retry after load error re-fetches lesson', () async {
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) throw Exception('first load fails');
        return _jsonResponse(_lessonJson());
      });
      final api = ApiClient(baseUrl: 'http://test', client: client);
      final ctrl = SessionController(api);

      await ctrl.loadLesson(_lessonId);       // fails → error
      expect(ctrl.state.phase, equals(SessionPhase.error));

      await ctrl.retry();                     // re-fetches

      expect(ctrl.state.phase, equals(SessionPhase.ready));
      expect(ctrl.state.lesson?.lessonId, equals(_lessonId));
      expect(call, equals(2));
    });

    test('retry with no prior state is a no-op', () async {
      final client = MockClient((_) async => _jsonResponse(_lessonJson()));
      final api = ApiClient(baseUrl: 'http://test', client: client);
      final ctrl = SessionController(api);

      // No loadLesson called, no _lastAnswer or _lastLessonId set
      await ctrl.retry();

      // Should remain in initial loading phase without crashing
      expect(ctrl.state.phase, equals(SessionPhase.loading));
    });
  });

  group('SessionController.advance', () {
    test('advance on single-exercise lesson → fetches summary', () async {
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) return _jsonResponse(_lessonJson());
        if (call == 2) return _jsonResponse(_evaluateJson());
        return _jsonResponse(_resultJson());
      });
      final api = ApiClient(baseUrl: 'http://test', client: client);
      final ctrl = SessionController(api);

      await ctrl.loadLesson(_lessonId);
      await ctrl.submitAnswer('is');
      ctrl.advance();           // last exercise → triggers _fetchSummary

      // give async summary call time to complete
      await Future.delayed(Duration.zero);

      expect(ctrl.state.phase, equals(SessionPhase.summary));
    });

    test('advance on first of two exercises → index=1, phase=ready, lastResult cleared', () async {
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) return _jsonResponse(_lessonJson2());
        return _jsonResponse(_evaluateJson());
      });
      final api = ApiClient(baseUrl: 'http://test', client: client);
      final ctrl = SessionController(api);

      await ctrl.loadLesson(_lessonId);
      await ctrl.submitAnswer('is');         // ex1 evaluated
      ctrl.advance();                        // not last → move to ex2

      expect(ctrl.state.currentIndex, equals(1));
      expect(ctrl.state.phase, equals(SessionPhase.ready));
      expect(ctrl.state.lastResult, isNull);
      expect(ctrl.state.currentExercise?.exerciseId, equals(_exId2));
    });

    test('isLastExercise false at index 0 in two-exercise lesson', () async {
      final client = MockClient((_) async => _jsonResponse(_lessonJson2()));
      final api = ApiClient(baseUrl: 'http://test', client: client);
      final ctrl = SessionController(api);

      await ctrl.loadLesson(_lessonId);

      expect(ctrl.state.isLastExercise, isFalse);
    });

    test('full two-exercise flow → results accumulate, summary reached', () async {
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) return _jsonResponse(_lessonJson2());   // loadLesson
        if (call == 2) return _jsonResponse(_evaluateJson(correct: true));   // submit ex1
        if (call == 3) return _jsonResponse(_evaluateJson2(correct: false));  // submit ex2
        return _jsonResponse(_resultJson2());                  // result
      });
      final api = ApiClient(baseUrl: 'http://test', client: client);
      final ctrl = SessionController(api);

      await ctrl.loadLesson(_lessonId);

      // exercise 1
      await ctrl.submitAnswer('is');
      expect(ctrl.state.results, equals([true]));
      ctrl.advance();                         // → ex2

      // exercise 2
      await ctrl.submitAnswer('wrong');
      expect(ctrl.state.results, equals([true, false]));
      ctrl.advance();                         // last → fetch summary

      await Future.delayed(Duration.zero);

      expect(ctrl.state.phase, equals(SessionPhase.summary));
      expect(ctrl.state.results.length, equals(2));
      expect(ctrl.state.correctCount, equals(1));
      expect(ctrl.state.summary?.correctCount, equals(1));
    });
  });
}
