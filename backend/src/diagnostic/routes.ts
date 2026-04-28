// Wave 12.2 — diagnostic-mode routes.
//
// Mounts under the same Express app. Four endpoints:
//
//   - POST /diagnostic/start          — auth, returns first item.
//   - POST /diagnostic/:id/answers    — auth, records attempt + next.
//   - POST /diagnostic/:id/complete   — auth, idempotent CEFR derive.
//   - POST /diagnostic/restart        — auth, abandon active + start.
//   - POST /diagnostic/skip           — auth, write-only telemetry.
//
// All routes require auth via the existing `requireAuth` middleware.
// Wave 7.4 product call: skip-for-now is still allowed (silent stub
// login on /auth/apple/stub/login covers the unauth case), and the
// Flutter client owns the routing decision; this route just lets the
// app declare the cohort intent for D1 retention analysis.

import { Router } from 'express';

import type { AppDatabase } from '../db/client';
import { requireAuth, type AuthedRequest } from '../auth/middleware';
import { projectExerciseForClient } from '../data/exerciseProjection';
import {
  DiagnosticError,
  completeDiagnostic,
  logSkippedDiagnostic,
  restartDiagnostic,
  startOrResumeDiagnostic,
  submitDiagnosticAnswer,
} from './service';

function handleDiagnosticError(
  err: unknown,
  res: import('express').Response
): boolean {
  if (err instanceof DiagnosticError) {
    res.status(err.status).json({ error: err.code });
    return true;
  }
  return false;
}

export function makeDiagnosticRouter(db: AppDatabase): Router {
  const router = Router();
  const auth = requireAuth(db);

  router.post('/diagnostic/start', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const { run, nextExercise, resumed } = await startOrResumeDiagnostic(
        db,
        userId
      );
      res.status(resumed ? 200 : 201).json({
        run_id: run.id,
        resumed,
        position: run.responses.length,
        total: run.exerciseIds.length,
        next_exercise: nextExercise
          ? projectExerciseForClient(nextExercise.exercise)
          : null,
      });
    } catch (err) {
      if (handleDiagnosticError(err, res)) return;
      next(err);
    }
  });

  router.post('/diagnostic/:runId/answers', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const runId = req.params.runId;
      const body = req.body ?? {};
      const exerciseId = typeof body.exercise_id === 'string' ? body.exercise_id : '';
      const exerciseType =
        typeof body.exercise_type === 'string' ? body.exercise_type : '';
      const userAnswer =
        typeof body.user_answer === 'string' ? body.user_answer : '';
      const submittedAt =
        typeof body.submitted_at === 'string'
          ? new Date(body.submitted_at)
          : new Date();
      if (!exerciseId || !exerciseType || !userAnswer) {
        res.status(400).json({ error: 'invalid_payload' });
        return;
      }
      const result = await submitDiagnosticAnswer(db, userId, runId, {
        exerciseId,
        exerciseType,
        userAnswer,
        submittedAt: Number.isNaN(submittedAt.getTime())
          ? undefined
          : submittedAt,
      });
      res.json({
        result: result.result,
        evaluation_source: result.evaluationSource,
        canonical_answer: result.canonicalAnswer,
        explanation: result.explanation,
        run_complete: result.runComplete,
        position: result.run.responses.length,
        total: result.run.exerciseIds.length,
        next_exercise: result.nextExercise
          ? projectExerciseForClient(result.nextExercise.exercise)
          : null,
      });
    } catch (err) {
      if (handleDiagnosticError(err, res)) return;
      next(err);
    }
  });

  router.post('/diagnostic/:runId/complete', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const runId = req.params.runId;
      const result = await completeDiagnostic(db, userId, runId);
      res.json({
        run_id: result.run.id,
        cefr_level: result.cefrLevel,
        skill_map: result.skillMap,
        completed_at: result.run.completedAt?.toISOString() ?? null,
        already_completed: result.alreadyCompleted,
      });
    } catch (err) {
      if (handleDiagnosticError(err, res)) return;
      next(err);
    }
  });

  router.post('/diagnostic/restart', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const { run, nextExercise } = await restartDiagnostic(db, userId);
      res.status(201).json({
        run_id: run.id,
        position: 0,
        total: run.exerciseIds.length,
        next_exercise: nextExercise
          ? projectExerciseForClient(nextExercise.exercise)
          : null,
      });
    } catch (err) {
      if (handleDiagnosticError(err, res)) return;
      next(err);
    }
  });

  router.post('/diagnostic/skip', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      await logSkippedDiagnostic(db, userId);
      res.status(204).send();
    } catch (err) {
      if (handleDiagnosticError(err, res)) return;
      next(err);
    }
  });

  return router;
}
