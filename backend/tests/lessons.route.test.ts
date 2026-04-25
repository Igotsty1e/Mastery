import { describe, it, expect } from 'vitest';
import { createApp } from '../src/app';
import type { AiProvider } from '../src/ai/interface';
import { inject } from './helpers/inject';

const LESSON_ID = 'a1b2c3d4-0001-4000-8000-000000000001';
const UNKNOWN_ID = '00000000-0000-4000-8000-000000000099';

const stubAi: AiProvider = { evaluateSentenceCorrection: () => Promise.resolve({ correct: false, feedback: '' }) };
const app = createApp(stubAi);

describe('GET /lessons', () => {
  it('returns 200 with lightweight lesson summaries', async () => {
    const res = await inject(app, { method: 'GET', path: '/lessons' });

    expect(res.status).toBe(200);
    expect(Array.isArray(res.json)).toBe(true);
    expect(res.json).toEqual([
      {
        id: LESSON_ID,
        title: 'The Third Conditional',
        slug: 'the-third-conditional',
        order: 1,
      },
    ]);
  });

  it('returns summary items with only the expected fields', async () => {
    const res = await inject(app, { method: 'GET', path: '/lessons' });

    for (const lesson of res.json as any[]) {
      expect(lesson).toMatchObject({
        id: expect.any(String),
        title: expect.any(String),
        slug: expect.any(String),
        order: expect.any(Number),
      });
      expect(Object.keys(lesson).sort()).toEqual(['id', 'order', 'slug', 'title']);
      expect(lesson).not.toHaveProperty('lesson_id');
      expect(lesson).not.toHaveProperty('language');
      expect(lesson).not.toHaveProperty('level');
      expect(lesson).not.toHaveProperty('intro_rule');
      expect(lesson).not.toHaveProperty('intro_examples');
      expect(lesson).not.toHaveProperty('exercises');
    }
  });
});

describe('GET /lessons/:lessonId', () => {
  it('returns 404 for unknown lesson', async () => {
    const res = await inject(app, { method: 'GET', path: `/lessons/${UNKNOWN_ID}` });
    expect(res.status).toBe(404);
    expect((res.json as any).error).toBe('lesson_not_found');
  });

  it('returns 200 with correct lesson shape', async () => {
    const res = await inject(app, { method: 'GET', path: `/lessons/${LESSON_ID}` });
    expect(res.status).toBe(200);
    expect((res.json as any).lesson_id).toBe(LESSON_ID);
    expect((res.json as any).title).toBe('The Third Conditional');
    expect((res.json as any).language).toBe('en');
    expect((res.json as any).level).toBe('B2');
    expect(typeof (res.json as any).intro_rule).toBe('string');
    expect(Array.isArray((res.json as any).intro_examples)).toBe(true);
    expect(Array.isArray((res.json as any).exercises)).toBe(true);
    expect((res.json as any).exercises).toHaveLength(10);
  });

  it('strips accepted_answers from fill_blank exercises', async () => {
    const res = await inject(app, { method: 'GET', path: `/lessons/${LESSON_ID}` });
    const fillBlanks = (res.json as any).exercises.filter((e: { type: string }) => e.type === 'fill_blank');
    expect(fillBlanks.length).toBeGreaterThan(0);
    for (const ex of fillBlanks) {
      expect(ex).not.toHaveProperty('accepted_answers');
    }
  });

  it('strips correct_option_id from multiple_choice exercises', async () => {
    const res = await inject(app, { method: 'GET', path: `/lessons/${LESSON_ID}` });
    const mc = (res.json as any).exercises.filter((e: { type: string }) => e.type === 'multiple_choice');
    expect(mc.length).toBeGreaterThan(0);
    for (const ex of mc) {
      expect(ex).not.toHaveProperty('correct_option_id');
    }
  });

  it('strips accepted_corrections from sentence_correction exercises', async () => {
    const res = await inject(app, { method: 'GET', path: `/lessons/${LESSON_ID}` });
    const sc = (res.json as any).exercises.filter((e: { type: string }) => e.type === 'sentence_correction');
    expect(sc.length).toBeGreaterThan(0);
    for (const ex of sc) {
      expect(ex).not.toHaveProperty('accepted_corrections');
    }
  });
});
