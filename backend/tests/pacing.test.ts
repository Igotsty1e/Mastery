// Wave 13 — pacing profile selector coverage.
//
// Pure unit tests: feed `derivePacingTarget` a mastery-status snapshot,
// assert the resulting profile + signal counts. Threshold names
// (`WEAK_THRESHOLD`, `STRONG_THRESHOLD`) come from `decision/pacing.ts`
// so a future tunable bump moves both the implementation and the
// expectation in one place.

import { describe, expect, it } from 'vitest';
import {
  derivePacingTarget,
  STRONG_PACING,
  STRONG_THRESHOLD,
  WEAK_PACING,
  WEAK_THRESHOLD,
} from '../src/decision/pacing';
import { DEFAULT_PACING } from '../src/decision/engine';

describe('Wave 13 — derivePacingTarget', () => {
  it('empty mastery snapshot → default profile', () => {
    const result = derivePacingTarget({});
    expect(result.profile).toBe('default');
    expect(result.target).toEqual(DEFAULT_PACING);
    expect(result.signal).toEqual({
      practicing_or_weaker: 0,
      mastered: 0,
    });
  });

  it('a few practicing skills below the weak threshold → default profile', () => {
    const skills: Record<string, string> = {};
    for (let i = 0; i < WEAK_THRESHOLD - 1; i += 1) {
      skills[`s${i}`] = 'practicing';
    }
    const result = derivePacingTarget(skills);
    expect(result.profile).toBe('default');
  });

  it('practicing/started skills ≥ WEAK_THRESHOLD → weak profile', () => {
    const skills: Record<string, string> = {};
    for (let i = 0; i < WEAK_THRESHOLD; i += 1) {
      skills[`s${i}`] = 'practicing';
    }
    const result = derivePacingTarget(skills);
    expect(result.profile).toBe('weak');
    expect(result.target).toEqual(WEAK_PACING);
    expect(result.signal.practicing_or_weaker).toBe(WEAK_THRESHOLD);
  });

  it('mastered skills ≥ STRONG_THRESHOLD → strong profile', () => {
    const skills: Record<string, string> = {};
    for (let i = 0; i < STRONG_THRESHOLD; i += 1) {
      skills[`s${i}`] = 'mastered';
    }
    const result = derivePacingTarget(skills);
    expect(result.profile).toBe('strong');
    expect(result.target).toEqual(STRONG_PACING);
    expect(result.signal.mastered).toBe(STRONG_THRESHOLD);
  });

  it('strong wins when both thresholds fire', () => {
    const skills: Record<string, string> = {};
    for (let i = 0; i < STRONG_THRESHOLD; i += 1) {
      skills[`m${i}`] = 'mastered';
    }
    for (let i = 0; i < WEAK_THRESHOLD; i += 1) {
      skills[`p${i}`] = 'practicing';
    }
    const result = derivePacingTarget(skills);
    expect(result.profile).toBe('strong');
    expect(result.signal.mastered).toBe(STRONG_THRESHOLD);
    expect(result.signal.practicing_or_weaker).toBe(WEAK_THRESHOLD);
  });

  it('intermediate statuses (`getting_there`, `almost_mastered`) do not move the bucket', () => {
    const skills: Record<string, string> = {
      a: 'getting_there',
      b: 'getting_there',
      c: 'almost_mastered',
      d: 'review_due',
    };
    const result = derivePacingTarget(skills);
    expect(result.profile).toBe('default');
    expect(result.signal).toEqual({
      practicing_or_weaker: 0,
      mastered: 0,
    });
  });
});
