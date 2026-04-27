// Wave 7.3 engine state types. Shape mirrors the Dart `LearnerSkillRecord`
// and `ReviewSchedule` classes in app/lib/learner/ so the Wave 7.4
// client rewrite is a thin transport layer.

/// Four target-error codes per the V1 spec (§5).
/// Wave 10 (2026-04-26) dropped `transfer_error` and `pragmatic_error`
/// — neither was referenced by any shipped lesson JSON, so the change
/// is a clean break with no content rewrite. Future content sticks to
/// the four codes below.
export type TargetError =
  | 'conceptual_error'
  | 'form_error'
  | 'contrast_error'
  | 'careless_error';

export const TARGET_ERROR_CODES: TargetError[] = [
  'conceptual_error',
  'form_error',
  'contrast_error',
  'careless_error',
];

/// Four evidence tiers per LEARNING_ENGINE.md §6.1.
export type EvidenceTier = 'weak' | 'medium' | 'strong' | 'strongest';

export const EVIDENCE_TIERS: EvidenceTier[] = [
  'weak',
  'medium',
  'strong',
  'strongest',
];

/// Six derived status labels per LEARNING_ENGINE.md §7.2. Status is
/// computed from stored inputs on read; only the inputs are persisted.
export type SkillStatus =
  | 'started'
  | 'practicing'
  | 'getting_there'
  | 'almost_mastered'
  | 'mastered'
  | 'review_due';

export interface LearnerSkillRecord {
  skillId: string;
  masteryScore: number;
  lastAttemptAt: Date | null;
  evidenceSummary: Record<EvidenceTier, number>;
  recentErrors: TargetError[];
  productionGateCleared: boolean;
  gateClearedAtVersion: number | null;
  // Wave 10 — V1 mastery gate inputs.
  attemptsCount: number;
  exerciseTypesSeen: string[];
  lastOutcome: 'correct' | 'partial' | 'wrong' | null;
  repeatedConceptualCount: number;
  weightedCorrectSum: number;
  weightedTotalSum: number;
}

export interface ReviewScheduleRecord {
  skillId: string;
  step: number;
  dueAt: Date;
  lastOutcomeAt: Date;
  lastOutcomeMistakes: number;
  graduated: boolean;
}
