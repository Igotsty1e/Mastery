import { and, asc, desc, eq, inArray, sql } from 'drizzle-orm';
import type { AppDatabase } from '../db/client';
import {
  exerciseAttempts,
  lessonProgress,
  lessonSessions,
} from '../db/schema';
import { isUniqueViolation } from '../db/errors';

// Wave 2 — typed selects on top of Drizzle. Routes/services should not
// touch raw queries; centralising them here keeps the active-session
// invariant and the latest-attempt-wins read path in one place.

export interface LessonSessionRow {
  id: string;
  userId: string;
  lessonId: string;
  lessonVersion: string;
  contentHash: string;
  unitId: string | null;
  ruleTag: string | null;
  microRuleTag: string | null;
  status: string;
  exerciseCount: number;
  correctCount: number;
  startedAt: Date;
  lastActivityAt: Date;
  completedAt: Date | null;
  debriefSnapshot: unknown;
}

export interface ExerciseAttemptRow {
  id: string;
  sessionId: string;
  userId: string;
  lessonId: string;
  lessonVersion: string;
  contentHash: string;
  exerciseId: string;
  exerciseType: string;
  userAnswer: string;
  correct: boolean;
  canonicalAnswer: string;
  evaluationSource: string;
  explanation: string | null;
  clientAttemptId: string | null;
  submittedAt: Date;
  createdAt: Date;
}

export interface LessonProgressRow {
  id: string;
  userId: string;
  lessonId: string;
  attemptsCount: number;
  completed: boolean;
  latestCorrect: number | null;
  latestTotal: number | null;
  bestCorrect: number | null;
  bestTotal: number | null;
  lastSessionId: string | null;
  firstCompletedAt: Date | null;
  lastCompletedAt: Date | null;
  updatedAt: Date;
}

export async function findActiveSession(
  db: AppDatabase,
  userId: string,
  lessonId: string
): Promise<LessonSessionRow | null> {
  const rows = await db
    .select()
    .from(lessonSessions)
    .where(
      and(
        eq(lessonSessions.userId, userId),
        eq(lessonSessions.lessonId, lessonId),
        eq(lessonSessions.status, 'in_progress')
      )
    )
    .limit(1);
  return (rows[0] as LessonSessionRow | undefined) ?? null;
}

export async function findSessionById(
  db: AppDatabase,
  sessionId: string
): Promise<LessonSessionRow | null> {
  const rows = await db
    .select()
    .from(lessonSessions)
    .where(eq(lessonSessions.id, sessionId))
    .limit(1);
  return (rows[0] as LessonSessionRow | undefined) ?? null;
}

export interface CreateSessionInput {
  userId: string;
  lessonId: string;
  lessonVersion: string;
  contentHash: string;
  unitId: string | null;
  ruleTag: string | null;
  microRuleTag: string | null;
  exerciseCount: number;
}

export async function insertSession(
  db: AppDatabase,
  input: CreateSessionInput
): Promise<LessonSessionRow> {
  const rows = await db
    .insert(lessonSessions)
    .values({
      userId: input.userId,
      lessonId: input.lessonId,
      lessonVersion: input.lessonVersion,
      contentHash: input.contentHash,
      unitId: input.unitId,
      ruleTag: input.ruleTag,
      microRuleTag: input.microRuleTag,
      exerciseCount: input.exerciseCount,
    })
    .returning();
  const row = rows[0];
  if (!row) throw new Error('failed_to_create_lesson_session');
  return row as LessonSessionRow;
}

export async function touchSession(
  db: AppDatabase,
  sessionId: string,
  at: Date = new Date()
): Promise<void> {
  await db
    .update(lessonSessions)
    .set({ lastActivityAt: at })
    .where(eq(lessonSessions.id, sessionId));
}

export interface InsertAttemptInput {
  sessionId: string;
  userId: string;
  lessonId: string;
  lessonVersion: string;
  contentHash: string;
  unitId: string | null;
  ruleTag: string | null;
  microRuleTag: string | null;
  exerciseId: string;
  exerciseType: string;
  userAnswer: string;
  correct: boolean;
  canonicalAnswer: string;
  evaluationSource: string;
  explanation: string | null;
  clientAttemptId: string | null;
  submittedAt: Date;
}

export async function findAttemptByClientId(
  db: AppDatabase,
  sessionId: string,
  clientAttemptId: string
): Promise<ExerciseAttemptRow | null> {
  const rows = await db
    .select()
    .from(exerciseAttempts)
    .where(
      and(
        eq(exerciseAttempts.sessionId, sessionId),
        eq(exerciseAttempts.clientAttemptId, clientAttemptId)
      )
    )
    .limit(1);
  return (rows[0] as ExerciseAttemptRow | undefined) ?? null;
}

/**
 * Insert one attempt. When `clientAttemptId` is set the partial unique
 * index on `(session_id, client_attempt_id)` makes the insert idempotent —
 * a duplicate insert raises a unique-violation, which the caller catches
 * and reads back the original row.
 */
export async function insertAttempt(
  db: AppDatabase,
  input: InsertAttemptInput
): Promise<{ row: ExerciseAttemptRow; duplicate: boolean }> {
  try {
    const rows = await db
      .insert(exerciseAttempts)
      .values({
        sessionId: input.sessionId,
        userId: input.userId,
        lessonId: input.lessonId,
        lessonVersion: input.lessonVersion,
        contentHash: input.contentHash,
        unitId: input.unitId,
        ruleTag: input.ruleTag,
        microRuleTag: input.microRuleTag,
        exerciseId: input.exerciseId,
        exerciseType: input.exerciseType,
        userAnswer: input.userAnswer,
        correct: input.correct,
        canonicalAnswer: input.canonicalAnswer,
        evaluationSource: input.evaluationSource,
        explanation: input.explanation,
        clientAttemptId: input.clientAttemptId,
        submittedAt: input.submittedAt,
      })
      .returning();
    const row = rows[0];
    if (!row) throw new Error('failed_to_persist_attempt');
    return { row: row as ExerciseAttemptRow, duplicate: false };
  } catch (err) {
    if (input.clientAttemptId && isUniqueViolation(err)) {
      const existing = await findAttemptByClientId(
        db,
        input.sessionId,
        input.clientAttemptId
      );
      if (existing) return { row: existing, duplicate: true };
    }
    throw err;
  }
}

export async function listAttemptsForSession(
  db: AppDatabase,
  sessionId: string
): Promise<ExerciseAttemptRow[]> {
  const rows = await db
    .select()
    .from(exerciseAttempts)
    .where(eq(exerciseAttempts.sessionId, sessionId))
    .orderBy(asc(exerciseAttempts.submittedAt), asc(exerciseAttempts.createdAt));
  return rows as ExerciseAttemptRow[];
}

/**
 * Build the "current state" of the session: one row per `exercise_id`,
 * being the latest attempt that exists. Used both for scoring and for
 * client resume payloads.
 */
export async function listLatestAttemptsForSession(
  db: AppDatabase,
  sessionId: string
): Promise<ExerciseAttemptRow[]> {
  const all = await listAttemptsForSession(db, sessionId);
  const latest = new Map<string, ExerciseAttemptRow>();
  for (const a of all) {
    const prev = latest.get(a.exerciseId);
    // Compare on submittedAt first, then createdAt as a deterministic
    // tiebreaker for two attempts in the same submitted_at ms.
    if (!prev) {
      latest.set(a.exerciseId, a);
      continue;
    }
    const prevTs = prev.submittedAt.getTime();
    const aTs = a.submittedAt.getTime();
    if (aTs > prevTs) latest.set(a.exerciseId, a);
    else if (aTs === prevTs && a.createdAt.getTime() > prev.createdAt.getTime())
      latest.set(a.exerciseId, a);
  }
  return Array.from(latest.values());
}

export async function findProgress(
  db: AppDatabase,
  userId: string,
  lessonId: string
): Promise<LessonProgressRow | null> {
  const rows = await db
    .select()
    .from(lessonProgress)
    .where(
      and(
        eq(lessonProgress.userId, userId),
        eq(lessonProgress.lessonId, lessonId)
      )
    )
    .limit(1);
  return (rows[0] as LessonProgressRow | undefined) ?? null;
}

export async function listProgressForUser(
  db: AppDatabase,
  userId: string
): Promise<LessonProgressRow[]> {
  const rows = await db
    .select()
    .from(lessonProgress)
    .where(eq(lessonProgress.userId, userId));
  return rows as LessonProgressRow[];
}

export async function listInProgressSessions(
  db: AppDatabase,
  userId: string
): Promise<LessonSessionRow[]> {
  const rows = await db
    .select()
    .from(lessonSessions)
    .where(
      and(
        eq(lessonSessions.userId, userId),
        eq(lessonSessions.status, 'in_progress')
      )
    );
  return rows as LessonSessionRow[];
}

export async function findMostRecentCompletedSession(
  db: AppDatabase,
  userId: string
): Promise<LessonSessionRow | null> {
  const rows = await db
    .select()
    .from(lessonSessions)
    .where(
      and(
        eq(lessonSessions.userId, userId),
        eq(lessonSessions.status, 'completed')
      )
    )
    .orderBy(desc(lessonSessions.completedAt))
    .limit(1);
  return (rows[0] as LessonSessionRow | undefined) ?? null;
}

export interface UpsertProgressInput {
  userId: string;
  lessonId: string;
  sessionId: string;
  correctCount: number;
  totalCount: number;
  completedAt: Date;
}

// Drizzle's tx parameter is the same shape as AppDatabase for our purposes
// — same `select`/`insert`/`update`/`delete` surface — so the helper takes
// either. Using a structural type instead of importing Drizzle's
// `PgTransaction` keeps this file from depending on internal generics.
type TxLike = Pick<
  AppDatabase,
  'select' | 'insert' | 'update' | 'delete'
>;

/**
 * Aggregate update on session completion. The existing row (if any) is
 * locked with `FOR UPDATE` so two concurrent completions for the same
 * `(user, lesson)` cannot both read the same `attempts_count` and emit a
 * lost update. When no row exists yet, the insert races against the
 * unique index — the loser catches the unique-violation, retries, and
 * lands on the update path.
 */
async function upsertProgressInTx(
  tx: TxLike,
  input: UpsertProgressInput
): Promise<LessonProgressRow> {
  const existing = (
    await tx
      .select()
      .from(lessonProgress)
      .where(
        and(
          eq(lessonProgress.userId, input.userId),
          eq(lessonProgress.lessonId, input.lessonId)
        )
      )
      .for('update')
      .limit(1)
  )[0] as LessonProgressRow | undefined;

  if (!existing) {
    try {
      const inserted = await tx
        .insert(lessonProgress)
        .values({
          userId: input.userId,
          lessonId: input.lessonId,
          attemptsCount: 1,
          completed: true,
          latestCorrect: input.correctCount,
          latestTotal: input.totalCount,
          bestCorrect: input.correctCount,
          bestTotal: input.totalCount,
          lastSessionId: input.sessionId,
          firstCompletedAt: input.completedAt,
          lastCompletedAt: input.completedAt,
          updatedAt: input.completedAt,
        })
        .returning();
      return inserted[0] as LessonProgressRow;
    } catch (err) {
      if (!isUniqueViolation(err)) throw err;
      // A concurrent insert beat us. Re-read with FOR UPDATE so we land
      // on the update path with a locked row.
      const winner = (
        await tx
          .select()
          .from(lessonProgress)
          .where(
            and(
              eq(lessonProgress.userId, input.userId),
              eq(lessonProgress.lessonId, input.lessonId)
            )
          )
          .for('update')
          .limit(1)
      )[0] as LessonProgressRow | undefined;
      if (!winner) throw err;
      return applyProgressUpdate(tx, winner, input);
    }
  }

  return applyProgressUpdate(tx, existing, input);
}

async function applyProgressUpdate(
  tx: TxLike,
  existing: LessonProgressRow,
  input: UpsertProgressInput
): Promise<LessonProgressRow> {
  const prevBestRatio =
    existing.bestTotal && existing.bestTotal > 0
      ? (existing.bestCorrect ?? 0) / existing.bestTotal
      : -1;
  const newRatio =
    input.totalCount > 0 ? input.correctCount / input.totalCount : -1;

  const bestCorrect =
    newRatio >= prevBestRatio ? input.correctCount : existing.bestCorrect;
  const bestTotal =
    newRatio >= prevBestRatio ? input.totalCount : existing.bestTotal;

  const updated = await tx
    .update(lessonProgress)
    .set({
      attemptsCount: existing.attemptsCount + 1,
      completed: true,
      latestCorrect: input.correctCount,
      latestTotal: input.totalCount,
      bestCorrect,
      bestTotal,
      lastSessionId: input.sessionId,
      firstCompletedAt: existing.firstCompletedAt ?? input.completedAt,
      lastCompletedAt: input.completedAt,
      updatedAt: input.completedAt,
    })
    .where(eq(lessonProgress.id, existing.id))
    .returning();
  return updated[0] as LessonProgressRow;
}

export async function upsertProgressOnCompletion(
  db: AppDatabase,
  input: UpsertProgressInput
): Promise<LessonProgressRow> {
  return db.transaction(async (tx) => upsertProgressInTx(tx, input));
}

export interface FinalizeCompletionInput {
  sessionId: string;
  userId: string;
  lessonId: string;
  correctCount: number;
  totalCount: number;
  completedAt: Date;
  debriefSnapshot: unknown;
}

export interface FinalizeCompletionResult {
  finalized: boolean;
  session: LessonSessionRow;
}

/**
 * Atomic in_progress -> completed transition plus lesson_progress upsert.
 *
 * The conditional UPDATE acts as a row-level race gate: only the call that
 * flips `status = 'in_progress'` to `'completed'` sees a RETURNING row and
 * is allowed to write the debrief snapshot and roll the outcome into
 * `lesson_progress`. The losing call gets `finalized = false` and the
 * already-finalised session row, so the route can return the persisted
 * payload without rebuilding the debrief or double-counting the attempt.
 */
export async function finalizeSessionCompletion(
  db: AppDatabase,
  input: FinalizeCompletionInput
): Promise<FinalizeCompletionResult> {
  return db.transaction(async (tx) => {
    const winner = await tx
      .update(lessonSessions)
      .set({
        status: 'completed',
        correctCount: input.correctCount,
        completedAt: input.completedAt,
        lastActivityAt: input.completedAt,
        debriefSnapshot: input.debriefSnapshot as object,
      })
      .where(
        and(
          eq(lessonSessions.id, input.sessionId),
          eq(lessonSessions.status, 'in_progress')
        )
      )
      .returning();

    const winnerRow = winner[0] as LessonSessionRow | undefined;
    if (!winnerRow) {
      const current = (
        await tx
          .select()
          .from(lessonSessions)
          .where(eq(lessonSessions.id, input.sessionId))
          .limit(1)
      )[0] as LessonSessionRow | undefined;
      if (!current) throw new Error('session_disappeared_during_complete');
      return { finalized: false, session: current };
    }

    await upsertProgressInTx(tx, {
      userId: input.userId,
      lessonId: input.lessonId,
      sessionId: input.sessionId,
      correctCount: input.correctCount,
      totalCount: input.totalCount,
      completedAt: input.completedAt,
    });

    return { finalized: true, session: winnerRow };
  });
}

/**
 * For the dashboard: count of distinct exercises that have at least one
 * attempt row in each session. The session row's `correct_count` is
 * frozen at completion time and cannot be reused as an "answered"
 * indicator for in-progress sessions.
 */
export async function countAnsweredPerSession(
  db: AppDatabase,
  sessionIds: string[]
): Promise<Map<string, number>> {
  if (sessionIds.length === 0) return new Map();
  const rows = await db
    .select({
      sessionId: exerciseAttempts.sessionId,
      cnt: sql<number>`count(distinct ${exerciseAttempts.exerciseId})::int`,
    })
    .from(exerciseAttempts)
    .where(inArray(exerciseAttempts.sessionId, sessionIds))
    .groupBy(exerciseAttempts.sessionId);
  return new Map(
    rows.map((r) => [r.sessionId as string, Number(r.cnt) || 0])
  );
}

// Diagnostic helper. The DB-level `correct_count` column is only refreshed
// on completion; for live in_progress sessions we re-derive it on demand.
export async function computeLatestCorrectCount(
  db: AppDatabase,
  sessionId: string
): Promise<number> {
  const latest = await listLatestAttemptsForSession(db, sessionId);
  return latest.filter((a) => a.correct).length;
}

// Used by the lesson-sessions tests to assert raw counts.
export async function countAttempts(
  db: AppDatabase,
  sessionId: string
): Promise<number> {
  const rows = await db
    .select({ c: sql<number>`count(*)::int` })
    .from(exerciseAttempts)
    .where(eq(exerciseAttempts.sessionId, sessionId));
  return Number(rows[0]?.c ?? 0);
}
