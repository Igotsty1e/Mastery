import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/models/evaluation.dart';

// Wave 5 (LEARNING_ENGINE.md §8.7) deserialisation contract for
// EvaluateResponse. The fields are optional during the rollout window
// — null is a valid state when the backend hasn't been redeployed
// or when the learner is on an older shape.

void main() {
  group('EvaluateResponse.fromJson — Wave 5 fields', () {
    test('parses the full Wave 5 shape', () {
      final r = EvaluateResponse.fromJson({
        'attempt_id': 'a',
        'exercise_id': 'e',
        'correct': true,
        'explanation': null,
        'canonical_answer': 'enjoying',
        'result': 'correct',
        'response_units': <Map<String, dynamic>>[],
        'evaluation_version': 1,
      });
      expect(r.correct, isTrue);
      expect(r.result, AttemptResult.correct);
      expect(r.responseUnits, isEmpty);
      expect(r.evaluationVersion, 1);
    });

    test('parses "wrong" result', () {
      final r = EvaluateResponse.fromJson({
        'attempt_id': 'a',
        'exercise_id': 'e',
        'correct': false,
        'canonical_answer': 'enjoying',
        'result': 'wrong',
        'response_units': <Object>[],
        'evaluation_version': 1,
      });
      expect(r.result, AttemptResult.wrong);
    });

    test('parses "partial" result (Wave 6 forward-compat)', () {
      final r = EvaluateResponse.fromJson({
        'attempt_id': 'a',
        'exercise_id': 'e',
        'correct': false,
        'canonical_answer': 'enjoying',
        'result': 'partial',
        'response_units': [
          {'unit_id': 'u1', 'correct': true},
          {'unit_id': 'u2', 'correct': false},
        ],
        'evaluation_version': 2,
      });
      expect(r.result, AttemptResult.partial);
      expect(r.responseUnits, hasLength(2));
      expect(r.evaluationVersion, 2);
    });

    test('tolerates missing Wave 5 fields (older backend shape)', () {
      // A learner on a fresh frontend bundle hitting an older backend that
      // pre-dates the Wave 5 redeploy. Must deserialise without crashing.
      final r = EvaluateResponse.fromJson({
        'attempt_id': 'a',
        'exercise_id': 'e',
        'correct': true,
        'canonical_answer': 'enjoying',
      });
      expect(r.correct, isTrue);
      expect(r.result, isNull);
      expect(r.responseUnits, isNull);
      expect(r.evaluationVersion, isNull);
    });

    test('tolerates unknown result string', () {
      // Future backend bumps add new result values. Must not crash.
      final r = EvaluateResponse.fromJson({
        'attempt_id': 'a',
        'exercise_id': 'e',
        'correct': true,
        'canonical_answer': 'enjoying',
        'result': 'made_up_status',
      });
      expect(r.result, isNull);
    });

    test('legacy correct field always parses, regardless of result enum', () {
      final r = EvaluateResponse.fromJson({
        'attempt_id': 'a',
        'exercise_id': 'e',
        'correct': true,
        'canonical_answer': 'enjoying',
      });
      expect(r.correct, isTrue);
    });
  });
}
