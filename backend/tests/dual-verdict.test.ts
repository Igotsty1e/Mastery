// Wave H2 — dual-verdict AI judge integration tests.
//
// The judge is invoked only on `fill_blank` items, only when:
//   1. the deterministic matcher fails;
//   2. the lesson declares a non-empty `target_form`;
//   3. the AI provider implements `evaluateTargetVerdict`;
//   4. the rate limit has spare budget.
// Any AI error keeps the deterministic verdict.
//
// These tests inject a hand-rolled AiProvider whose
// `evaluateTargetVerdict` returns scripted verdicts so we can
// assert the combiner end-to-end through the route.

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { inject } from './helpers/inject';
import { makeTestApp, type TestApp } from './helpers/db';
import { resetAiRateLimitStore } from '../src/middleware/aiRateLimit';
import type {
  AiProvider,
  AiTargetVerdictArgs,
  AiTargetVerdictResult,
} from '../src/ai/interface';

const LESSON_ONE = 'a1b2c3d4-0001-4000-8000-000000000001';
// Wave H3 (2026-05-01): items …031–034 in Lesson 1 were converted
// from fill_blank to short_free_sentence. The lone surviving
// fill_blank in Lesson 1 is …037 (expected "reading"); keep that
// one as the fixture for the dual-verdict (fill_blank-only) path.
const EX_FB_1 = 'a1b2c3d4-0001-4000-8000-000000000037';

const SUBMITTED = '2026-04-26T12:00:00.000Z';

function makeAi(
  verdict: AiTargetVerdictResult,
  recorder?: { calls: AiTargetVerdictArgs[] }
): AiProvider {
  return {
    evaluateSentenceCorrection: () =>
      Promise.resolve({ correct: false, feedback: '' }),
    evaluateTargetVerdict: async (args) => {
      recorder?.calls.push(args);
      return verdict;
    },
  };
}

let h: TestApp;

afterEach(async () => {
  if (h) await h.close();
});

beforeEach(() => {
  resetAiRateLimitStore();
});

async function login(subject: string) {
  const res = await inject(h.app, {
    method: 'POST',
    path: '/auth/apple/stub/login',
    json: { subject },
  });
  const body = res.json as { accessToken: string; user: { id: string } };
  return {
    headers: { authorization: `Bearer ${body.accessToken}` },
    userId: body.user.id,
  };
}

async function start(headers: Record<string, string>) {
  const res = await inject(h.app, {
    method: 'POST',
    path: `/sessions/start`,
    headers,
  });
  if (res.status !== 200) {
    throw new Error(
      `start failed: ${res.status} ${JSON.stringify(res.json)}`
    );
  }
  return (res.json as any).session_id as string;
}

let attemptCounter = 0;
function attemptUuid(): string {
  attemptCounter += 1;
  const hex = attemptCounter.toString(16).padStart(12, '0');
  return `dddddddd-0001-4000-8000-${hex}`;
}

async function submit(
  headers: Record<string, string>,
  sessionId: string,
  exerciseId: string,
  userAnswer: string
) {
  return inject(h.app, {
    method: 'POST',
    path: `/lesson-sessions/${sessionId}/answers`,
    headers,
    json: {
      attempt_id: attemptUuid(),
      exercise_id: exerciseId,
      exercise_type: 'fill_blank',
      user_answer: userAnswer,
      submitted_at: SUBMITTED,
    },
  });
}

describe('dual-verdict judge — fill_blank', () => {
  it('flips a wrong fill_blank to correct when target_met=true', async () => {
    const recorder = { calls: [] as AiTargetVerdictArgs[] };
    h = await makeTestApp({
      ai: makeAi(
        { target_met: true, off_target_error: false, off_target_note: '' },
        recorder
      ),
    });
    const { headers } = await login('h2-flip-correct');
    const sid = await start(headers);

    // EX_FB_1 (lesson 1, item 037) expects "reading" in
    // "I enjoy ___ before bed". "swimming" is a synonym that uses
    // the verb-ing form but is not in the accepted list.
    // Deterministic fails → judge runs → flip.
    const res = await submit(headers, sid, EX_FB_1, 'swimming');
    expect(res.status).toBe(200);
    expect((res.json as any).correct).toBe(true);
    expect(recorder.calls).toHaveLength(1);
    expect(recorder.calls[0].targetForm).toContain('verb-ing');
  });

  it('appends off_target_note when judge says target_met but off_target_error', async () => {
    h = await makeTestApp({
      ai: makeAi({
        target_met: true,
        off_target_error: true,
        off_target_note: 'small spelling slip in the verb base',
      }),
    });
    const { headers } = await login('h2-soft-note');
    const sid = await start(headers);

    const res = await submit(headers, sid, EX_FB_1, 'redaing');
    expect((res.json as any).correct).toBe(true);
    expect((res.json as any).explanation).toBe(
      'small spelling slip in the verb base'
    );
  });

  it('keeps deterministic verdict when target_met=false', async () => {
    h = await makeTestApp({
      ai: makeAi({
        target_met: false,
        off_target_error: false,
        off_target_note: '',
      }),
    });
    const { headers } = await login('h2-no-flip');
    const sid = await start(headers);

    const res = await submit(headers, sid, EX_FB_1, 'to read');
    expect((res.json as any).correct).toBe(false);
  });

  it('keeps deterministic verdict when AI throws', async () => {
    h = await makeTestApp({
      ai: {
        evaluateSentenceCorrection: () =>
          Promise.resolve({ correct: false, feedback: '' }),
        evaluateTargetVerdict: async () => {
          throw new Error('OpenAI 503');
        },
      },
    });
    const { headers } = await login('h2-ai-error');
    const sid = await start(headers);

    const res = await submit(headers, sid, EX_FB_1, 'swimming');
    expect((res.json as any).correct).toBe(false);
  });

  it('does not call the judge on deterministic-correct answers', async () => {
    const recorder = { calls: [] as AiTargetVerdictArgs[] };
    h = await makeTestApp({
      ai: makeAi(
        { target_met: false, off_target_error: false, off_target_note: '' },
        recorder
      ),
    });
    const { headers } = await login('h2-skip-on-correct');
    const sid = await start(headers);

    const res = await submit(headers, sid, EX_FB_1, 'reading');
    expect((res.json as any).correct).toBe(true);
    expect(recorder.calls).toHaveLength(0);
  });

  it('does not call the judge when provider lacks evaluateTargetVerdict', async () => {
    h = await makeTestApp({
      ai: {
        evaluateSentenceCorrection: () =>
          Promise.resolve({ correct: false, feedback: '' }),
      },
    });
    const { headers } = await login('h2-no-method');
    const sid = await start(headers);

    const res = await submit(headers, sid, EX_FB_1, 'swimming');
    expect((res.json as any).correct).toBe(false);
  });
});
