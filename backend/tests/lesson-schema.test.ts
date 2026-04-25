import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { LessonSchema } from '../src/data/lessonSchema';

describe('LessonSchema', () => {
  it('parses the shipped lesson fixture', () => {
    const lessonPath = path.resolve(__dirname, '../data/lessons/b2-lesson-001.json');
    const raw = fs.readFileSync(lessonPath, 'utf8');
    const parsed = LessonSchema.safeParse(JSON.parse(raw));
    expect(parsed.success).toBe(true);
  });

  it("rejects fill_blank prompts without exactly one '___'", () => {
    const lesson = {
      lesson_id: '00000000-0000-4000-8000-000000000001',
      title: 'T',
      language: 'en',
      level: 'B2',
      intro_rule: '',
      intro_examples: [],
      exercises: [
        {
          exercise_id: '00000000-0000-4000-8000-000000000011',
          type: 'fill_blank',
          prompt: 'No placeholder here.',
          accepted_answers: ['x'],
        },
      ],
    };

    expect(LessonSchema.safeParse(lesson).success).toBe(false);

    (lesson.exercises[0] as any).prompt = 'Too ___ many ___ placeholders.';
    expect(LessonSchema.safeParse(lesson).success).toBe(false);
  });

  it('rejects multiple_choice with duplicate option ids', () => {
    const lesson = {
      lesson_id: '00000000-0000-4000-8000-000000000001',
      title: 'T',
      language: 'en',
      level: 'B2',
      intro_rule: '',
      intro_examples: [],
      exercises: [
        {
          exercise_id: '00000000-0000-4000-8000-000000000012',
          type: 'multiple_choice',
          prompt: 'Pick one.',
          options: [
            { id: 'a', text: 'A' },
            { id: 'a', text: 'A2' },
          ],
          correct_option_id: 'a',
        },
      ],
    };

    expect(LessonSchema.safeParse(lesson).success).toBe(false);
  });

  it('rejects multiple_choice when correct_option_id is missing from options', () => {
    const lesson = {
      lesson_id: '00000000-0000-4000-8000-000000000001',
      title: 'T',
      language: 'en',
      level: 'B2',
      intro_rule: '',
      intro_examples: [],
      exercises: [
        {
          exercise_id: '00000000-0000-4000-8000-000000000013',
          type: 'multiple_choice',
          prompt: 'Pick one.',
          options: [
            { id: 'a', text: 'A' },
            { id: 'b', text: 'B' },
          ],
          correct_option_id: 'c',
        },
      ],
    };

    expect(LessonSchema.safeParse(lesson).success).toBe(false);
  });

  it('rejects sentence_correction when borderline_ai_fallback is not true', () => {
    const lesson = {
      lesson_id: '00000000-0000-4000-8000-000000000001',
      title: 'T',
      language: 'en',
      level: 'B2',
      intro_rule: '',
      intro_examples: [],
      exercises: [
        {
          exercise_id: '00000000-0000-4000-8000-000000000014',
          type: 'sentence_correction',
          prompt: 'Bad.',
          accepted_corrections: ['Good.'],
          borderline_ai_fallback: false,
        },
      ],
    };

    expect(LessonSchema.safeParse(lesson).success).toBe(false);
  });

  it('rejects lessons with duplicate exercise_id values', () => {
    const lesson = {
      lesson_id: '00000000-0000-4000-8000-000000000001',
      title: 'T',
      language: 'en',
      level: 'B2',
      intro_rule: '',
      intro_examples: [],
      exercises: [
        {
          exercise_id: '00000000-0000-4000-8000-000000000011',
          type: 'fill_blank',
          prompt: 'One ___ placeholder.',
          accepted_answers: ['x'],
        },
        {
          exercise_id: '00000000-0000-4000-8000-000000000011',
          type: 'fill_blank',
          prompt: 'One ___ placeholder.',
          accepted_answers: ['x'],
        },
      ],
    };

    expect(LessonSchema.safeParse(lesson).success).toBe(false);
  });
});

