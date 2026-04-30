import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/learner/latency_history_store.dart';
import 'package:mastery/learner/learner_skill_store.dart';
import 'package:mastery/models/lesson.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _skillA = 'verb-ing-after-gerund-verbs';
const _skillB = 'present-perfect-continuous-vs-simple';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await LatencyHistoryStore.clearForTests();
  });

  group('LearnerSkillRecord.statusAt', () {
    final now = DateTime.utc(2026, 4, 26);

    test('empty record → started', () {
      final r = LearnerSkillRecord.empty(_skillA);
      expect(r.statusAt(now), SkillStatus.started);
    });

    test('low score → started', () {
      final r = LearnerSkillRecord.empty(_skillA).copyWith(masteryScore: 20);
      expect(r.statusAt(now), SkillStatus.started);
    });

    test('mid score, no strong evidence → practicing', () {
      final r = LearnerSkillRecord.empty(_skillA).copyWith(
        masteryScore: 45,
        evidenceSummary: const {EvidenceTier.weak: 3, EvidenceTier.medium: 2},
      );
      expect(r.statusAt(now), SkillStatus.practicing);
    });

    test('mid score with strong evidence → getting_there', () {
      final r = LearnerSkillRecord.empty(_skillA).copyWith(
        masteryScore: 60,
        evidenceSummary: const {EvidenceTier.medium: 3, EvidenceTier.strong: 1},
      );
      expect(r.statusAt(now), SkillStatus.gettingThere);
    });

    test('high score with strong evidence but no production gate → almost_mastered', () {
      final r = LearnerSkillRecord.empty(_skillA).copyWith(
        masteryScore: 75,
        evidenceSummary: const {EvidenceTier.strong: 2},
      );
      expect(r.statusAt(now), SkillStatus.almostMastered);
    });

    test('mastered requires score, strong-or-stronger evidence, production gate, AND fast median (Wave D)', () {
      final base = LearnerSkillRecord.empty(_skillA).copyWith(
        masteryScore: 85,
        evidenceSummary: const {EvidenceTier.strong: 3, EvidenceTier.strongest: 1},
        lastAttemptAt: now.subtract(const Duration(days: 2)),
      );
      // Without gate → almost_mastered, not mastered
      expect(base.statusAt(now), SkillStatus.almostMastered);
      // With gate but no median snapshot → still almost_mastered (Wave D)
      final gated = base.copyWith(productionGateCleared: true);
      expect(gated.statusAt(now), SkillStatus.almostMastered);
      // With gate AND fast median → mastered
      final fast = gated.copyWith(medianResponseMsSnapshot: 4000);
      expect(fast.statusAt(now), SkillStatus.mastered);
    });

    test('Wave D — slow median (≥ 6000ms) caps at almost_mastered even when fully gated',
        () {
      final slow = LearnerSkillRecord.empty(_skillA).copyWith(
        masteryScore: 90,
        evidenceSummary: const {EvidenceTier.strong: 3, EvidenceTier.strongest: 1},
        productionGateCleared: true,
        lastAttemptAt: now.subtract(const Duration(days: 1)),
        medianResponseMsSnapshot: 8000,
      );
      expect(slow.statusAt(now), SkillStatus.almostMastered);
    });

    test('Wave D — boundary: median exactly 6000ms is NOT mastered (6000 is amber)',
        () {
      final amber = LearnerSkillRecord.empty(_skillA).copyWith(
        masteryScore: 95,
        evidenceSummary: const {EvidenceTier.strongest: 3},
        productionGateCleared: true,
        lastAttemptAt: now.subtract(const Duration(days: 1)),
        medianResponseMsSnapshot: 6000,
      );
      expect(amber.statusAt(now), SkillStatus.almostMastered);
    });

    test('Wave D — median 5999ms (just under green threshold) → mastered',
        () {
      final fast = LearnerSkillRecord.empty(_skillA).copyWith(
        masteryScore: 95,
        evidenceSummary: const {EvidenceTier.strongest: 3},
        productionGateCleared: true,
        lastAttemptAt: now.subtract(const Duration(days: 1)),
        medianResponseMsSnapshot: 5999,
      );
      expect(fast.statusAt(now), SkillStatus.mastered);
    });

    test('mastered + fast median + last attempt > 21 days ago → review_due',
        () {
      final stale = LearnerSkillRecord.empty(_skillA).copyWith(
        masteryScore: 90,
        evidenceSummary: const {EvidenceTier.strong: 4, EvidenceTier.strongest: 1},
        productionGateCleared: true,
        lastAttemptAt: now.subtract(const Duration(days: 30)),
        medianResponseMsSnapshot: 3500,
      );
      expect(stale.statusAt(now), SkillStatus.reviewDue);
    });
  });

  group('LearnerSkillStore.recordAttempt', () {
    test('first correct attempt seeds the record and bumps the score', () async {
      final rec = await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.medium,
        correct: true,
      );
      expect(rec, isNotNull);
      expect(rec!.masteryScore, 10);
      expect(rec.evidenceSummary[EvidenceTier.medium], 1);
      expect(rec.recentErrors, isEmpty);
      expect(rec.productionGateCleared, isFalse);
      expect(rec.lastAttemptAt, isNotNull);
    });

    test('wrong attempt with target error pushes onto recent_errors', () async {
      final rec = await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.medium,
        correct: false,
        primaryTargetError: TargetError.contrast,
      );
      expect(rec!.recentErrors, [TargetError.contrast]);
      expect(rec.masteryScore, 0); // clamped — started at 0, can't go negative
    });

    test('score is clamped to [0, 100]', () async {
      // Floor: many wrongs from zero stay at zero
      var rec = await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.strongest,
        correct: false,
      );
      rec = await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.strongest,
        correct: false,
      );
      expect(rec!.masteryScore, 0);

      // Ceiling: many corrects max at 100
      for (var i = 0; i < 10; i++) {
        rec = await LearnerSkillStore.recordAttempt(
          skillId: _skillA,
          evidenceTier: EvidenceTier.strongest,
          correct: true,
        );
      }
      expect(rec!.masteryScore, 100);
    });

    test('recent_errors is FIFO-bounded at recentErrorsCap', () async {
      for (var i = 0; i < LearnerSkillStore.recentErrorsCap + 3; i++) {
        await LearnerSkillStore.recordAttempt(
          skillId: _skillA,
          evidenceTier: EvidenceTier.medium,
          correct: false,
          primaryTargetError:
              i.isEven ? TargetError.contrast : TargetError.form,
        );
      }
      final rec = await LearnerSkillStore.getRecord(_skillA);
      expect(rec.recentErrors.length, LearnerSkillStore.recentErrorsCap);
      // Oldest entries dropped: first errors were 'contrast' alternating with
      // 'form'. The last 5 should be the most recent 5 pushed.
      // Pushed sequence (8 items): C F C F C F C F → last 5 = F C F C F
      expect(
        rec.recentErrors,
        [
          TargetError.form,
          TargetError.contrast,
          TargetError.form,
          TargetError.contrast,
          TargetError.form,
        ],
      );
    });

    test('production_gate_cleared flips on first strongest+meaning_frame correct', () async {
      // Strongest correct WITHOUT meaning_frame → no gate
      var rec = await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.strongest,
        correct: true,
      );
      expect(rec!.productionGateCleared, isFalse);

      // Strongest correct WITH meaning_frame → gate clears
      rec = await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.strongest,
        correct: true,
        meaningFrame: 'Decline a meeting politely.',
      );
      expect(rec!.productionGateCleared, isTrue);
    });

    test('production_gate_cleared is sticky — never flips back', () async {
      // Set the gate
      await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.strongest,
        correct: true,
        meaningFrame: 'context',
      );
      // Wrong attempts on same skill should NOT clear it
      await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.strongest,
        correct: false,
        primaryTargetError: TargetError.form,
      );
      final rec = await LearnerSkillStore.getRecord(_skillA);
      expect(rec.productionGateCleared, isTrue);
    });

    test('weak-tier strongest+correct without meaning_frame does NOT clear gate', () async {
      await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.strong,
        correct: true,
        meaningFrame: 'context', // strong tier — gate is strongest-only
      );
      final rec = await LearnerSkillStore.getRecord(_skillA);
      expect(rec.productionGateCleared, isFalse);
    });

    // §12.3: production gate must invalidate when evaluator semantics
    // move under a previously-cleared learner. Evaluator version pivot.
    test('§12.3 invalidation: gate clears + restamps to current version on bump', () async {
      // Clear the gate at version 1
      var rec = await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.strongest,
        correct: true,
        meaningFrame: 'context',
        evaluationVersion: 1,
      );
      expect(rec!.productionGateCleared, isTrue);
      expect(rec.gateClearedAtVersion, 1);

      // A subsequent attempt with a HIGHER evaluator version invalidates
      // the gate. The current attempt (medium correct, not strongest)
      // does not re-clear it, so it stays cleared = false.
      rec = await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.medium,
        correct: true,
        evaluationVersion: 2,
      );
      expect(rec!.productionGateCleared, isFalse);
      expect(rec.gateClearedAtVersion, isNull);
    });

    test('§12.3: same-version attempt does NOT invalidate the gate', () async {
      await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.strongest,
        correct: true,
        meaningFrame: 'context',
        evaluationVersion: 1,
      );
      final rec = await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.medium,
        correct: true,
        evaluationVersion: 1,
      );
      expect(rec!.productionGateCleared, isTrue);
      expect(rec.gateClearedAtVersion, 1);
    });

    test('§12.3: null evaluationVersion leaves gate version stamp untouched', () async {
      // Pre-Wave-5 caller path — no evaluator version available.
      await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.strongest,
        correct: true,
        meaningFrame: 'context',
        evaluationVersion: 1,
      );
      final rec = await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.medium,
        correct: false,
        primaryTargetError: TargetError.contrast,
        // evaluationVersion intentionally omitted
      );
      expect(rec!.productionGateCleared, isTrue);
      expect(rec.gateClearedAtVersion, 1);
    });

    test('§12.3: gate cleared on a fresh strongest+correct stamps the version', () async {
      final rec = await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.strongest,
        correct: true,
        meaningFrame: 'context',
        evaluationVersion: 7,
      );
      expect(rec!.productionGateCleared, isTrue);
      expect(rec.gateClearedAtVersion, 7);
    });
  });

  group('LearnerSkillStore index', () {
    test('allRecords returns every skill the learner has attempted', () async {
      await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.medium,
        correct: true,
      );
      await LearnerSkillStore.recordAttempt(
        skillId: _skillB,
        evidenceTier: EvidenceTier.weak,
        correct: false,
        primaryTargetError: TargetError.contrast,
      );
      final all = await LearnerSkillStore.allRecords();
      final ids = all.map((r) => r.skillId).toSet();
      expect(ids, {_skillA, _skillB});
    });

    test('allRecords starts empty when no attempts have been recorded', () async {
      final all = await LearnerSkillStore.allRecords();
      expect(all, isEmpty);
    });

    test('clearForTests wipes every record and the index', () async {
      await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.medium,
        correct: true,
      );
      await LearnerSkillStore.clearForTests();
      final all = await LearnerSkillStore.allRecords();
      expect(all, isEmpty);
    });
  });

  group('Wave D — latency enrichment on the LearnerSkillStore facade', () {
    test('recordAttempt returns null medianResponseMsSnapshot when history < 5',
        () async {
      // Pre-seed only 4 latency samples — below the default
      // stable-median floor.
      for (final ms in const [3000, 3200, 3400, 3600]) {
        await LatencyHistoryStore.record(skillId: _skillA, responseTimeMs: ms);
      }
      final rec = await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.medium,
        correct: true,
      );
      expect(rec!.medianResponseMsSnapshot, isNull);
    });

    test('recordAttempt enriches the snapshot once history hits the floor',
        () async {
      for (final ms in const [3000, 3200, 3400, 3600, 3800]) {
        await LatencyHistoryStore.record(skillId: _skillA, responseTimeMs: ms);
      }
      final rec = await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.medium,
        correct: true,
      );
      // Median of [3000, 3200, 3400, 3600, 3800] = 3400.
      expect(rec!.medianResponseMsSnapshot, 3400);
    });

    test('getRecord folds the current stable median into the returned record',
        () async {
      await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.medium,
        correct: true,
      );
      // No latency samples → snapshot is null.
      var rec = await LearnerSkillStore.getRecord(_skillA);
      expect(rec.medianResponseMsSnapshot, isNull);

      for (final ms in const [4000, 4100, 4200, 4300, 4400]) {
        await LatencyHistoryStore.record(skillId: _skillA, responseTimeMs: ms);
      }
      // New read picks up the freshly-stable median.
      rec = await LearnerSkillStore.getRecord(_skillA);
      expect(rec.medianResponseMsSnapshot, 4200);
    });

    test('allRecords enriches every record independently', () async {
      // Two skills with distinct latency profiles.
      await LearnerSkillStore.recordAttempt(
        skillId: _skillA,
        evidenceTier: EvidenceTier.medium,
        correct: true,
      );
      await LearnerSkillStore.recordAttempt(
        skillId: _skillB,
        evidenceTier: EvidenceTier.medium,
        correct: true,
      );
      // skillA is fast, skillB hasn't crossed the stable-median floor.
      for (final ms in const [2000, 2500, 3000, 3500, 4000]) {
        await LatencyHistoryStore.record(skillId: _skillA, responseTimeMs: ms);
      }
      for (final ms in const [9000, 9500]) {
        await LatencyHistoryStore.record(skillId: _skillB, responseTimeMs: ms);
      }

      final all = await LearnerSkillStore.allRecords();
      final byId = {for (final r in all) r.skillId: r};
      expect(byId[_skillA]!.medianResponseMsSnapshot, 3000);
      expect(byId[_skillB]!.medianResponseMsSnapshot, isNull);
    });
  });

  group('LearnerSkillRecord JSON round-trip', () {
    test('toJson + tryFromJson preserves every field', () {
      final original = LearnerSkillRecord(
        skillId: _skillA,
        masteryScore: 72,
        lastAttemptAt: DateTime.utc(2026, 4, 26, 12, 0, 0),
        evidenceSummary: const {
          EvidenceTier.weak: 1,
          EvidenceTier.medium: 2,
          EvidenceTier.strong: 1,
        },
        recentErrors: const [TargetError.contrast, TargetError.form],
        productionGateCleared: false,
      );
      final round =
          LearnerSkillRecord.tryFromJson(_skillA, original.toJson());
      expect(round, isNotNull);
      expect(round!.masteryScore, 72);
      expect(round.lastAttemptAt, original.lastAttemptAt);
      expect(round.evidenceSummary, original.evidenceSummary);
      expect(round.recentErrors, original.recentErrors);
      expect(round.productionGateCleared, isFalse);
    });

    test('tryFromJson tolerates unknown enum codes', () {
      final j = {
        'skill_id': _skillA,
        'mastery_score': 10,
        'last_attempt_at': null,
        'evidence_summary': {'weak': 1, 'unknown_tier': 99},
        'recent_errors': ['contrast_error', 'made_up_error'],
        'production_gate_cleared': false,
      };
      final r = LearnerSkillRecord.tryFromJson(_skillA, j);
      expect(r, isNotNull);
      expect(r!.evidenceSummary, {EvidenceTier.weak: 1});
      expect(r.recentErrors, [TargetError.contrast]);
    });
  });
}
