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
          instruction: 'Complete the gap with the correct verb form.',
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
          instruction: 'Choose the correct option.',
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
          instruction: 'Choose the correct option.',
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

  it('accepts optional Wave 1 engine metadata when present', () => {
    const lesson = {
      lesson_id: '00000000-0000-4000-8000-000000000001',
      title: 'T',
      language: 'en',
      level: 'B2',
      intro_rule: '',
      intro_examples: [],
      exercises: [
        {
          exercise_id: '00000000-0000-4000-8000-000000000020',
          type: 'fill_blank',
          instruction: 'Complete the gap with the correct verb form.',
          prompt: 'One ___ placeholder.',
          accepted_answers: ['x'],
          skill_id: 'verbs.suggest_ing',
          primary_target_error: 'form_error',
          evidence_tier: 'medium',
        },
      ],
    };

    expect(LessonSchema.safeParse(lesson).success).toBe(true);
  });

  it('treats engine metadata as optional (omitting it still parses)', () => {
    const lesson = {
      lesson_id: '00000000-0000-4000-8000-000000000001',
      title: 'T',
      language: 'en',
      level: 'B2',
      intro_rule: '',
      intro_examples: [],
      exercises: [
        {
          exercise_id: '00000000-0000-4000-8000-000000000021',
          type: 'fill_blank',
          instruction: 'Complete the gap with the correct verb form.',
          prompt: 'One ___ placeholder.',
          accepted_answers: ['x'],
        },
      ],
    };

    expect(LessonSchema.safeParse(lesson).success).toBe(true);
  });

  it('rejects unknown primary_target_error values', () => {
    const lesson = {
      lesson_id: '00000000-0000-4000-8000-000000000001',
      title: 'T',
      language: 'en',
      level: 'B2',
      intro_rule: '',
      intro_examples: [],
      exercises: [
        {
          exercise_id: '00000000-0000-4000-8000-000000000022',
          type: 'fill_blank',
          instruction: 'Complete the gap with the correct verb form.',
          prompt: 'One ___ placeholder.',
          accepted_answers: ['x'],
          primary_target_error: 'spelling_error',
        },
      ],
    };

    expect(LessonSchema.safeParse(lesson).success).toBe(false);
  });

  it('rejects unknown evidence_tier values', () => {
    const lesson = {
      lesson_id: '00000000-0000-4000-8000-000000000001',
      title: 'T',
      language: 'en',
      level: 'B2',
      intro_rule: '',
      intro_examples: [],
      exercises: [
        {
          exercise_id: '00000000-0000-4000-8000-000000000023',
          type: 'fill_blank',
          instruction: 'Complete the gap with the correct verb form.',
          prompt: 'One ___ placeholder.',
          accepted_answers: ['x'],
          evidence_tier: 'super-strong',
        },
      ],
    };

    expect(LessonSchema.safeParse(lesson).success).toBe(false);
  });

  it('requires meaning_frame when evidence_tier is "strongest"', () => {
    const lesson = {
      lesson_id: '00000000-0000-4000-8000-000000000001',
      title: 'T',
      language: 'en',
      level: 'B2',
      intro_rule: '',
      intro_examples: [],
      exercises: [
        {
          exercise_id: '00000000-0000-4000-8000-000000000024',
          type: 'sentence_correction',
          instruction: 'Rewrite the sentence correctly.',
          prompt: 'She suggest to leave.',
          accepted_corrections: ['She suggested leaving.'],
          skill_id: 'verbs.suggest_ing',
          primary_target_error: 'form_error',
          evidence_tier: 'strongest',
        },
      ],
    };

    const fail = LessonSchema.safeParse(lesson);
    expect(fail.success).toBe(false);

    (lesson.exercises[0] as any).meaning_frame =
      'Decline a meeting politely; the rule must serve a request.';
    expect(LessonSchema.safeParse(lesson).success).toBe(true);
  });

  it('does not require meaning_frame when evidence_tier is below strongest', () => {
    const lesson = {
      lesson_id: '00000000-0000-4000-8000-000000000001',
      title: 'T',
      language: 'en',
      level: 'B2',
      intro_rule: '',
      intro_examples: [],
      exercises: [
        {
          exercise_id: '00000000-0000-4000-8000-000000000025',
          type: 'multiple_choice',
          instruction: 'Choose the correct option.',
          prompt: 'Pick one.',
          options: [
            { id: 'a', text: 'A' },
            { id: 'b', text: 'B' },
          ],
          correct_option_id: 'a',
          evidence_tier: 'weak',
        },
      ],
    };

    expect(LessonSchema.safeParse(lesson).success).toBe(true);
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
          instruction: 'Complete the gap with the correct verb form.',
          prompt: 'One ___ placeholder.',
          accepted_answers: ['x'],
        },
        {
          exercise_id: '00000000-0000-4000-8000-000000000011',
          type: 'fill_blank',
          instruction: 'Complete the gap with the correct verb form.',
          prompt: 'One ___ placeholder.',
          accepted_answers: ['x'],
        },
      ],
    };

    expect(LessonSchema.safeParse(lesson).success).toBe(false);
  });

  it('accepts the optional Wave 12 is_diagnostic flag on every exercise type', () => {
    const lesson = {
      lesson_id: '00000000-0000-4000-8000-000000000001',
      title: 'T',
      language: 'en',
      level: 'B2',
      intro_rule: '',
      intro_examples: [],
      exercises: [
        {
          exercise_id: '00000000-0000-4000-8000-000000000020',
          type: 'fill_blank',
          instruction: 'Complete the gap.',
          prompt: 'One ___ placeholder.',
          accepted_answers: ['x'],
          is_diagnostic: true,
        },
        {
          exercise_id: '00000000-0000-4000-8000-000000000021',
          type: 'multiple_choice',
          instruction: 'Choose.',
          prompt: 'Pick one.',
          options: [
            { id: 'a', text: 'A' },
            { id: 'b', text: 'B' },
          ],
          correct_option_id: 'a',
          is_diagnostic: false,
        },
      ],
    };

    const parsed = LessonSchema.safeParse(lesson);
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      const fb = parsed.data.exercises[0];
      const mc = parsed.data.exercises[1];
      expect((fb as { is_diagnostic?: boolean }).is_diagnostic).toBe(true);
      expect((mc as { is_diagnostic?: boolean }).is_diagnostic).toBe(false);
    }
  });

  it('rejects a non-boolean is_diagnostic value', () => {
    const lesson = {
      lesson_id: '00000000-0000-4000-8000-000000000001',
      title: 'T',
      language: 'en',
      level: 'B2',
      intro_rule: '',
      intro_examples: [],
      exercises: [
        {
          exercise_id: '00000000-0000-4000-8000-000000000022',
          type: 'fill_blank',
          instruction: 'Complete the gap.',
          prompt: 'One ___ placeholder.',
          accepted_answers: ['x'],
          is_diagnostic: 'yes',
        },
      ],
    };

    expect(LessonSchema.safeParse(lesson).success).toBe(false);
  });
});
