// Wave 12.2 — CEFR derivation from a finished diagnostic run.
//
// Pure function. Input: the run's response history (per-attempt
// outcomes + skill_id + evidence_tier). Output: a coarse CEFR level +
// per-skill status map per `LEARNING_ENGINE.md §7.2`.
//
// V1 spec §15 hybrid logic: overall correctness + per-skill min. With
// the V1 MVP probe (5 weak-tier MC items, one per shipped skill), the
// thresholds are calibrated to the bank size — not to the engine
// spec's hypothetical 7-skill probe — so the math stays meaningful on
// what actually shipped:
//
//   correct  | cefr
//   --------- ------
//   5 / 5    | B2
//   4 / 5    | B2
//   3 / 5    | B1
//   ≤ 2 / 5  | A2
//
// The C1 ceiling is intentional: the bank is B2-scoped and the probe
// cannot honestly distinguish C1 from B2 today. Lifting the ceiling
// requires a C1-tier probe item and is V1.5 territory.
//
// Per-skill status from the probe: 'practicing' on a correct
// recognition attempt, 'started' on a wrong one (the learner has no
// other signal yet — `learner_skills` writes the actual evidence
// during /complete).

export type CefrLevel = 'A2' | 'B1' | 'B2' | 'C1';

export type ProbeOutcomeStatus = 'started' | 'practicing';

export interface DiagnosticResponse {
  exercise_id: string;
  skill_id: string | null;
  evidence_tier: string | null;
  correct: boolean;
}

export interface DiagnosticDerivation {
  cefrLevel: CefrLevel;
  skillMap: Record<string, ProbeOutcomeStatus>;
  totalCorrect: number;
  totalAnswered: number;
}

export function deriveCefrFromRun(
  responses: DiagnosticResponse[]
): DiagnosticDerivation {
  const totalAnswered = responses.length;
  const totalCorrect = responses.filter((r) => r.correct).length;

  const skillMap: Record<string, ProbeOutcomeStatus> = {};
  for (const r of responses) {
    if (!r.skill_id) continue;
    // If the same skill appears twice (unlikely on the V1 probe but
    // not forbidden), the latest correct attempt wins. Two attempts on
    // the same skill in one run is a probe-design choice, not engine
    // semantics.
    const prior = skillMap[r.skill_id];
    if (r.correct) {
      skillMap[r.skill_id] = 'practicing';
    } else if (prior !== 'practicing') {
      skillMap[r.skill_id] = 'started';
    }
  }

  const cefrLevel = deriveCefrLevel(totalCorrect, totalAnswered);

  return { cefrLevel, skillMap, totalCorrect, totalAnswered };
}

function deriveCefrLevel(correct: number, total: number): CefrLevel {
  if (total <= 0) return 'A2';
  // V1 thresholds calibrated to a 5-item B2 probe. Express as a
  // percentage so the function tolerates probe-size changes (e.g. a
  // future 7-item probe) without a re-tune.
  const pct = correct / total;
  if (pct >= 0.8) return 'B2';
  if (pct >= 0.5) return 'B1';
  return 'A2';
}
