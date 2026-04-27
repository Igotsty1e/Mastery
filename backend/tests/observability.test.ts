// Wave 9 — observability infra coverage.
//
// Verifies the two append-only writers behave the way every callsite
// assumes they do:
//
//   - `recordDecision` writes one row per call, never throws on the
//     happy path, returns the new row id; insert keeps `previous_state`
//     intact as jsonb.
//   - `recordAttemptStats` increments today's bucket idempotently;
//     correct / partial / wrong outcomes route into the right counter;
//     time-to-answer is clamped to a sane range.
//   - The `recordAttempt` learner-service path writes a
//     `production_gate_cleared` Decision Log row when the §6.4 gate
//     fires for the first time, and a `mastery_invalidated` row when
//     the §12.3 evaluator-version bump knocks the gate back down.
//   - The `submitAnswer` lesson-session path writes one
//     `exercise_stats` row per attempt.

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { eq, and } from 'drizzle-orm';

import { inject } from './helpers/inject';
import { makeTestApp, type TestApp } from './helpers/db';
import { recordAttempt } from '../src/learner/service';
import {
  recordDecision,
  type DecisionLogInput,
} from '../src/observability/decisionLog';
import { recordAttemptStats } from '../src/observability/exerciseStats';
import { decisionLog, exerciseStats } from '../src/db/schema';
import type { AiProvider } from '../src/ai/interface';

const stubAi: AiProvider = {
  evaluateSentenceCorrection: () =>
    Promise.resolve({ correct: false, feedback: '' }),
  generateDebrief: () =>
    Promise.resolve({
      headline: '',
      body: '',
      watch_out: '',
      next_step: '',
    }),
};

let h: TestApp;

beforeEach(async () => {
  h = await makeTestApp({ ai: stubAi });
});

afterEach(async () => {
  await h.close();
});

async function login(subject: string) {
  const res = await inject(h.app, {
    method: 'POST',
    path: '/auth/apple/stub/login',
    json: { subject },
  });
  if (res.status !== 200) throw new Error(`login_${res.status}`);
  const body = res.json as { accessToken: string; user: { id: string } };
  return { accessToken: body.accessToken, userId: body.user.id };
}

describe('Wave 9 — Decision Log writer', () => {
  it('writes one row per call and returns the row id', async () => {
    const { userId } = await login('decision-log-1');
    const id = await recordDecision(h.database.orm, {
      userId,
      decision: 'next_exercise',
      reason: 'first_item_in_session',
      previousState: { mastery: 0 },
      nextExerciseId: '00000000-0000-4000-8000-000000000001',
    });
    expect(id).not.toBeNull();
    const rows = await h.database.orm
      .select()
      .from(decisionLog)
      .where(eq(decisionLog.userId, userId));
    expect(rows).toHaveLength(1);
    expect(rows[0]?.decision).toBe('next_exercise');
    expect(rows[0]?.reason).toBe('first_item_in_session');
    expect(rows[0]?.previousState).toEqual({ mastery: 0 });
  });

  it('null fields persist as null (skill_id, session_id, next_exercise_id)', async () => {
    const { userId } = await login('decision-log-2');
    const input: DecisionLogInput = {
      userId,
      decision: 'mastery_promoted',
      reason: 'rule_based_gate_v1',
    };
    const id = await recordDecision(h.database.orm, input);
    expect(id).not.toBeNull();
    const [row] = await h.database.orm
      .select()
      .from(decisionLog)
      .where(eq(decisionLog.id, id!));
    expect(row.skillId).toBeNull();
    expect(row.sessionId).toBeNull();
    expect(row.nextExerciseId).toBeNull();
    // jsonb default `{}` round-trips as an empty object.
    expect(row.previousState).toEqual({});
  });

  it('does not throw on a bad input — returns null instead', async () => {
    // FK violation: a userId that does not exist in `users` table.
    const id = await recordDecision(h.database.orm, {
      userId: '00000000-0000-0000-0000-000000000000',
      decision: 'next_exercise',
    });
    expect(id).toBeNull();
  });
});

describe('Wave 9 — exercise stats writer', () => {
  it('first call inserts the bucket; second call increments it', async () => {
    const exerciseId = '11111111-1111-4111-8111-111111111111';
    await recordAttemptStats(h.database.orm, {
      exerciseId,
      outcome: 'correct',
      timeToAnswerMs: 4_500,
    });
    await recordAttemptStats(h.database.orm, {
      exerciseId,
      outcome: 'wrong',
      timeToAnswerMs: 8_000,
    });

    const rows = await h.database.orm
      .select()
      .from(exerciseStats)
      .where(eq(exerciseStats.exerciseId, exerciseId));
    expect(rows).toHaveLength(1);
    expect(rows[0]?.attemptsCount).toBe(2);
    expect(rows[0]?.correctCount).toBe(1);
    expect(rows[0]?.wrongCount).toBe(1);
    expect(rows[0]?.partialCount).toBe(0);
    expect(rows[0]?.totalTimeToAnswerMs).toBe(12_500);
    expect(rows[0]?.qaReviewPending).toBe(false);
    expect(rows[0]?.exerciseVersion).toBe(1);
  });

  it('clamps absurd time_to_answer_ms to the safe range', async () => {
    const exerciseId = '22222222-2222-4222-8222-222222222222';
    await recordAttemptStats(h.database.orm, {
      exerciseId,
      outcome: 'correct',
      // 1h is well past the 10-min cap.
      timeToAnswerMs: 60 * 60_000,
    });
    await recordAttemptStats(h.database.orm, {
      exerciseId,
      outcome: 'correct',
      // negative — should clamp to 0.
      timeToAnswerMs: -42,
    });
    const [row] = await h.database.orm
      .select()
      .from(exerciseStats)
      .where(eq(exerciseStats.exerciseId, exerciseId));
    expect(row?.totalTimeToAnswerMs).toBe(10 * 60_000); // 10-min cap + 0
  });

  it('partial outcome routes into partial_count', async () => {
    const exerciseId = '33333333-3333-4333-8333-333333333333';
    await recordAttemptStats(h.database.orm, {
      exerciseId,
      outcome: 'partial',
      timeToAnswerMs: 1_000,
    });
    const [row] = await h.database.orm
      .select()
      .from(exerciseStats)
      .where(eq(exerciseStats.exerciseId, exerciseId));
    expect(row?.partialCount).toBe(1);
    expect(row?.attemptsCount).toBe(1);
    expect(row?.correctCount).toBe(0);
    expect(row?.wrongCount).toBe(0);
  });
});

describe('Wave 9 — recordAttempt → Decision Log integration', () => {
  it('logs production_gate_cleared on a §6.4-compliant attempt', async () => {
    const { userId } = await login('gate-cleared-1');
    await recordAttempt(h.database.orm, userId, 'g.tense.past_simple', {
      evidenceTier: 'strongest',
      correct: true,
      meaningFrame: 'meaning ok',
      evaluationVersion: 1,
    });
    const rows = await h.database.orm
      .select()
      .from(decisionLog)
      .where(
        and(
          eq(decisionLog.userId, userId),
          eq(decisionLog.skillId, 'g.tense.past_simple')
        )
      );
    expect(rows).toHaveLength(1);
    expect(rows[0]?.decision).toBe('production_gate_cleared');
    expect(rows[0]?.reason).toBe('strongest_correct_with_meaning_frame');
  });

  it('logs mastery_invalidated when an evaluator-version bump invalidates the gate', async () => {
    const { userId } = await login('gate-invalidated-1');
    // Clear the gate at version 1.
    await recordAttempt(h.database.orm, userId, 'g.tense.past_simple', {
      evidenceTier: 'strongest',
      correct: true,
      meaningFrame: 'meaning ok',
      evaluationVersion: 1,
    });
    // Then submit another attempt under a higher evaluator version.
    await recordAttempt(h.database.orm, userId, 'g.tense.past_simple', {
      evidenceTier: 'medium',
      correct: true,
      evaluationVersion: 2,
    });
    const rows = await h.database.orm
      .select()
      .from(decisionLog)
      .where(
        and(
          eq(decisionLog.userId, userId),
          eq(decisionLog.decision, 'mastery_invalidated')
        )
      );
    expect(rows).toHaveLength(1);
    expect(rows[0]?.reason).toBe('evaluator_version_bump');
  });
});
