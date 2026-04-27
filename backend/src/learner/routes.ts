import { Router } from 'express';
import { z } from 'zod';
import type { AppDatabase } from '../db/client';
import { requireAuth, type AuthedRequest } from '../auth/middleware';
import {
  bulkImportLearnerState,
  deriveStatus,
  getReviewSchedule,
  getSkillRecord,
  listAllSkillRecords,
  listDueReviews,
  recordAttempt,
  recordSessionEnd,
} from './service';
import { logAuditEvent } from '../auth/events';
import {
  EVIDENCE_TIERS,
  TARGET_ERROR_CODES,
  type LearnerSkillRecord,
  type ReviewScheduleRecord,
} from './types';

const SkillIdSchema = z.string().min(1).max(120).regex(/^[a-zA-Z0-9._-]+$/);

const RecordAttemptSchema = z.object({
  evidence_tier: z.enum(['weak', 'medium', 'strong', 'strongest']),
  correct: z.boolean(),
  primary_target_error: z.enum(TARGET_ERROR_CODES as [string, ...string[]]).optional(),
  meaning_frame: z.string().min(1).max(500).optional(),
  evaluation_version: z.number().int().nonnegative().optional(),
  // Wave 10 — V1 mastery gate inputs.
  exercise_type: z.string().min(1).max(64).optional(),
  outcome: z.enum(['correct', 'partial', 'wrong']).optional(),
});

const RecordCadenceSchema = z.object({
  mistakes_in_session: z.number().int().min(0).max(1000),
});

const BulkImportSkillSchema = z.object({
  skill_id: SkillIdSchema,
  mastery_score: z.number().int().min(0).max(100),
  last_attempt_at: z.string().datetime().optional(),
  evidence_summary: z.record(z.enum(['weak', 'medium', 'strong', 'strongest']), z.number().int().nonnegative()).optional(),
  recent_errors: z.array(z.enum(TARGET_ERROR_CODES as [string, ...string[]])).optional(),
  production_gate_cleared: z.boolean().optional(),
  gate_cleared_at_version: z.number().int().nonnegative().optional(),
});

const BulkImportScheduleSchema = z.object({
  skill_id: SkillIdSchema,
  step: z.number().int().min(1).max(5),
  due_at: z.string().datetime(),
  last_outcome_at: z.string().datetime(),
  last_outcome_mistakes: z.number().int().min(0).max(1000),
  graduated: z.boolean().optional(),
});

const BulkImportSchema = z.object({
  learner_skills: z.array(BulkImportSkillSchema).max(500),
  review_schedules: z.array(BulkImportScheduleSchema).max(500),
});

function recordToDto(record: LearnerSkillRecord, now: Date) {
  const evidence: Record<string, number> = {};
  for (const tier of EVIDENCE_TIERS) {
    evidence[tier] = record.evidenceSummary[tier] ?? 0;
  }
  return {
    skill_id: record.skillId,
    mastery_score: record.masteryScore,
    last_attempt_at: record.lastAttemptAt?.toISOString() ?? null,
    evidence_summary: evidence,
    recent_errors: record.recentErrors,
    production_gate_cleared: record.productionGateCleared,
    gate_cleared_at_version: record.gateClearedAtVersion,
    status: deriveStatus(record, now),
  };
}

function scheduleToDto(record: ReviewScheduleRecord) {
  return {
    skill_id: record.skillId,
    step: record.step,
    due_at: record.dueAt.toISOString(),
    last_outcome_at: record.lastOutcomeAt.toISOString(),
    last_outcome_mistakes: record.lastOutcomeMistakes,
    graduated: record.graduated,
  };
}

export function makeLearnerRouter(db: AppDatabase): Router {
  const router = Router();
  const auth = requireAuth(db);

  // Per-skill mastery state — Flutter LearnerSkillStore mirror.

  router.post('/me/skills/:skillId/attempts', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const skillId = req.params.skillId;
      if (!SkillIdSchema.safeParse(skillId).success) {
        res.status(400).json({ error: 'invalid_skill_id' });
        return;
      }
      const parsed = RecordAttemptSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({ error: 'invalid_payload' });
        return;
      }
      const updated = await recordAttempt(db, userId, skillId, {
        evidenceTier: parsed.data.evidence_tier,
        correct: parsed.data.correct,
        primaryTargetError: parsed.data.primary_target_error as
          | (typeof TARGET_ERROR_CODES)[number]
          | undefined,
        meaningFrame: parsed.data.meaning_frame,
        evaluationVersion: parsed.data.evaluation_version,
        exerciseType: parsed.data.exercise_type,
        outcome: parsed.data.outcome,
      });
      res.json(recordToDto(updated, new Date()));
    } catch (err) {
      next(err);
    }
  });

  router.get('/me/skills/:skillId', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const skillId = req.params.skillId;
      if (!SkillIdSchema.safeParse(skillId).success) {
        res.status(400).json({ error: 'invalid_skill_id' });
        return;
      }
      const record = await getSkillRecord(db, userId, skillId);
      res.json(recordToDto(record, new Date()));
    } catch (err) {
      next(err);
    }
  });

  router.get('/me/skills', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const records = await listAllSkillRecords(db, userId);
      const now = new Date();
      res.json({ skills: records.map((r) => recordToDto(r, now)) });
    } catch (err) {
      next(err);
    }
  });

  // Cross-session review cadence — Flutter ReviewScheduler mirror.

  router.post(
    '/me/skills/:skillId/review-cadence',
    auth,
    async (req, res, next) => {
      try {
        const userId = (req as AuthedRequest).auth.userId;
        const skillId = req.params.skillId;
        if (!SkillIdSchema.safeParse(skillId).success) {
          res.status(400).json({ error: 'invalid_skill_id' });
          return;
        }
        const parsed = RecordCadenceSchema.safeParse(req.body);
        if (!parsed.success) {
          res.status(400).json({ error: 'invalid_payload' });
          return;
        }
        const updated = await recordSessionEnd(db, userId, skillId, {
          mistakesInSession: parsed.data.mistakes_in_session,
        });
        res.json(scheduleToDto(updated));
      } catch (err) {
        next(err);
      }
    }
  );

  router.get(
    '/me/skills/:skillId/review-cadence',
    auth,
    async (req, res, next) => {
      try {
        const userId = (req as AuthedRequest).auth.userId;
        const skillId = req.params.skillId;
        if (!SkillIdSchema.safeParse(skillId).success) {
          res.status(400).json({ error: 'invalid_skill_id' });
          return;
        }
        const schedule = await getReviewSchedule(db, userId, skillId);
        if (!schedule) {
          res.status(404).json({ error: 'no_schedule' });
          return;
        }
        res.json(scheduleToDto(schedule));
      } catch (err) {
        next(err);
      }
    }
  );

  // Wave 7.4 part 2.4 — bulk migration from device-scoped state on
  // first sign-in. Idempotent: already-present (user, skill) rows on
  // the server are preserved; the response reports which skills were
  // adopted vs skipped so the client knows what to clear locally.
  router.post('/me/state/bulk-import', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const parsed = BulkImportSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({ error: 'invalid_payload' });
        return;
      }
      const result = await bulkImportLearnerState(db, userId, {
        learnerSkills: parsed.data.learner_skills.map((s) => ({
          skillId: s.skill_id,
          masteryScore: s.mastery_score,
          lastAttemptAt: s.last_attempt_at ? new Date(s.last_attempt_at) : undefined,
          evidenceSummary: s.evidence_summary as
            | Partial<Record<'weak' | 'medium' | 'strong' | 'strongest', number>>
            | undefined,
          recentErrors: s.recent_errors as
            | (typeof TARGET_ERROR_CODES)[number][]
            | undefined,
          productionGateCleared: s.production_gate_cleared,
          gateClearedAtVersion: s.gate_cleared_at_version,
        })),
        reviewSchedules: parsed.data.review_schedules.map((r) => ({
          skillId: r.skill_id,
          step: r.step,
          dueAt: new Date(r.due_at),
          lastOutcomeAt: new Date(r.last_outcome_at),
          lastOutcomeMistakes: r.last_outcome_mistakes,
          graduated: r.graduated,
        })),
      });
      // Audit so we can investigate any future "I lost my progress"
      // report. Payload kept small — counts only, not the full payload.
      await logAuditEvent(db, {
        userId,
        eventType: 'learner_state.bulk_import',
        payload: {
          imported_skills: result.importedSkills.length,
          skipped_skills: result.skippedSkills.length,
          imported_schedules: result.importedSchedules.length,
          skipped_schedules: result.skippedSchedules.length,
        },
      });
      res.json({
        imported_skill_ids: result.importedSkills,
        skipped_skill_ids: result.skippedSkills,
        imported_schedule_skill_ids: result.importedSchedules,
        skipped_schedule_skill_ids: result.skippedSchedules,
      });
    } catch (err) {
      next(err);
    }
  });

  router.get('/me/reviews/due', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const atParam = typeof req.query.at === 'string' ? req.query.at : null;
      const at = atParam ? new Date(atParam) : new Date();
      if (Number.isNaN(at.getTime())) {
        res.status(400).json({ error: 'invalid_at' });
        return;
      }
      const due = await listDueReviews(db, userId, at);
      res.json({ at: at.toISOString(), reviews: due.map(scheduleToDto) });
    } catch (err) {
      next(err);
    }
  });

  return router;
}
