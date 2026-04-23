import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createApp } from '../src/app';
import type { AiProvider } from '../src/ai/interface';
import { resetMemoryStore } from '../src/store/memory';
import { resetAiRateLimitStore } from '../src/middleware/aiRateLimit';
import { inject } from './helpers/inject';

const LESSON_ID = 'a1b2c3d4-0001-4000-8000-000000000001';
const FB_EX_ID  = 'a1b2c3d4-0001-4000-8000-000000000011'; // fill_blank, accepted: ['had']
const MC_EX_ID  = 'a1b2c3d4-0001-4000-8000-000000000015'; // multiple_choice, correct: 'a'
const SC_EX_ID  = 'a1b2c3d4-0001-4000-8000-000000000018'; // sentence_correction

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

  it('correct answer → correct: true, source: deterministic', async () => {
    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({ user_answer: 'had' }),
    });
    expect(res.status).toBe(200);
    expect((res.json as any).correct).toBe(true);
    expect((res.json as any).evaluation_source).toBe('deterministic');
    expect((res.json as any).feedback).toBeNull();
  });

  it('wrong answer → correct: false', async () => {
    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({ user_answer: 'has' }),
    });
    expect(res.status).toBe(200);
    expect((res.json as any).correct).toBe(false);
    expect((res.json as any).evaluation_source).toBe('deterministic');
  });
});

describe('POST /lessons/:lessonId/answers — multiple_choice', () => {
  const app = createApp(stubAi);
  const body = makeBody({ exercise_id: MC_EX_ID, exercise_type: 'multiple_choice' });

  it('correct option → correct: true', async () => {
    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: { ...body, user_answer: 'a' },
    });
    expect(res.status).toBe(200);
    expect((res.json as any).correct).toBe(true);
  });

  it('wrong option → correct: false', async () => {
    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: { ...body, user_answer: 'b' },
    });
    expect(res.status).toBe(200);
    expect((res.json as any).correct).toBe(false);
  });
});

describe('POST /lessons/:lessonId/answers — sentence_correction via route', () => {
  it('exact accepted → deterministic, no AI called', async () => {
    const ai: AiProvider = { evaluateSentenceCorrection: vi.fn() };
    const app = createApp(ai);
    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({
        exercise_id: SC_EX_ID,
        exercise_type: 'sentence_correction',
        user_answer: 'She has been working at this company for ten years.',
      }),
    });
    expect(res.status).toBe(200);
    expect((res.json as any).correct).toBe(true);
    expect((res.json as any).evaluation_source).toBe('deterministic');
    expect(ai.evaluateSentenceCorrection).not.toHaveBeenCalled();
  });

  it('borderline input → AI called via route', async () => {
    // One-letter typo from accepted answer: "for" → "fo" — but let's use a near miss
    // Accepted: "She has been working at this company for ten years."
    // Close miss: "She has been working at this company fo ten years." (1 char edit)
    const ai: AiProvider = {
      evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: true, feedback: 'Minor typo.' }),
    };
    const app = createApp(ai);
    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({
        exercise_id: SC_EX_ID,
        exercise_type: 'sentence_correction',
        user_answer: 'She has been working at this company fo ten years.',
      }),
    });
    expect(res.status).toBe(200);
    expect(ai.evaluateSentenceCorrection).toHaveBeenCalled();
    expect((res.json as any).evaluation_source).toBe('ai_fallback');
  });

  it('clearly wrong → deterministic false, AI not called', async () => {
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
  });
});

describe('POST /lessons/:lessonId/answers — AI rate limit', () => {
  // Each request with a borderline SC answer triggers one AI call.
  // Near-miss: one-letter typo from the accepted answer.
  const borderlineBody = makeBody({
    exercise_id: SC_EX_ID,
    exercise_type: 'sentence_correction',
    user_answer: 'She has been working at this company fo ten years.',
  });

  it('allows up to 10 AI-triggering requests per IP', async () => {
    const ai: AiProvider = {
      evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: true, feedback: 'ok' }),
    };
    const app = createApp(ai);

    for (let i = 0; i < 10; i++) {
      const res = await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: borderlineBody });
      expect(res.status).toBe(200);
    }
  });

  it('blocks the 11th AI-triggering request with 429', async () => {
    const ai: AiProvider = {
      evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: true, feedback: 'ok' }),
    };
    const app = createApp(ai);

    for (let i = 0; i < 10; i++) {
      await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: borderlineBody });
    }

    const res = await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: borderlineBody });
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
      await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: borderlineBody });
    }

    const res = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({
        exercise_id: SC_EX_ID,
        exercise_type: 'sentence_correction',
        user_answer: 'She has been working at this company for ten years.',
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
      await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: borderlineBody });
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

    // Exhaust the AI rate limit with SC requests
    for (let i = 0; i < 10; i++) {
      await inject(app, { method: 'POST', path: `/lessons/${LESSON_ID}/answers`, json: borderlineBody });
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
