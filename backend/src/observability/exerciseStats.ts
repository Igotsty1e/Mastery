// Wave 9 — daily exercise-health counters per `LEARNING_ENGINE.md §17`.
//
// Wave 9 only writes the counters; the bad-exercise detector that
// flips `qa_review_pending` lands in Wave 11+. The schema lives in
// `db/schema.ts → exerciseStats`. We bucket by UTC date so the time
// series stays readable and rotation is cheap.
//
// Like `decisionLog.ts`, this writer never throws on the happy path —
// observability writes must not break the lesson flow.

import { sql } from 'drizzle-orm';

import type { AppDatabase } from '../db/client';
import { exerciseStats } from '../db/schema';

export type AttemptOutcome = 'correct' | 'partial' | 'wrong';

export interface ExerciseStatsInput {
  exerciseId: string;
  outcome: AttemptOutcome;
  /// Time spent on the exercise in milliseconds. Caller passes the
  /// difference between `submitted_at` and the exercise's start time.
  /// Negative or absurdly large values are clamped to 0 so a
  /// misbehaving client cannot poison the average.
  timeToAnswerMs: number;
  /// Pinned to the exercise's current version so a rewrite (version
  /// bump) starts fresh buckets and old buckets stay tied to the old
  /// content.
  exerciseVersion?: number;
}

function utcDateString(now: Date = new Date()): string {
  // ISO date in UTC: 2026-04-26 — matches Postgres `date` type.
  return now.toISOString().slice(0, 10);
}

/// Increments today's bucket by one attempt. Atomic upsert (Postgres
/// `INSERT ... ON CONFLICT ... DO UPDATE`) so concurrent calls don't
/// race the counter.
export async function recordAttemptStats(
  db: AppDatabase,
  input: ExerciseStatsInput
): Promise<void> {
  try {
    const today = utcDateString();
    const safeMs = Math.max(0, Math.min(input.timeToAnswerMs, 10 * 60_000));
    const isCorrect = input.outcome === 'correct';
    const isPartial = input.outcome === 'partial';
    const isWrong = input.outcome === 'wrong';

    await db
      .insert(exerciseStats)
      .values({
        exerciseId: input.exerciseId,
        statDate: today,
        attemptsCount: 1,
        correctCount: isCorrect ? 1 : 0,
        partialCount: isPartial ? 1 : 0,
        wrongCount: isWrong ? 1 : 0,
        totalTimeToAnswerMs: safeMs,
        exerciseVersion: input.exerciseVersion ?? 1,
      })
      .onConflictDoUpdate({
        target: [exerciseStats.exerciseId, exerciseStats.statDate],
        set: {
          attemptsCount: sql`${exerciseStats.attemptsCount} + 1`,
          correctCount: sql`${exerciseStats.correctCount} + ${
            isCorrect ? 1 : 0
          }`,
          partialCount: sql`${exerciseStats.partialCount} + ${
            isPartial ? 1 : 0
          }`,
          wrongCount: sql`${exerciseStats.wrongCount} + ${isWrong ? 1 : 0}`,
          totalTimeToAnswerMs: sql`${exerciseStats.totalTimeToAnswerMs} + ${safeMs}`,
          updatedAt: sql`now()`,
        },
      });
  } catch (_) {
    // Counters are observability-only; a write failure here never
    // breaks the user's lesson.
  }
}
