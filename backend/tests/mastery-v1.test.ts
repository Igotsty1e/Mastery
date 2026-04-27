// Wave 10 — Mastery V1 rule-based gate coverage.
//
// Each clause from the V1 spec §10 has a "fails on this rule alone" test
// so a future tunable bump (`MIN_ATTEMPTS_FOR_MASTERY`,
// `WEIGHTED_ACCURACY_THRESHOLD`, etc.) can be made with confidence.
//
// Tests build `LearnerSkillRecord` objects directly — no DB round-trip
// — so the evaluator stays unit-testable without test scaffolding.

import { describe, expect, it } from 'vitest';
import { evaluateMasteryV1, weightedAccuracy } from '../src/learner/mastery';
import type { LearnerSkillRecord } from '../src/learner/types';

function rec(overrides: Partial<LearnerSkillRecord> = {}): LearnerSkillRecord {
  return {
    skillId: 'g.tense.past_simple',
    masteryScore: 0,
    lastAttemptAt: null,
    evidenceSummary: { weak: 0, medium: 0, strong: 0, strongest: 0 },
    recentErrors: [],
    productionGateCleared: false,
    gateClearedAtVersion: null,
    attemptsCount: 0,
    exerciseTypesSeen: [],
    lastOutcome: null,
    repeatedConceptualCount: 0,
    weightedCorrectSum: 0,
    weightedTotalSum: 0,
    ...overrides,
  };
}

describe('Wave 10 — V1 mastery gate clauses', () => {
  it('< 3 attempts → started', () => {
    expect(evaluateMasteryV1(rec({ attemptsCount: 0 })).status).toBe('started');
    expect(evaluateMasteryV1(rec({ attemptsCount: 2 })).status).toBe('started');
  });

  it('3+ attempts but below the V1 attempts arm → practicing or getting_there', () => {
    // 3 attempts, all wrong → accuracy 0 → practicing.
    expect(
      evaluateMasteryV1(
        rec({
          attemptsCount: 3,
          weightedCorrectSum: 0,
          weightedTotalSum: 3,
        })
      ).status
    ).toBe('practicing');

    // 3 attempts, all correct → accuracy 1.0 → quick-exit getting_there.
    expect(
      evaluateMasteryV1(
        rec({
          attemptsCount: 3,
          weightedCorrectSum: 3,
          weightedTotalSum: 3,
        })
      ).status
    ).toBe('getting_there');
  });

  it('reduced arm: ≥4 attempts with correction/production unlocks the gate', () => {
    const recAlmost = rec({
      attemptsCount: 4,
      exerciseTypesSeen: ['sentence_correction'],
      // accuracy 1.0 — meets threshold.
      weightedCorrectSum: 12,
      weightedTotalSum: 12,
      productionGateCleared: true,
      lastOutcome: 'correct',
      lastAttemptAt: new Date('2026-04-26'),
    });
    const result = evaluateMasteryV1(recAlmost, new Date('2026-04-26'));
    expect(result.status).toBe('mastered');
    expect(result.gateCleared).toBe(true);
  });

  it('full arm: ≥6 attempts even without correction/production unlocks the gate', () => {
    const recAlmost = rec({
      attemptsCount: 6,
      exerciseTypesSeen: ['fill_blank'],
      weightedCorrectSum: 12,
      weightedTotalSum: 12,
      productionGateCleared: true,
      lastOutcome: 'correct',
      lastAttemptAt: new Date('2026-04-26'),
    });
    const result = evaluateMasteryV1(recAlmost, new Date('2026-04-26'));
    expect(result.status).toBe('mastered');
    expect(result.gateCleared).toBe(true);
  });

  it('weighted accuracy below threshold blocks promotion', () => {
    const r = rec({
      attemptsCount: 6,
      exerciseTypesSeen: ['fill_blank'],
      // 60% accuracy — below the 80% V1 threshold.
      weightedCorrectSum: 7.2,
      weightedTotalSum: 12,
      productionGateCleared: true,
      lastOutcome: 'correct',
      lastAttemptAt: new Date('2026-04-26'),
    });
    const result = evaluateMasteryV1(r);
    expect(result.status).toBe('getting_there');
    expect(result.blockedBy).toBe('weighted_accuracy');
  });

  it('repeated conceptual (≥2 in last 5) blocks promotion', () => {
    const r = rec({
      attemptsCount: 6,
      exerciseTypesSeen: ['fill_blank'],
      weightedCorrectSum: 12,
      weightedTotalSum: 12,
      productionGateCleared: true,
      lastOutcome: 'correct',
      lastAttemptAt: new Date('2026-04-26'),
      repeatedConceptualCount: 2,
    });
    const result = evaluateMasteryV1(r);
    expect(result.status).toBe('almost_mastered');
    expect(result.blockedBy).toBe('repeated_conceptual');
  });

  it('last attempt wrong blocks promotion', () => {
    const r = rec({
      attemptsCount: 6,
      exerciseTypesSeen: ['fill_blank'],
      weightedCorrectSum: 12,
      weightedTotalSum: 12,
      productionGateCleared: true,
      lastOutcome: 'wrong',
      lastAttemptAt: new Date('2026-04-26'),
    });
    const result = evaluateMasteryV1(r);
    expect(result.status).toBe('almost_mastered');
    expect(result.blockedBy).toBe('last_outcome_wrong');
  });

  it('production gate not cleared blocks promotion (sticky bit preserved)', () => {
    const r = rec({
      attemptsCount: 6,
      exerciseTypesSeen: ['fill_blank'],
      weightedCorrectSum: 12,
      weightedTotalSum: 12,
      productionGateCleared: false,
      lastOutcome: 'correct',
      lastAttemptAt: new Date('2026-04-26'),
    });
    const result = evaluateMasteryV1(r);
    expect(result.status).toBe('almost_mastered');
    expect(result.blockedBy).toBe('production_gate');
  });

  it('mastered + 21 d stale → review_due', () => {
    const r = rec({
      attemptsCount: 6,
      exerciseTypesSeen: ['fill_blank'],
      weightedCorrectSum: 12,
      weightedTotalSum: 12,
      productionGateCleared: true,
      lastOutcome: 'correct',
      lastAttemptAt: new Date('2026-04-01'),
    });
    const result = evaluateMasteryV1(r, new Date('2026-04-26'));
    expect(result.status).toBe('review_due');
    expect(result.gateCleared).toBe(true);
  });

  it('weightedAccuracy returns 0 on a fresh record (no divide-by-zero NaN)', () => {
    expect(weightedAccuracy(rec())).toBe(0);
  });
});
