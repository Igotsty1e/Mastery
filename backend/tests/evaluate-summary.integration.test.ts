/**
 * Integration: POST /lessons/:id/answers → GET /lessons/:id/result
 *
 * Validates that result output reflects what the answers route stored.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createApp } from '../src/app';
import type { AiProvider } from '../src/ai/interface';
import { resetMemoryStore } from '../src/store/memory';
import { inject } from './helpers/inject';

const LESSON_ID = 'a1b2c3d4-0001-4000-8000-000000000001';
const FB_EX_ID  = 'a1b2c3d4-0001-4000-8000-000000000011'; // fill_blank, accepted: ['had']
const MC_EX_ID  = 'a1b2c3d4-0001-4000-8000-000000000015'; // multiple_choice, correct: 'a'
const SC_EX_ID  = 'a1b2c3d4-0001-4000-8000-000000000018'; // sentence_correction, accepted: ['She has been working at this company for ten years.']
const SESSION_ID = 'dddddddd-0001-4000-8000-000000000001';
const ATTEMPT_1 = 'cccccccc-0001-4000-8000-000000000001';
const ATTEMPT_2 = 'cccccccc-0001-4000-8000-000000000002';
const ATTEMPT_3 = 'cccccccc-0001-4000-8000-000000000003';
const SUBMITTED = '2026-01-01T00:00:00.000Z';
// Borderline SC answer: 1-char edit from accepted after normalize (drops "r" in "for")
const SC_BORDERLINE = 'She has been working at this company fo ten years.';

function answerBody(overrides: Record<string, unknown> = {}) {
  return {
    session_id: SESSION_ID,
    attempt_id: ATTEMPT_1,
    exercise_id: FB_EX_ID,
    exercise_type: 'fill_blank',
    user_answer: 'had',
    submitted_at: SUBMITTED,
    ...overrides,
  };
}

const stubAi: AiProvider = { evaluateSentenceCorrection: vi.fn() };
const app = createApp(stubAi);

beforeEach(() => resetMemoryStore());

describe('integration: POST /lessons/:id/answers → GET /lessons/:id/result', () => {
  it('single correct attempt → result shows correct_count=1', async () => {
    const evalRes = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: answerBody({ attempt_id: ATTEMPT_1, user_answer: 'had' }),
    });
    expect(evalRes.status).toBe(200);
    expect((evalRes.json as any).correct).toBe(true);

    const res = await inject(app, { method: 'GET', path: `/lessons/${LESSON_ID}/result?session_id=${SESSION_ID}` });
    expect(res.status).toBe(200);
    expect((res.json as any).lesson_id).toBe(LESSON_ID);
    expect((res.json as any).total_exercises).toBe(10);
    expect((res.json as any).correct_count).toBe(1);
    expect((res.json as any).answers).toContainEqual(expect.objectContaining({ exercise_id: FB_EX_ID, correct: true }));
  });

  it('AI-fallback sentence_correction affects result count', async () => {
    const aiCorrect: AiProvider = {
      evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: true, feedback: 'Almost perfect.' }),
    };
    const aiApp = createApp(aiCorrect);

    const evalRes = await inject(aiApp, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: answerBody({
        attempt_id: ATTEMPT_3,
        exercise_id: SC_EX_ID,
        exercise_type: 'sentence_correction',
        user_answer: SC_BORDERLINE,
      }),
    });
    expect(evalRes.status).toBe(200);
    expect((evalRes.json as any).correct).toBe(true);
    expect((evalRes.json as any).evaluation_source).toBe('ai_fallback');
    expect(aiCorrect.evaluateSentenceCorrection).toHaveBeenCalled();

    const res = await inject(aiApp, { method: 'GET', path: `/lessons/${LESSON_ID}/result?session_id=${SESSION_ID}` });
    expect(res.status).toBe(200);
    expect((res.json as any).correct_count).toBe(1);
    expect((res.json as any).answers).toContainEqual(expect.objectContaining({ exercise_id: SC_EX_ID, correct: true }));
  });

  it('re-submit same exercise_id: last attempt wins', async () => {
    await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: answerBody({
        attempt_id: ATTEMPT_1,
        exercise_id: FB_EX_ID,
        exercise_type: 'fill_blank',
        user_answer: 'has',
      }),
    });

    await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: answerBody({
        attempt_id: ATTEMPT_2,
        exercise_id: FB_EX_ID,
        exercise_type: 'fill_blank',
        user_answer: 'had',
      }),
    });

    const res = await inject(app, { method: 'GET', path: `/lessons/${LESSON_ID}/result?session_id=${SESSION_ID}` });
    expect(res.status).toBe(200);
    expect((res.json as any).answers).toHaveLength(1);
    expect((res.json as any).correct_count).toBe(1);
    expect((res.json as any).answers[0]).toMatchObject({ exercise_id: FB_EX_ID, correct: true });
  });
});
