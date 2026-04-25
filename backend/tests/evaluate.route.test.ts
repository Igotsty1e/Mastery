import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createApp } from '../src/app';
import type { AiProvider } from '../src/ai/interface';
import { resetMemoryStore } from '../src/store/memory';
import { resetAiRateLimitStore } from '../src/middleware/aiRateLimit';
import { inject } from './helpers/inject';

const LESSON_ID = 'a1b2c3d4-0001-4000-8000-000000000001';
const FB_EX_ID  = 'a1b2c3d4-0001-4000-8000-000000000021'; // fill_blank, accepted: ['had']
const MC_EX_ID  = 'a1b2c3d4-0001-4000-8000-000000000025'; // multiple_choice, correct: 'b'
const SC_EX_ID  = 'a1b2c3d4-0001-4000-8000-000000000028'; // sentence_correction

const ATTEMPT_ID  = '00000000-0000-4000-8000-000000000002';
const SUBMITTED   = '2026-01-01T00:00:00.000Z';

const SESSION_ID = '11111111-0001-4000-8000-000000000001';

function makeBody(overrides: Record<string, unknown> = {}) {
  return {
    session_id: SESSION_ID,
    attempt_id: ATTEMPT_ID,
    exercise_id: FB_EX_ID,
    exercise_type: 'fill_blank',
    user_answer: 'had',
    submitted_at: SUBMITTED,
    ...overrides,
  };
}

const stubAi: AiProvider = { evaluateSentenceCorrection: vi.fn() };
beforeEach(() => { resetMemoryStore(); resetAiRateLimitStore(); });

describe('POST /lessons/:lessonId/answers — input validation', () => {
  const app = createApp(stubAi);

  it('returns 400 for empty body', async () => {
    const res = await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: {} });
    expect(res.status).toBe(400);
    expect((res.json as any).error).toBe('invalid_payload');
  });

  it('returns 400 when attempt_id is not a UUID', async () => {
    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({ attempt_id: 'not-a-uuid' }),
    });
    expect(res.status).toBe(400);
    expect((res.json as any).error).toBe('invalid_payload');
  });

  it('returns 400 when exercise_type is unknown', async () => {
    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({ exercise_type: 'unknown_type' }),
    });
    expect(res.status).toBe(400);
    expect((res.json as any).error).toBe('invalid_payload');
  });

  it('returns 400 when user_answer exceeds 500 chars', async () => {
    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({ user_answer: 'a'.repeat(501) }),
    });
    expect(res.status).toBe(400);
    expect((res.json as any).error).toBe('invalid_payload');
  });
});

describe('POST /lessons/:lessonId/answers — 404 paths', () => {
  const app = createApp(stubAi);

  it('returns 404 for unknown lesson_id', async () => {
    const res = await inject(app, {
      method: 'POST',
      path: '/lessons/00000000-0000-4000-8000-000000000099/answers',
      json: makeBody(),
    });
    expect(res.status).toBe(404);
    expect((res.json as any).error).toBe('lesson_not_found');
  });

  it('returns 404 for unknown exercise_id in known lesson', async () => {
    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({ exercise_id: '00000000-0000-4000-8000-000000000099' }),
    });
    expect(res.status).toBe(404);
    expect((res.json as any).error).toBe('exercise_not_found');
  });
});

describe('POST /lessons/:lessonId/answers — fill_blank', () => {
  const app = createApp(stubAi);

  it('correct answer → correct: true, source: deterministic, no feedback', async () => {
    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({ user_answer: 'had' }),
    });
    expect(res.status).toBe(200);
    expect((res.json as any).correct).toBe(true);
    expect((res.json as any).evaluation_source).toBe('deterministic');
    expect((res.json as any).explanation).toBeNull();
  });

  it('wrong answer → correct: false, explanation populated', async () => {
    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({ user_answer: 'has' }),
    });
    expect(res.status).toBe(200);
    expect((res.json as any).correct).toBe(false);
    expect((res.json as any).evaluation_source).toBe('deterministic');
    expect(typeof (res.json as any).explanation).toBe('string');
    expect((res.json as any).explanation!.length).toBeGreaterThan(0);
  });
});

describe('POST /lessons/:lessonId/answers — multiple_choice', () => {
  const app = createApp(stubAi);
  const body = makeBody({ exercise_id: MC_EX_ID, exercise_type: 'multiple_choice' });

  it('correct option → correct: true', async () => {
    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: { ...body, user_answer: 'b' },
    });
    expect(res.status).toBe(200);
    expect((res.json as any).correct).toBe(true);
  });

  it('wrong option → correct: false, explanation populated', async () => {
    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: { ...body, user_answer: 'a' },
    });
    expect(res.status).toBe(200);
    expect((res.json as any).correct).toBe(false);
    expect(typeof (res.json as any).explanation).toBe('string');
    expect((res.json as any).explanation!.length).toBeGreaterThan(0);
  });
});

describe('POST /lessons/:lessonId/answers — sentence_correction via route', () => {
  it('exact accepted → deterministic, no AI called, no feedback', async () => {
    const ai: AiProvider = { evaluateSentenceCorrection: vi.fn() };
    const app = createApp(ai);
    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({
        exercise_id: SC_EX_ID,
        exercise_type: 'sentence_correction',
        user_answer: 'If I had known you were coming, I would have cooked dinner.',
      }),
    });
    expect(res.status).toBe(200);
    expect((res.json as any).correct).toBe(true);
    expect((res.json as any).evaluation_source).toBe('deterministic');
    expect((res.json as any).explanation).toBeNull();
    expect(ai.evaluateSentenceCorrection).not.toHaveBeenCalled();
  });

  it('borderline input → AI called via route, explanation from exercise data', async () => {
    // One-letter typo from accepted answer: 'dinner' → 'diner'
    const ai: AiProvider = {
      evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: false, feedback: 'Minor typo.' }),
    };
    const app = createApp(ai);
    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({
        exercise_id: SC_EX_ID,
        exercise_type: 'sentence_correction',
        user_answer: 'If I had known you were coming, I would have cooked diner.',
      }),
    });
    expect(res.status).toBe(200);
    expect(ai.evaluateSentenceCorrection).toHaveBeenCalled();
    expect((res.json as any).evaluation_source).toBe('ai_fallback');
    // explanation comes from exercise.feedback.explanation, not AI feedback
    expect(typeof (res.json as any).explanation).toBe('string');
  });

  it('clearly wrong → deterministic false, AI not called, explanation from exercise', async () => {
    const ai: AiProvider = { evaluateSentenceCorrection: vi.fn() };
    const app = createApp(ai);
    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({
        exercise_id: SC_EX_ID,
        exercise_type: 'sentence_correction',
        user_answer: 'Completely wrong sentence about something else entirely.',
      }),
    });
    expect(res.status).toBe(200);
    expect((res.json as any).correct).toBe(false);
    expect((res.json as any).evaluation_source).toBe('deterministic');
    expect(ai.evaluateSentenceCorrection).not.toHaveBeenCalled();
    expect(typeof (res.json as any).explanation).toBe('string');
    expect((res.json as any).explanation!.length).toBeGreaterThan(0);
  });
});

describe('POST /lessons/:lessonId/answers — AI rate limit', () => {
  // Each request with a borderline SC answer triggers one AI call.
  // Near-miss: one-letter typo from the accepted answer ('dinner' → 'diner').
  const BORDERLINE_ANSWER = 'If I had known you were coming, I would have cooked diner.';
  const borderlineBody = makeBody({
    exercise_id: SC_EX_ID,
    exercise_type: 'sentence_correction',
    user_answer: BORDERLINE_ANSWER,
  });

  // Generates a borderline body with a unique session ID so each call is a
  // cache miss and counts as a distinct AI call toward the rate limit.
  function uniqueSessionBorderlineBody(i: number) {
    const sessionId = `11111111-${String(i + 1).padStart(4, '0')}-4000-8000-000000000099`;
    return { ...borderlineBody, session_id: sessionId };
  }

  it('allows up to 10 AI-triggering requests per IP', async () => {
    const ai: AiProvider = {
      evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: true, feedback: 'ok' }),
    };
    const app = createApp(ai);

    for (let i = 0; i < 10; i++) {
      const res = await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: uniqueSessionBorderlineBody(i) });
      expect(res.status).toBe(200);
    }
  });

  it('blocks the 11th AI-triggering request with 429', async () => {
    const ai: AiProvider = {
      evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: true, feedback: 'ok' }),
    };
    const app = createApp(ai);

    for (let i = 0; i < 10; i++) {
      await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: uniqueSessionBorderlineBody(i) });
    }

    const res = await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: uniqueSessionBorderlineBody(10) });
    expect(res.status).toBe(429);
    expect((res.json as any).error).toBe('rate_limit_exceeded');
    expect(ai.evaluateSentenceCorrection).toHaveBeenCalledTimes(10);
  });

  it('does not 429 exact accepted sentence_correction after AI limit is exhausted', async () => {
    const ai: AiProvider = {
      evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: true, feedback: 'ok' }),
    };
    const app = createApp(ai);

    for (let i = 0; i < 10; i++) {
      await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: uniqueSessionBorderlineBody(i) });
    }

    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({
        exercise_id: SC_EX_ID,
        exercise_type: 'sentence_correction',
        user_answer: 'If I had known you were coming, I would have cooked dinner.',
      }),
    });

    expect(res.status).toBe(200);
    expect((res.json as any).correct).toBe(true);
    expect((res.json as any).evaluation_source).toBe('deterministic');
    expect(ai.evaluateSentenceCorrection).toHaveBeenCalledTimes(10);
  });

  it('does not 429 clearly wrong sentence_correction after AI limit is exhausted', async () => {
    const ai: AiProvider = {
      evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: true, feedback: 'ok' }),
    };
    const app = createApp(ai);

    for (let i = 0; i < 10; i++) {
      await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: uniqueSessionBorderlineBody(i) });
    }

    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({
        exercise_id: SC_EX_ID,
        exercise_type: 'sentence_correction',
        user_answer: 'Completely wrong sentence about something else entirely.',
      }),
    });

    expect(res.status).toBe(200);
    expect((res.json as any).correct).toBe(false);
    expect((res.json as any).evaluation_source).toBe('deterministic');
    expect(ai.evaluateSentenceCorrection).toHaveBeenCalledTimes(10);
  });

  it('does not rate-limit fill_blank or multiple_choice (no AI involved)', async () => {
    const ai: AiProvider = { evaluateSentenceCorrection: vi.fn() };
    const app = createApp(ai);

    // Exhaust the AI rate limit with SC requests (unique sessions to bypass cache)
    for (let i = 0; i < 10; i++) {
      await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: uniqueSessionBorderlineBody(i) });
    }

    // fill_blank must still work
    const fbRes = await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: makeBody({ user_answer: 'had' }) });
    expect(fbRes.status).toBe(200);

    // multiple_choice must still work
    const mcRes = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({ exercise_id: MC_EX_ID, exercise_type: 'multiple_choice', user_answer: 'a' }),
    });
    expect(mcRes.status).toBe(200);
  });
});

describe('POST /lessons/:lessonId/answers — AI result cache (identical resubmit)', () => {
  const borderlineAnswer = 'If I had known you were coming, I would have cooked diner.';
  const borderlineBody = makeBody({
    exercise_id: SC_EX_ID,
    exercise_type: 'sentence_correction',
    user_answer: borderlineAnswer,
  });

  it('identical resubmit within same session calls AI only once', async () => {
    const ai: AiProvider = {
      evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: true, feedback: 'Minor typo.' }),
    };
    const app = createApp(ai);

    const res1 = await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: borderlineBody });
    const res2 = await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: borderlineBody });
    const res3 = await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: borderlineBody });

    expect(res1.status).toBe(200);
    expect(res2.status).toBe(200);
    expect(res3.status).toBe(200);
    expect((res1.json as any).correct).toBe(true);
    expect((res2.json as any).correct).toBe(true);
    expect((res3.json as any).correct).toBe(true);
    expect((res1.json as any).evaluation_source).toBe('ai_fallback');
    expect((res2.json as any).evaluation_source).toBe('ai_fallback');
    expect((res3.json as any).evaluation_source).toBe('ai_fallback');
    // AI must be called exactly once — subsequent identical submissions hit the cache
    expect(ai.evaluateSentenceCorrection).toHaveBeenCalledTimes(1);
  });

  it('identical answer with different whitespace/casing hits cache (normalised)', async () => {
    const ai: AiProvider = {
      evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: true, feedback: 'ok' }),
    };
    const app = createApp(ai);

    // First call with normalised form
    await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: borderlineBody });
    // Second call with leading/trailing whitespace — normalises to same key
    const res2 = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: { ...borderlineBody, user_answer: `  ${borderlineAnswer}  ` },
    });

    expect(res2.status).toBe(200);
    expect(ai.evaluateSentenceCorrection).toHaveBeenCalledTimes(1);
  });

  it('different answer in same session calls AI again', async () => {
    const ai: AiProvider = {
      evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: false, feedback: 'Not quite.' }),
    };
    const app = createApp(ai);

    await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: borderlineBody });
    // Slightly different borderline answer: drop 'n' from 'known' rather than from 'dinner'
    const differentBody = { ...borderlineBody, user_answer: 'If I had know you were coming, I would have cooked dinner.' };
    await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: differentBody });

    expect(ai.evaluateSentenceCorrection).toHaveBeenCalledTimes(2);
  });

  it('same answer in different sessions calls AI per session', async () => {
    const ai: AiProvider = {
      evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: true, feedback: 'ok' }),
    };
    const app = createApp(ai);

    const session2 = '22222222-0002-4000-8000-000000000002';
    await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: borderlineBody });
    await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: { ...borderlineBody, session_id: session2 },
    });

    // Different sessions = different cache buckets = 2 AI calls
    expect(ai.evaluateSentenceCorrection).toHaveBeenCalledTimes(2);
  });

  it('cached resubmit does not consume rate limit quota', async () => {
    const ai: AiProvider = {
      evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: true, feedback: 'ok' }),
    };
    const app = createApp(ai);

    // First call consumes 1 quota unit
    await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: borderlineBody });

    // 9 more identical resubmits (all cache hits — no rate limit consumed)
    for (let i = 0; i < 9; i++) {
      const res = await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: borderlineBody });
      expect(res.status).toBe(200);
    }

    // AI only called once; rate limit only charged once
    expect(ai.evaluateSentenceCorrection).toHaveBeenCalledTimes(1);
  });
});
