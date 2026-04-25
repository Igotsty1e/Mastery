import { z } from 'zod';

const LevelSchema = z.enum(['A1', 'A2', 'B1', 'B2', 'C1', 'C2']);

const ExerciseFeedbackSchema = z.object({
  explanation: z.string(),
});

const FillBlankExerciseBaseSchema = z.object({
  exercise_id: z.string().uuid(),
  type: z.literal('fill_blank'),
  instruction: z.string().min(1),
  prompt: z.string(),
  accepted_answers: z.array(z.string()).min(1),
  feedback: ExerciseFeedbackSchema.optional(),
});

const MultipleChoiceOptionSchema = z.object({
  id: z.enum(['a', 'b', 'c', 'd']),
  text: z.string(),
});

const MultipleChoiceExerciseBaseSchema = z.object({
  exercise_id: z.string().uuid(),
  type: z.literal('multiple_choice'),
  instruction: z.string().min(1),
  prompt: z.string(),
  options: z.array(MultipleChoiceOptionSchema).min(2).max(4),
  correct_option_id: z.enum(['a', 'b', 'c', 'd']),
  feedback: ExerciseFeedbackSchema.optional(),
});

const SentenceCorrectionExerciseBaseSchema = z.object({
  exercise_id: z.string().uuid(),
  type: z.literal('sentence_correction'),
  instruction: z.string().min(1),
  prompt: z.string(),
  accepted_corrections: z.array(z.string()).min(1),
  borderline_ai_fallback: z.literal(true),
  feedback: ExerciseFeedbackSchema.optional(),
});

const ExerciseBaseSchema = z.discriminatedUnion('type', [
  FillBlankExerciseBaseSchema,
  MultipleChoiceExerciseBaseSchema,
  SentenceCorrectionExerciseBaseSchema,
]);

export const ExerciseSchema = ExerciseBaseSchema.superRefine((value, ctx) => {
  if (value.type === 'fill_blank') {
    const count = value.prompt.split('___').length - 1;
    if (count !== 1) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "fill_blank.prompt must contain exactly one '___' placeholder",
        path: ['prompt'],
      });
    }
  }

  if (value.type === 'multiple_choice') {
    const ids = value.options.map((o) => o.id);
    const uniqueIds = new Set(ids);
    if (uniqueIds.size !== ids.length) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'multiple_choice.options must not contain duplicate ids',
        path: ['options'],
      });
    }

    if (!uniqueIds.has(value.correct_option_id)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'multiple_choice.correct_option_id must match an option id',
        path: ['correct_option_id'],
      });
    }
  }
});

export const LessonSchema = z
  .object({
    lesson_id: z.string().uuid(),
    title: z.string(),
    language: z.string(),
    level: LevelSchema,
    intro_rule: z.string(),
    intro_examples: z.array(z.string()),
    exercises: z.array(ExerciseSchema).min(1),
  })
  .superRefine((value, ctx) => {
    const ids = value.exercises.map((e) => e.exercise_id);
    const unique = new Set(ids);
    if (unique.size !== ids.length) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'lesson.exercises contains duplicate exercise_id values',
        path: ['exercises'],
      });
    }
  });

export type Lesson = z.infer<typeof LessonSchema>;
export type Exercise = z.infer<typeof ExerciseSchema>;
