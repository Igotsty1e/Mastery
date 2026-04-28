import { desc, eq } from 'drizzle-orm';

import { exerciseAttempts } from '../db/schema';
import type { AppDatabase } from '../db/client';
import { getBankEntry } from '../data/exerciseBank';

/// Wave 14.3 phase 3 — V1.5 friction detection.
///
/// V1 detector: `repeated_error` — the current attempt is wrong AND
/// the most recent prior attempt in this session was also wrong AND
/// both attempts targeted the same `skill_id`. This is the cheapest
/// signal that "the rule isn't landing yet" without dragging mastery
/// state into the per-attempt path.
///
/// The other §17 friction tags (`abandon_after_error`, `retry_loop`,
/// `time_spike`) are intentionally NOT shipped here — they need
/// session-end / time-baseline state the V1 service does not yet
/// thread through. Adding them is a follow-up wave.
///
/// Failures are silent: if the lookup throws or returns nothing, we
/// resolve to `null` (= unremarkable attempt). The friction tag is a
/// product hint, not a correctness signal — the eval still runs.

export type FrictionEvent =
  | 'repeated_error'
  | 'abandon_after_error'
  | 'retry_loop'
  | 'time_spike';

export interface FrictionDetectInput {
  sessionId: string;
  /// `skill_id` of the exercise this attempt is on. Null when the
  /// authored item lacks the engine-metadata tag — detection skips.
  currentSkillId: string | null;
  currentCorrect: boolean;
}

export async function detectFrictionEvent(
  db: AppDatabase,
  input: FrictionDetectInput
): Promise<FrictionEvent | null> {
  // Only wrong-on-this-attempt is a candidate for repeated_error.
  if (input.currentCorrect) return null;
  if (!input.currentSkillId) return null;

  try {
    // Most recent prior attempt in this session, regardless of which
    // exercise it was on.
    const prior = await db
      .select({
        exerciseId: exerciseAttempts.exerciseId,
        correct: exerciseAttempts.correct,
      })
      .from(exerciseAttempts)
      .where(eq(exerciseAttempts.sessionId, input.sessionId))
      .orderBy(desc(exerciseAttempts.submittedAt))
      .limit(1);

    const last = prior[0];
    if (!last || last.correct) return null;

    // Resolve the prior exercise's skill_id via the bank lookup. The
    // bank indexes every authored item by exercise_id (Wave 14.2
    // RUNTIME_SUPPORTED_EXERCISE_TYPES gate has no effect on
    // by-id lookups), so this works for both engine-eligible and
    // currently-disabled types.
    const lastEntry = getBankEntry(last.exerciseId);
    const lastSkillId = lastEntry?.exercise.skill_id ?? null;
    if (!lastSkillId) return null;
    if (lastSkillId !== input.currentSkillId) return null;

    return 'repeated_error';
  } catch {
    return null;
  }
}
