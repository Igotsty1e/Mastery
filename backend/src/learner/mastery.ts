// Wave 10 — Mastery V1 rule-based gate per V1 spec §10.
//
// The V0 mastery model (Wave 2) was score-based: a `mastery_score 0-100`
// plus a sticky `production_gate_cleared` boolean. V1 replaces the
// score-only thresholds with a rule-based gate. The new inputs live on
// `learner_skills` (Wave 10 migration `0007_mastery_v1`); this module
// is the single read-only evaluator that turns them into a status.
//
// All numeric thresholds live in one block at the top of this file so
// they can be tuned in one place when the D1/D7 telemetry from Wave 9
// shows the gate is too tight or too loose.

import type { LearnerSkillRecord } from './types';

// ────────────────────────────────────────────────────────────────────
// Tunable constants — single source for the V1 gate. Bump these when
// telemetry says so; the rest of the engine reads through this module.
// ────────────────────────────────────────────────────────────────────

/// Minimum total attempts the V1 gate will consider. Below this, status
/// caps at `practicing` regardless of weighted accuracy.
export const MIN_ATTEMPTS_FOR_MASTERY = 6;

/// Reduced minimum if the learner has tried at least one correction or
/// production exercise type. The two condition arms in the V1 spec are
/// `≥6 attempts` OR `≥4 attempts AND at least one correction/production`.
export const MIN_ATTEMPTS_WITH_PRODUCTION = 4;

/// Weighted accuracy threshold for `mastered`. Range 0..1.
export const WEIGHTED_ACCURACY_THRESHOLD = 0.8;

/// FIFO window for repeated-conceptual detection. Stays in sync with
/// `RECENT_ERRORS_CAP` in service.ts.
export const REPEATED_CONCEPTUAL_WINDOW = 5;

/// `repeatedConceptualCount` ≥ this number blocks promotion.
export const REPEATED_CONCEPTUAL_BLOCK_THRESHOLD = 2;

/// Days since `lastAttemptAt` after which a mastered skill flips to
/// `review_due`.
export const REVIEW_DUE_AFTER_DAYS = 21;

/// Evidence weights per V1 spec §6 — selection low, completion medium,
/// correction high, production very high. The exact numbers are
/// proportional, not absolute, so adjusting one tier shifts the gate.
export const EVIDENCE_WEIGHTS: Record<string, number> = {
  // Selection family.
  single_choice: 1,
  multi_select: 1,
  multiple_choice: 1, // legacy alias used by shipped lessons
  // Completion family.
  fill_blank: 2,
  single_blank: 2,
  multi_blank: 2,
  // Correction family.
  sentence_correction: 3,
  multi_error_correction: 3,
  // Production family (V1.5).
  sentence_rewrite: 5,
  short_free_sentence: 5,
  // Listening discrimination — selection family.
  listening_discrimination: 1,
};

/// Exercise-type codes that count as "correction or production" for the
/// reduced-attempts arm of the V1 gate.
const PRODUCTION_OR_CORRECTION_TYPES = new Set<string>([
  'sentence_correction',
  'multi_error_correction',
  'sentence_rewrite',
  'short_free_sentence',
]);

// ────────────────────────────────────────────────────────────────────
// Public API
// ────────────────────────────────────────────────────────────────────

/// Status thresholds final per `docs/plans/learning-engine-v1.md`
/// Decisions log #8. The Wave 9 Flutter `LearnerSkillRecord.statusAt`
/// already uses these boundaries; this module mirrors them for the
/// server-derived status returned alongside record DTOs.
export type MasteryStatusV1 =
  | 'started'
  | 'practicing'
  | 'getting_there'
  | 'almost_mastered'
  | 'mastered'
  | 'review_due';

export interface MasteryEvaluation {
  status: MasteryStatusV1;
  /// True only when every V1 gate clause holds. Used by the Decision
  /// Engine in Wave 13 to decide whether to advance the learner to a
  /// new skill.
  gateCleared: boolean;
  /// The clause that blocked promotion to `mastered`, when blocked.
  /// `null` when the gate cleared, and on the trivial `started` /
  /// `practicing` paths.
  blockedBy:
    | 'attempts_floor'
    | 'no_correction_or_production'
    | 'weighted_accuracy'
    | 'repeated_conceptual'
    | 'last_outcome_wrong'
    | 'production_gate'
    | null;
}

/// V1 mastery evaluation. Reads only the inputs already on the
/// `LearnerSkillRecord`; safe to call without a database round-trip.
export function evaluateMasteryV1(
  record: LearnerSkillRecord,
  now: Date = new Date()
): MasteryEvaluation {
  const accuracy = weightedAccuracy(record);

  // Attempts floor — combined two-arm rule from the V1 spec.
  const hasCorrectionOrProduction = record.exerciseTypesSeen.some((t) =>
    PRODUCTION_OR_CORRECTION_TYPES.has(t)
  );
  const meetsAttemptsArm =
    record.attemptsCount >= MIN_ATTEMPTS_FOR_MASTERY ||
    (record.attemptsCount >= MIN_ATTEMPTS_WITH_PRODUCTION &&
      hasCorrectionOrProduction);

  // Quick exits to the lower statuses before the full gate is
  // evaluated. Below `practicing` is anything with fewer than 3
  // attempts.
  if (record.attemptsCount < 3) {
    return { status: 'started', gateCleared: false, blockedBy: 'attempts_floor' };
  }

  if (!meetsAttemptsArm) {
    if (accuracy >= 0.7) {
      return {
        status: 'getting_there',
        gateCleared: false,
        blockedBy: 'attempts_floor',
      };
    }
    return {
      status: 'practicing',
      gateCleared: false,
      blockedBy: 'attempts_floor',
    };
  }

  // Inside the attempts arm — evaluate the full V1 gate.
  if (accuracy < WEIGHTED_ACCURACY_THRESHOLD) {
    return {
      status: 'getting_there',
      gateCleared: false,
      blockedBy: 'weighted_accuracy',
    };
  }

  if (record.repeatedConceptualCount >= REPEATED_CONCEPTUAL_BLOCK_THRESHOLD) {
    return {
      status: 'almost_mastered',
      gateCleared: false,
      blockedBy: 'repeated_conceptual',
    };
  }

  if (record.lastOutcome === 'wrong') {
    return {
      status: 'almost_mastered',
      gateCleared: false,
      blockedBy: 'last_outcome_wrong',
    };
  }

  // §6.4 production gate — strongest+meaning_frame attempt is still
  // required for `mastered`. The V1 spec keeps this requirement
  // implicit through the production-or-correction arm + accuracy floor;
  // we keep the explicit sticky bit so a previously-cleared learner
  // does not regress on transient noise.
  if (!record.productionGateCleared) {
    return {
      status: 'almost_mastered',
      gateCleared: false,
      blockedBy: 'production_gate',
    };
  }

  // Every clause holds — `mastered`, modulo the §13 review-due window.
  if (record.lastAttemptAt) {
    const ageMs = now.getTime() - record.lastAttemptAt.getTime();
    if (ageMs > REVIEW_DUE_AFTER_DAYS * 24 * 60 * 60 * 1000) {
      return { status: 'review_due', gateCleared: true, blockedBy: null };
    }
  }
  return { status: 'mastered', gateCleared: true, blockedBy: null };
}

/// Weighted accuracy = Σ(weight × correct) / Σ(weight).
/// Stored as a running pair (`weighted_correct_sum`,
/// `weighted_total_sum`) on `learner_skills`. Returns 0 when the learner
/// has no attempts (avoids a divide-by-zero into NaN).
export function weightedAccuracy(record: LearnerSkillRecord): number {
  if (record.weightedTotalSum <= 0) return 0;
  return record.weightedCorrectSum / record.weightedTotalSum;
}

/// Returns the weight to add to `weightedCorrectSum` (0 or `weight`)
/// and `weightedTotalSum` (always `weight`) for a single attempt. The
/// recordAttempt path uses these to keep the running sums in sync with
/// the attempt log without recomputing from scratch.
export function evidenceWeight(exerciseType: string | undefined): number {
  if (!exerciseType) return 1;
  return EVIDENCE_WEIGHTS[exerciseType] ?? 1;
}
