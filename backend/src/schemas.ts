import { z } from 'zod';

export const AnswerRequestSchema = z.object({
  session_id: z.string().uuid(),
  attempt_id: z.string().uuid(),
  exercise_id: z.string().uuid(),
  exercise_type: z.enum([
    'fill_blank',
    'multiple_choice',
    'sentence_correction',
    'sentence_rewrite',
    'short_free_sentence',
    'listening_discrimination',
  ]),
  user_answer: z.string().max(500),
  submitted_at: z.string().datetime(),
});

export type AnswerRequest = z.infer<typeof AnswerRequestSchema>;

export const AiResponseSchema = z.object({
  correct: z.boolean(),
  // Truncate rather than reject: a valid correct verdict must not be lost
  // solely because the model returned slightly more feedback text than expected.
  feedback: z.string().transform(s => s.slice(0, 80)),
});

export type AiResponse = z.infer<typeof AiResponseSchema>;
