// Wave 12.2 — diagnostic-mode service.
//
// Orchestrates the four /diagnostic/... endpoints:
//
//   - start    : find active run or create one; return next item.
//   - answers  : evaluate, persist response, augment learner_skills.
//   - complete : derive CEFR + skill_map, persist on the run +
//                user_profiles row, write audit_event.
//   - restart  : abandon any active run, then start a fresh one.
//                The probe AUGMENTS, never resets, so learner_skills
//                is left untouched per V1 spec §15.
//
// Hard rules (LEARNING_ENGINE.md §10 + V1 plan §12):
//   - All probe items must be drawn from `getDiagnosticPool()`. The
//     loader falls back to the first 5 flat-bank entries when nothing
//     is tagged, so the route works on a partially-tagged bank.
//   - Diagnostic items still serve in regular sessions; the run does
//     not block them out of `lesson_sessions` flows.
//   - Per V1 spec, the probe never penalises. Wrong answers contribute
//     `started` status; nothing is ever decremented from
//     `learner_skills`.

import { and, eq } from 'drizzle-orm';
import type { AppDatabase } from '../db/client';
import { logAuditEvent } from '../auth/events';
import { getBankEntry, getDiagnosticPool, type BankEntry } from '../data/exerciseBank';
import { evaluateMultipleChoice } from '../evaluators/multipleChoice';
import { recordAttempt } from '../learner/service';
import type { EvidenceTier } from '../learner/types';
import { userProfiles } from '../db/schema';
import {
  appendResponse,
  findActiveRun,
  findRunById,
  insertRun,
  markAbandoned,
  markCompleted,
  type DiagnosticRunRow,
} from './repository';
import { deriveCefrFromRun } from './cefr';

export class DiagnosticError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string, message?: string) {
    super(message ?? code);
    this.status = status;
    this.code = code;
  }
}

export interface DiagnosticStartResult {
  run: DiagnosticRunRow;
  nextExercise: BankEntry | null;
  resumed: boolean;
}

export async function startOrResumeDiagnostic(
  db: AppDatabase,
  userId: string
): Promise<DiagnosticStartResult> {
  const active = await findActiveRun(db, userId);
  if (active) {
    return {
      run: active,
      nextExercise: nextItemFor(active),
      resumed: true,
    };
  }
  const pool = getDiagnosticPool();
  if (pool.length === 0) {
    throw new DiagnosticError(503, 'diagnostic_pool_empty');
  }
  // Probe order is whatever the bank loader returned. The
  // tag-based path returns one item per skill; the fallback returns
  // `flat.slice(0, 5)` which lands the same 5 items in source order.
  const exerciseIds = pool.map((entry) => entry.exercise.exercise_id);
  const run = await insertRun(db, { userId, exerciseIds });
  return {
    run,
    nextExercise: nextItemFor(run),
    resumed: false,
  };
}

function nextItemFor(run: DiagnosticRunRow): BankEntry | null {
  if (run.responses.length >= run.exerciseIds.length) return null;
  const id = run.exerciseIds[run.responses.length];
  return getBankEntry(id) ?? null;
}

export interface DiagnosticAnswerInput {
  exerciseId: string;
  exerciseType: string;
  userAnswer: string;
  submittedAt?: Date;
}

export interface DiagnosticAnswerResult {
  run: DiagnosticRunRow;
  result: 'correct' | 'wrong';
  canonicalAnswer: string;
  explanation: string | null;
  evaluationSource: 'deterministic';
  nextExercise: BankEntry | null;
  runComplete: boolean;
}

export async function submitDiagnosticAnswer(
  db: AppDatabase,
  userId: string,
  runId: string,
  input: DiagnosticAnswerInput
): Promise<DiagnosticAnswerResult> {
  const run = await findRunById(db, runId);
  if (!run) throw new DiagnosticError(404, 'diagnostic_run_not_found');
  if (run.userId !== userId)
    throw new DiagnosticError(403, 'forbidden');
  if (run.status !== 'in_progress')
    throw new DiagnosticError(409, 'diagnostic_run_not_active');

  // The next expected exercise is positionally pinned to the run order
  // so a client cannot answer items out of order. This also blocks
  // the trivial double-submit case.
  const expected = nextItemFor(run);
  if (!expected)
    throw new DiagnosticError(409, 'diagnostic_run_already_complete');
  if (expected.exercise.exercise_id !== input.exerciseId)
    throw new DiagnosticError(409, 'diagnostic_answer_out_of_order');

  // V1 probe is multiple_choice only. Anything else is an authoring
  // mistake the bank loader caught at boot, but we double-check.
  if (expected.exercise.type !== 'multiple_choice')
    throw new DiagnosticError(500, 'diagnostic_unsupported_type');
  if (input.exerciseType !== 'multiple_choice')
    throw new DiagnosticError(400, 'exercise_type_mismatch');

  const evalResult = evaluateMultipleChoice(
    input.userAnswer,
    expected.exercise.correct_option_id,
    expected.exercise.options
  );

  const submittedAt = input.submittedAt ?? new Date();
  const updated = await appendResponse(db, run.id, {
    exercise_id: expected.exercise.exercise_id,
    skill_id: expected.exercise.skill_id ?? null,
    evidence_tier: expected.exercise.evidence_tier ?? null,
    correct: evalResult.correct,
    submitted_at: submittedAt.toISOString(),
  });
  if (!updated) throw new DiagnosticError(500, 'diagnostic_persist_failed');

  // Augment learner_skills so the probe contributes to the engine
  // state per "the probe augments, does not reset" rule. We feed it
  // through the same recordAttempt path the lesson sessions use so
  // every downstream invariant (recent_errors, weighted accuracy,
  // exercise_types_seen) stays consistent.
  if (expected.exercise.skill_id && expected.exercise.evidence_tier) {
    await recordAttempt(db, userId, expected.exercise.skill_id, {
      evidenceTier: expected.exercise.evidence_tier as EvidenceTier,
      correct: evalResult.correct,
      primaryTargetError: expected.exercise.primary_target_error,
      meaningFrame: expected.exercise.meaning_frame,
      occurredAt: submittedAt,
      exerciseType: 'multiple_choice',
      outcome: evalResult.correct ? 'correct' : 'wrong',
    });
  }

  const nextExercise = nextItemFor(updated);
  const runComplete = nextExercise === null;

  return {
    run: updated,
    result: evalResult.correct ? 'correct' : 'wrong',
    canonicalAnswer: evalResult.canonical_answer,
    explanation: expected.exercise.feedback?.explanation ?? null,
    evaluationSource: evalResult.evaluation_source,
    nextExercise,
    runComplete,
  };
}

export interface DiagnosticCompleteResult {
  run: DiagnosticRunRow;
  cefrLevel: string;
  skillMap: Record<string, string>;
  alreadyCompleted: boolean;
}

export async function completeDiagnostic(
  db: AppDatabase,
  userId: string,
  runId: string
): Promise<DiagnosticCompleteResult> {
  const run = await findRunById(db, runId);
  if (!run) throw new DiagnosticError(404, 'diagnostic_run_not_found');
  if (run.userId !== userId)
    throw new DiagnosticError(403, 'forbidden');

  if (run.status === 'completed' && run.cefrLevel && run.skillMap) {
    // Idempotent re-call: return the persisted derivation untouched.
    return {
      run,
      cefrLevel: run.cefrLevel,
      skillMap: run.skillMap,
      alreadyCompleted: true,
    };
  }

  // V1 plan: a partial run that finishes early should still derive a
  // CEFR. We don't gate on "all items answered" because the client
  // may surface a "Finish now" affordance, and an incomplete probe is
  // still better than nothing. The skill_map only records skills the
  // learner actually saw.
  const derivation = deriveCefrFromRun(run.responses);

  const completedAt = new Date();
  const updated = await markCompleted(db, runId, {
    cefrLevel: derivation.cefrLevel,
    skillMap: derivation.skillMap,
    completedAt,
  });
  if (!updated) throw new DiagnosticError(500, 'diagnostic_persist_failed');

  // Stamp the derived level on user_profiles.level so the dashboard
  // can render "Welcome — your level is B2". user_profiles is
  // primary-key'd by user_id; upsert-style write so the row is
  // created on first completion.
  await db
    .insert(userProfiles)
    .values({ userId, level: derivation.cefrLevel })
    .onConflictDoUpdate({
      target: userProfiles.userId,
      set: { level: derivation.cefrLevel, updatedAt: new Date() },
    });

  await logAuditEvent(db, {
    userId,
    eventType: 'diagnostic_completed',
    payload: {
      run_id: runId,
      cefr_level: derivation.cefrLevel,
      total_correct: derivation.totalCorrect,
      total_answered: derivation.totalAnswered,
      skills_touched: Object.keys(derivation.skillMap),
    },
  });

  return {
    run: updated,
    cefrLevel: derivation.cefrLevel,
    skillMap: derivation.skillMap,
    alreadyCompleted: false,
  };
}

export async function restartDiagnostic(
  db: AppDatabase,
  userId: string
): Promise<DiagnosticStartResult> {
  const active = await findActiveRun(db, userId);
  if (active) {
    await markAbandoned(db, active.id);
    await logAuditEvent(db, {
      userId,
      eventType: 'diagnostic_abandoned',
      payload: {
        run_id: active.id,
        responses_count: active.responses.length,
      },
    });
  }
  return startOrResumeDiagnostic(db, userId);
}

export async function logSkippedDiagnostic(
  db: AppDatabase,
  userId: string
): Promise<void> {
  await logAuditEvent(db, {
    userId,
    eventType: 'diagnostic_skipped',
    payload: {},
  });
}
