import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/learner/review_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _skillA = 'verb-ing-after-gerund-verbs';
const _skillB = 'present-perfect-continuous-vs-simple';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ReviewScheduler.intervalForStep — §9.3 cadence', () {
    test('step 1 → 1 day', () {
      expect(ReviewScheduler.intervalForStep(1), const Duration(days: 1));
    });
    test('step 2 → 3 days', () {
      expect(ReviewScheduler.intervalForStep(2), const Duration(days: 3));
    });
    test('step 3 → 7 days', () {
      expect(ReviewScheduler.intervalForStep(3), const Duration(days: 7));
    });
    test('step 4 → 21 days', () {
      expect(ReviewScheduler.intervalForStep(4), const Duration(days: 21));
    });
    test('step 5+ caps at 21 days', () {
      expect(ReviewScheduler.intervalForStep(5), const Duration(days: 21));
      expect(ReviewScheduler.intervalForStep(99), const Duration(days: 21));
    });
    test('step 0 or negative defaults to 1 day', () {
      expect(ReviewScheduler.intervalForStep(0), const Duration(days: 1));
      expect(ReviewScheduler.intervalForStep(-3), const Duration(days: 1));
    });
  });

  group('ReviewScheduler.recordSessionEnd', () {
    final fixedNow = DateTime.utc(2026, 4, 26, 12, 0, 0);

    test('first clean session enters cadence at step 1, due in 1 day', () async {
      final s = await ReviewScheduler.recordSessionEnd(
        skillId: _skillA,
        mistakesInSession: 0,
        occurredAt: fixedNow,
      );
      expect(s, isNotNull);
      expect(s!.step, 1);
      expect(s.dueAt, fixedNow.add(const Duration(days: 1)));
      expect(s.graduated, isFalse);
      expect(s.lastOutcomeMistakes, 0);
    });

    test('two clean sessions advance step 1 → 2, due in 3 days', () async {
      await ReviewScheduler.recordSessionEnd(
        skillId: _skillA,
        mistakesInSession: 0,
        occurredAt: fixedNow,
      );
      final s = await ReviewScheduler.recordSessionEnd(
        skillId: _skillA,
        mistakesInSession: 0,
        occurredAt: fixedNow.add(const Duration(days: 1)),
      );
      expect(s!.step, 2);
      expect(s.dueAt,
          fixedNow.add(const Duration(days: 1)).add(const Duration(days: 3)));
    });

    test('mistakes reset cadence to step 1', () async {
      // Get the skill up to step 3
      var s = await ReviewScheduler.recordSessionEnd(
        skillId: _skillA,
        mistakesInSession: 0,
        occurredAt: fixedNow,
      );
      s = await ReviewScheduler.recordSessionEnd(
        skillId: _skillA,
        mistakesInSession: 0,
        occurredAt: fixedNow.add(const Duration(days: 1)),
      );
      s = await ReviewScheduler.recordSessionEnd(
        skillId: _skillA,
        mistakesInSession: 0,
        occurredAt: fixedNow.add(const Duration(days: 4)),
      );
      expect(s!.step, 3);

      // Now a session with mistakes
      s = await ReviewScheduler.recordSessionEnd(
        skillId: _skillA,
        mistakesInSession: 2,
        occurredAt: fixedNow.add(const Duration(days: 11)),
      );
      expect(s!.step, 1);
      expect(s.dueAt,
          fixedNow.add(const Duration(days: 11)).add(const Duration(days: 1)));
      expect(s.lastOutcomeMistakes, 2);
    });

    test('3rd-mistake "weak" outcome (§9.1) lands at step 1', () async {
      final s = await ReviewScheduler.recordSessionEnd(
        skillId: _skillA,
        mistakesInSession: 3,
        occurredAt: fixedNow,
      );
      expect(s!.step, 1);
      expect(s.dueAt, fixedNow.add(const Duration(days: 1)));
    });

    test('reaching step 5 without resetting flags graduated (§9.4)', () async {
      // Walk 5 clean sessions to land at step 5
      for (var i = 0; i < 5; i++) {
        await ReviewScheduler.recordSessionEnd(
          skillId: _skillA,
          mistakesInSession: 0,
          occurredAt: fixedNow.add(Duration(days: i * 30)),
        );
      }
      final s = await ReviewScheduler.get(_skillA);
      expect(s!.step, 5);
      expect(s.graduated, isTrue);
    });

    test('mistakes-after-graduated drops the flag and resets cadence', () async {
      for (var i = 0; i < 5; i++) {
        await ReviewScheduler.recordSessionEnd(
          skillId: _skillA,
          mistakesInSession: 0,
          occurredAt: fixedNow.add(Duration(days: i * 30)),
        );
      }
      final s = await ReviewScheduler.recordSessionEnd(
        skillId: _skillA,
        mistakesInSession: 1,
        occurredAt: fixedNow.add(const Duration(days: 200)),
      );
      expect(s!.step, 1);
      expect(s.graduated, isFalse);
    });
  });

  group('ReviewScheduler.dueAt', () {
    final t0 = DateTime.utc(2026, 4, 26, 12, 0, 0);

    test('returns nothing when no skills are scheduled', () async {
      final due = await ReviewScheduler.dueAt(t0);
      expect(due, isEmpty);
    });

    test('returns only skills whose dueAt is at or before the given moment', () async {
      await ReviewScheduler.recordSessionEnd(
        skillId: _skillA,
        mistakesInSession: 0,
        occurredAt: t0, // due at t0+1d
      );
      await ReviewScheduler.recordSessionEnd(
        skillId: _skillB,
        mistakesInSession: 0,
        occurredAt: t0.subtract(const Duration(days: 5)), // due at t0-4d
      );

      // Asking at t0: only _skillB is due
      final dueNow = await ReviewScheduler.dueAt(t0);
      expect(dueNow.map((r) => r.skillId), [_skillB]);

      // Asking at t0+1d: both are due
      final dueLater = await ReviewScheduler.dueAt(t0.add(const Duration(days: 1)));
      expect(dueLater.map((r) => r.skillId).toSet(), {_skillA, _skillB});
    });

    test('graduated skills are excluded from dueAt', () async {
      // Walk skill A to step 5 (graduated)
      for (var i = 0; i < 5; i++) {
        await ReviewScheduler.recordSessionEnd(
          skillId: _skillA,
          mistakesInSession: 0,
          occurredAt: t0.add(Duration(days: i * 30)),
        );
      }
      final later = t0.add(const Duration(days: 500));
      final due = await ReviewScheduler.dueAt(later);
      expect(due, isEmpty);
    });

    test('sorted by dueAt (oldest overdue first)', () async {
      await ReviewScheduler.recordSessionEnd(
        skillId: _skillA,
        mistakesInSession: 0,
        occurredAt: t0.subtract(const Duration(days: 2)), // due t0-1d
      );
      await ReviewScheduler.recordSessionEnd(
        skillId: _skillB,
        mistakesInSession: 0,
        occurredAt: t0.subtract(const Duration(days: 5)), // due t0-4d
      );
      final due = await ReviewScheduler.dueAt(t0);
      expect(due.map((r) => r.skillId), [_skillB, _skillA]);
    });
  });

  group('ReviewSchedule JSON round-trip', () {
    test('serialise + deserialise preserves every field', () {
      final original = ReviewSchedule(
        skillId: _skillA,
        step: 3,
        dueAt: DateTime.utc(2026, 5, 5, 12, 0, 0),
        lastOutcomeAt: DateTime.utc(2026, 4, 28, 12, 0, 0),
        lastOutcomeMistakes: 1,
        graduated: false,
      );
      final round = ReviewSchedule.tryFromJson(_skillA, original.toJson());
      expect(round, isNotNull);
      expect(round!.step, 3);
      expect(round.dueAt, original.dueAt);
      expect(round.lastOutcomeAt, original.lastOutcomeAt);
      expect(round.lastOutcomeMistakes, 1);
      expect(round.graduated, isFalse);
    });

    test('tryFromJson tolerates malformed timestamps', () {
      final r = ReviewSchedule.tryFromJson(_skillA, {
        'step': 1,
        'due_at': 'not-a-date',
        'last_outcome_at': '2026-04-26T12:00:00Z',
        'last_outcome_mistakes': 0,
        'graduated': false,
      });
      expect(r, isNull);
    });
  });
}
