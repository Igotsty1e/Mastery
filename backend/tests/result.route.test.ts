import { describe, it, expect, beforeEach, vi } from 'vitest';
import { createApp } from '../src/app';
import type { AiProvider } from '../src/ai/interface';
import { resetMemoryStore } from '../src/store/memory';
import { inject } from './helpers/inject';

const LESSON_ID = 'a1b2c3d4-0001-4000-8000-000000000001';
const EX_11 = 'a1b2c3d4-0001-4000-8000-000000000011'; // fill_blank
const EX_15 = 'a1b2c3d4-0001-4000-8000-000000000015'; // multiple_choice
const EX_18 = 'a1b2c3d4-0001-4000-8000-000000000018'; // sentence_correction

const SESSION_A = 'aaaaaaaa-0001-4000-8000-000000000001';
const SESSION_B = 'bbbbbbbb-0001-4000-8000-000000000001';

const stubAi: AiProvider = { evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: false, feedback: '' }) };
const app = createApp(stubAi);

const SUBMITTED = '2026-01-01T00:00:00.000Z';

function makeBody(overrides: Record<string, unknown> = {}) {
  return {
    session_id: SESSION_A,
    attempt_id: 'cccccccc-0001-4000-8000-000000000001',
    exercise_id: EX_11,
    exercise_type: 'fill_blank',
    user_answer: 'had',
    submitted_at: SUBMITTED,
    ...overrides,
  };
}

beforeEach(() => resetMemoryStore());

describe('GET /lessons/:lessonId/result', () => {
  it('returns 404 for unknown lesson', async () => {
    const res = await inject(app, {
      method: 'GET',
      path: '/lessons/00000000-0000-4000-8000-000000000099/result',
    });
    expect(res.status).toBe(404);
    expect((res.json as any).error).toBe('lesson_not_found');
  });

  it('returns 200 with empty answers when no attempts recorded', async () => {
    const res = await inject(app, { method: 'GET', path: `/lessons/${LESSON_ID}/result?session_id=${SESSION_A}` });
    expect(res.status).toBe(200);
    expect((res.json as any).lesson_id).toBe(LESSON_ID);
    expect((res.json as any).total_exercises).toBe(10); // lesson has 10 exercises
    expect((res.json as any).correct_count).toBe(0);
    expect((res.json as any).answers).toHaveLength(0);
  });

  it('aggregates attempts recorded via /answers', async () => {
    const eval1 = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({
        attempt_id: 'cccccccc-0001-4000-8000-000000000002',
        exercise_id: EX_11,
        exercise_type: 'fill_blank',
        user_answer: 'had',
      }),
    });
    expect(eval1.status).toBe(200);
    expect((eval1.json as any).correct).toBe(true);

    const eval2 = await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({
        attempt_id: 'cccccccc-0001-4000-8000-000000000003',
        exercise_id: EX_15,
        exercise_type: 'multiple_choice',
        user_answer: 'b',
      }),
    });
    expect(eval2.status).toBe(200);
    expect((eval2.json as any).correct).toBe(false);

    const res = await inject(app, { method: 'GET', path: `/lessons/${LESSON_ID}/result?session_id=${SESSION_A}` });
    expect(res.status).toBe(200);
    expect((res.json as any).correct_count).toBe(1);
    expect((res.json as any).total_exercises).toBe(10);
    expect((res.json as any).answers).toHaveLength(2);
    expect((res.json as any).answers).toContainEqual(expect.objectContaining({ exercise_id: EX_11, correct: true }));
    expect((res.json as any).answers).toContainEqual(expect.objectContaining({ exercise_id: EX_15, correct: false }));
  });

  it('re-submit same exercise_id: last attempt wins', async () => {
    await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({
        attempt_id: 'cccccccc-0001-4000-8000-000000000004',
        exercise_id: EX_11,
        exercise_type: 'fill_blank',
        user_answer: 'has',
      }),
    });

    await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({
        attempt_id: 'cccccccc-0001-4000-8000-000000000005',
        exercise_id: EX_11,
        exercise_type: 'fill_blank',
        user_answer: 'had',
      }),
    });

    const res = await inject(app, { method: 'GET', path: `/lessons/${LESSON_ID}/result?session_id=${SESSION_A}` });
    expect(res.status).toBe(200);
    expect((res.json as any).answers).toHaveLength(1);
    expect((res.json as any).correct_count).toBe(1);
    expect((res.json as any).answers[0]).toMatchObject({ exercise_id: EX_11, correct: true });
  });

  it('enriches answers with prompt, canonical_answer, explanation, practical_tip', async () => {
    // Correct answer — explanation and practical_tip should be null
    await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({
        attempt_id: 'cccccccc-0001-4000-8000-000000000007',
        exercise_id: EX_11,
        exercise_type: 'fill_blank',
        user_answer: 'had',
      }),
    });
    // Wrong answer — explanation and practical_tip should be populated
    await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({
        attempt_id: 'cccccccc-0001-4000-8000-000000000008',
        exercise_id: EX_15,
        exercise_type: 'multiple_choice',
        user_answer: 'b',
      }),
    });

    const res = await inject(app, { method: 'GET', path: `/lessons/${LESSON_ID}/result?session_id=${SESSION_A}` });
    expect(res.status).toBe(200);
    const answers = (res.json as any).answers;

    const correctAnswer = answers.find((a: any) => a.exercise_id === EX_11);
    expect(correctAnswer.correct).toBe(true);
    expect(correctAnswer.prompt).toBeTruthy();
    expect(correctAnswer.canonical_answer).toBe('had');
    expect(correctAnswer.explanation).toBeNull();
    expect(correctAnswer.practical_tip).toBeNull();

    const wrongAnswer = answers.find((a: any) => a.exercise_id === EX_15);
    expect(wrongAnswer.correct).toBe(false);
    expect(wrongAnswer.prompt).toBeTruthy();
    expect(wrongAnswer.canonical_answer).toBeTruthy();
    expect(wrongAnswer.explanation).toBeTruthy();
    expect(wrongAnswer.practical_tip).toBeTruthy();
  });

  it('returns conclusion string', async () => {
    // Perfect score
    await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({
        attempt_id: 'cccccccc-0001-4000-8000-000000000009',
        exercise_id: EX_11,
        exercise_type: 'fill_blank',
        user_answer: 'had',
      }),
    });
    const res = await inject(app, { method: 'GET', path: `/lessons/${LESSON_ID}/result?session_id=${SESSION_A}` });
    expect(res.status).toBe(200);
    expect(typeof (res.json as any).conclusion).toBe('string');
    expect((res.json as any).conclusion.length).toBeGreaterThan(0);
  });

  it('session isolation: session B cannot see session A attempts', async () => {
    await inject(app, {
      method: 'POST',
      path: `/lessons/${LESSON_ID}/answers`,
      json: makeBody({ session_id: SESSION_A, attempt_id: 'cccccccc-0001-4000-8000-000000000006' }),
    });

    const resB = await inject(app, { method: 'GET', path: `/lessons/${LESSON_ID}/result?session_id=${SESSION_B}` });
    expect(resB.status).toBe(200);
    expect((resB.json as any).correct_count).toBe(0);
    expect((resB.json as any).answers).toHaveLength(0);

    const resA = await inject(app, { method: 'GET', path: `/lessons/${LESSON_ID}/result?session_id=${SESSION_A}` });
    expect(resA.status).toBe(200);
    expect((resA.json as any).answers).toHaveLength(1);
  });
});
