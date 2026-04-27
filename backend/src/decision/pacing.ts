// Wave 13 — pacing profile selector per V1 spec §12.
//
// The Decision Engine reads `PacingTarget` to weight new vs.
// reinforcement vs. review picks. V1 ships three discrete profiles:
//
//   - default (60 / 30 / 10) — every learner who isn't obviously
//     struggling or obviously cruising.
//   - weak (40 / 40 / 20) — `weakSkillThreshold` skills sit under
//     `practicing`. The Decision Engine pulls more reinforcement and
//     review items so the learner doesn't keep banging into new rules.
//   - strong (70 / 20 / 10) — `strongSkillThreshold` skills sit at
//     `mastered`. Decision Engine biases toward new content; review
//     stays at the same 10% floor.
//
// The thresholds live in the constants block at the top so a future
// telemetry-driven tune (D7 retention vs profile distribution) can
// shift them in one place.

import { DEFAULT_PACING, type PacingTarget } from './engine';
import type { MasteryStatusV1 } from '../learner/mastery';

/// Number of skills sitting at `practicing` (or weaker) that flips the
/// learner into the weak profile.
export const WEAK_THRESHOLD = 3;

/// Number of skills sitting at `mastered` that flips the learner into
/// the strong profile.
export const STRONG_THRESHOLD = 3;

/// Hard cap on new skills introduced per session. The Decision Engine
/// reads this in `pickNext` to avoid surfacing more than one untouched
/// skill per 10-item run.
export const MAX_NEW_SKILLS_PER_SESSION = 1;

/// V1 spec §12 weak profile.
export const WEAK_PACING: PacingTarget = {
  newShare: 0.4,
  reinforcementShare: 0.4,
  reviewShare: 0.2,
};

/// V1 spec §12 strong profile.
export const STRONG_PACING: PacingTarget = {
  newShare: 0.7,
  reinforcementShare: 0.2,
  reviewShare: 0.1,
};

export type PacingProfile = 'default' | 'weak' | 'strong';

export interface PacingDecision {
  target: PacingTarget;
  profile: PacingProfile;
  /// Snapshot of the counters that drove the decision. Surfaces in the
  /// Decision Log so a regression can be traced back to the input
  /// distribution (e.g. "wait, why did this learner end up in weak?").
  signal: {
    practicing_or_weaker: number;
    mastered: number;
  };
}

/// Picks the pacing profile from a per-skill mastery status snapshot.
/// Reads only the values that ship today — `started`, `practicing`,
/// `getting_there`, `almost_mastered`, `mastered`, `review_due`.
export function derivePacingTarget(
  masteryStatusBySkill: Record<string, MasteryStatusV1 | string>
): PacingDecision {
  let practicingOrWeaker = 0;
  let masteredCount = 0;
  for (const status of Object.values(masteryStatusBySkill)) {
    if (status === 'practicing' || status === 'started') {
      practicingOrWeaker += 1;
    } else if (status === 'mastered') {
      masteredCount += 1;
    }
  }

  // Strong profile wins when both thresholds fire (mastered ≥ 3 AND
  // practicing ≥ 3) — this reflects a learner with a wide skill graph
  // who has both old work to keep warm and new ground to cover. We
  // prefer biasing toward new content in that case; the reinforcement
  // gain from weak isn't enough to override the strong's payoff.
  if (masteredCount >= STRONG_THRESHOLD) {
    return {
      target: STRONG_PACING,
      profile: 'strong',
      signal: {
        practicing_or_weaker: practicingOrWeaker,
        mastered: masteredCount,
      },
    };
  }
  if (practicingOrWeaker >= WEAK_THRESHOLD) {
    return {
      target: WEAK_PACING,
      profile: 'weak',
      signal: {
        practicing_or_weaker: practicingOrWeaker,
        mastered: masteredCount,
      },
    };
  }
  return {
    target: DEFAULT_PACING,
    profile: 'default',
    signal: {
      practicing_or_weaker: practicingOrWeaker,
      mastered: masteredCount,
    },
  };
}
