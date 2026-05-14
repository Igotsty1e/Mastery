// Wave E.1 — pure dispatch helper for the diagnostic probe.
//
// Routes a probe attempt to the right deterministic evaluator based on
// the bank-trusted exercise type. Extracted from `service.ts` so the
// dispatch is unit-testable without standing up a full HTTP run.
//
// Supported types in E.1: multiple_choice, fill_blank, sentence_correction.
// short_free_sentence is intentionally NOT supported — it requires AI
// budget + cache + idempotency wiring that lands in E.2.
//
// sentence_correction in lesson sessions can defer to AI on borderline
// inputs (the deterministic evaluator returns `null`). In the probe we
// treat `null` as wrong so the probe stays deterministic, fast, and
// free of rate-limit consumption.

// Use the hand-written `Exercise` union from `lessons.ts` (the same
// type `BankEntry.exercise` resolves to) rather than the z.infer'd
// version from `lessonSchema.ts`. The two have slightly different
// structural types — narrowed on `.type` only the hand-written one
// matches what callers pass through `BankEntry`.
import type { Exercise } from '../data/lessons';
import { evaluateMultipleChoice } from '../evaluators/multipleChoice';
import { evaluateFillBlank } from '../evaluators/fillBlank';
import { evaluateSentenceCorrectionDeterministic } from '../evaluators/sentenceCorrection';

export type ProbeSupportedType =
  | 'multiple_choice'
  | 'fill_blank'
  | 'sentence_correction';

export interface ProbeDispatchResult {
  correct: boolean;
  canonicalAnswer: string;
}

export function isProbeSupportedType(t: string): t is ProbeSupportedType {
  return (
    t === 'multiple_choice' ||
    t === 'fill_blank' ||
    t === 'sentence_correction'
  );
}

export function evaluateProbeAttempt(
  exercise: Exercise,
  userAnswer: string
): ProbeDispatchResult {
  switch (exercise.type) {
    case 'multiple_choice': {
      const r = evaluateMultipleChoice(
        userAnswer,
        exercise.correct_option_id,
        exercise.options
      );
      return { correct: r.correct, canonicalAnswer: r.canonical_answer };
    }
    case 'fill_blank': {
      const r = evaluateFillBlank(userAnswer, exercise.accepted_answers);
      return { correct: r.correct, canonicalAnswer: r.canonical_answer };
    }
    case 'sentence_correction': {
      const r = evaluateSentenceCorrectionDeterministic(
        userAnswer,
        exercise.accepted_corrections,
        exercise.prompt
      );
      if (r === null) {
        // Borderline → AI in lesson sessions; wrong in the probe.
        return {
          correct: false,
          canonicalAnswer: exercise.accepted_corrections[0],
        };
      }
      return { correct: r.correct, canonicalAnswer: r.canonical_answer };
    }
    default:
      throw new Error(
        `evaluateProbeAttempt: unsupported probe type "${exercise.type}". ` +
          'Supported in E.1: multiple_choice, fill_blank, sentence_correction. ' +
          'short_free_sentence is deferred to E.2.'
      );
  }
}
