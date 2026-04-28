// Wave 12.2 — diagnostic-mode HTTP coverage.
//
// End-to-end through HTTP:
//   - /diagnostic/start requires auth, returns first item.
//   - /diagnostic/start resumes an existing in-progress run.
//   - /diagnostic/:id/answers records an attempt, returns the next.
//   - /diagnostic/:id/complete derives CEFR + skill_map, idempotent.
//   - /diagnostic/restart abandons the active run, returns a fresh one.
//   - /diagnostic/skip writes a `diagnostic_skipped` audit event.
//   - learner_skills augments per /answers (probe never resets state).
//   - user_profiles.level is stamped on /complete.

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { eq } from 'drizzle-orm';
import { inject } from './helpers/inject';
import { makeTestApp, type TestApp } from './helpers/db';
import type { AiProvider } from '../src/ai/interface';
import {
  auditEvents,
  diagnosticRuns,
  learnerSkills,
  userProfiles,
} from '../src/db/schema';
import { deriveCefrFromRun } from '../src/diagnostic/cefr';

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
  if (res.status !== 200) {
    throw new Error(`login failed: ${res.status} ${res.text}`);
  }
  const body = res.json as { accessToken: string };
  return {
    accessToken: body.accessToken,
    headers: { authorization: `Bearer ${body.accessToken}` },
  };
}

async function startDiagnostic(headers: Record<string, string>) {
  const res = await inject(h.app, {
    method: 'POST',
    path: '/diagnostic/start',
    headers,
  });
  return res;
}

describe('CEFR derivation (pure)', () => {
  it('returns A2 for an empty run', () => {
    const out = deriveCefrFromRun([]);
    expect(out.cefrLevel).toBe('A2');
    expect(out.skillMap).toEqual({});
    expect(out.totalAnswered).toBe(0);
  });

  it('returns B2 when ≥ 80% are correct on the probe', () => {
    const responses = [
      { exercise_id: 'a', skill_id: 's1', evidence_tier: 'weak', correct: true },
      { exercise_id: 'b', skill_id: 's2', evidence_tier: 'weak', correct: true },
      { exercise_id: 'c', skill_id: 's3', evidence_tier: 'weak', correct: true },
      { exercise_id: 'd', skill_id: 's4', evidence_tier: 'weak', correct: true },
      { exercise_id: 'e', skill_id: 's5', evidence_tier: 'weak', correct: false },
    ];
    const out = deriveCefrFromRun(responses);
    expect(out.cefrLevel).toBe('B2');
    expect(out.totalCorrect).toBe(4);
    expect(out.skillMap.s1).toBe('practicing');
    expect(out.skillMap.s5).toBe('started');
  });

  it('returns B1 between 50% and 79% correct', () => {
    const responses = [
      { exercise_id: 'a', skill_id: 's1', evidence_tier: 'weak', correct: true },
      { exercise_id: 'b', skill_id: 's2', evidence_tier: 'weak', correct: true },
      { exercise_id: 'c', skill_id: 's3', evidence_tier: 'weak', correct: true },
      { exercise_id: 'd', skill_id: 's4', evidence_tier: 'weak', correct: false },
      { exercise_id: 'e', skill_id: 's5', evidence_tier: 'weak', correct: false },
    ];
    const out = deriveCefrFromRun(responses);
    expect(out.cefrLevel).toBe('B1');
  });

  it('returns A2 below 50% correct', () => {
    const responses = [
      { exercise_id: 'a', skill_id: 's1', evidence_tier: 'weak', correct: true },
      { exercise_id: 'b', skill_id: 's2', evidence_tier: 'weak', correct: false },
      { exercise_id: 'c', skill_id: 's3', evidence_tier: 'weak', correct: false },
    ];
    const out = deriveCefrFromRun(responses);
    expect(out.cefrLevel).toBe('A2');
  });
});

describe('Wave 12.2 — POST /diagnostic/start', () => {
  it('rejects unauthenticated callers with 401', async () => {
    const res = await inject(h.app, {
      method: 'POST',
      path: '/diagnostic/start',
    });
    expect(res.status).toBe(401);
  });

  it('creates a fresh run with an MC first item', async () => {
    const { headers } = await login('diag-1');
    const res = await startDiagnostic(headers);
    expect(res.status).toBe(201);
    const body = res.json as any;
    expect(body.run_id).toBeTruthy();
    expect(body.resumed).toBe(false);
    expect(body.position).toBe(0);
    expect(body.total).toBe(5);
    expect(body.next_exercise).toBeTruthy();
    expect(body.next_exercise.type).toBe('multiple_choice');
    expect(body.next_exercise.skill_id).toBeTruthy();
  });

  it('resumes an existing in-progress run instead of starting a new one', async () => {
    const { headers } = await login('diag-2');
    const first = await startDiagnostic(headers);
    const firstId = (first.json as any).run_id as string;
    const second = await startDiagnostic(headers);
    expect(second.status).toBe(200);
    const body = second.json as any;
    expect(body.run_id).toBe(firstId);
    expect(body.resumed).toBe(true);
  });
});

describe('Wave 12.2 — POST /diagnostic/:runId/answers', () => {
  it('records a correct attempt and surfaces the next item', async () => {
    const { headers } = await login('diag-3');
    const start = await startDiagnostic(headers);
    const startBody = start.json as any;
    const runId = startBody.run_id as string;
    const ex = startBody.next_exercise;

    const res = await inject(h.app, {
      method: 'POST',
      path: `/diagnostic/${runId}/answers`,
      headers,
      json: {
        exercise_id: ex.exercise_id,
        exercise_type: 'multiple_choice',
        user_answer: 'a', // pick something — half will be wrong
      },
    });
    expect(res.status).toBe(200);
    const body = res.json as any;
    expect(['correct', 'wrong']).toContain(body.result);
    expect(body.evaluation_source).toBe('deterministic');
    expect(typeof body.canonical_answer).toBe('string');
    expect(body.position).toBe(1);
    expect(body.total).toBe(5);
    expect(body.next_exercise).toBeTruthy();
    expect(body.next_exercise.exercise_id).not.toBe(ex.exercise_id);
  });

  it('rejects answers submitted out of order', async () => {
    const { headers } = await login('diag-4');
    const start = await startDiagnostic(headers);
    const runId = (start.json as any).run_id as string;
    // Use a known exercise_id that exists in the bank but is NOT the
    // first probe item.
    const wrongFirstId = 'a1b2c3d4-0001-4000-8000-000000000031';
    const res = await inject(h.app, {
      method: 'POST',
      path: `/diagnostic/${runId}/answers`,
      headers,
      json: {
        exercise_id: wrongFirstId,
        exercise_type: 'fill_blank',
        user_answer: 'trying',
      },
    });
    expect(res.status).toBe(409);
    expect((res.json as any).error).toBe('diagnostic_answer_out_of_order');
  });

  it('augments learner_skills on the matching skill', async () => {
    const { headers } = await login('diag-5');
    const start = await startDiagnostic(headers);
    const runId = (start.json as any).run_id as string;
    const ex = (start.json as any).next_exercise;
    const correctOption = ex.options.find((_o: any, i: number) => i === 1)?.id;

    await inject(h.app, {
      method: 'POST',
      path: `/diagnostic/${runId}/answers`,
      headers,
      json: {
        exercise_id: ex.exercise_id,
        exercise_type: 'multiple_choice',
        user_answer: correctOption ?? 'a',
      },
    });

    const skillRows = await h.database.orm
      .select()
      .from(learnerSkills)
      .where(eq(learnerSkills.skillId, ex.skill_id));
    expect(skillRows.length).toBe(1);
    expect(skillRows[0].attemptsCount).toBe(1);
  });
});

async function answerEntireRun(
  headers: Record<string, string>,
  runId: string,
  firstExercise: any
) {
  let current = firstExercise;
  while (current) {
    const correctOption =
      current.options?.[1]?.id ?? current.options?.[0]?.id ?? 'a';
    const res = await inject(h.app, {
      method: 'POST',
      path: `/diagnostic/${runId}/answers`,
      headers,
      json: {
        exercise_id: current.exercise_id,
        exercise_type: 'multiple_choice',
        user_answer: correctOption,
      },
    });
    const body = res.json as any;
    if (body.run_complete) return;
    current = body.next_exercise;
  }
}

describe('Wave 12.2 — POST /diagnostic/:runId/complete', () => {
  it('derives CEFR + skill_map, stamps user_profiles, audit-logs', async () => {
    const { headers } = await login('diag-6');
    const start = await startDiagnostic(headers);
    const runId = (start.json as any).run_id as string;
    await answerEntireRun(headers, runId, (start.json as any).next_exercise);

    const res = await inject(h.app, {
      method: 'POST',
      path: `/diagnostic/${runId}/complete`,
      headers,
    });
    expect(res.status).toBe(200);
    const body = res.json as any;
    expect(['A2', 'B1', 'B2']).toContain(body.cefr_level);
    expect(typeof body.skill_map).toBe('object');
    expect(Object.keys(body.skill_map).length).toBeGreaterThanOrEqual(1);
    expect(body.already_completed).toBe(false);
    expect(body.completed_at).toBeTruthy();

    const userId = (await h.database.orm
      .select()
      .from(diagnosticRuns)
      .where(eq(diagnosticRuns.id, runId)))[0].userId;

    const profile = await h.database.orm
      .select()
      .from(userProfiles)
      .where(eq(userProfiles.userId, userId));
    expect(profile[0]?.level).toBe(body.cefr_level);

    const events = await h.database.orm
      .select()
      .from(auditEvents)
      .where(eq(auditEvents.userId, userId));
    const completedEvent = events.find(
      (e) => e.eventType === 'diagnostic_completed'
    );
    expect(completedEvent).toBeTruthy();
    // Wave 12.4 — D1 cohort split reads from this payload. Lock the
    // shape so future refactors don't silently drop the fields the
    // retention dashboard query depends on.
    const payload = completedEvent!.payload as Record<string, unknown>;
    expect(payload.run_id).toBe(runId);
    expect(['A2', 'B1', 'B2']).toContain(payload.cefr_level);
    expect(typeof payload.total_correct).toBe('number');
    expect(typeof payload.total_answered).toBe('number');
    expect(Array.isArray(payload.skills_touched)).toBe(true);
  });

  it('is idempotent on re-call', async () => {
    const { headers } = await login('diag-7');
    const start = await startDiagnostic(headers);
    const runId = (start.json as any).run_id as string;
    await answerEntireRun(headers, runId, (start.json as any).next_exercise);

    const first = await inject(h.app, {
      method: 'POST',
      path: `/diagnostic/${runId}/complete`,
      headers,
    });
    const second = await inject(h.app, {
      method: 'POST',
      path: `/diagnostic/${runId}/complete`,
      headers,
    });
    expect(second.status).toBe(200);
    expect((second.json as any).cefr_level).toBe((first.json as any).cefr_level);
    expect((second.json as any).already_completed).toBe(true);
  });
});

describe('Wave 12.2 — POST /diagnostic/restart', () => {
  it('abandons the active run and returns a fresh one', async () => {
    const { headers } = await login('diag-8');
    const start = await startDiagnostic(headers);
    const firstRunId = (start.json as any).run_id as string;

    const res = await inject(h.app, {
      method: 'POST',
      path: '/diagnostic/restart',
      headers,
    });
    expect(res.status).toBe(201);
    const body = res.json as any;
    expect(body.run_id).not.toBe(firstRunId);
    expect(body.position).toBe(0);
    expect(body.next_exercise).toBeTruthy();
  });
});

describe('Wave 12.2 — POST /diagnostic/skip', () => {
  it('writes a diagnostic_skipped audit event', async () => {
    const { headers } = await login('diag-9');
    const res = await inject(h.app, {
      method: 'POST',
      path: '/diagnostic/skip',
      headers,
    });
    expect(res.status).toBe(204);

    const events = await h.database.orm
      .select()
      .from(auditEvents)
      .where(eq(auditEvents.eventType, 'diagnostic_skipped'));
    expect(events.length).toBeGreaterThanOrEqual(1);
  });
});
