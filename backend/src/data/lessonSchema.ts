import { z } from 'zod';

const LevelSchema = z.enum(['A1', 'A2', 'B1', 'B2', 'C1', 'C2']);

const ExerciseFeedbackSchema = z.object({
  explanation: z.string(),
});

// Learning Engine Wave 1 metadata (additive). Every field is optional during
// the Wave 1 backfill; meaning_frame becomes required when evidence_tier is
// "strongest" (LEARNING_ENGINE.md §6.5). Runtime ignores these fields beyond
// validation; GET /lessons/:lessonId passes them through unchanged so the
// future Mastery Model + Decision Engine waves can consume them.
// Wave 10: error model 6→4. `transfer_error` and `pragmatic_error`
// removed; neither was referenced by any shipped lesson JSON, so the
// drop is a clean break with no content rewrite.
export const TargetErrorSchema = z.enum([
  'conceptual_error',
  'form_error',
  'contrast_error',
  'careless_error',
]);

export const EvidenceTierSchema = z.enum(['weak', 'medium', 'strong', 'strongest']);

const EngineMetadataShape = {
  skill_id: z.string().min(1).optional(),
  primary_target_error: TargetErrorSchema.optional(),
  evidence_tier: EvidenceTierSchema.optional(),
  meaning_frame: z.string().min(1).optional(),
  // Wave 12 — items eligible for the diagnostic probe (LEARNING_ENGINE.md
  // §10, V1 spec §15). Optional and defaults to `false`. Diagnostic items
  // also serve in regular sessions; the flag is purely about probe
  // eligibility, not about exclusion from the main bank.
  is_diagnostic: z.boolean().optional(),
};

// Visual Context Layer per exercise_structure.md §2.9. Authoring metadata
// (brief / dont_show / risk) lives inline so authors edit one file; the route
// layer strips authoring-only fields before sending the public payload.
export const ExerciseImageSchema = z.object({
  url: z.string().min(1),
  alt: z.string().min(1),
  role: z.enum([
    'scene_setting',
    'context_support',
    'disambiguation',
    'listening_support',
  ]),
  policy: z.enum(['optional', 'recommended', 'required']),
  brief: z.string().min(1).optional(),
  dont_show: z.string().optional(),
  risk: z.enum(['low', 'medium', 'high']).optional(),
});

const FillBlankExerciseBaseSchema = z.object({
  exercise_id: z.string().uuid(),
  type: z.literal('fill_blank'),
  instruction: z.string().min(1),
  prompt: z.string(),
  accepted_answers: z.array(z.string()).min(1),
  image: ExerciseImageSchema.optional(),
  feedback: ExerciseFeedbackSchema.optional(),
  ...EngineMetadataShape,
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
  image: ExerciseImageSchema.optional(),
  feedback: ExerciseFeedbackSchema.optional(),
  ...EngineMetadataShape,
});

const SentenceCorrectionExerciseBaseSchema = z.object({
  exercise_id: z.string().uuid(),
  type: z.literal('sentence_correction'),
  instruction: z.string().min(1),
  prompt: z.string(),
  accepted_corrections: z.array(z.string()).min(1),
  image: ExerciseImageSchema.optional(),
  feedback: ExerciseFeedbackSchema.optional(),
  ...EngineMetadataShape,
});

// Wave 14.2 — V1.5 open-answer family, phase 1.
//
// `sentence_rewrite` asks the learner to rewrite the prompt under a
// transformation constraint stated in `instruction` (e.g. "Rewrite
// using past perfect"). Unlike `sentence_correction`, the prompt is
// not malformed — it's a correct sentence that must be transformed
// into another correct shape. `accepted_answers` lists the canonical
// post-rewrite variants; the runtime mirrors the `sentence_correction`
// evaluator (deterministic match → AI fallback) so the operational
// surface stays identical.
//
// `short_free_sentence` is intentionally NOT in this slice. Its
// evaluator is fundamentally different (rule-conformance, not match
// against canonical variants) and ships in a follow-up wave.
const SentenceRewriteExerciseBaseSchema = z.object({
  exercise_id: z.string().uuid(),
  type: z.literal('sentence_rewrite'),
  instruction: z.string().min(1),
  prompt: z.string().min(1),
  accepted_answers: z.array(z.string().min(1)).min(1),
  image: ExerciseImageSchema.optional(),
  feedback: ExerciseFeedbackSchema.optional(),
  ...EngineMetadataShape,
});

const VoiceSchema = z.enum(['nova', 'onyx']);

const ExerciseAudioSchema = z.object({
  url: z.string().min(1),
  voice: VoiceSchema,
  transcript: z.string().min(1),
});

const ListeningDiscriminationExerciseBaseSchema = z.object({
  exercise_id: z.string().uuid(),
  type: z.literal('listening_discrimination'),
  instruction: z.string().min(1),
  audio: ExerciseAudioSchema,
  options: z.array(MultipleChoiceOptionSchema).min(2).max(4),
  correct_option_id: z.enum(['a', 'b', 'c', 'd']),
  image: ExerciseImageSchema.optional(),
  feedback: ExerciseFeedbackSchema.optional(),
  ...EngineMetadataShape,
});

const ExerciseBaseSchema = z.discriminatedUnion('type', [
  FillBlankExerciseBaseSchema,
  MultipleChoiceExerciseBaseSchema,
  SentenceCorrectionExerciseBaseSchema,
  SentenceRewriteExerciseBaseSchema,
  ListeningDiscriminationExerciseBaseSchema,
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

  if (value.type === 'listening_discrimination') {
    const ids = value.options.map((o) => o.id);
    const uniqueIds = new Set(ids);
    if (uniqueIds.size !== ids.length) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'listening_discrimination.options must not contain duplicate ids',
        path: ['options'],
      });
    }

    if (!uniqueIds.has(value.correct_option_id)) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: 'listening_discrimination.correct_option_id must match an option id',
        path: ['correct_option_id'],
      });
    }

    const correctOption = value.options.find(o => o.id === value.correct_option_id);
    if (correctOption && correctOption.text.trim() !== value.audio.transcript.trim()) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message:
          'listening_discrimination.audio.transcript must match the correct option text',
        path: ['audio', 'transcript'],
      });
    }
  }

  // LEARNING_ENGINE.md §6.5: strongest-tier items must declare a
  // meaning_frame. The field is optional for every other tier and is
  // optional in the absence of evidence_tier (Wave 1 backfill).
  if (value.evidence_tier === 'strongest' && !value.meaning_frame) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      message:
        'meaning_frame is required when evidence_tier is "strongest"',
      path: ['meaning_frame'],
    });
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
