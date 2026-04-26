import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/learner/decision_engine.dart';
import 'package:mastery/models/lesson.dart';

const _skillA = 'verb-ing-after-gerund-verbs';
const _skillB = 'present-perfect-continuous-vs-simple';

Exercise _ex(String id, {String? skillId}) => Exercise(
      exerciseId: id,
      type: ExerciseType.fillBlank,
      instruction: 'i',
      prompt: 'p',
      skillId: skillId,
      evidenceTier: skillId == null ? null : EvidenceTier.medium,
    );

Lesson _lesson(List<Exercise> exs) => Lesson(
      lessonId: 'L',
      title: 'T',
      language: 'en',
      level: 'B2',
      introRule: '',
      introExamples: const [],
      exercises: exs,
    );

void main() {
  group('DecisionEngine.decideAfterAttempt — linear default', () {
    test('correct answer with no metadata → linear advance, no reason', () {
      final lesson = _lesson([
        _ex('e1'),
        _ex('e2'),
        _ex('e3'),
      ]);
      final r = DecisionEngine.decideAfterAttempt(
        lesson: lesson,
        remainingQueue: const [0, 1, 2],
        mistakesBySkill: const {},
        justAttempted: lesson.exercises[0],
        justCorrect: true,
      );
      expect(r.endSession, isFalse);
      expect(r.remainingQueue, [1, 2]);
      expect(r.reason, isNull);
    });

    test('wrong answer with no skillId → linear advance (no decision)', () {
      final lesson = _lesson([_ex('e1'), _ex('e2')]);
      final r = DecisionEngine.decideAfterAttempt(
        lesson: lesson,
        remainingQueue: const [0, 1],
        mistakesBySkill: const {},
        justAttempted: lesson.exercises[0],
        justCorrect: false,
      );
      expect(r.remainingQueue, [1]);
      expect(r.reason, isNull);
    });

    test('correct answer on tagged item → linear advance (no decision triggered)', () {
      final lesson = _lesson([
        _ex('e1', skillId: _skillA),
        _ex('e2', skillId: _skillB),
      ]);
      final r = DecisionEngine.decideAfterAttempt(
        lesson: lesson,
        remainingQueue: const [0, 1],
        mistakesBySkill: const {_skillA: 0},
        justAttempted: lesson.exercises[0],
        justCorrect: true,
      );
      expect(r.remainingQueue, [1]);
      expect(r.reason, isNull);
    });

    test('queue with one item left → endSession on next advance', () {
      final lesson = _lesson([_ex('e1', skillId: _skillA)]);
      final r = DecisionEngine.decideAfterAttempt(
        lesson: lesson,
        remainingQueue: const [0],
        mistakesBySkill: const {_skillA: 0},
        justAttempted: lesson.exercises[0],
        justCorrect: true,
      );
      expect(r.endSession, isTrue);
    });
  });

  group('DecisionEngine — §9.1 1st mistake', () {
    test('1st mistake on skill A pulls next un-attempted skill-A item to head', () {
      final lesson = _lesson([
        _ex('e1', skillId: _skillA), // just attempted, wrong
        _ex('e2', skillId: _skillB), // un-attempted, different skill
        _ex('e3', skillId: _skillA), // un-attempted, SAME skill — should jump
        _ex('e4', skillId: _skillA),
      ]);
      final r = DecisionEngine.decideAfterAttempt(
        lesson: lesson,
        remainingQueue: const [0, 1, 2, 3],
        mistakesBySkill: const {_skillA: 1},
        justAttempted: lesson.exercises[0],
        justCorrect: false,
      );
      expect(r.endSession, isFalse);
      // Original after-drop-head: [1, 2, 3]; pull idx 2 (e3, skillA) to head → [2, 1, 3]
      expect(r.remainingQueue, [2, 1, 3]);
      expect(r.reason, contains('different angle'));
    });

    test('1st mistake but the next item is already same-skill → no reorder', () {
      final lesson = _lesson([
        _ex('e1', skillId: _skillA),
        _ex('e2', skillId: _skillA), // already same-skill at head of remaining
        _ex('e3', skillId: _skillB),
      ]);
      final r = DecisionEngine.decideAfterAttempt(
        lesson: lesson,
        remainingQueue: const [0, 1, 2],
        mistakesBySkill: const {_skillA: 1},
        justAttempted: lesson.exercises[0],
        justCorrect: false,
      );
      // sameSkillIndex = 0 (e2 already at head) → no reorder, no decision reason
      expect(r.remainingQueue, [1, 2]);
      expect(r.reason, isNull);
    });

    test('1st mistake but no remaining same-skill items → linear default', () {
      final lesson = _lesson([
        _ex('e1', skillId: _skillA),
        _ex('e2', skillId: _skillB),
        _ex('e3', skillId: _skillB),
      ]);
      final r = DecisionEngine.decideAfterAttempt(
        lesson: lesson,
        remainingQueue: const [0, 1, 2],
        mistakesBySkill: const {_skillA: 1},
        justAttempted: lesson.exercises[0],
        justCorrect: false,
      );
      expect(r.remainingQueue, [1, 2]);
      expect(r.reason, isNull);
    });
  });

  group('DecisionEngine — §9.1 2nd mistake', () {
    test('2nd mistake on skill A pulls next same-skill item with simpler-ask reason', () {
      final lesson = _lesson([
        _ex('e1', skillId: _skillA),
        _ex('e2', skillId: _skillB),
        _ex('e3', skillId: _skillA),
      ]);
      final r = DecisionEngine.decideAfterAttempt(
        lesson: lesson,
        remainingQueue: const [0, 1, 2],
        mistakesBySkill: const {_skillA: 2},
        justAttempted: lesson.exercises[0],
        justCorrect: false,
      );
      expect(r.remainingQueue, [2, 1]);
      expect(r.reason, contains('simpler ask'));
    });
  });

  group('DecisionEngine — §9.1 3rd mistake (skip remaining same-skill)', () {
    test('3rd mistake on skill A drops every remaining skill-A item', () {
      final lesson = _lesson([
        _ex('e1', skillId: _skillA),
        _ex('e2', skillId: _skillA),
        _ex('e3', skillId: _skillB),
        _ex('e4', skillId: _skillA),
        _ex('e5', skillId: _skillB),
      ]);
      final r = DecisionEngine.decideAfterAttempt(
        lesson: lesson,
        remainingQueue: const [0, 1, 2, 3, 4],
        mistakesBySkill: const {_skillA: 3},
        justAttempted: lesson.exercises[0],
        justCorrect: false,
      );
      // After dropping head: [1,2,3,4]. Drop all skillA items (idx 1,3) → [2,4]
      expect(r.endSession, isFalse);
      expect(r.remainingQueue, [2, 4]);
      expect(r.reason, contains('moving on'));
    });

    test('3rd mistake when every remaining item is skill A → endSession', () {
      final lesson = _lesson([
        _ex('e1', skillId: _skillA),
        _ex('e2', skillId: _skillA),
        _ex('e3', skillId: _skillA),
      ]);
      final r = DecisionEngine.decideAfterAttempt(
        lesson: lesson,
        remainingQueue: const [0, 1, 2],
        mistakesBySkill: const {_skillA: 3},
        justAttempted: lesson.exercises[0],
        justCorrect: false,
      );
      expect(r.endSession, isTrue);
      expect(r.reason, contains('moving on'));
    });

    test('3rd mistake also fires on a correct-but-already-3-mistakes attempt', () {
      // Edge case: 3rd mistake counted earlier, this attempt just happened
      // to be correct. The §9.1 rule still says "stop repeating in this
      // session" once 3 mistakes are reached.
      final lesson = _lesson([
        _ex('e1', skillId: _skillA),
        _ex('e2', skillId: _skillA),
        _ex('e3', skillId: _skillB),
      ]);
      final r = DecisionEngine.decideAfterAttempt(
        lesson: lesson,
        remainingQueue: const [0, 1, 2],
        mistakesBySkill: const {_skillA: 3},
        justAttempted: lesson.exercises[0],
        justCorrect: true,
      );
      expect(r.remainingQueue, [2]);
      expect(r.reason, contains('moving on'));
    });
  });

  group('DecisionEngine — robustness', () {
    test('empty remaining queue → endSession with no reason', () {
      final lesson = _lesson([_ex('e1', skillId: _skillA)]);
      final r = DecisionEngine.decideAfterAttempt(
        lesson: lesson,
        remainingQueue: const [],
        mistakesBySkill: const {},
        justAttempted: lesson.exercises[0],
        justCorrect: true,
      );
      expect(r.endSession, isTrue);
      expect(r.reason, isNull);
    });
  });
}
