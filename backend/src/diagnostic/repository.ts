// Wave 12.2 — typed selects/inserts/updates on `diagnostic_runs`.
//
// Mirrors the lessonSessions/repository.ts shape: standalone async
// functions taking the Drizzle handle (AppDatabase) first. The
// active-run invariant ("at most one in_progress run per user") is
// enforced by the partial unique index in the migration; this module
// reads + writes through that invariant but does not duplicate the
// check.

import { and, desc, eq } from 'drizzle-orm';
import type { AppDatabase } from '../db/client';
import { diagnosticRuns } from '../db/schema';

export type DiagnosticRunStatus =
  | 'in_progress'
  | 'completed'
  | 'abandoned';

export interface DiagnosticResponseRow {
  exercise_id: string;
  skill_id: string | null;
  evidence_tier: string | null;
  correct: boolean;
  submitted_at: string;
}

export interface DiagnosticRunRow {
  id: string;
  userId: string;
  status: DiagnosticRunStatus;
  exerciseIds: string[];
  responses: DiagnosticResponseRow[];
  cefrLevel: string | null;
  skillMap: Record<string, string> | null;
  startedAt: Date;
  completedAt: Date | null;
  createdAt: Date;
}

function rowFromDrizzle(
  r: typeof diagnosticRuns.$inferSelect
): DiagnosticRunRow {
  return {
    id: r.id,
    userId: r.userId,
    status: r.status as DiagnosticRunStatus,
    exerciseIds: (r.exerciseIds as string[] | null) ?? [],
    responses: (r.responses as DiagnosticResponseRow[] | null) ?? [],
    cefrLevel: r.cefrLevel,
    skillMap: r.skillMap as Record<string, string> | null,
    startedAt: r.startedAt,
    completedAt: r.completedAt,
    createdAt: r.createdAt,
  };
}

export async function findActiveRun(
  db: AppDatabase,
  userId: string
): Promise<DiagnosticRunRow | undefined> {
  const rows = await db
    .select()
    .from(diagnosticRuns)
    .where(
      and(
        eq(diagnosticRuns.userId, userId),
        eq(diagnosticRuns.status, 'in_progress')
      )
    )
    .limit(1);
  return rows[0] ? rowFromDrizzle(rows[0]) : undefined;
}

export async function findRunById(
  db: AppDatabase,
  runId: string
): Promise<DiagnosticRunRow | undefined> {
  const rows = await db
    .select()
    .from(diagnosticRuns)
    .where(eq(diagnosticRuns.id, runId))
    .limit(1);
  return rows[0] ? rowFromDrizzle(rows[0]) : undefined;
}

export async function findLatestRun(
  db: AppDatabase,
  userId: string
): Promise<DiagnosticRunRow | undefined> {
  const rows = await db
    .select()
    .from(diagnosticRuns)
    .where(eq(diagnosticRuns.userId, userId))
    .orderBy(desc(diagnosticRuns.startedAt))
    .limit(1);
  return rows[0] ? rowFromDrizzle(rows[0]) : undefined;
}

export async function insertRun(
  db: AppDatabase,
  input: { userId: string; exerciseIds: string[] }
): Promise<DiagnosticRunRow> {
  const [row] = await db
    .insert(diagnosticRuns)
    .values({
      userId: input.userId,
      status: 'in_progress',
      exerciseIds: input.exerciseIds,
      responses: [],
    })
    .returning();
  return rowFromDrizzle(row);
}

export async function appendResponse(
  db: AppDatabase,
  runId: string,
  response: DiagnosticResponseRow
): Promise<DiagnosticRunRow | undefined> {
  // Read-modify-write through Drizzle. Concurrent submissions on the
  // same run are guarded at the service layer (only one in_progress
  // run per user; client orchestrates one /answers at a time).
  const current = await findRunById(db, runId);
  if (!current) return undefined;
  const next = [...current.responses, response];
  const [row] = await db
    .update(diagnosticRuns)
    .set({ responses: next })
    .where(eq(diagnosticRuns.id, runId))
    .returning();
  return row ? rowFromDrizzle(row) : undefined;
}

export async function markCompleted(
  db: AppDatabase,
  runId: string,
  input: {
    cefrLevel: string;
    skillMap: Record<string, string>;
    completedAt: Date;
  }
): Promise<DiagnosticRunRow | undefined> {
  const [row] = await db
    .update(diagnosticRuns)
    .set({
      status: 'completed',
      cefrLevel: input.cefrLevel,
      skillMap: input.skillMap,
      completedAt: input.completedAt,
    })
    .where(eq(diagnosticRuns.id, runId))
    .returning();
  return row ? rowFromDrizzle(row) : undefined;
}

export async function markAbandoned(
  db: AppDatabase,
  runId: string
): Promise<DiagnosticRunRow | undefined> {
  const [row] = await db
    .update(diagnosticRuns)
    .set({ status: 'abandoned', completedAt: new Date() })
    .where(eq(diagnosticRuns.id, runId))
    .returning();
  return row ? rowFromDrizzle(row) : undefined;
}
