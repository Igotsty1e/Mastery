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

/// Wave 13 — V1 spec §12 cap on new (mastery=`started` / unknown)
/// skills introduced per session. The Decision Engine excludes any
/// new-skill candidate once the running session has already shown
/// `MAX_NEW_SKILLS_PER_SESSION` distinct new skills.
export const MAX_NEW_SKILLS_PER_SESSION = 1;

/// Wave 12.6 — total cap on distinct skills per session. Counts ALL
/// skills (new + already-practicing + mastered), not just brand-new
/// ones. Once the session has surfaced this many distinct skills,
/// the primary pass blocks candidates from a (cap+1)th skill.
///
/// Pedagogy: focused practice on 1–2 skills beats fragmented exposure
/// to 5 (Ericsson on deliberate practice, supported by methodologist
/// consult 2026-04-28). Also bounds rule-card volume in any future
/// Library / auto-card UX.
///
/// Interaction with Wave 13's `MAX_NEW_SKILLS_PER_SESSION`: that cap
/// blocks brand-new skills only; this cap blocks any (cap+1)th
/// skill regardless of status. They compose — both filters run in
/// the primary loop. The Wave 12.5 `cap_relaxed_fallback` still
/// applies if the combined caps + §9.1 dropout starve the engine.
export const MAX_SKILLS_PER_SESSION = 2;

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

  // Wave 13 — Max-new-skills-per-session cap (§12). Count distinct
  // skills already shown that are still considered "new"
  // (no mastery status) and stop surfacing brand-new skills once the
  // cap is reached. Same-skill follow-ups are unaffected — only
  // brand-new skills past the cap are blocked.
  const shownNewSkillIds = new Set<string>();
  // Wave 12.6 — total distinct skills shown so far in this session
  // (any status). The MAX_SKILLS_PER_SESSION cap blocks candidates
  // from a (cap+1)th skill regardless of status.
  const shownAllSkillIds = new Set<string>();
  for (const id of ctx.shownExerciseIds) {
    const entry = getBankEntry(id);
    const skillId = entry?.exercise.skill_id ?? null;
    if (!skillId) continue;
    shownAllSkillIds.add(skillId);
    const status = ctx.masteryStatusBySkill[skillId];
    if (status === undefined || status === 'started') {
      shownNewSkillIds.add(skillId);
    }
  }
  const newSkillCapReached =
    shownNewSkillIds.size >= MAX_NEW_SKILLS_PER_SESSION;
  const totalSkillCapReached =
    shownAllSkillIds.size >= MAX_SKILLS_PER_SESSION;

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

    // Wave 12.6 — total-skills cap. Block candidates from a
    // (cap+1)th distinct skill. Items from already-touched skills
    // are unaffected. Cap-relaxed fallback below kicks in if this
    // (combined with the Wave 13 new-skill cap and §9.1 dropouts)
    // starves the primary pass.
    if (skillId && totalSkillCapReached && !shownAllSkillIds.has(skillId)) {
      continue;
    }

    // Wave 13 — block brand-new skills past the cap. A "new" skill is
    // one with no prior mastery record (or status `started`); once the
    // session has already introduced one, every additional new skill
    // candidate is filtered out so the run can settle on practising
    // that one new rule instead of fragmenting attention.
    if (skillId && newSkillCapReached && !shownNewSkillIds.has(skillId)) {
      const status = ctx.masteryStatusBySkill[skillId];
      if (status === undefined || status === 'started') continue;
    }

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

  // Wave 12.5 hot-fix — cap-relaxed fallback. The primary pass above
  // can starve the engine in this exact scenario, observed in prod
  // 2026-04-28 with the Wave 10.5 expanded bank:
  //
  //   1. New learner, no `learner_skills` rows.
  //   2. Engine surfaces an item from skill A; shownNewSkillIds = {A}.
  //   3. `MAX_NEW_SKILLS_PER_SESSION = 1` is now reached. Every
  //      candidate from skills B/C/D/E is blocked because they too
  //      have status=undefined.
  //   4. Learner makes 3 mistakes on skill A.
  //   5. §9.1 puts A into `dropoutSkills` — A's items now also blocked.
  //   6. Primary loop finds zero candidates → returns null → client
  //      treats it as "session complete" and ends at ~Q5.
  //
  // Fix: when the primary pass yields nothing AND the session is
  // under length, run a relaxed pass that ignores the new-skill cap.
  // It is strictly better to introduce a second new skill than to
  // kill the session prematurely. The dropout filter still applies —
  // a 3-mistake skill stays out of rotation, which is the §9.1
  // intent. Emits a distinct reason so the Decision Log makes the
  // fallback observable for retention analysis.
  if (bestEntry === null) {
    let fallbackBest: BankEntry | null = null;
    let fallbackScore = -Infinity;
    for (const entry of flat) {
      if (shownSet.has(entry.exercise.exercise_id)) continue;
      const skillId = entry.exercise.skill_id ?? null;
      if (skillId && dropoutSkills.has(skillId)) continue;
      // NB: cap filter intentionally OMITTED here.
      const score = positionJitter(entry.positionInSource);
      if (score > fallbackScore) {
        fallbackScore = score;
        fallbackBest = entry;
      }
    }
    if (fallbackBest !== null) {
      return { next: fallbackBest, reason: 'cap_relaxed_fallback' };
    }
  }

  // Wave G1 hot-fix — last-resort fallback. Observed in prod 2026-05-01:
  // when the §9.1 dropout filter eliminates every touched skill AND the
  // MAX_SKILLS_PER_SESSION cap blocks every untouched one, both the
  // primary pass and the cap-relaxed pass starve. The session ends
  // abruptly at item 6 (3 mistakes on skill A + 3 on skill B = both
  // dropouts, 0 fresh candidates).
  //
  // Pedagogy is unhappy either way: re-showing a 3-mistake skill
  // re-pokes the §9.1 intent, but ending the session 4 items short
  // breaks the learner's contract with the 1/10 progress counter and
  // skips the post-lesson debrief. The lesser evil is to keep the
  // session alive — re-show an item from a dropout skill if there is
  // truly nothing else. The Decision Log emits a distinct reason so
  // we can spot how often the engine resorts to this in the wild.
  if (bestEntry === null) {
    let lastResortBest: BankEntry | null = null;
    let lastResortScore = -Infinity;
    for (const entry of flat) {
      if (shownSet.has(entry.exercise.exercise_id)) continue;
      // NB: dropout AND cap filters BOTH intentionally omitted here.
      const score = positionJitter(entry.positionInSource);
      if (score > lastResortScore) {
        lastResortScore = score;
        lastResortBest = entry;
      }
    }
    if (lastResortBest !== null) {
      return { next: lastResortBest, reason: 'last_resort_fallback' };
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
