import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mastery/api/api_client.dart';
import 'package:mastery/session/session_controller.dart';
import 'package:mastery/session/session_state.dart';
import 'package:mastery/models/lesson.dart';
import 'package:mastery/models/evaluation.dart';
import 'package:mastery/learner/learner_skill_store.dart';
import 'package:mastery/learner/review_scheduler.dart';
import 'package:mastery/progress/local_progress_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'helpers/api_test_helpers.dart';

// Wave 8 (legacy drop): every `submitAnswer` + `getResult` now goes
// through the auth-protected `/lesson-sessions/...` endpoints. The
// helper `mountAuthedApiClient` seeds the AuthClient's storage and
// intercepts `/auth/refresh` so tests only need to mock the lesson
// content, session-start, and the lesson-session sub-routes.
ApiClient _authed(http.Response Function(http.Request req) handler) =>
    mountAuthedApiClient(baseUrl: 'http://test', raw: handler);

http.Response _routedDispatch(
  http.Request req, {
  Map<String, dynamic>? lesson,
  Map<String, dynamic>? sessionStart,
  http.Response Function(http.Request)? answer,
  Map<String, dynamic>? complete,
  Map<String, dynamic>? result,
}) {
  final p = req.url.path;
  if (lesson != null && p.endsWith('/lessons/${lesson['lesson_id']}') &&
      !p.contains('/sessions/')) {
    return _jsonResponse(lesson);
  }
  if (p.endsWith('/sessions/start') && sessionStart != null) {
    return _jsonResponse(sessionStart);
  }
  if (p.endsWith('/answers') && answer != null) {
    return answer(req);
  }
  if (p.endsWith('/complete') && complete != null) {
    return _jsonResponse(complete);
  }
  if (p.endsWith('/result') && result != null) {
    return _jsonResponse(result);
  }
  return _jsonResponse({'error': 'unmocked', 'path': p}, status: 404);
}

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
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('success → phase becomes ready, lesson is set', () async {
      final api = _authed((req) => _routedDispatch(req,
          lesson: _lessonJson(), sessionStart: sessionStartDto(_lessonId)));
      final ctrl = SessionController(api);

      final phases = <SessionPhase>[];
      ctrl.addListener(() => phases.add(ctrl.state.phase));

      await ctrl.loadLesson(_lessonId);

      expect(phases, containsAllInOrder([SessionPhase.loading, SessionPhase.ready]));
      expect(ctrl.state.lesson?.lessonId, equals(_lessonId));
    });

    test('network failure → phase becomes error', () async {
      final api = _authed((_) => throw Exception('connection refused'));
      final ctrl = SessionController(api);

      await ctrl.loadLesson(_lessonId);

      expect(ctrl.state.phase, equals(SessionPhase.error));
      expect(ctrl.state.errorMessage, isNotNull);
    });

    test('non-200 response → phase becomes error', () async {
      final api = _authed(
          (_) => _jsonResponse({'error': 'lesson_not_found'}, status: 404));
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
      final api = _authed((req) => _routedDispatch(
            req,
            lesson: _lessonJson(),
            sessionStart: sessionStartDto(_lessonId),
            answer: (_) => _jsonResponse(_evaluateJson()),
            complete: _resultJson(),
            result: _resultJson(),
          ));
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

      final api = _authed((req) => _routedDispatch(
            req,
            lesson: tagged,
            sessionStart: sessionStartDto(_lessonId),
            answer: (_) => _jsonResponse(_evaluateJson()),
            complete: _resultJson(),
            result: _resultJson(),
          ));
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
  });

  // ── Wave 3 — DecisionEngine + ReviewScheduler integration ──────────────────

  group('SessionController + DecisionEngine (§9.1)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<SessionController> makeCtrl({
      required Map<String, dynamic> lessonJson,
      required List<Map<String, dynamic>> evalJsonByCallOrder,
    }) async {
      // Wave 8: dispatch by exercise_id instead of call counter, since
      // each loadLesson now triggers two requests (lesson content + the
      // server-owned session-start) before any answer is submitted.
      final byExerciseId = <String, Map<String, dynamic>>{};
      for (final e in evalJsonByCallOrder) {
        byExerciseId[e['exercise_id'] as String] = e;
      }
      int answerCallIdx = 0;
      final api = _authed((req) {
        final p = req.url.path;
        if (p.endsWith('/sessions/start')) {
          return _jsonResponse(sessionStartDto(lessonJson['lesson_id'] as String,
              exerciseCount:
                  (lessonJson['exercises'] as List).length));
        }
        if (p.endsWith('/answers')) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final exId = body['exercise_id'] as String;
          final hit = byExerciseId[exId];
          if (hit != null) return _jsonResponse(hit);
          // Fall back to positional dispatch when an exercise_id is reused.
          final fallback = evalJsonByCallOrder[answerCallIdx++];
          return _jsonResponse(fallback);
        }
        if (p.endsWith('/complete') || p.endsWith('/result')) {
          return _jsonResponse({
            'lesson_id': lessonJson['lesson_id'],
            'total_exercises':
                (lessonJson['exercises'] as List).length,
            'correct_count': 0,
            'answers': const <Map<String, dynamic>>[],
          });
        }
        // GET /lessons/:id (read-only public route).
        return _jsonResponse(lessonJson);
      });
      final ctrl = SessionController(api);
      await ctrl.loadLesson(_lessonId);
      return ctrl;
    }

    test('correct answer on tagged item → no decision reason, linear advance', () async {
      final ctrl = await makeCtrl(
        lessonJson: {
          'lesson_id': _lessonId,
          'title': 'T',
          'language': 'en',
          'level': 'B2',
          'intro_rule': '',
          'intro_examples': <String>[],
          'exercises': [
            {
              'exercise_id': _exId,
              'type': 'fill_blank',
              'instruction': 'i',
              'prompt': 'p',
              'skill_id': 'verb-ing-after-gerund-verbs',
              'evidence_tier': 'medium',
              'primary_target_error': 'contrast_error',
            },
            {
              'exercise_id': _exId2,
              'type': 'fill_blank',
              'instruction': 'i',
              'prompt': 'p',
              'skill_id': 'present-perfect-continuous-vs-simple',
              'evidence_tier': 'medium',
            },
          ],
        },
        evalJsonByCallOrder: [
          {
            'attempt_id': 'a1',
            'exercise_id': _exId,
            'correct': true,
            'evaluation_source': 'deterministic',
            'canonical_answer': 'is',
          }
        ],
      );
      await ctrl.submitAnswer('is');
      ctrl.advance();
      expect(ctrl.state.currentExercise?.exerciseId, _exId2);
      expect(ctrl.state.lastDecisionReason, isNull);
    });

    test('1st mistake on skill A pulls a later skill-A item to the head', () async {
      // Lesson: [skillA, skillB, skillA]. Wrong on idx 0 → expect idx 2 next.
      const taggedLesson = {
        'lesson_id': _lessonId,
        'title': 'T',
        'language': 'en',
        'level': 'B2',
        'intro_rule': '',
        'intro_examples': <String>[],
        'exercises': [
          {
            'exercise_id': 'a1b2c3d4-0001-4000-8000-000000000041',
            'type': 'fill_blank',
            'instruction': 'i',
            'prompt': 'p',
            'skill_id': 'verb-ing-after-gerund-verbs',
            'evidence_tier': 'medium',
            'primary_target_error': 'contrast_error',
          },
          {
            'exercise_id': 'a1b2c3d4-0001-4000-8000-000000000042',
            'type': 'fill_blank',
            'instruction': 'i',
            'prompt': 'p',
            'skill_id': 'present-perfect-continuous-vs-simple',
            'evidence_tier': 'medium',
          },
          {
            'exercise_id': 'a1b2c3d4-0001-4000-8000-000000000043',
            'type': 'fill_blank',
            'instruction': 'i',
            'prompt': 'p',
            'skill_id': 'verb-ing-after-gerund-verbs',
            'evidence_tier': 'medium',
          },
        ],
      };
      final ctrl = await makeCtrl(
        lessonJson: taggedLesson,
        evalJsonByCallOrder: [
          {
            'attempt_id': 'a1',
            'exercise_id': 'a1b2c3d4-0001-4000-8000-000000000041',
            'correct': false,
            'evaluation_source': 'deterministic',
            'canonical_answer': 'enjoying',
          }
        ],
      );
      await ctrl.submitAnswer('to enjoy');
      ctrl.advance();
      expect(ctrl.state.currentExercise?.exerciseId,
          'a1b2c3d4-0001-4000-8000-000000000043');
      expect(ctrl.state.lastDecisionReason, contains('different angle'));
    });

    test('reason string clears once a subsequent linear advance fires', () async {
      // Two-skill lesson: A, B, A. Wrong on first A → reason set; advance
      // to second A. If that's correct, the next linear advance should
      // not carry the prior reason.
      const lesson = {
        'lesson_id': _lessonId,
        'title': 'T',
        'language': 'en',
        'level': 'B2',
        'intro_rule': '',
        'intro_examples': <String>[],
        'exercises': [
          {
            'exercise_id': 'a1',
            'type': 'fill_blank',
            'instruction': 'i',
            'prompt': 'p',
            'skill_id': 'verb-ing-after-gerund-verbs',
            'evidence_tier': 'medium',
          },
          {
            'exercise_id': 'b1',
            'type': 'fill_blank',
            'instruction': 'i',
            'prompt': 'p',
            'skill_id': 'present-perfect-continuous-vs-simple',
            'evidence_tier': 'medium',
          },
          {
            'exercise_id': 'a2',
            'type': 'fill_blank',
            'instruction': 'i',
            'prompt': 'p',
            'skill_id': 'verb-ing-after-gerund-verbs',
            'evidence_tier': 'medium',
          },
        ],
      };
      final ctrl = await makeCtrl(
        lessonJson: lesson,
        evalJsonByCallOrder: [
          {
            'attempt_id': 'a1',
            'exercise_id': 'a1',
            'correct': false,
            'evaluation_source': 'deterministic',
            'canonical_answer': 'enjoying',
          },
          {
            'attempt_id': 'a2',
            'exercise_id': 'a2',
            'correct': true,
            'evaluation_source': 'deterministic',
            'canonical_answer': 'avoiding',
          },
        ],
      );
      await ctrl.submitAnswer('to enjoy');
      expect(ctrl.state.lastDecisionReason, isNotNull);
      ctrl.advance();
      // Now on a2 (reason carried through advance).
      expect(ctrl.state.currentExercise?.exerciseId, 'a2');
      expect(ctrl.state.lastDecisionReason, isNotNull);
      await ctrl.submitAnswer('avoiding');
      // Correct answer on a2 → linear advance, no decision; reason cleared.
      ctrl.advance();
      expect(ctrl.state.lastDecisionReason, isNull);
    });
  });

  group('SessionController → ReviewScheduler (§9.3)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('every touched skill enters the cadence on session end', () async {
      const lesson = {
        'lesson_id': _lessonId,
        'title': 'T',
        'language': 'en',
        'level': 'B2',
        'intro_rule': '',
        'intro_examples': <String>[],
        'exercises': [
          {
            'exercise_id': 'a1',
            'type': 'fill_blank',
            'instruction': 'i',
            'prompt': 'p',
            'skill_id': 'verb-ing-after-gerund-verbs',
            'evidence_tier': 'medium',
          },
          {
            'exercise_id': 'b1',
            'type': 'fill_blank',
            'instruction': 'i',
            'prompt': 'p',
            'skill_id': 'present-perfect-continuous-vs-simple',
            'evidence_tier': 'medium',
          },
        ],
      };
      const summary = {
        'lesson_id': _lessonId,
        'total_exercises': 2,
        'correct_count': 2,
        'answers': [
          {'exercise_id': 'a1', 'correct': true},
          {'exercise_id': 'b1', 'correct': true},
        ],
      };
      final answersByExId = <String, Map<String, dynamic>>{
        'a1': {
          'attempt_id': 'a1',
          'exercise_id': 'a1',
          'correct': true,
          'evaluation_source': 'deterministic',
          'canonical_answer': 'enjoying',
        },
        'b1': {
          'attempt_id': 'b1',
          'exercise_id': 'b1',
          'correct': true,
          'evaluation_source': 'deterministic',
          'canonical_answer': 'have been',
        },
      };
      final api = _authed((req) {
        final p = req.url.path;
        if (p.endsWith('/sessions/start')) {
          return _jsonResponse(sessionStartDto(_lessonId, exerciseCount: 2));
        }
        if (p.endsWith('/answers')) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          return _jsonResponse(answersByExId[body['exercise_id']]!);
        }
        if (p.endsWith('/complete') || p.endsWith('/result')) {
          return _jsonResponse(summary);
        }
        return _jsonResponse(lesson);
      });
      final ctrl = SessionController(api);
      await ctrl.loadLesson(_lessonId);
      await ctrl.submitAnswer('enjoying');
      ctrl.advance();
      await ctrl.submitAnswer('have been');
      ctrl.advance();
      // Allow async _scheduleReviews to flush.
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      final scheduled = await ReviewScheduler.all();
      final ids = scheduled.map((r) => r.skillId).toSet();
      expect(ids, {
        'verb-ing-after-gerund-verbs',
        'present-perfect-continuous-vs-simple',
      });
      // Both clean → step 1, due in 1 day.
      for (final r in scheduled) {
        expect(r.step, 1);
        expect(r.lastOutcomeMistakes, 0);
      }
    });

    test('network failure during submit → phase becomes error', () async {
      final api = _authed((req) {
        final p = req.url.path;
        if (p.endsWith('/sessions/start')) {
          return _jsonResponse(sessionStartDto(_lessonId));
        }
        if (p.endsWith('/answers')) throw Exception('timeout');
        return _jsonResponse(_lessonJson());
      });
      final ctrl = SessionController(api);
      await ctrl.loadLesson(_lessonId);
      await ctrl.submitAnswer('is');
      expect(ctrl.state.phase, equals(SessionPhase.error));
    });
  });

  group('SessionController.retry', () {
    test('retry after submit error replays last answer', () async {
      int answerHits = 0;
      final api = _authed((req) {
        final p = req.url.path;
        if (p.endsWith('/sessions/start')) {
          return _jsonResponse(sessionStartDto(_lessonId));
        }
        if (p.endsWith('/answers')) {
          answerHits += 1;
          if (answerHits == 1) throw Exception('first submit fails');
          return _jsonResponse(_evaluateJson());
        }
        return _jsonResponse(_lessonJson());
      });
      final ctrl = SessionController(api);

      await ctrl.loadLesson(_lessonId);
      await ctrl.submitAnswer('is');
      expect(ctrl.state.phase, equals(SessionPhase.error));

      await ctrl.retry();

      expect(ctrl.state.phase, equals(SessionPhase.result));
      expect(ctrl.state.lastResult?.correct, isTrue);
      expect(answerHits, equals(2));
    });

    test('retry after load error re-fetches lesson', () async {
      int lessonHits = 0;
      final api = _authed((req) {
        final p = req.url.path;
        if (p.endsWith('/sessions/start')) {
          return _jsonResponse(sessionStartDto(_lessonId));
        }
        // GET /lessons/:id is the public read-only route the helper
        // dispatches via the raw http.Client in ApiClient.fetch.
        if (p == '/lessons/$_lessonId') {
          lessonHits += 1;
          if (lessonHits == 1) throw Exception('first load fails');
          return _jsonResponse(_lessonJson());
        }
        return _jsonResponse(_lessonJson());
      });
      final ctrl = SessionController(api);

      await ctrl.loadLesson(_lessonId);
      expect(ctrl.state.phase, equals(SessionPhase.error));

      await ctrl.retry();

      expect(ctrl.state.phase, equals(SessionPhase.ready));
      expect(ctrl.state.lesson?.lessonId, equals(_lessonId));
      expect(lessonHits, equals(2));
    });

    test('retry with no prior state is a no-op', () async {
      final api = _authed((_) => _jsonResponse(_lessonJson()));
      final ctrl = SessionController(api);

      await ctrl.retry();

      expect(ctrl.state.phase, equals(SessionPhase.loading));
    });
  });

  group('SessionController.advance', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('advance on single-exercise lesson → fetches summary', () async {
      final api = _authed((req) => _routedDispatch(
            req,
            lesson: _lessonJson(),
            sessionStart: sessionStartDto(_lessonId),
            answer: (_) => _jsonResponse(_evaluateJson()),
            complete: _resultJson(),
            result: _resultJson(),
          ));
      final ctrl = SessionController(api);

      await ctrl.loadLesson(_lessonId);
      await ctrl.submitAnswer('is');
      ctrl.advance();

      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.state.phase, equals(SessionPhase.summary));
    });

    test('advance on first of two exercises → index=1, phase=ready, lastResult cleared', () async {
      final api = _authed((req) => _routedDispatch(
            req,
            lesson: _lessonJson2(),
            sessionStart: sessionStartDto(_lessonId, exerciseCount: 2),
            answer: (_) => _jsonResponse(_evaluateJson()),
          ));
      final ctrl = SessionController(api);

      await ctrl.loadLesson(_lessonId);
      await ctrl.submitAnswer('is');
      ctrl.advance();

      expect(ctrl.state.currentIndex, equals(1));
      expect(ctrl.state.phase, equals(SessionPhase.ready));
      expect(ctrl.state.lastResult, isNull);
      expect(ctrl.state.currentExercise?.exerciseId, equals(_exId2));
    });

    test('isLastExercise false at index 0 in two-exercise lesson', () async {
      final api = _authed((req) => _routedDispatch(req,
          lesson: _lessonJson2(),
          sessionStart:
              sessionStartDto(_lessonId, exerciseCount: 2)));
      final ctrl = SessionController(api);

      await ctrl.loadLesson(_lessonId);

      expect(ctrl.state.isLastExercise, isFalse);
    });

    test('full two-exercise flow → results accumulate, summary reached', () async {
      final answersByExId = <String, Map<String, dynamic>>{
        _exId: _evaluateJson(correct: true),
        _exId2: _evaluateJson2(correct: false),
      };
      final api = _authed((req) {
        final p = req.url.path;
        if (p.endsWith('/sessions/start')) {
          return _jsonResponse(sessionStartDto(_lessonId, exerciseCount: 2));
        }
        if (p.endsWith('/answers')) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          return _jsonResponse(answersByExId[body['exercise_id']]!);
        }
        if (p.endsWith('/complete') || p.endsWith('/result')) {
          return _jsonResponse(_resultJson2());
        }
        return _jsonResponse(_lessonJson2());
      });
      final ctrl = SessionController(api);

      await ctrl.loadLesson(_lessonId);

      await ctrl.submitAnswer('is');
      expect(ctrl.state.results, equals([true]));
      ctrl.advance();

      await ctrl.submitAnswer('wrong');
      expect(ctrl.state.results, equals([true, false]));
      ctrl.advance();

      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.state.phase, equals(SessionPhase.summary));
      expect(ctrl.state.results.length, equals(2));
      expect(ctrl.state.correctCount, equals(1));
      expect(ctrl.state.summary?.correctCount, equals(1));
    });
  });

  // ── Wave 11.3 — V1 dynamic-session flow ─────────────────────────────────────
  group('SessionController.loadDynamicSession', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Map<String, dynamic> dynamicStartDto({String? exerciseId}) => {
          'reason': 'linear_default',
          'session_id': testSessionId,
          'title': 'Today\u2019s session',
          'level': 'B2',
          'exercise_count': 10,
          'started_at': '2026-04-26T00:00:00.000Z',
          'first_exercise': {
            'exercise_id':
                exerciseId ?? 'a1b2c3d4-0001-4000-8000-000000000011',
            'type': 'fill_blank',
            'instruction': 'Complete the gap.',
            'prompt': 'She ___ working.',
          },
        };

    test(
        'loadDynamicSession seeds a synthetic lesson with the first picked exercise',
        () async {
      final api = _authed((req) {
        final p = req.url.path;
        if (p.endsWith('/sessions/start')) {
          return _jsonResponse(dynamicStartDto());
        }
        return _jsonResponse({'error': 'unmocked', 'path': p}, status: 404);
      });
      final ctrl = SessionController(api);

      await ctrl.loadDynamicSession();

      expect(ctrl.state.phase, equals(SessionPhase.ready));
      expect(ctrl.state.lesson?.title, contains('session'));
      expect(ctrl.state.lesson?.exercises.length, equals(1));
      expect(ctrl.state.currentExercise?.exerciseId,
          equals('a1b2c3d4-0001-4000-8000-000000000011'));
    });

    test(
        'submitAnswer in dynamic mode appends the next picked exercise on advance',
        () async {
      final secondId = 'a1b2c3d4-0001-4000-8000-000000000012';
      final api = _authed((req) {
        final p = req.url.path;
        if (p.endsWith('/sessions/start')) {
          return _jsonResponse(dynamicStartDto());
        }
        if (p.endsWith('/answers')) {
          return _jsonResponse(_evaluateJson());
        }
        if (p.endsWith('/next')) {
          return _jsonResponse({
            'reason': 'variety_switch',
            'position': 1,
            'next_exercise': {
              'exercise_id': secondId,
              'type': 'fill_blank',
              'instruction': 'Complete the gap.',
              'prompt': 'They ___ students.',
            },
          });
        }
        return _jsonResponse({'error': 'unmocked', 'path': p}, status: 404);
      });
      final ctrl = SessionController(api);

      await ctrl.loadDynamicSession();
      await ctrl.submitAnswer('is');
      // Decision result from /next is now pending; advance() promotes it.
      ctrl.advance();

      expect(ctrl.state.lesson?.exercises.length, equals(2));
      expect(ctrl.state.currentExercise?.exerciseId, equals(secondId));
      expect(ctrl.state.lastDecisionReason, equals('variety_switch'));
    });

    test(
        '/next returning null next_exercise ends the dynamic session on advance',
        () async {
      final api = _authed((req) {
        final p = req.url.path;
        if (p.endsWith('/sessions/start')) {
          return _jsonResponse(dynamicStartDto());
        }
        if (p.endsWith('/answers')) {
          return _jsonResponse(_evaluateJson());
        }
        if (p.endsWith('/next')) {
          return _jsonResponse({
            'reason': 'session_complete',
            'position': 10,
            'next_exercise': null,
          });
        }
        if (p.endsWith('/complete') || p.endsWith('/result')) {
          return _jsonResponse(_resultJson());
        }
        return _jsonResponse({'error': 'unmocked', 'path': p}, status: 404);
      });
      final ctrl = SessionController(api);

      await ctrl.loadDynamicSession();
      await ctrl.submitAnswer('is');
      ctrl.advance();

      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(ctrl.state.phase, equals(SessionPhase.summary));
    });

    // Wave 12.5b regression test. Reproduces the prod bug observed
    // 2026-04-28: a single wrong answer on a dynamic session ended
    // the session at Q1 because (a) the synthetic queue
    // `remainingIndices = [0]` made `isLastExercise` always true and
    // (b) the local DecisionEngine emitted `endSession()` for the
    // single-item queue — which won the race against the in-flight
    // `/next` fetch.
    //
    // After 1 wrong answer with the server still having items in
    // the bank, the session must NOT enter the summary phase. The
    // post-submit button must read "Next", not "Finish".
    test(
        'one wrong answer in dynamic mode advances to the next item, never the summary',
        () async {
      final secondId = 'a1b2c3d4-0001-4000-8000-000000000099';
      final api = _authed((req) {
        final p = req.url.path;
        if (p.endsWith('/sessions/start')) {
          return _jsonResponse(dynamicStartDto());
        }
        if (p.endsWith('/answers')) {
          // Wrong answer — the server-side evaluator returns
          // correct=false here. The bug being reproduced does not
          // depend on the evaluator output, but a wrong answer
          // exercises the "Try again" branch of the result panel.
          return _jsonResponse(_evaluateJson(correct: false));
        }
        if (p.endsWith('/next')) {
          return _jsonResponse({
            'reason': 'same_rule_different_angle',
            'position': 1,
            'next_exercise': {
              'exercise_id': secondId,
              'type': 'fill_blank',
              'instruction': 'Complete the gap.',
              'prompt': 'He ___ a teacher.',
            },
          });
        }
        if (p.endsWith('/complete') || p.endsWith('/result')) {
          return _jsonResponse(_resultJson());
        }
        return _jsonResponse({'error': 'unmocked', 'path': p}, status: 404);
      });
      final ctrl = SessionController(api);

      await ctrl.loadDynamicSession();
      // Sanity: total denominator anchored on the server target,
      // not the lazy queue length (Wave 12.5 fix #2).
      expect(ctrl.state.totalCount, equals(10));
      // After loadDynamicSession the queue has only the first item.
      // The bug was: isLastExercise returned true here, surfacing
      // a "Finish" button label after the first attempt. The fix:
      // dynamic-mode isLastExercise is anchored on
      // `results.length >= sessionTargetLength`.
      expect(ctrl.state.isLastExercise, isFalse,
          reason: 'Q1 must NOT be the last exercise — total is 10');

      await ctrl.submitAnswer('wrong');
      // Result panel shown. Wave 12.5b — no race: by the time the
      // user sees the result, /next has resolved and
      // _pendingDecision is correctly set to advance.
      expect(ctrl.state.phase, equals(SessionPhase.result));
      // Still NOT the last exercise — fixes the prod label bug.
      expect(ctrl.state.isLastExercise, isFalse,
          reason: 'After Q1 there are 9 more items; button must say Next');
      ctrl.advance();

      // Advance must transition to the next picked exercise — NOT
      // bail out to the summary phase (which is what the prod bug
      // did).
      expect(ctrl.state.phase, equals(SessionPhase.ready));
      expect(ctrl.state.currentExercise?.exerciseId, equals(secondId));
      expect(ctrl.state.lastDecisionReason,
          equals('same_rule_different_angle'));
    });
  });
}
