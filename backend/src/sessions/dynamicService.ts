// Wave 11.2 — dynamic session service.
//
// Sits next to the legacy lesson-bound session service so the routes
// can adopt the new flow incrementally. Dynamic sessions:
//
//   - Have `lesson_id = DYNAMIC_SESSION_LESSON_ID` (sentinel UUID) so
//     the partial unique index in `lesson_sessions` doesn't gate
//     concurrent dynamic runs.
//   - Are assembled exercise-by-exercise via `Decision Engine`
//     (`backend/src/decision/engine.ts`). The first exercise comes
//     back from `startDynamicSession`; subsequent ones from
//     `pickNextForSession` after each answer is recorded.
//   - Stamp every attempt row with the picked `BankEntry`'s source-
//     lesson metadata for replay traceability.

import { eq } from 'drizzle-orm';

import type { AppDatabase } from '../db/client';
import { lessonSessions } from '../db/schema';
import {
  bankSize,
  getAllBankEntries,
  getBankEntry,
  type BankEntry,
} from '../data/exerciseBank';
import {
  pickNext,
  SESSION_LENGTH,
  type DecisionContext,
} from '../decision/engine';
import { recordDecision } from '../observability/decisionLog';
import {
  insertSession,
  listLatestAttemptsForSession,
  type LessonSessionRow,
} from '../lessonSessions/repository';
import {
  deriveStatus,
  listAllSkillRecords,
} from '../learner/service';
import { LessonSessionError } from '../lessonSessions/service';

/// Sentinel UUID written to `lesson_sessions.lesson_id` for dynamic
/// sessions so the partial unique index does not raise when the user
/// has a concurrent dynamic run.
export const DYNAMIC_SESSION_LESSON_ID =
  '00000000-0000-0000-0000-000000000000';

const DYNAMIC_LESSON_VERSION = 'dynamic';
const DYNAMIC_CONTENT_HASH = 'dynamic';

export interface DynamicSessionStart {
  session: LessonSessionRow;
  firstExercise: BankEntry;
  reason: string;
}

export async function startDynamicSession(
  db: AppDatabase,
  userId: string
): Promise<DynamicSessionStart> {
  if (bankSize() === 0) {
    throw new LessonSessionError(503, 'bank_empty');
  }
  // Build a Decision Engine context from the learner's snapshot. The
  // first pick reads only mastery_status (no in-session mistakes
  // yet, no shown exercises).
  const masteryStatusBySkill: Record<string, string> = {};
  const records = await listAllSkillRecords(db, userId);
  const now = new Date();
  for (const record of records) {
    masteryStatusBySkill[record.skillId] = deriveStatus(record, now);
  }

  const ctx: DecisionContext = {
    shownExerciseIds: [],
    mistakesBySkill: {},
    masteryStatusBySkill,
  };
  const result = pickNext(ctx);
  if (!result.next) {
    throw new LessonSessionError(503, 'no_candidates');
  }

  const session = await insertSession(db, {
    userId,
    lessonId: DYNAMIC_SESSION_LESSON_ID,
    lessonVersion: DYNAMIC_LESSON_VERSION,
    contentHash: DYNAMIC_CONTENT_HASH,
    unitId: result.next.unitId,
    ruleTag: result.next.ruleTag,
    microRuleTag: result.next.microRuleTag,
    exerciseCount: SESSION_LENGTH,
  });

  void recordDecision(db, {
    userId,
    sessionId: session.id,
    skillId: result.next.exercise.skill_id ?? null,
    decision: 'next_exercise',
    reason: result.reason,
    nextExerciseId: result.next.exercise.exercise_id,
    previousState: { position: 0 },
  });

  return { session, firstExercise: result.next, reason: result.reason ?? '' };
}

export interface DynamicNextResult {
  next: BankEntry | null;
  reason: string | null;
  /// Position in the session (0-indexed). When equal to
  /// `SESSION_LENGTH`, the session is complete and the client should
  /// call `/complete` instead of `/next`.
  position: number;
}

/// Returns the next exercise for an in-progress dynamic session. Reads
/// the existing attempts to compute `shownExerciseIds` and
/// `mistakesBySkill`, then asks the Decision Engine.
export async function pickNextForSession(
  db: AppDatabase,
  userId: string,
  sessionId: string
): Promise<DynamicNextResult> {
  const rows = await db
    .select()
    .from(lessonSessions)
    .where(eq(lessonSessions.id, sessionId))
    .limit(1);
  const session = (rows[0] as LessonSessionRow | undefined) ?? null;
  if (!session) throw new LessonSessionError(404, 'session_not_found');
  if (session.userId !== userId) {
    throw new LessonSessionError(404, 'session_not_found');
  }
  if (session.lessonId !== DYNAMIC_SESSION_LESSON_ID) {
    throw new LessonSessionError(409, 'session_not_dynamic');
  }
  if (session.status !== 'in_progress') {
    return { next: null, reason: 'session_not_in_progress', position: 0 };
  }

  const attempts = await listLatestAttemptsForSession(db, sessionId);
  const shownExerciseIds = attempts.map((a) => a.exerciseId);
  const mistakesBySkill: Record<string, number> = {};
  for (const a of attempts) {
    if (a.correct) continue;
    const entry = getBankEntry(a.exerciseId);
    const skillId = entry?.exercise.skill_id ?? null;
    if (!skillId) continue;
    mistakesBySkill[skillId] = (mistakesBySkill[skillId] ?? 0) + 1;
  }

  const masteryStatusBySkill: Record<string, string> = {};
  const records = await listAllSkillRecords(db, userId);
  const now = new Date();
  for (const record of records) {
    masteryStatusBySkill[record.skillId] = deriveStatus(record, now);
  }

  const ctx: DecisionContext = {
    shownExerciseIds,
    mistakesBySkill,
    masteryStatusBySkill,
  };
  const result = pickNext(ctx);
  const position = shownExerciseIds.length;

  void recordDecision(db, {
    userId,
    sessionId,
    skillId: result.next?.exercise.skill_id ?? null,
    decision: result.next ? 'next_exercise' : 'session_complete',
    reason: result.reason,
    nextExerciseId: result.next?.exercise.exercise_id ?? null,
    previousState: {
      position,
      shown_count: shownExerciseIds.length,
      mistakes: mistakesBySkill,
    },
  });

  return { next: result.next, reason: result.reason, position };
}

/// Convenience accessor used by route layer to surface the bank's
/// shape on `/sessions/start`'s response.
export function snapshotBankSize(): number {
  return bankSize();
}

/// Convenience: project a BankEntry into the same shape the existing
/// `projectExerciseForClient` produces. The route layer reuses that
/// projection — this helper just returns the raw exercise object so
/// `routes.ts` can hand it to `projectExerciseForClient`.
export function bankEntryToExercise(entry: BankEntry): BankEntry['exercise'] {
  return entry.exercise;
}

/// Test helper: returns the first N flat bank entries.
export function firstNBankEntries(n: number): BankEntry[] {
  return getAllBankEntries().slice(0, n);
}
