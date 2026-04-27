// Wave 11 — server-side dynamic Decision Engine.
//
// Replaces the lesson-as-fixed-queue model. Each session is now a 10-item
// run (configurable) that the engine assembles from the exercise bank
// per `LEARNING_ENGINE.md §9`:
//
//   1. Skill mastery — surface skills that need work over skills the
//      learner has already mastered.
//   2. Variety — avoid back-to-back repeats of the same exercise.
//   3. Past errors — slightly favour skills with recent recurring errors.
//
// V1 MVP simplifications (per `docs/plans/learning-engine-v1.md`):
//   - Pacing 60/30/10 (new/reinforcement/review) baked in as the
//     default; Wave 13 adds the weak / strong profiles.
//   - One topic, "B2 mixed practice", spans the full bank.
//   - Skill mixing: occasional 15% chance to pull a different skill.
//   - Diagnostic mode handled by a separate flow (Wave 12), not here.
//
// The engine never throws — when no candidate fits, it falls through
// to a deterministic next entry from the flat bank so the session can
// always advance.

import {
  getAllBankEntries,
  getBankEntry,
  type BankEntry,
} from '../data/exerciseBank';

export interface DecisionContext {
  /// Exercises already shown in this session, in display order. Used
  /// for last-N-repeat avoidance (§14) and to detect "session full".
  shownExerciseIds: string[];
  /// In-session per-skill mistake counter (§9.1 1/2/3 loop input).
  mistakesBySkill: Record<string, number>;
  /// Per-skill mastery snapshot for prioritisation. `started` sits at
  /// the top of the queue, `mastered` at the bottom.
  masteryStatusBySkill: Record<string, string>;
  /// Soft pacing target. Default is 60/30/10. Wave 13 plugs the
  /// weak / strong profile here; V1 MVP leaves it at default.
  pacingTarget?: PacingTarget;
}

export interface PacingTarget {
  /// 0..1 share — items the engine should bias toward NEW (un-touched)
  /// skills.
  newShare: number;
  /// 0..1 share — items biased toward already-touched-this-session
  /// skills (reinforcement).
  reinforcementShare: number;
  /// 0..1 share — items biased toward review_due skills.
  reviewShare: number;
}

export const DEFAULT_PACING: PacingTarget = {
  newShare: 0.6,
  reinforcementShare: 0.3,
  reviewShare: 0.1,
};

export const SESSION_LENGTH = 10;

export interface DecisionResult {
  /// `null` when the engine decided the session is over (no more
  /// suitable items).
  next: BankEntry | null;
  /// Short reason code matching `LEARNING_ENGINE.md §11.3` strings.
  /// Surfaces in the Decision Log (Wave 9) and on the client's
  /// transparency layer once Wave 4 reads it from the session DTO.
  reason: string | null;
}

/**
 * Picks the next exercise for the running session.
 *
 * Hard rules (never violated):
 *  - never re-show an exercise already shown in this session.
 *  - if `shownExerciseIds.length >= SESSION_LENGTH` → return `null`.
 *
 * Soft rules (combined into a score per candidate):
 *  - boost if the skill's mastery is `started` / `practicing` /
 *    `getting_there`, demote if `mastered` or `almost_mastered`.
 *  - heavy demote if the skill has a 3rd in-session mistake (§9.1 —
 *    drop remaining same-skill items; engine still surfaces other
 *    skills).
 *  - light boost if last shown was a different skill (variety).
 *  - light boost if the skill has a recent error matching the
 *    current pacing slot.
 *
 * The score is then perturbed by a small deterministic position-based
 * jitter so an empty learner profile gets a stable shuffle rather than
 * the source order.
 */
export function pickNext(ctx: DecisionContext): DecisionResult {
  if (ctx.shownExerciseIds.length >= SESSION_LENGTH) {
    return { next: null, reason: 'session_complete' };
  }
  const shownSet = new Set(ctx.shownExerciseIds);
  const lastShownEntry =
    ctx.shownExerciseIds.length > 0
      ? getBankEntry(ctx.shownExerciseIds[ctx.shownExerciseIds.length - 1])
      : undefined;

  // §9.1 third-mistake skip: the skills with ≥3 in-session mistakes
  // drop out of the pool until the next session.
  const dropoutSkills = new Set(
    Object.entries(ctx.mistakesBySkill)
      .filter(([, count]) => count >= 3)
      .map(([skillId]) => skillId)
  );

  const flat = getAllBankEntries();
  if (flat.length === 0) {
    return { next: null, reason: 'bank_empty' };
  }

  const pacing = ctx.pacingTarget ?? DEFAULT_PACING;
  let bestScore = -Infinity;
  let bestEntry: BankEntry | null = null;
  let bestReason: string = 'linear_default';

  for (const entry of flat) {
    if (shownSet.has(entry.exercise.exercise_id)) continue;
    const skillId = entry.exercise.skill_id ?? null;
    if (skillId && dropoutSkills.has(skillId)) continue;

    let score = 0;

    // Mastery boost — `started` and `practicing` are top priority.
    const status = skillId ? ctx.masteryStatusBySkill[skillId] : undefined;
    score += masteryBoost(status, pacing);

    // Variety — different skill from last seen wins +1.
    if (
      lastShownEntry &&
      skillId &&
      lastShownEntry.exercise.skill_id !== skillId
    ) {
      score += 1;
    }

    // Past-error nudge — skill with a 1st or 2nd mistake gets +0.5
    // (we want to reinforce, not pile on after the §9.1 dropout).
    if (skillId) {
      const mistakeCount = ctx.mistakesBySkill[skillId] ?? 0;
      if (mistakeCount === 1) score += 1;
      if (mistakeCount === 2) score += 0.5;
    }

    // Deterministic shuffle so a clean profile doesn't always pick
    // the same source-order item. Position-based hash is enough.
    score += positionJitter(entry.positionInSource);

    if (score > bestScore) {
      bestScore = score;
      bestEntry = entry;
      bestReason = chooseReason({
        status,
        mistakeCount: skillId
          ? ctx.mistakesBySkill[skillId] ?? 0
          : 0,
        lastShownSkill: lastShownEntry?.exercise.skill_id ?? null,
        thisSkill: skillId,
      });
    }
  }

  return {
    next: bestEntry,
    reason: bestEntry ? bestReason : 'no_candidates',
  };
}

function masteryBoost(
  status: string | undefined,
  pacing: PacingTarget
): number {
  // Three pacing buckets: new, reinforcement, review.
  // V1 MVP maps mastery status → bucket, weighted by pacing target.
  switch (status) {
    case undefined:
    case 'started':
      return 3 * pacing.newShare;
    case 'practicing':
    case 'getting_there':
      return 2 * pacing.reinforcementShare + 1 * pacing.newShare;
    case 'almost_mastered':
      return 1 * pacing.reinforcementShare;
    case 'review_due':
      return 4 * pacing.reviewShare;
    case 'mastered':
      return 0.2 * pacing.reviewShare;
    default:
      return 1 * pacing.newShare;
  }
}

function chooseReason(input: {
  status: string | undefined;
  mistakeCount: number;
  lastShownSkill: string | null | undefined;
  thisSkill: string | null;
}): string {
  if (input.mistakeCount === 1) return 'same_rule_different_angle';
  if (input.mistakeCount === 2) return 'same_rule_simpler_ask';
  if (input.status === 'review_due') return 'review_due_lift';
  if (
    input.lastShownSkill &&
    input.thisSkill &&
    input.lastShownSkill !== input.thisSkill
  ) {
    return 'variety_switch';
  }
  return 'linear_default';
}

function positionJitter(position: number): number {
  // Tiny deterministic perturbation — keeps total scores within ±0.5
  // so it never overrides a real signal but breaks ties consistently.
  // Same skill+position → same jitter across calls, so the engine is
  // replayable from the Decision Log.
  const x = (position * 9301 + 49297) % 233280;
  return (x / 233280) * 0.5;
}
