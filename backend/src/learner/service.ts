import { eq, and, lte } from 'drizzle-orm';
import type { AppDatabase } from '../db/client';
import { learnerSkills, learnerReviewSchedule } from '../db/schema';
import type {
  EvidenceTier,
  LearnerSkillRecord,
  ReviewScheduleRecord,
  SkillStatus,
  TargetError,
} from './types';
import { EVIDENCE_TIERS, TARGET_ERROR_CODES } from './types';

export class LearnerStateError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
  }
}

const RECENT_ERRORS_CAP = 5;

// V0 score deltas — match Flutter LearnerSkillStore._scoreDelta.
function scoreDelta(tier: EvidenceTier, correct: boolean): number {
  const base =
    tier === 'weak'
      ? 5
      : tier === 'medium'
        ? 10
        : tier === 'strong'
          ? 15
          : 20;
  return correct ? base : -base;
}

/// Status derivation per §7.2. Labels are the contract; thresholds are
/// V0 and tunable. Mirrors Flutter LearnerSkillRecord.statusAt.
export function deriveStatus(
  record: LearnerSkillRecord,
  now: Date
): SkillStatus {
  const strongOrStronger =
    (record.evidenceSummary.strong ?? 0) +
    (record.evidenceSummary.strongest ?? 0);

  if (
    record.productionGateCleared &&
    strongOrStronger > 0 &&
    record.masteryScore >= 80
  ) {
    if (
      record.lastAttemptAt &&
      now.getTime() - record.lastAttemptAt.getTime() > 21 * 24 * 60 * 60 * 1000
    ) {
      return 'review_due';
    }
    return 'mastered';
  }
  if (record.masteryScore >= 70 && strongOrStronger > 0) return 'almost_mastered';
  if (record.masteryScore >= 50 && strongOrStronger > 0) return 'getting_there';
  if (record.masteryScore >= 30) return 'practicing';
  return 'started';
}

/// Cadence intervals per §9.3.
export function intervalForStep(step: number): number {
  // milliseconds
  const day = 24 * 60 * 60 * 1000;
  if (step <= 1) return day;
  if (step === 2) return 3 * day;
  if (step === 3) return 7 * day;
  return 21 * day;
}

function emptyRecord(skillId: string): LearnerSkillRecord {
  return {
    skillId,
    masteryScore: 0,
    lastAttemptAt: null,
    evidenceSummary: { weak: 0, medium: 0, strong: 0, strongest: 0 },
    recentErrors: [],
    productionGateCleared: false,
    gateClearedAtVersion: null,
  };
}

function rowToRecord(row: any): LearnerSkillRecord {
  const ev: Record<EvidenceTier, number> = {
    weak: 0,
    medium: 0,
    strong: 0,
    strongest: 0,
  };
  if (row.evidenceSummary && typeof row.evidenceSummary === 'object') {
    for (const tier of EVIDENCE_TIERS) {
      const v = (row.evidenceSummary as Record<string, unknown>)[tier];
      if (typeof v === 'number') ev[tier] = v;
    }
  }
  const errors: TargetError[] = [];
  if (Array.isArray(row.recentErrors)) {
    for (const e of row.recentErrors) {
      if (TARGET_ERROR_CODES.includes(e)) errors.push(e as TargetError);
    }
  }
  return {
    skillId: row.skillId,
    masteryScore: row.masteryScore ?? 0,
    lastAttemptAt: row.lastAttemptAt ?? null,
    evidenceSummary: ev,
    recentErrors: errors,
    productionGateCleared: row.productionGateCleared ?? false,
    gateClearedAtVersion: row.gateClearedAtVersion ?? null,
  };
}

function rowToSchedule(row: any): ReviewScheduleRecord {
  return {
    skillId: row.skillId,
    step: row.step ?? 1,
    dueAt: row.dueAt,
    lastOutcomeAt: row.lastOutcomeAt,
    lastOutcomeMistakes: row.lastOutcomeMistakes ?? 0,
    graduated: row.graduated ?? false,
  };
}

export interface RecordAttemptInput {
  evidenceTier: EvidenceTier;
  correct: boolean;
  primaryTargetError?: TargetError;
  meaningFrame?: string;
  evaluationVersion?: number;
  occurredAt?: Date;
}

/// Records one attempt for one skill. Mirrors Flutter
/// `LearnerSkillStore.recordAttempt`. The §12.3 production-gate
/// invalidation pivot fires when `evaluationVersion` is greater than
/// the existing `gateClearedAtVersion`.
export async function recordAttempt(
  db: AppDatabase,
  userId: string,
  skillId: string,
  input: RecordAttemptInput
): Promise<LearnerSkillRecord> {
  const now = input.occurredAt ?? new Date();
  const existingRows = await db
    .select()
    .from(learnerSkills)
    .where(
      and(eq(learnerSkills.userId, userId), eq(learnerSkills.skillId, skillId))
    )
    .limit(1);
  let existing: LearnerSkillRecord =
    existingRows.length > 0
      ? rowToRecord(existingRows[0])
      : emptyRecord(skillId);

  // §12.3 invalidation. If the gate was previously cleared at a lower
  // evaluator version than what just shipped, drop it before applying
  // this attempt's effect.
  if (
    existing.productionGateCleared &&
    input.evaluationVersion !== undefined &&
    existing.gateClearedAtVersion !== null &&
    input.evaluationVersion > existing.gateClearedAtVersion
  ) {
    existing = {
      ...existing,
      productionGateCleared: false,
      gateClearedAtVersion: null,
    };
  }

  const summary: Record<EvidenceTier, number> = { ...existing.evidenceSummary };
  summary[input.evidenceTier] = (summary[input.evidenceTier] ?? 0) + 1;

  const score = Math.max(
    0,
    Math.min(
      100,
      existing.masteryScore + scoreDelta(input.evidenceTier, input.correct)
    )
  );

  const errors: TargetError[] = [...existing.recentErrors];
  if (!input.correct && input.primaryTargetError) {
    errors.push(input.primaryTargetError);
    while (errors.length > RECENT_ERRORS_CAP) errors.shift();
  }

  // Production gate per §6.4: a strongest-tier correct attempt that
  // also carries a non-empty meaning_frame (the §6.3 meaning+form proof).
  const gateClearedThisAttempt =
    input.correct &&
    input.evidenceTier === 'strongest' &&
    input.meaningFrame !== undefined &&
    input.meaningFrame.trim().length > 0;
  const gate = existing.productionGateCleared || gateClearedThisAttempt;
  const gateVersion = !gate
    ? null
    : gateClearedThisAttempt
      ? input.evaluationVersion ?? existing.gateClearedAtVersion
      : existing.gateClearedAtVersion;

  const next: LearnerSkillRecord = {
    skillId,
    masteryScore: score,
    lastAttemptAt: now,
    evidenceSummary: summary,
    recentErrors: errors,
    productionGateCleared: gate,
    gateClearedAtVersion: gateVersion,
  };

  await db
    .insert(learnerSkills)
    .values({
      userId,
      skillId: next.skillId,
      masteryScore: next.masteryScore,
      lastAttemptAt: next.lastAttemptAt,
      evidenceSummary: next.evidenceSummary as Record<string, number>,
      recentErrors: next.recentErrors as string[],
      productionGateCleared: next.productionGateCleared,
      gateClearedAtVersion: next.gateClearedAtVersion,
      updatedAt: now,
    })
    .onConflictDoUpdate({
      target: [learnerSkills.userId, learnerSkills.skillId],
      set: {
        masteryScore: next.masteryScore,
        lastAttemptAt: next.lastAttemptAt,
        evidenceSummary: next.evidenceSummary as Record<string, number>,
        recentErrors: next.recentErrors as string[],
        productionGateCleared: next.productionGateCleared,
        gateClearedAtVersion: next.gateClearedAtVersion,
        updatedAt: now,
      },
    });

  return next;
}

export async function getSkillRecord(
  db: AppDatabase,
  userId: string,
  skillId: string
): Promise<LearnerSkillRecord> {
  const rows = await db
    .select()
    .from(learnerSkills)
    .where(
      and(eq(learnerSkills.userId, userId), eq(learnerSkills.skillId, skillId))
    )
    .limit(1);
  if (rows.length === 0) return emptyRecord(skillId);
  return rowToRecord(rows[0]);
}

export async function listAllSkillRecords(
  db: AppDatabase,
  userId: string
): Promise<LearnerSkillRecord[]> {
  const rows = await db
    .select()
    .from(learnerSkills)
    .where(eq(learnerSkills.userId, userId));
  return rows.map(rowToRecord);
}

export interface RecordSessionEndInput {
  mistakesInSession: number;
  occurredAt?: Date;
}

/// Records the in-session outcome for one skill at session end.
/// Mirrors Flutter `ReviewScheduler.recordSessionEnd`. Outcome rules:
/// any mistakes → cadence reset to step 1 (V0 over-conservative — §9.3
/// distinguishes review-session-vs-first-lesson, which Wave 7 does not
/// yet differentiate); zero mistakes → step advances by 1 (capped at 5).
/// Step 5 with no mistakes flags `graduated` per §9.4.
export async function recordSessionEnd(
  db: AppDatabase,
  userId: string,
  skillId: string,
  input: RecordSessionEndInput
): Promise<ReviewScheduleRecord> {
  const now = input.occurredAt ?? new Date();
  const existingRows = await db
    .select()
    .from(learnerReviewSchedule)
    .where(
      and(
        eq(learnerReviewSchedule.userId, userId),
        eq(learnerReviewSchedule.skillId, skillId)
      )
    )
    .limit(1);
  const priorStep =
    existingRows.length > 0 ? (existingRows[0].step ?? 0) : 0;

  const hadAnyMistakes = input.mistakesInSession > 0;
  const nextStep = hadAnyMistakes
    ? 1
    : Math.max(1, Math.min(5, priorStep + 1));
  const dueAt = new Date(now.getTime() + intervalForStep(nextStep));
  const graduated = !hadAnyMistakes && nextStep >= 5;

  const next: ReviewScheduleRecord = {
    skillId,
    step: nextStep,
    dueAt,
    lastOutcomeAt: now,
    lastOutcomeMistakes: input.mistakesInSession,
    graduated,
  };

  await db
    .insert(learnerReviewSchedule)
    .values({
      userId,
      skillId,
      step: next.step,
      dueAt: next.dueAt,
      lastOutcomeAt: next.lastOutcomeAt,
      lastOutcomeMistakes: next.lastOutcomeMistakes,
      graduated: next.graduated,
      updatedAt: now,
    })
    .onConflictDoUpdate({
      target: [learnerReviewSchedule.userId, learnerReviewSchedule.skillId],
      set: {
        step: next.step,
        dueAt: next.dueAt,
        lastOutcomeAt: next.lastOutcomeAt,
        lastOutcomeMistakes: next.lastOutcomeMistakes,
        graduated: next.graduated,
        updatedAt: now,
      },
    });

  return next;
}

export async function getReviewSchedule(
  db: AppDatabase,
  userId: string,
  skillId: string
): Promise<ReviewScheduleRecord | null> {
  const rows = await db
    .select()
    .from(learnerReviewSchedule)
    .where(
      and(
        eq(learnerReviewSchedule.userId, userId),
        eq(learnerReviewSchedule.skillId, skillId)
      )
    )
    .limit(1);
  if (rows.length === 0) return null;
  return rowToSchedule(rows[0]);
}

export interface BulkImportInput {
  /// Inbound learner_skills payload from a device that's about to clear
  /// its local LearnerSkillStore. Each entry is a snapshot of the
  /// device's record at a moment in time. Server keeps its own row for
  /// the (user, skill) when one already exists — the migration is
  /// idempotent and never clobbers server progress.
  learnerSkills: Array<{
    skillId: string;
    masteryScore: number;
    lastAttemptAt?: Date;
    evidenceSummary?: Partial<Record<EvidenceTier, number>>;
    recentErrors?: TargetError[];
    productionGateCleared?: boolean;
    gateClearedAtVersion?: number;
  }>;
  reviewSchedules: Array<{
    skillId: string;
    step: number;
    dueAt: Date;
    lastOutcomeAt: Date;
    lastOutcomeMistakes: number;
    graduated?: boolean;
  }>;
}

export interface BulkImportResult {
  /// Skill IDs from the inbound payload that the server adopted (no
  /// pre-existing row).
  importedSkills: string[];
  /// Skill IDs the server already had — skipped to avoid clobbering
  /// progress accumulated by other devices on the same account.
  skippedSkills: string[];
  importedSchedules: string[];
  skippedSchedules: string[];
}

/// Wave 7.4 part 2.4 — bulk migration from device-scoped state on first
/// sign-in. Designed to be safe to call multiple times: if the user has
/// already signed in on another device, that device's progress wins and
/// the inbound payload is discarded for the conflicting skill.
export async function bulkImportLearnerState(
  db: AppDatabase,
  userId: string,
  input: BulkImportInput
): Promise<BulkImportResult> {
  const result: BulkImportResult = {
    importedSkills: [],
    skippedSkills: [],
    importedSchedules: [],
    skippedSchedules: [],
  };

  for (const skill of input.learnerSkills) {
    const existing = await db
      .select()
      .from(learnerSkills)
      .where(
        and(
          eq(learnerSkills.userId, userId),
          eq(learnerSkills.skillId, skill.skillId)
        )
      )
      .limit(1);
    if (existing.length > 0) {
      result.skippedSkills.push(skill.skillId);
      continue;
    }
    // Normalise the inbound evidence summary so missing tiers default
    // to 0 rather than undefined.
    const ev: Record<EvidenceTier, number> = {
      weak: 0,
      medium: 0,
      strong: 0,
      strongest: 0,
    };
    if (skill.evidenceSummary) {
      for (const tier of EVIDENCE_TIERS) {
        const v = skill.evidenceSummary[tier];
        if (typeof v === 'number') ev[tier] = v;
      }
    }
    await db.insert(learnerSkills).values({
      userId,
      skillId: skill.skillId,
      masteryScore: Math.max(0, Math.min(100, skill.masteryScore)),
      lastAttemptAt: skill.lastAttemptAt ?? null,
      evidenceSummary: ev as Record<string, number>,
      recentErrors: (skill.recentErrors ?? []) as string[],
      productionGateCleared: skill.productionGateCleared ?? false,
      gateClearedAtVersion: skill.gateClearedAtVersion ?? null,
      updatedAt: new Date(),
    });
    result.importedSkills.push(skill.skillId);
  }

  for (const sched of input.reviewSchedules) {
    const existing = await db
      .select()
      .from(learnerReviewSchedule)
      .where(
        and(
          eq(learnerReviewSchedule.userId, userId),
          eq(learnerReviewSchedule.skillId, sched.skillId)
        )
      )
      .limit(1);
    if (existing.length > 0) {
      result.skippedSchedules.push(sched.skillId);
      continue;
    }
    await db.insert(learnerReviewSchedule).values({
      userId,
      skillId: sched.skillId,
      step: sched.step,
      dueAt: sched.dueAt,
      lastOutcomeAt: sched.lastOutcomeAt,
      lastOutcomeMistakes: sched.lastOutcomeMistakes,
      graduated: sched.graduated ?? false,
      updatedAt: new Date(),
    });
    result.importedSchedules.push(sched.skillId);
  }

  return result;
}

export async function listDueReviews(
  db: AppDatabase,
  userId: string,
  at: Date
): Promise<ReviewScheduleRecord[]> {
  const rows = await db
    .select()
    .from(learnerReviewSchedule)
    .where(
      and(
        eq(learnerReviewSchedule.userId, userId),
        eq(learnerReviewSchedule.graduated, false),
        lte(learnerReviewSchedule.dueAt, at)
      )
    );
  return rows.map(rowToSchedule).sort(
    (a, b) => a.dueAt.getTime() - b.dueAt.getTime()
  );
}
