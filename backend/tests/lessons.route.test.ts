import { describe, it, expect } from 'vitest';
import { createApp } from '../src/app';
import type { AiProvider } from '../src/ai/interface';
import type { Exercise } from '../src/data/lessons';
import { projectExerciseForClient } from '../src/data/exerciseProjection';
import { inject } from './helpers/inject';

const LESSON_ID = 'a1b2c3d4-0001-4000-8000-000000000001';
const LESSON_ID_2 = 'a1b2c3d4-0002-4000-8000-000000000001';
const LESSON_ID_3 = 'a1b2c3d4-0003-4000-8000-000000000001';
const LESSON_ID_4 = 'a1b2c3d4-0004-4000-8000-000000000001';
const LESSON_ID_5 = 'a1b2c3d4-0005-4000-8000-000000000001';
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
        title: 'Verbs Followed by -ing',
        slug: 'verbs-followed-by-ing',
        order: 1,
        total_exercises: 13,
      },
      {
        id: LESSON_ID_2,
        title: 'Present Perfect: Continuous vs Simple',
        slug: 'present-perfect-continuous-vs-simple',
        order: 2,
        total_exercises: 13,
      },
      {
        id: LESSON_ID_3,
        title: 'Verbs Followed by to + Infinitive',
        slug: 'verbs-followed-by-to-infinitive',
        order: 3,
        total_exercises: 13,
      },
      {
        id: LESSON_ID_4,
        title: 'Verbs with a Change in Meaning: -ing vs to + Infinitive',
        slug: 'verbs-with-a-change-in-meaning-ing-vs-to-infinitive',
        order: 4,
        total_exercises: 13,
      },
      {
        id: LESSON_ID_5,
        title: 'Verbs with Both Forms: Little or No Change in Meaning',
        slug: 'verbs-with-both-forms-little-or-no-change-in-meaning',
        order: 5,
        total_exercises: 13,
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
        total_exercises: expect.any(Number),
      });
      expect(Object.keys(lesson).sort()).toEqual(
          ['id', 'order', 'slug', 'title', 'total_exercises']);
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
    expect((res.json as any).title).toBe('Verbs Followed by -ing');
    expect((res.json as any).language).toBe('en');
    expect((res.json as any).level).toBe('B2');
    expect(typeof (res.json as any).intro_rule).toBe('string');
    expect(Array.isArray((res.json as any).intro_examples)).toBe(true);
    expect(Array.isArray((res.json as any).exercises)).toBe(true);
    expect((res.json as any).exercises).toHaveLength(13);
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

  it('passes Wave 1 engine metadata through unchanged when present on the fixture', async () => {
    const res = await inject(app, { method: 'GET', path: `/lessons/${LESSON_ID}` });
    const exercises = (res.json as any).exercises as Array<Record<string, unknown>>;
    const tagged = exercises.filter((e) => 'skill_id' in e);

    // Either the fixture has been backfilled (every tagged exercise must
    // carry the canonical Wave 1 trio) or it has not (no fields present).
    // The route must not invent or drop fields.
    if (tagged.length > 0) {
      for (const ex of tagged) {
        expect(typeof ex.skill_id).toBe('string');
        expect(typeof ex.primary_target_error).toBe('string');
        expect(typeof ex.evidence_tier).toBe('string');
      }
    }
  });
});

describe('projectExerciseForClient (Wave 1 metadata pass-through)', () => {
  it('keeps Wave 1 engine metadata on fill_blank', () => {
    const exercise: Exercise = {
      exercise_id: '00000000-0000-4000-8000-000000000111',
      type: 'fill_blank',
      instruction: 'Fill the blank.',
      prompt: 'I ___ to leave.',
      accepted_answers: ['suggested'],
      skill_id: 'verbs.suggest_ing',
      primary_target_error: 'form_error',
      evidence_tier: 'medium',
    };
    const projected = projectExerciseForClient(exercise) as Record<string, unknown>;
    expect(projected.skill_id).toBe('verbs.suggest_ing');
    expect(projected.primary_target_error).toBe('form_error');
    expect(projected.evidence_tier).toBe('medium');
    expect(projected).not.toHaveProperty('accepted_answers');
  });

  it('keeps Wave 1 engine metadata on multiple_choice', () => {
    const exercise: Exercise = {
      exercise_id: '00000000-0000-4000-8000-000000000112',
      type: 'multiple_choice',
      instruction: 'Choose the correct option.',
      prompt: 'Pick one.',
      options: [
        { id: 'a', text: 'A' },
        { id: 'b', text: 'B' },
      ],
      correct_option_id: 'a',
      skill_id: 'verbs.suggest_ing',
      primary_target_error: 'contrast_error',
      evidence_tier: 'weak',
    };
    const projected = projectExerciseForClient(exercise) as Record<string, unknown>;
    expect(projected.skill_id).toBe('verbs.suggest_ing');
    expect(projected.primary_target_error).toBe('contrast_error');
    expect(projected.evidence_tier).toBe('weak');
    expect(projected).not.toHaveProperty('correct_option_id');
  });

  it('keeps meaning_frame on strongest-tier sentence_correction', () => {
    const exercise: Exercise = {
      exercise_id: '00000000-0000-4000-8000-000000000113',
      type: 'sentence_correction',
      instruction: 'Rewrite the sentence correctly.',
      prompt: 'She suggest to leave.',
      accepted_corrections: ['She suggested leaving.'],
      skill_id: 'verbs.suggest_ing',
      primary_target_error: 'form_error',
      evidence_tier: 'strongest',
      meaning_frame: 'Decline a meeting politely.',
    };
    const projected = projectExerciseForClient(exercise) as Record<string, unknown>;
    expect(projected.evidence_tier).toBe('strongest');
    expect(projected.meaning_frame).toBe('Decline a meeting politely.');
    expect(projected).not.toHaveProperty('accepted_corrections');
  });

  it('keeps Wave 1 engine metadata on listening_discrimination', () => {
    const exercise: Exercise = {
      exercise_id: '00000000-0000-4000-8000-000000000114',
      type: 'listening_discrimination',
      instruction: 'Choose what you heard.',
      audio: {
        url: '/audio/test.mp3',
        voice: 'nova',
        transcript: 'I have been working.',
      },
      options: [
        { id: 'a', text: 'I have been working.' },
        { id: 'b', text: 'I have worked.' },
      ],
      correct_option_id: 'a',
      skill_id: 'tense.present_perfect_continuous',
      primary_target_error: 'contrast_error',
      evidence_tier: 'weak',
    };
    const projected = projectExerciseForClient(exercise) as Record<string, unknown>;
    expect(projected.skill_id).toBe('tense.present_perfect_continuous');
    expect(projected.primary_target_error).toBe('contrast_error');
    expect(projected.evidence_tier).toBe('weak');
    expect(projected).not.toHaveProperty('correct_option_id');
    // Transcript stays on the wire by design (accessibility / Show
    // transcript toggle).
    expect((projected.audio as Record<string, unknown>).transcript).toBe(
      'I have been working.'
    );
  });
});
