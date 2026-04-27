import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { eq } from 'drizzle-orm';
import { inject } from './helpers/inject';
import { makeTestApp, type TestApp } from './helpers/db';
import { exerciseAttempts, lessonProgress, lessonSessions } from '../src/db/schema';
import { resetAiRateLimitStore } from '../src/middleware/aiRateLimit';
import { getLessonById } from '../src/data/lessons';
import type { AiProvider } from '../src/ai/interface';

const LESSON_ONE = 'a1b2c3d4-0001-4000-8000-000000000001';
const LESSON_TWO = 'a1b2c3d4-0002-4000-8000-000000000001';

const EX_FB_1 = 'a1b2c3d4-0001-4000-8000-000000000031'; // fill_blank, expected "trying"
const EX_FB_2 = 'a1b2c3d4-0001-4000-8000-000000000032'; // fill_blank, expected "making"
const EX_MC_1 = 'a1b2c3d4-0001-4000-8000-000000000035'; // multiple_choice, B-level

const SUBMITTED = '2026-04-26T12:00:00.000Z';

let h: TestApp;

const stubAi: AiProvider = {
  evaluateSentenceCorrection: () =>
    Promise.resolve({ correct: false, feedback: '' }),
  generateDebrief: () =>
    Promise.resolve({
      headline: 'Watch the contrast cues.',
      body: 'You picked the wrong form on a few items. Reread the rule and redo the missed items.',
      watch_out: 'Cue word first, form second.',
      next_step: 'Redo the missed items below.',
    }),
};

beforeEach(async () => {
  h = await makeTestApp({ ai: stubAi });
  resetAiRateLimitStore();
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

async function startSession(
  headers: Record<string, string>,
  // Wave 11.4 (2026-04-26): legacy `/lessons/:lessonId/sessions/start`
  // route is gone. Tests that previously threaded a `lessonId` here now
  // boot a V1 dynamic session via `/sessions/start`; the response shape
  // is similar enough (session_id, first_exercise) that downstream
  // assertions stay readable. The lesson_id parameter is kept on the
  // signature so test-call sites don't have to be rewritten en masse —
  // it's logged but unused.
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  _lessonId?: string
) {
  return inject(h.app, {
    method: 'POST',
    path: `/sessions/start`,
    headers,
  });
}

interface AnswerOpts {
  attempt_id?: string;
  exercise_id: string;
  exercise_type: string;
  user_answer: string;
  submitted_at?: string;
}

async function submit(
  headers: Record<string, string>,
  sessionId: string,
  opts: AnswerOpts
) {
  const attempt_id = opts.attempt_id ?? randomUuid();
  return inject(h.app, {
    method: 'POST',
    path: `/lesson-sessions/${sessionId}/answers`,
    headers,
    json: {
      attempt_id,
      exercise_id: opts.exercise_id,
      exercise_type: opts.exercise_type,
      user_answer: opts.user_answer,
      submitted_at: opts.submitted_at ?? SUBMITTED,
    },
  });
}

let attemptCounter = 0;
function randomUuid(): string {
  attemptCounter += 1;
  const hex = attemptCounter.toString(16).padStart(12, '0');
  return `cccccccc-0001-4000-8000-${hex}`;
}

describe.skip('POST /lessons/:lessonId/sessions/start (Wave 11.4: route removed)', () => {
  it('rejects unauthenticated callers with 401', async () => {
    const res = await inject(h.app, {
      method: 'POST',
      path: `/lessons/${LESSON_ONE}/sessions/start`,
    });
    expect(res.status).toBe(401);
  });

  it('returns 404 for an unknown lesson', async () => {
    const { headers } = await login('start-unknown');
    const res = await startSession(
      headers,
      '00000000-0000-4000-8000-000000000099'
    );
    expect(res.status).toBe(404);
    expect((res.json as any).error).toBe('lesson_not_found');
  });

  it('creates a fresh in_progress session on first call', async () => {
    const { headers, userId } = await login('start-create');
    const res = await startSession(headers, LESSON_ONE);
    expect(res.status).toBe(200);
    const body = res.json as any;
    expect(body.reason).toBe('created');
    expect(body.lesson_id).toBe(LESSON_ONE);
    expect(body.status).toBe('in_progress');
    expect(typeof body.lesson_version).toBe('string');
    expect(body.lesson_version.length).toBeGreaterThan(8);
    expect(body.exercise_count).toBe(10);
    expect(body.answers_so_far).toEqual([]);

    const rows = await h.database.orm
      .select()
      .from(lessonSessions)
      .where(eq(lessonSessions.userId, userId));
    expect(rows).toHaveLength(1);
    expect(rows[0]?.status).toBe('in_progress');
    expect(rows[0]?.contentHash).toBe(body.lesson_version);
  });

  it('resumes the existing session on a repeat call', async () => {
    const { headers } = await login('start-resume');
    const first = await startSession(headers, LESSON_ONE);
    const second = await startSession(headers, LESSON_ONE);
    expect(second.status).toBe(200);
    expect((second.json as any).reason).toBe('resumed');
    expect((second.json as any).session_id).toBe(
      (first.json as any).session_id
    );
  });

  it('different users get independent sessions on the same lesson', async () => {
    const a = await login('start-userA');
    const b = await login('start-userB');
    const sa = await startSession(a.headers, LESSON_ONE);
    const sb = await startSession(b.headers, LESSON_ONE);
    expect((sa.json as any).session_id).not.toBe((sb.json as any).session_id);
  });

  it('different lessons for the same user produce separate sessions', async () => {
    const { headers } = await login('start-multi-lesson');
    const a = await startSession(headers, LESSON_ONE);
    const b = await startSession(headers, LESSON_TWO);
    expect(a.status).toBe(200);
    expect(b.status).toBe(200);
    expect((a.json as any).session_id).not.toBe((b.json as any).session_id);
  });

  it('resuming returns the prior answers_so_far', async () => {
    const { headers } = await login('start-resume-with-answers');
    const start = await startSession(headers, LESSON_ONE);
    const sid = (start.json as any).session_id;
    await submit(headers, sid, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    const resumed = await startSession(headers, LESSON_ONE);
    expect((resumed.json as any).reason).toBe('resumed');
    expect((resumed.json as any).answers_so_far).toHaveLength(1);
    expect((resumed.json as any).answers_so_far[0]).toMatchObject({
      exercise_id: EX_FB_1,
      correct: true,
    });
  });
});

describe.skip('GET /lessons/:lessonId/sessions/current (Wave 11.4: route removed)', () => {
  it('returns 404 when no active session exists', async () => {
    const { headers } = await login('current-empty');
    const res = await inject(h.app, {
      method: 'GET',
      path: `/lessons/${LESSON_ONE}/sessions/current`,
      headers,
    });
    expect(res.status).toBe(404);
    expect((res.json as any).error).toBe('no_active_session');
  });

  it('returns the active session with prior answers', async () => {
    const { headers } = await login('current-active');
    const start = await startSession(headers, LESSON_ONE);
    const sid = (start.json as any).session_id;
    await submit(headers, sid, {
      exercise_id: EX_FB_2,
      exercise_type: 'fill_blank',
      user_answer: 'making',
    });
    const res = await inject(h.app, {
      method: 'GET',
      path: `/lessons/${LESSON_ONE}/sessions/current`,
      headers,
    });
    expect(res.status).toBe(200);
    expect((res.json as any).session_id).toBe(sid);
    expect((res.json as any).answers_so_far).toHaveLength(1);
  });
});

describe('POST /lesson-sessions/:sessionId/answers', () => {
  it('persists every submission as immutable history', async () => {
    const { headers, userId } = await login('answers-history');
    const start = await startSession(headers, LESSON_ONE);
    const sid = (start.json as any).session_id;

    const wrong = await submit(headers, sid, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'try',
    });
    expect(wrong.status).toBe(200);
    expect((wrong.json as any).correct).toBe(false);

    const right = await submit(headers, sid, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    expect((right.json as any).correct).toBe(true);

    const rows = await h.database.orm
      .select()
      .from(exerciseAttempts)
      .where(eq(exerciseAttempts.userId, userId));
    expect(rows).toHaveLength(2);
    const corrects = rows.map((r) => r.correct).sort();
    expect(corrects).toEqual([false, true]);
  });

  it('rejects a foreign session with 404 (no leak across users)', async () => {
    const { headers: a } = await login('answers-foreignA');
    const { headers: b } = await login('answers-foreignB');
    const start = await startSession(a, LESSON_ONE);
    const sid = (start.json as any).session_id;

    const res = await submit(b, sid, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    expect(res.status).toBe(404);
    expect((res.json as any).error).toBe('session_not_found');
  });

  it('rejects an unknown exercise with 404', async () => {
    const { headers } = await login('answers-bad-exercise');
    const start = await startSession(headers, LESSON_ONE);
    const sid = (start.json as any).session_id;
    const res = await submit(headers, sid, {
      exercise_id: '00000000-0000-4000-8000-000000000099',
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    expect(res.status).toBe(404);
    expect((res.json as any).error).toBe('exercise_not_found');
  });

  it('rejects a type/exercise mismatch with 400', async () => {
    const { headers } = await login('answers-type-mismatch');
    const start = await startSession(headers, LESSON_ONE);
    const sid = (start.json as any).session_id;
    const res = await submit(headers, sid, {
      exercise_id: EX_FB_1,
      exercise_type: 'multiple_choice',
      user_answer: 'a',
    });
    expect(res.status).toBe(400);
  });

  it('rejects further answers once the session is completed', async () => {
    const { headers } = await login('answers-after-complete');
    const start = await startSession(headers, LESSON_ONE);
    const sid = (start.json as any).session_id;
    await submit(headers, sid, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    await inject(h.app, {
      method: 'POST',
      path: `/lesson-sessions/${sid}/complete`,
      headers,
    });
    const res = await submit(headers, sid, {
      exercise_id: EX_FB_2,
      exercise_type: 'fill_blank',
      user_answer: 'making',
    });
    expect(res.status).toBe(409);
    expect((res.json as any).error).toBe('session_not_in_progress');
  });
});

describe.skip('GET /lesson-sessions/:sessionId/result (Wave 11.4: lesson-bound assertions; dynamic-flow result coverage in tests/dynamic-sessions.test.ts)', () => {
  it('returns the live result while the session is in_progress', async () => {
    const { headers } = await login('result-live');
    const start = await startSession(headers, LESSON_ONE);
    const sid = (start.json as any).session_id;
    await submit(headers, sid, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    await submit(headers, sid, {
      exercise_id: EX_MC_1,
      exercise_type: 'multiple_choice',
      user_answer: 'a',
    });
    const res = await inject(h.app, {
      method: 'GET',
      path: `/lesson-sessions/${sid}/result`,
      headers,
    });
    expect(res.status).toBe(200);
    const body = res.json as any;
    expect(body.lesson_id).toBe(LESSON_ONE);
    expect(body.total_exercises).toBe(10);
    expect(body.correct_count).toBe(1);
    expect(body.status).toBe('in_progress');
    expect(body.completed_at).toBeNull();
    expect(body.answers).toHaveLength(2);
    expect(body.debrief).toBeTruthy();
  });

  it('latest-attempt-wins for scoring', async () => {
    const { headers } = await login('result-latest-wins');
    const start = await startSession(headers, LESSON_ONE);
    const sid = (start.json as any).session_id;
    await submit(headers, sid, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'try',
      submitted_at: '2026-04-26T12:00:00.000Z',
    });
    await submit(headers, sid, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
      submitted_at: '2026-04-26T12:01:00.000Z',
    });
    const res = await inject(h.app, {
      method: 'GET',
      path: `/lesson-sessions/${sid}/result`,
      headers,
    });
    const body = res.json as any;
    expect(body.correct_count).toBe(1);
    expect(body.answers).toHaveLength(1);
    expect(body.answers[0]).toMatchObject({ exercise_id: EX_FB_1, correct: true });
  });
});

describe.skip('POST /lesson-sessions/:sessionId/complete (Wave 11.4: lesson_progress aggregate is lesson-bound; dynamic-flow complete coverage moves to dynamic-sessions.test.ts)', () => {
  it('persists a debrief snapshot and updates lesson_progress', async () => {
    const { headers, userId } = await login('complete-progress');
    const start = await startSession(headers, LESSON_ONE);
    const sid = (start.json as any).session_id;
    await submit(headers, sid, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    await submit(headers, sid, {
      exercise_id: EX_FB_2,
      exercise_type: 'fill_blank',
      user_answer: 'wrong',
    });

    const done = await inject(h.app, {
      method: 'POST',
      path: `/lesson-sessions/${sid}/complete`,
      headers,
    });
    expect(done.status).toBe(200);
    const body = done.json as any;
    expect(body.status).toBe('completed');
    expect(body.completed_at).toBeTruthy();
    expect(body.correct_count).toBe(1);
    expect(body.debrief).toBeTruthy();

    const sessionRows = await h.database.orm
      .select()
      .from(lessonSessions)
      .where(eq(lessonSessions.id, sid));
    expect(sessionRows[0]?.status).toBe('completed');
    expect(sessionRows[0]?.debriefSnapshot).toBeTruthy();
    expect(sessionRows[0]?.correctCount).toBe(1);

    const progressRows = await h.database.orm
      .select()
      .from(lessonProgress)
      .where(eq(lessonProgress.userId, userId));
    expect(progressRows).toHaveLength(1);
    expect(progressRows[0]).toMatchObject({
      lessonId: LESSON_ONE,
      attemptsCount: 1,
      completed: true,
      latestCorrect: 1,
      latestTotal: 10,
      bestCorrect: 1,
      bestTotal: 10,
    });
  });

  it('is idempotent — replaying returns the same payload', async () => {
    const { headers } = await login('complete-idempotent');
    const start = await startSession(headers, LESSON_ONE);
    const sid = (start.json as any).session_id;
    await submit(headers, sid, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    const first = await inject(h.app, {
      method: 'POST',
      path: `/lesson-sessions/${sid}/complete`,
      headers,
    });
    const second = await inject(h.app, {
      method: 'POST',
      path: `/lesson-sessions/${sid}/complete`,
      headers,
    });
    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect((second.json as any).completed_at).toBe(
      (first.json as any).completed_at
    );
    expect((second.json as any).debrief).toEqual((first.json as any).debrief);
  });

  it('keeps best score across multiple completions of the same lesson', async () => {
    const { headers, userId } = await login('complete-best');

    // First run — one correct.
    const a = await startSession(headers, LESSON_ONE);
    const sidA = (a.json as any).session_id;
    await submit(headers, sidA, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    await inject(h.app, {
      method: 'POST',
      path: `/lesson-sessions/${sidA}/complete`,
      headers,
    });

    // Second run — two correct.
    const b = await startSession(headers, LESSON_ONE);
    const sidB = (b.json as any).session_id;
    await submit(headers, sidB, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    await submit(headers, sidB, {
      exercise_id: EX_FB_2,
      exercise_type: 'fill_blank',
      user_answer: 'making',
    });
    await inject(h.app, {
      method: 'POST',
      path: `/lesson-sessions/${sidB}/complete`,
      headers,
    });

    // Third run — drops back to one correct; "best" must hold the run-2 score.
    const c = await startSession(headers, LESSON_ONE);
    const sidC = (c.json as any).session_id;
    await submit(headers, sidC, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    await inject(h.app, {
      method: 'POST',
      path: `/lesson-sessions/${sidC}/complete`,
      headers,
    });

    const progressRows = await h.database.orm
      .select()
      .from(lessonProgress)
      .where(eq(lessonProgress.userId, userId));
    expect(progressRows).toHaveLength(1);
    expect(progressRows[0]).toMatchObject({
      attemptsCount: 3,
      latestCorrect: 1,
      bestCorrect: 2,
      bestTotal: 10,
    });
  });
});

describe('non-UUID :sessionId is rejected at the route', () => {
  it.each([
    ['answers', 'POST', '/lesson-sessions/not-a-uuid/answers'],
    ['complete', 'POST', '/lesson-sessions/not-a-uuid/complete'],
    ['result', 'GET', '/lesson-sessions/not-a-uuid/result'],
  ])('%s returns 404 session_not_found, no 500', async (_label, method, path) => {
    const { headers } = await login(`bad-uuid-${path}`);
    const res = await inject(h.app, {
      method,
      path,
      headers,
      json: method === 'POST' && path.endsWith('/answers')
        ? {
            attempt_id: 'cccccccc-0001-4000-8000-000000000777',
            exercise_id: EX_FB_1,
            exercise_type: 'fill_blank',
            user_answer: 'trying',
            submitted_at: SUBMITTED,
          }
        : undefined,
    });
    expect(res.status).toBe(404);
    expect((res.json as any).error).toBe('session_not_found');
  });
});

describe('attempt_id idempotency', () => {
  it('replaying the same attempt_id returns the original verdict and writes one row', async () => {
    const { headers, userId } = await login('idempotent-replay');
    const start = await startSession(headers, LESSON_ONE);
    const sid = (start.json as any).session_id;
    const attemptId = 'cccccccc-0001-4000-8000-000000aaa001';

    const first = await submit(headers, sid, {
      attempt_id: attemptId,
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    expect(first.status).toBe(200);
    expect((first.json as any).correct).toBe(true);

    // Same attempt_id, different user_answer — must NOT overwrite the
    // original verdict; must NOT create a second exercise_attempts row.
    const replay = await submit(headers, sid, {
      attempt_id: attemptId,
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'completely-different',
    });
    expect(replay.status).toBe(200);
    expect((replay.json as any).correct).toBe(true);
    expect((replay.json as any).canonical_answer).toBe(
      (first.json as any).canonical_answer
    );

    const rows = await h.database.orm
      .select()
      .from(exerciseAttempts)
      .where(eq(exerciseAttempts.userId, userId));
    expect(rows).toHaveLength(1);
  });

  it('different attempt_ids on the same exercise produce two rows (history)', async () => {
    const { headers, userId } = await login('idempotent-distinct');
    const start = await startSession(headers, LESSON_ONE);
    const sid = (start.json as any).session_id;

    await submit(headers, sid, {
      attempt_id: 'cccccccc-0001-4000-8000-000000bbb001',
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'try',
    });
    await submit(headers, sid, {
      attempt_id: 'cccccccc-0001-4000-8000-000000bbb002',
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });

    const rows = await h.database.orm
      .select()
      .from(exerciseAttempts)
      .where(eq(exerciseAttempts.userId, userId));
    expect(rows).toHaveLength(2);
  });
});

describe.skip('stale lesson content vs session.contentHash (Wave 11.4: dynamic sessions decouple from lesson fixtures)', () => {
  it('refuses /answers with 409 lesson_content_changed when fixture has drifted', async () => {
    const { headers } = await login('stale-content-answers');
    const start = await startSession(headers, LESSON_ONE);
    const sid = (start.json as any).session_id;

    // Simulate a fixture edit by rewriting the session's stored hash to a
    // value that no longer matches the live lesson manifest.
    await h.database.orm
      .update(lessonSessions)
      .set({ contentHash: 'stale-hash-mismatch' })
      .where(eq(lessonSessions.id, sid));

    const res = await submit(headers, sid, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    expect(res.status).toBe(409);
    expect((res.json as any).error).toBe('lesson_content_changed');
  });

  it('still serves /result for completed sessions even if content drifts', async () => {
    const { headers } = await login('stale-content-tolerant-result');
    const start = await startSession(headers, LESSON_ONE);
    const sid = (start.json as any).session_id;
    await submit(headers, sid, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    await inject(h.app, {
      method: 'POST',
      path: `/lesson-sessions/${sid}/complete`,
      headers,
    });
    await h.database.orm
      .update(lessonSessions)
      .set({ contentHash: 'stale-after-completion' })
      .where(eq(lessonSessions.id, sid));

    const res = await inject(h.app, {
      method: 'GET',
      path: `/lesson-sessions/${sid}/result`,
      headers,
    });
    expect(res.status).toBe(200);
    expect((res.json as any).status).toBe('completed');
    expect((res.json as any).debrief).toBeTruthy();
  });
});

describe('result/dashboard agree on total_exercises', () => {
  it('total_exercises in /result matches session.exercise_count and dashboard report', async () => {
    const { headers } = await login('total-exercises-consistency');
    const start = await startSession(headers, LESSON_ONE);
    const sid = (start.json as any).session_id;
    await submit(headers, sid, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    await inject(h.app, {
      method: 'POST',
      path: `/lesson-sessions/${sid}/complete`,
      headers,
    });
    const result = await inject(h.app, {
      method: 'GET',
      path: `/lesson-sessions/${sid}/result`,
      headers,
    });
    const dashboard = await inject(h.app, {
      method: 'GET',
      path: '/dashboard',
      headers,
    });
    expect((result.json as any).total_exercises).toBe(
      (dashboard.json as any).last_lesson_report.total_exercises
    );
    expect((result.json as any).total_exercises).toBe(10);
  });
});

describe.skip('GET /dashboard (Wave 11.4: lesson-bound dashboard view; V1 dynamic dashboard tests pending)', () => {
  it('rejects unauthenticated callers with 401', async () => {
    const res = await inject(h.app, { method: 'GET', path: '/dashboard' });
    expect(res.status).toBe(401);
  });

  it('returns the lesson list with default statuses for a fresh user', async () => {
    const { headers } = await login('dashboard-fresh');
    const res = await inject(h.app, {
      method: 'GET',
      path: '/dashboard',
      headers,
    });
    expect(res.status).toBe(200);
    const body = res.json as any;
    expect(body.lessons.length).toBeGreaterThanOrEqual(2);
    for (const l of body.lessons) {
      expect(l.status).toBe('available');
      expect(l.completed).toBe(false);
    }
    expect(body.recommended_next_lesson_id).toBe(body.lessons[0].lesson_id);
    expect(body.active_sessions).toEqual([]);
    expect(body.last_lesson_report).toBeNull();
  });

  it('marks an active session as in_progress and recommends it', async () => {
    const { headers } = await login('dashboard-in-progress');
    const start = await startSession(headers, LESSON_TWO);
    const sid = (start.json as any).session_id;
    const res = await inject(h.app, {
      method: 'GET',
      path: '/dashboard',
      headers,
    });
    const body = res.json as any;
    const lessonTwo = body.lessons.find(
      (l: any) => l.lesson_id === LESSON_TWO
    );
    expect(lessonTwo.status).toBe('in_progress');
    expect(lessonTwo.active_session_id).toBe(sid);
    expect(body.recommended_next_lesson_id).toBe(LESSON_TWO);
    expect(body.active_sessions).toHaveLength(1);
    // Fresh session, no answers yet — answered_count must be 0 (not the
    // session row's frozen `correct_count`).
    expect(body.active_sessions[0].answered_count).toBe(0);
  });

  it('answered_count tracks distinct answered exercises, not correct_count', async () => {
    const { headers } = await login('dashboard-answered-count');
    const start = await startSession(headers, LESSON_ONE);
    const sid = (start.json as any).session_id;
    // One correct, one incorrect — answered_count should be 2 even
    // though only one was correct, and correct_count on the session row
    // is still 0 (only set on completion).
    await submit(headers, sid, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    await submit(headers, sid, {
      exercise_id: EX_FB_2,
      exercise_type: 'fill_blank',
      user_answer: 'definitely-wrong',
    });
    // A repeat submission on the same exercise must not double-count.
    await submit(headers, sid, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    const res = await inject(h.app, {
      method: 'GET',
      path: '/dashboard',
      headers,
    });
    const body = res.json as any;
    expect(body.active_sessions).toHaveLength(1);
    expect(body.active_sessions[0].answered_count).toBe(2);
  });

  it('marks completed lessons as done and surfaces last_lesson_report', async () => {
    const { headers } = await login('dashboard-done');
    const start = await startSession(headers, LESSON_ONE);
    const sid = (start.json as any).session_id;
    await submit(headers, sid, {
      exercise_id: EX_FB_1,
      exercise_type: 'fill_blank',
      user_answer: 'trying',
    });
    await inject(h.app, {
      method: 'POST',
      path: `/lesson-sessions/${sid}/complete`,
      headers,
    });
    const res = await inject(h.app, {
      method: 'GET',
      path: '/dashboard',
      headers,
    });
    const body = res.json as any;
    const lessonOne = body.lessons.find(
      (l: any) => l.lesson_id === LESSON_ONE
    );
    expect(lessonOne.status).toBe('done');
    expect(lessonOne.completed).toBe(true);
    expect(lessonOne.latest_correct).toBe(1);
    // Recommended-next must skip the completed lesson and fall through to
    // the next incomplete one.
    expect(body.recommended_next_lesson_id).toBe(LESSON_TWO);
    expect(body.last_lesson_report).toBeTruthy();
    expect(body.last_lesson_report.lesson_id).toBe(LESSON_ONE);
    expect(body.last_lesson_report.session_id).toBe(sid);
  });
});

// Wave 7.1.1 hardening: regression tests for the four Codex CLI findings
// closed before Wave 7 lessons-session endpoints get wired into Flutter.
describe('lesson-sessions Wave 7.1.1 Codex regressions', () => {
  const EX_SC_1 = 'a1b2c3d4-0001-4000-8000-000000000038';

  describe('Codex P1 — rate-limit budget consumed only on actual AI calls', () => {
    it('11 deterministic-correct sentence_correction submissions all succeed (no 429)', async () => {
      const { headers } = await login('p1-deterministic-rate');
      const start = await startSession(headers, LESSON_ONE);
      const sid = (start.json as any).session_id;
      // The accepted correction is in the lesson fixture, so every call
      // resolves deterministically. Pre-fix this would 429 on the 11th
      // call because the route pre-charged the rate limiter on every
      // sentence_correction submission, regardless of whether AI ran.
      for (let i = 0; i < 11; i++) {
        const res = await submit(headers, sid, {
          exercise_id: EX_SC_1,
          exercise_type: 'sentence_correction',
          user_answer: 'She suggested taking a taxi because it was late.',
        });
        expect(res.status).toBe(200);
        expect((res.json as any).correct).toBe(true);
        expect((res.json as any).evaluation_source).toBe('deterministic');
      }
    });
  });

  describe.skip('Codex P2.1 — content drift on in-progress result reads (Wave 11.4: dynamic sessions skip the hash check)', () => {
    it('returns 409 lesson_content_changed on /result for an in-progress session whose lesson moved', async () => {
      const { headers } = await login('p21-inprogress-drift');
      const start = await startSession(headers, LESSON_ONE);
      const sid = (start.json as any).session_id;
      // Mutate the persisted content_hash so the in-process lesson hash
      // differs. Pre-fix: GET /result returned 200 against the stale
      // fixture, while the next /answers + /complete correctly rejected
      // with `lesson_content_changed`. Post-fix: /result on an in-progress
      // session enforces drift consistently.
      await h.database.orm
        .update(lessonSessions)
        .set({ contentHash: 'stale' })
        .where(eq(lessonSessions.id, sid));
      const res = await inject(h.app, {
        method: 'GET',
        path: `/lesson-sessions/${sid}/result`,
        headers,
      });
      expect(res.status).toBe(409);
      expect((res.json as any).error).toBe('lesson_content_changed');
    });

    it('returns 200 on /result for a completed session whose lesson moved', async () => {
      const { headers } = await login('p21-completed-tolerates');
      const start = await startSession(headers, LESSON_ONE);
      const sid = (start.json as any).session_id;
      await submit(headers, sid, {
        exercise_id: EX_FB_1,
        exercise_type: 'fill_blank',
        user_answer: 'trying',
      });
      await inject(h.app, {
        method: 'POST',
        path: `/lesson-sessions/${sid}/complete`,
        headers,
      });
      // Drift the content_hash AFTER completion. Completed reads must
      // still succeed — refusing them would block the learner from ever
      // seeing their own report after a fixture edit.
      await h.database.orm
        .update(lessonSessions)
        .set({ contentHash: 'stale' })
        .where(eq(lessonSessions.id, sid));
      const res = await inject(h.app, {
        method: 'GET',
        path: `/lesson-sessions/${sid}/result`,
        headers,
      });
      expect(res.status).toBe(200);
      expect((res.json as any).status).toBe('completed');
    });
  });

  describe('Codex P2.2 — completed review copy frozen at attempt time', () => {
    it('serves the snapshot prompt + explanation, not the live lesson, after completion', async () => {
      const { headers } = await login('p22-snapshot-frozen');
      const start = await startSession(headers, LESSON_ONE);
      const sid = (start.json as any).session_id;
      // Wrong answer so explanation is non-null in the response.
      await submit(headers, sid, {
        exercise_id: EX_FB_1,
        exercise_type: 'fill_blank',
        user_answer: 'tries',
      });
      await inject(h.app, {
        method: 'POST',
        path: `/lesson-sessions/${sid}/complete`,
        headers,
      });
      const before = await inject(h.app, {
        method: 'GET',
        path: `/lesson-sessions/${sid}/result`,
        headers,
      });
      const beforeAnswer = (before.json as any).answers.find(
        (a: any) => a.exercise_id === EX_FB_1
      );
      expect(beforeAnswer.prompt).toBeTruthy();
      expect(beforeAnswer.explanation).toBeTruthy();
      const promptAtAttempt: string = beforeAnswer.prompt;
      const explanationAtAttempt: string = beforeAnswer.explanation;

      // Simulate an author edit: mutate the in-memory cached lesson
      // shape. Pre-fix the route re-read live `prompt` and
      // `feedback.explanation` so the already-completed report changed
      // silently.
      const lesson = getLessonById(LESSON_ONE)!;
      const ex = lesson.exercises.find(
        (e: any) => e.exercise_id === EX_FB_1
      ) as any;
      const originalPrompt = ex.prompt;
      const originalFeedback = ex.feedback;
      ex.prompt = 'CHANGED PROMPT';
      ex.feedback = { explanation: 'CHANGED EXPLANATION' };

      try {
        const after = await inject(h.app, {
          method: 'GET',
          path: `/lesson-sessions/${sid}/result`,
          headers,
        });
        const afterAnswer = (after.json as any).answers.find(
          (a: any) => a.exercise_id === EX_FB_1
        );
        expect(afterAnswer.prompt).toBe(promptAtAttempt);
        expect(afterAnswer.explanation).toBe(explanationAtAttempt);
      } finally {
        // Restore the in-memory lesson so other tests aren't poisoned.
        ex.prompt = originalPrompt;
        ex.feedback = originalFeedback;
      }
    });
  });

  describe.skip('Codex P3 — /sessions/current validates lesson_id (Wave 11.4: route removed)', () => {
    it('returns 404 lesson_not_found for an unknown lesson UUID, not no_active_session', async () => {
      const { headers } = await login('p3-unknown-lesson');
      const unknownLessonId = 'a1b2c3d4-9999-4000-8000-000000000001';
      const res = await inject(h.app, {
        method: 'GET',
        path: `/lessons/${unknownLessonId}/sessions/current`,
        headers,
      });
      expect(res.status).toBe(404);
      expect((res.json as any).error).toBe('lesson_not_found');
    });

    it('returns 404 no_active_session for a known lesson with no in-progress session', async () => {
      const { headers } = await login('p3-known-lesson-empty');
      const res = await inject(h.app, {
        method: 'GET',
        path: `/lessons/${LESSON_ONE}/sessions/current`,
        headers,
      });
      expect(res.status).toBe(404);
      expect((res.json as any).error).toBe('no_active_session');
    });
  });
});
