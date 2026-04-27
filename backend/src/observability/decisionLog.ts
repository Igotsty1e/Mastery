// Wave 9 — append-only Decision Log writer per `LEARNING_ENGINE.md §18`.
//
// Every Decision Engine call writes one row. The schema lives in
// `db/schema.ts → decisionLog`; this module is the thin wrapper every
// callsite goes through so we keep the contract narrow:
//
//   - never throw on the happy path (logging must not break the lesson
//     flow even if Postgres misbehaves transiently),
//   - never write the full learner_skill row (only the small inputs
//     the engine actually read — mastery score, recent errors, in-session
//     mistakes),
//   - never call this from inside a transaction the caller still owns
//     (the writer fires its own insert; the caller decides whether to
//     await it or fire-and-forget).
//
// The Wave 11 dynamic Decision Engine will be the heaviest caller. Wave
// 9 already wires the existing decision points (lessonSessions service
// and the learner-state service) so we have a baseline of decision
// telemetry to compare against.

import type { AppDatabase } from '../db/client';
import { decisionLog } from '../db/schema';

export type DecisionCode =
  | 'next_exercise'
  | 'reorder_queue'
  | 'mark_weak'
  | 'schedule_review'
  | 'mastery_promoted'
  | 'mastery_invalidated'
  | 'production_gate_cleared';

export interface DecisionLogInput {
  userId: string;
  sessionId?: string | null;
  skillId?: string | null;
  decision: DecisionCode;
  reason?: string | null;
  /// Small jsonb snapshot of the inputs read by the engine. Keep it tight
  /// — single skill record, not a dump of the whole learner state.
  previousState?: Record<string, unknown>;
  nextExerciseId?: string | null;
}

/// Writes one Decision Log row. Returns the insert id on success, null on
/// any error. Never throws — the caller can ignore the return safely.
export async function recordDecision(
  db: AppDatabase,
  input: DecisionLogInput
): Promise<string | null> {
  try {
    const [row] = await db
      .insert(decisionLog)
      .values({
        userId: input.userId,
        sessionId: input.sessionId ?? null,
        skillId: input.skillId ?? null,
        decision: input.decision,
        reason: input.reason ?? null,
        previousState: input.previousState ?? {},
        nextExerciseId: input.nextExerciseId ?? null,
      })
      .returning({ id: decisionLog.id });
    return row?.id ?? null;
  } catch (_) {
    return null;
  }
}
