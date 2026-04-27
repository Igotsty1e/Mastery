import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { inject } from './helpers/inject';
import { makeTestApp, type TestApp } from './helpers/db';
import type { AiProvider } from '../src/ai/interface';

let h: TestApp;

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
  const body = res.json as { accessToken: string; user: { id: string } };
  return {
    accessToken: body.accessToken,
    userId: body.user.id,
    headers: { authorization: `Bearer ${body.accessToken}` },
  };
}

const SKILL_A = 'verb-ing-after-gerund-verbs';
const SKILL_B = 'present-perfect-continuous-vs-simple';

describe('Wave 7.3 — POST /me/skills/:skillId/attempts', () => {
  it('rejects unauthenticated callers with 401', async () => {
    const res = await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/attempts`,
      json: { evidence_tier: 'medium', correct: true },
    });
    expect(res.status).toBe(401);
  });

  it('first attempt seeds the record and bumps the score', async () => {
    const { headers } = await login('seed');
    const res = await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/attempts`,
      headers,
      json: { evidence_tier: 'medium', correct: true },
    });
    expect(res.status).toBe(200);
    const body = res.json as any;
    expect(body.skill_id).toBe(SKILL_A);
    expect(body.mastery_score).toBe(10);
    expect(body.evidence_summary.medium).toBe(1);
    expect(body.recent_errors).toEqual([]);
    expect(body.production_gate_cleared).toBe(false);
    expect(body.last_attempt_at).toBeTruthy();
  });

  it('clamp to [0, 100]', async () => {
    const { headers } = await login('clamp');
    // Floor: many wrongs from zero stay at zero.
    for (let i = 0; i < 3; i++) {
      const r = await inject(h.app, {
        method: 'POST',
        path: `/me/skills/${SKILL_A}/attempts`,
        headers,
        json: { evidence_tier: 'strongest', correct: false },
      });
      expect(r.status).toBe(200);
    }
    let read = await inject(h.app, {
      method: 'GET',
      path: `/me/skills/${SKILL_A}`,
      headers,
    });
    expect((read.json as any).mastery_score).toBe(0);

    // Ceiling: many corrects max at 100.
    for (let i = 0; i < 10; i++) {
      await inject(h.app, {
        method: 'POST',
        path: `/me/skills/${SKILL_A}/attempts`,
        headers,
        json: { evidence_tier: 'strongest', correct: true },
      });
    }
    read = await inject(h.app, {
      method: 'GET',
      path: `/me/skills/${SKILL_A}`,
      headers,
    });
    expect((read.json as any).mastery_score).toBe(100);
  });

  it('recent_errors FIFO-bounded at 5', async () => {
    const { headers } = await login('fifo');
    const codes = [
      'contrast_error',
      'form_error',
      'contrast_error',
      'form_error',
      'contrast_error',
      'form_error',
      'contrast_error',
      'form_error',
    ];
    for (const code of codes) {
      await inject(h.app, {
        method: 'POST',
        path: `/me/skills/${SKILL_A}/attempts`,
        headers,
        json: {
          evidence_tier: 'medium',
          correct: false,
          primary_target_error: code,
        },
      });
    }
    const read = await inject(h.app, {
      method: 'GET',
      path: `/me/skills/${SKILL_A}`,
      headers,
    });
    const body = read.json as any;
    expect(body.recent_errors).toHaveLength(5);
    expect(body.recent_errors[0]).toBe('form_error');
    expect(body.recent_errors[4]).toBe('form_error');
  });

  it('production_gate_cleared flips on first strongest+meaning_frame correct', async () => {
    const { headers } = await login('gate-flip');
    let r = await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/attempts`,
      headers,
      json: { evidence_tier: 'strongest', correct: true },
    });
    expect((r.json as any).production_gate_cleared).toBe(false);

    r = await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/attempts`,
      headers,
      json: {
        evidence_tier: 'strongest',
        correct: true,
        meaning_frame: 'Decline a meeting politely.',
      },
    });
    expect((r.json as any).production_gate_cleared).toBe(true);
  });

  it('§12.3 invalidation: gate clears on evaluation_version bump', async () => {
    const { headers } = await login('gate-bump');
    await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/attempts`,
      headers,
      json: {
        evidence_tier: 'strongest',
        correct: true,
        meaning_frame: 'context',
        evaluation_version: 1,
      },
    });
    const r = await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/attempts`,
      headers,
      json: {
        evidence_tier: 'medium',
        correct: true,
        evaluation_version: 2,
      },
    });
    const body = r.json as any;
    expect(body.production_gate_cleared).toBe(false);
    expect(body.gate_cleared_at_version).toBeNull();
  });

  it('rejects malformed skill_id at the route boundary', async () => {
    const { headers } = await login('bad-id');
    const r = await inject(h.app, {
      method: 'POST',
      path: '/me/skills/has spaces/attempts',
      headers,
      json: { evidence_tier: 'weak', correct: true },
    });
    expect(r.status).toBe(400);
  });
});

describe('Wave 7.3 — derived status (§7.2)', () => {
  it('"started" copy fires for low score with at most one attempt', async () => {
    const { headers } = await login('status-started');
    await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/attempts`,
      headers,
      json: { evidence_tier: 'medium', correct: true },
    });
    const read = await inject(h.app, {
      method: 'GET',
      path: `/me/skills/${SKILL_A}`,
      headers,
    });
    expect((read.json as any).status).toBe('started');
  });

  it('Wave 10 V1 — 4 correct attempts without correction/production caps at "getting_there"', async () => {
    const { headers } = await login('status-prac');
    for (let i = 0; i < 4; i++) {
      await inject(h.app, {
        method: 'POST',
        path: `/me/skills/${SKILL_A}/attempts`,
        headers,
        json: { evidence_tier: 'medium', correct: true },
      });
    }
    const read = await inject(h.app, {
      method: 'GET',
      path: `/me/skills/${SKILL_A}`,
      headers,
    });
    // V1 gate (`docs/plans/learning-engine-v1.md`): the attempts arm
    // requires ≥6 attempts OR ≥4 with at least one correction/production
    // exercise type. 4 medium attempts without an `exercise_type`
    // payload meet neither, so the status caps at `getting_there`
    // (accuracy 1.0 ≥ 0.7) per `mastery.ts` quick-exit branch.
    expect((read.json as any).status).toBe('getting_there');
  });
});

describe('Wave 7.3 — GET /me/skills', () => {
  it('returns every touched skill for the caller', async () => {
    const { headers } = await login('all-skills');
    await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/attempts`,
      headers,
      json: { evidence_tier: 'weak', correct: true },
    });
    await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_B}/attempts`,
      headers,
      json: { evidence_tier: 'medium', correct: false, primary_target_error: 'contrast_error' },
    });
    const r = await inject(h.app, {
      method: 'GET',
      path: '/me/skills',
      headers,
    });
    const ids = ((r.json as any).skills as any[])
      .map((s) => s.skill_id)
      .sort();
    expect(ids).toEqual([SKILL_B, SKILL_A].sort());
  });

  it('does not leak other users\' state', async () => {
    const a = await login('isolation-a');
    const b = await login('isolation-b');
    await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/attempts`,
      headers: a.headers,
      json: { evidence_tier: 'medium', correct: true },
    });
    const r = await inject(h.app, {
      method: 'GET',
      path: '/me/skills',
      headers: b.headers,
    });
    expect((r.json as any).skills).toEqual([]);
  });
});

describe('Wave 7.3 — POST /me/skills/:skillId/review-cadence', () => {
  it('first clean session enters cadence at step 1, due ~1 day later', async () => {
    const { headers } = await login('cadence-clean');
    const r = await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/review-cadence`,
      headers,
      json: { mistakes_in_session: 0 },
    });
    const body = r.json as any;
    expect(body.step).toBe(1);
    expect(body.graduated).toBe(false);
    expect(body.last_outcome_mistakes).toBe(0);
    const dueAt = new Date(body.due_at).getTime();
    const lastAt = new Date(body.last_outcome_at).getTime();
    const dayMs = 24 * 60 * 60 * 1000;
    expect(dueAt - lastAt).toBe(dayMs);
  });

  it('two clean sessions advance step 1 → 2', async () => {
    const { headers } = await login('cadence-step');
    await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/review-cadence`,
      headers,
      json: { mistakes_in_session: 0 },
    });
    const r = await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/review-cadence`,
      headers,
      json: { mistakes_in_session: 0 },
    });
    expect((r.json as any).step).toBe(2);
  });

  it('mistakes reset cadence to step 1', async () => {
    const { headers } = await login('cadence-reset');
    await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/review-cadence`,
      headers,
      json: { mistakes_in_session: 0 },
    });
    await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/review-cadence`,
      headers,
      json: { mistakes_in_session: 0 },
    });
    const r = await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/review-cadence`,
      headers,
      json: { mistakes_in_session: 2 },
    });
    expect((r.json as any).step).toBe(1);
    expect((r.json as any).last_outcome_mistakes).toBe(2);
  });

  it('reaching step 5 without resetting flags graduated (§9.4)', async () => {
    const { headers } = await login('cadence-grad');
    for (let i = 0; i < 5; i++) {
      await inject(h.app, {
        method: 'POST',
        path: `/me/skills/${SKILL_A}/review-cadence`,
        headers,
        json: { mistakes_in_session: 0 },
      });
    }
    const r = await inject(h.app, {
      method: 'GET',
      path: `/me/skills/${SKILL_A}/review-cadence`,
      headers,
    });
    expect((r.json as any).step).toBe(5);
    expect((r.json as any).graduated).toBe(true);
  });
});

describe('Wave 7.3 — GET /me/reviews/due', () => {
  it('empty list when nothing scheduled', async () => {
    const { headers } = await login('due-empty');
    const r = await inject(h.app, {
      method: 'GET',
      path: '/me/reviews/due',
      headers,
    });
    expect((r.json as any).reviews).toEqual([]);
  });

  it('returns only skills due at or before `at`, sorted oldest-first', async () => {
    const { headers } = await login('due-window');
    // Start a cadence on each skill so both have schedules.
    await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/review-cadence`,
      headers,
      json: { mistakes_in_session: 0 },
    });
    await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_B}/review-cadence`,
      headers,
      json: { mistakes_in_session: 0 },
    });
    // Both due ~1 day from now. Asking at +2d should return both;
    // skillA was inserted first so it's slightly earlier.
    const future = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000);
    const r = await inject(h.app, {
      method: 'GET',
      path: `/me/reviews/due?at=${encodeURIComponent(future.toISOString())}`,
      headers,
    });
    const ids = ((r.json as any).reviews as any[]).map((s) => s.skill_id);
    expect(ids).toEqual([SKILL_A, SKILL_B]);
  });

  it('graduated skills excluded from dueAt', async () => {
    const { headers } = await login('due-graduated');
    for (let i = 0; i < 5; i++) {
      await inject(h.app, {
        method: 'POST',
        path: `/me/skills/${SKILL_A}/review-cadence`,
        headers,
        json: { mistakes_in_session: 0 },
      });
    }
    const veryFuture = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000);
    const r = await inject(h.app, {
      method: 'GET',
      path: `/me/reviews/due?at=${encodeURIComponent(veryFuture.toISOString())}`,
      headers,
    });
    expect((r.json as any).reviews).toEqual([]);
  });
});

describe('Wave 7.4 part 2.4 — POST /me/state/bulk-import', () => {
  it('rejects unauthenticated callers with 401', async () => {
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/state/bulk-import',
      json: { learner_skills: [], review_schedules: [] },
    });
    expect(res.status).toBe(401);
  });

  it('imports a fresh device payload into empty server state', async () => {
    const { headers } = await login('bulk-fresh');
    const lastAt = new Date('2026-04-26T12:00:00.000Z').toISOString();
    const dueAt = new Date('2026-04-28T12:00:00.000Z').toISOString();
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/state/bulk-import',
      headers,
      json: {
        learner_skills: [
          {
            skill_id: SKILL_A,
            mastery_score: 35,
            last_attempt_at: lastAt,
            evidence_summary: { medium: 3, weak: 1 },
            recent_errors: ['contrast_error', 'form_error'],
            production_gate_cleared: false,
          },
          {
            skill_id: SKILL_B,
            mastery_score: 80,
            last_attempt_at: lastAt,
            evidence_summary: { strong: 4, strongest: 1 },
            production_gate_cleared: true,
            gate_cleared_at_version: 1,
          },
        ],
        review_schedules: [
          {
            skill_id: SKILL_A,
            step: 2,
            due_at: dueAt,
            last_outcome_at: lastAt,
            last_outcome_mistakes: 0,
          },
        ],
      },
    });
    expect(res.status).toBe(200);
    const body = res.json as any;
    expect(body.imported_skill_ids.sort()).toEqual([SKILL_A, SKILL_B].sort());
    expect(body.skipped_skill_ids).toEqual([]);
    expect(body.imported_schedule_skill_ids).toEqual([SKILL_A]);

    // Verify server state reflects the import.
    const all = await inject(h.app, {
      method: 'GET',
      path: '/me/skills',
      headers,
    });
    const skillA = ((all.json as any).skills as any[]).find(
      (s) => s.skill_id === SKILL_A
    );
    expect(skillA.mastery_score).toBe(35);
    expect(skillA.evidence_summary.medium).toBe(3);
    expect(skillA.recent_errors).toEqual(['contrast_error', 'form_error']);

    const skillB = ((all.json as any).skills as any[]).find(
      (s) => s.skill_id === SKILL_B
    );
    expect(skillB.production_gate_cleared).toBe(true);
    expect(skillB.gate_cleared_at_version).toBe(1);
  });

  it('skips skills already present on the server (idempotent)', async () => {
    const { headers } = await login('bulk-idempotent');
    // Pre-seed the server with one attempt on SKILL_A.
    await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/attempts`,
      headers,
      json: { evidence_tier: 'strong', correct: true },
    });
    // Now try to bulk-import a different (lower) state for SKILL_A.
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/state/bulk-import',
      headers,
      json: {
        learner_skills: [
          {
            skill_id: SKILL_A,
            mastery_score: 5,
            evidence_summary: { weak: 1 },
          },
          {
            skill_id: SKILL_B,
            mastery_score: 20,
            evidence_summary: { medium: 2 },
          },
        ],
        review_schedules: [],
      },
    });
    const body = res.json as any;
    expect(body.skipped_skill_ids).toEqual([SKILL_A]);
    expect(body.imported_skill_ids).toEqual([SKILL_B]);

    // Verify SKILL_A still has the server's higher state.
    const a = await inject(h.app, {
      method: 'GET',
      path: `/me/skills/${SKILL_A}`,
      headers,
    });
    expect((a.json as any).mastery_score).toBe(15); // strong correct = +15
  });

  it('skipped schedules do not clobber server cadence', async () => {
    const { headers } = await login('bulk-sched-skip');
    // Pre-seed cadence for SKILL_A at step 1.
    await inject(h.app, {
      method: 'POST',
      path: `/me/skills/${SKILL_A}/review-cadence`,
      headers,
      json: { mistakes_in_session: 0 },
    });
    const oldDue = new Date('2026-01-01T00:00:00.000Z').toISOString();
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/state/bulk-import',
      headers,
      json: {
        learner_skills: [],
        review_schedules: [
          {
            skill_id: SKILL_A,
            step: 5,
            due_at: oldDue,
            last_outcome_at: oldDue,
            last_outcome_mistakes: 0,
            graduated: true,
          },
        ],
      },
    });
    expect((res.json as any).skipped_schedule_skill_ids).toEqual([SKILL_A]);
    const sched = await inject(h.app, {
      method: 'GET',
      path: `/me/skills/${SKILL_A}/review-cadence`,
      headers,
    });
    // Server's pre-existing step=1 entry preserved, NOT clobbered by
    // the inbound step=5 graduated entry.
    expect((sched.json as any).step).toBe(1);
    expect((sched.json as any).graduated).toBe(false);
  });

  it('rejects oversized payloads (>500 entries)', async () => {
    const { headers } = await login('bulk-big');
    const skills = Array.from({ length: 501 }, (_, i) => ({
      skill_id: `skill_${i}`,
      mastery_score: 0,
    }));
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/state/bulk-import',
      headers,
      json: { learner_skills: skills, review_schedules: [] },
    });
    expect(res.status).toBe(400);
  });

  it('rejects malformed entries', async () => {
    const { headers } = await login('bulk-bad');
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/state/bulk-import',
      headers,
      json: {
        learner_skills: [
          { skill_id: 'has spaces', mastery_score: 50 },
        ],
        review_schedules: [],
      },
    });
    expect(res.status).toBe(400);
  });
});
