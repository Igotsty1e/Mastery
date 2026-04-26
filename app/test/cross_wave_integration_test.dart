// End-to-end integration test that exercises Waves 1+2+3+5 together.
//
// Unit tests cover each wave in isolation. This test proves the waves
// compose: a single learner session runs through metadata-tagged
// exercises (Wave 1), records mastery state (Wave 2), triggers an
// in-session reorder + a cross-session review (Wave 3), and validates
// the Wave 5 wire response shape — all without touching production.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mastery/api/api_client.dart';
import 'package:mastery/learner/learner_skill_store.dart';
import 'package:mastery/learner/review_scheduler.dart';
import 'package:mastery/models/lesson.dart';
import 'package:mastery/session/session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lesson = 'a1b2c3d4-0001-4000-8000-000000000001';
const _exA1 = 'a1b2c3d4-0001-4000-8000-000000000041';
const _exB1 = 'a1b2c3d4-0001-4000-8000-000000000042';
const _exA2 = 'a1b2c3d4-0001-4000-8000-000000000043';

const _skillA = 'verb-ing-after-gerund-verbs';
const _skillB = 'present-perfect-continuous-vs-simple';

/// Lesson with three exercises across two skills:
///   idx 0 = skill A (medium evidence)
///   idx 1 = skill B (weak evidence)
///   idx 2 = skill A (strong evidence)
/// Wave 3 exit criterion: a wrong answer on idx 0 should pull idx 2 to
/// the head, since idx 2 is the next un-attempted skill-A item.
Map<String, dynamic> _lessonJson() => {
      'lesson_id': _lesson,
      'title': 'Cross-Wave Smoke',
      'language': 'en',
      'level': 'B2',
      'intro_rule': '',
      'intro_examples': <String>[],
      'exercises': [
        {
          'exercise_id': _exA1,
          'type': 'fill_blank',
          'instruction': 'Complete.',
          'prompt': 'I enjoy ___ jazz.',
          'skill_id': _skillA,
          'evidence_tier': 'medium',
          'primary_target_error': 'contrast_error',
        },
        {
          'exercise_id': _exB1,
          'type': 'fill_blank',
          'instruction': 'Complete.',
          'prompt': 'She ___ here for years.',
          'skill_id': _skillB,
          'evidence_tier': 'weak',
        },
        {
          'exercise_id': _exA2,
          'type': 'sentence_correction',
          'instruction': 'Rewrite.',
          'prompt': 'I avoid to drive at night.',
          'skill_id': _skillA,
          'evidence_tier': 'strong',
          'primary_target_error': 'form_error',
        },
      ],
    };

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// Wave 5 wire shape — the integration test asserts the SessionController
/// happily deserialises a response that carries the new fields. The
/// existing `EvaluateResponse.fromJson` only reads `correct`; the others
/// are forward-compat for Wave 6 and Wave 4 surfaces.
Map<String, dynamic> _evalJson({
  required String exerciseId,
  required bool correct,
  required String canonical,
}) =>
    {
      'attempt_id': '00000000-0000-4000-8000-000000000099',
      'exercise_id': exerciseId,
      'correct': correct,
      'result': correct ? 'correct' : 'wrong',
      'response_units': <Object>[],
      'evaluation_version': 1,
      'evaluation_source': 'deterministic',
      'explanation': null,
      'canonical_answer': canonical,
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Waves 1+2+3+5: full single-session flow composes correctly', () async {
    int call = 0;
    final client = MockClient((req) async {
      call++;
      // Calls: 1=loadLesson, 2=submit ex_a1 (wrong), 3=submit ex_a2 (correct after reorder),
      // 4=submit ex_b1 (correct), 5=getResult.
      if (call == 1) return _json(_lessonJson());
      if (call == 2) {
        return _json(
            _evalJson(exerciseId: _exA1, correct: false, canonical: 'enjoying'));
      }
      if (call == 3) {
        return _json(_evalJson(
            exerciseId: _exA2, correct: true, canonical: 'I avoid driving'));
      }
      if (call == 4) {
        return _json(_evalJson(
            exerciseId: _exB1, correct: true, canonical: 'has been working'));
      }
      // /result
      return _json({
        'lesson_id': _lesson,
        'total_exercises': 3,
        'correct_count': 2,
        'answers': [
          {'exercise_id': _exA1, 'correct': false},
          {'exercise_id': _exA2, 'correct': true},
          {'exercise_id': _exB1, 'correct': true},
        ],
      });
    });
    final api = ApiClient(baseUrl: 'http://test', client: client);
    final ctrl = SessionController(api);

    // ── 1. Wave 1: lesson loads with metadata trio ──────────────────────────
    await ctrl.loadLesson(_lesson);
    expect(ctrl.state.lesson?.exercises[0].skillId, _skillA);
    expect(ctrl.state.lesson?.exercises[0].evidenceTier, EvidenceTier.medium);
    expect(ctrl.state.lesson?.exercises[2].evidenceTier, EvidenceTier.strong);

    // ── 2. Wave 3: wrong answer on skill A → DecisionEngine reorders queue ──
    await ctrl.submitAnswer('to enjoy'); // wrong on _exA1
    expect(ctrl.state.lastResult?.correct, isFalse);
    expect(ctrl.state.lastDecisionReason, contains('different angle'));

    ctrl.advance();
    // The queue dropped _exA1 (just-attempted) and pulled _exA2 (next skill A
    // un-attempted) to head, ahead of _exB1 — Wave 3 §9.1 1st-mistake reorder.
    expect(ctrl.state.currentExercise?.exerciseId, _exA2);

    // ── 3. Wave 2: LearnerSkillStore captured the wrong attempt on skill A ──
    final aRecAfter1st = await LearnerSkillStore.getRecord(_skillA);
    expect(aRecAfter1st.evidenceSummary[EvidenceTier.medium], 1);
    expect(aRecAfter1st.recentErrors, [TargetError.contrast]);
    expect(aRecAfter1st.masteryScore, 0); // clamped — 0 - 10 floors at 0
    expect(aRecAfter1st.productionGateCleared, isFalse);

    // ── 4. Wave 3: correct answer on the reordered skill A item ─────────────
    await ctrl.submitAnswer('I avoid driving'); // correct on _exA2
    expect(ctrl.state.lastResult?.correct, isTrue);
    expect(ctrl.state.lastDecisionReason, isNull); // linear default after correct
    ctrl.advance();
    // Queue continues with _exB1 — the only remaining item.
    expect(ctrl.state.currentExercise?.exerciseId, _exB1);

    final aRecAfter2nd = await LearnerSkillStore.getRecord(_skillA);
    // medium wrong (-10) + strong correct (+15), clamped at floor 0 → 15.
    expect(aRecAfter2nd.masteryScore, 15);
    expect(aRecAfter2nd.evidenceSummary[EvidenceTier.medium], 1);
    expect(aRecAfter2nd.evidenceSummary[EvidenceTier.strong], 1);

    // ── 5. Wave 2: skill B record gets created on its first attempt ─────────
    await ctrl.submitAnswer('has been working');
    final bRec = await LearnerSkillStore.getRecord(_skillB);
    expect(bRec.evidenceSummary[EvidenceTier.weak], 1);
    expect(bRec.masteryScore, 5); // weak correct delta

    // ── 6. Wave 3 cadence: advance from last item triggers session-end ──────
    ctrl.advance();
    // Two ticks are enough to let the async _scheduleReviews + _fetchSummary
    // chain settle (both are awaitable but ctrl.advance() is sync-launched).
    await Future.delayed(Duration.zero);
    await Future.delayed(Duration.zero);

    final scheduled = await ReviewScheduler.all();
    final byId = {for (final r in scheduled) r.skillId: r};

    // Skill A had a mistake — cadence resets to step 1, due in 1 day.
    expect(byId[_skillA]?.step, 1);
    expect(byId[_skillA]?.lastOutcomeMistakes, 1);

    // Skill B had no mistakes — also enters at step 1 (first session).
    expect(byId[_skillB]?.step, 1);
    expect(byId[_skillB]?.lastOutcomeMistakes, 0);

    // ── 7. Wave 5 happy-path: dueAt sees no skills until tomorrow ───────────
    final today = DateTime.now().toUtc();
    final dueToday = await ReviewScheduler.dueAt(today);
    expect(dueToday, isEmpty);

    final tomorrow = today.add(const Duration(days: 2));
    final dueTomorrow = await ReviewScheduler.dueAt(tomorrow);
    expect(dueTomorrow.length, 2);
  });
}
