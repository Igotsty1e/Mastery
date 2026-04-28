// Wave 14.3 phase 3 — V1.5 friction detection (repeated_error).
//
// V1 detector: same skill_id, two consecutive wrongs in this session.
// We drive the dynamic-session route end-to-end and submit using
// hard-coded fixture exercise_ids from `b2-lesson-001.json` — every
// item in that lesson carries `skill_id = verb-ing-after-gerund-verbs`,
// which makes the same-skill precondition trivially satisfied.

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';

import { inject } from './helpers/inject';
import { makeTestApp, type TestApp } from './helpers/db';

let h: TestApp;

beforeEach(async () => {
  h = await makeTestApp();
});

afterEach(async () => {
  await h.close();
});

// Known IDs from b2-lesson-001.json — every item is on
// `verb-ing-after-gerund-verbs` so any two of them satisfy the
// same-skill precondition for `repeated_error`.
const EX_FILL_BLANK_1 = 'a1b2c3d4-0001-4000-8000-000000000031';
const EX_FILL_BLANK_2 = 'a1b2c3d4-0001-4000-8000-000000000032';
const EX_MC_1 = 'a1b2c3d4-0001-4000-8000-000000000034';

async function login(subject: string) {
  const res = await inject(h.app, {
    method: 'POST',
    path: '/auth/apple/stub/login',
    json: { subject },
  });
  if (res.status !== 200) throw new Error(`login_${res.status}`);
  const body = res.json as { accessToken: string };
  return { authorization: `Bearer ${body.accessToken}` };
}

async function startSession(authHeader: Record<string, string>) {
  const res = await inject(h.app, {
    method: 'POST',
    path: '/sessions/start',
    headers: authHeader,
  });
  if (res.status !== 200) throw new Error(`start_${res.status}`);
  return res.json as { session_id: string };
}

async function submit(
  authHeader: Record<string, string>,
  sessionId: string,
  payload: {
    exercise_id: string;
    exercise_type: string;
    user_answer: string;
  }
) {
  return inject(h.app, {
    method: 'POST',
    path: `/lesson-sessions/${sessionId}/answers`,
    headers: authHeader,
    json: {
      attempt_id: randomUUID(),
      submitted_at: new Date().toISOString(),
      ...payload,
    },
  });
}

describe('Wave 14.3 phase 3 — friction detection', () => {
  it('returns friction_event=null on a single wrong attempt', async () => {
    const auth = await login('friction-single');
    const start = await startSession(auth);
    const res = await submit(auth, start.session_id, {
      exercise_id: EX_FILL_BLANK_1,
      exercise_type: 'fill_blank',
      user_answer: 'definitely-not-right',
    });
    expect(res.status).toBe(200);
    expect((res.json as { correct: boolean }).correct).toBe(false);
    expect((res.json as { friction_event: string | null }).friction_event).toBeNull();
  });

  it('flips friction_event=repeated_error on two consecutive wrong attempts on the same skill', async () => {
    const auth = await login('friction-repeated');
    const start = await startSession(auth);

    const r1 = await submit(auth, start.session_id, {
      exercise_id: EX_FILL_BLANK_1,
      exercise_type: 'fill_blank',
      user_answer: 'definitely-not-right',
    });
    expect(r1.status).toBe(200);
    expect((r1.json as { friction_event: string | null }).friction_event).toBeNull();

    const r2 = await submit(auth, start.session_id, {
      exercise_id: EX_FILL_BLANK_2,
      exercise_type: 'fill_blank',
      user_answer: 'still-not-right',
    });
    expect(r2.status).toBe(200);
    expect((r2.json as { friction_event: string | null }).friction_event).toBe(
      'repeated_error'
    );
  });

  it('does NOT fire friction when the prior attempt was correct', async () => {
    const auth = await login('friction-prior-ok');
    const start = await startSession(auth);

    // Multiple-choice with a non-existent option_id is wrong (not the
    // shape we want for this case) — we want a correct prior. The MC
    // first option in lesson 001 ex 34 is the correct one ('a' or so).
    // Either way, do not engage that complexity — submit a correct
    // fill_blank by reading the lesson and using its accepted answer.
    // Lesson 001 ex 31: prompt has '___' and 'trying' is the canonical.
    const r1 = await submit(auth, start.session_id, {
      exercise_id: EX_FILL_BLANK_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    expect(r1.status).toBe(200);
    expect((r1.json as { correct: boolean }).correct).toBe(true);

    const r2 = await submit(auth, start.session_id, {
      exercise_id: EX_FILL_BLANK_2,
      exercise_type: 'fill_blank',
      user_answer: 'wrong-answer',
    });
    expect(r2.status).toBe(200);
    expect((r2.json as { correct: boolean }).correct).toBe(false);
    // Prior was correct → no friction even though current is wrong.
    expect((r2.json as { friction_event: string | null }).friction_event).toBeNull();
  });

  it('does NOT fire friction when the prior wrong was on a different skill', async () => {
    const auth = await login('friction-different-skill');
    const start = await startSession(auth);

    // Both items are on the same lesson / same skill in our fixture
    // (every lesson is one-skill in V1). To exercise the
    // different-skill branch we use exercises from two different
    // lessons. Lesson 002 is `present-perfect-continuous-vs-simple`.
    const EX_LESSON_2_FB = 'a1b2c3d4-0002-4000-8000-000000000031';
    const r1 = await submit(auth, start.session_id, {
      exercise_id: EX_FILL_BLANK_1,
      exercise_type: 'fill_blank',
      user_answer: 'definitely-not-right',
    });
    expect(r1.status).toBe(200);
    expect((r1.json as { correct: boolean }).correct).toBe(false);

    const r2 = await submit(auth, start.session_id, {
      exercise_id: EX_LESSON_2_FB,
      exercise_type: 'fill_blank',
      user_answer: 'still-not-right',
    });
    expect(r2.status).toBe(200);
    expect((r2.json as { correct: boolean }).correct).toBe(false);
    // Different skill → friction stays null.
    expect((r2.json as { friction_event: string | null }).friction_event).toBeNull();
  });
});
