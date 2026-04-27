// Wave 11.2 — dynamic session routes.
//
// Mounts under the same Express app as `lessonSessions/routes.ts`. The
// legacy `POST /lessons/:id/sessions/start` and
// `GET /lessons/:id/sessions/current` endpoints stay live; this router
// adds the V1 dynamic counterparts:
//
//   - `POST /sessions/start` — auth, creates a dynamic session and
//     returns the first picked exercise.
//   - `POST /lesson-sessions/:sid/next` — auth, returns the next picked
//     exercise based on the running session's attempt history. Client
//     calls this after each `POST /lesson-sessions/:sid/answers`.
//
// The shared `/lesson-sessions/:sid/answers`, `/complete`, and
// `/result` endpoints already work for dynamic sessions because they
// don't rely on `session.lessonId` for the bank lookup any more —
// `submitAnswer` resolves the exercise via `getBankEntry` first.

import { Router } from 'express';

import type { AppDatabase } from '../db/client';
import { requireAuth, type AuthedRequest } from '../auth/middleware';
import { projectExerciseForClient } from '../data/exerciseProjection';
import {
  startDynamicSession,
  pickNextForSession,
} from './dynamicService';
import { LessonSessionError } from '../lessonSessions/service';

function handleError(
  err: unknown,
  res: import('express').Response
): boolean {
  if (err instanceof LessonSessionError) {
    res.status(err.status).json({ error: err.code });
    return true;
  }
  return false;
}

export function makeDynamicSessionsRouter(db: AppDatabase): Router {
  const router = Router();
  const auth = requireAuth(db);

  router.post('/sessions/start', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const { session, firstExercise, reason } = await startDynamicSession(
        db,
        userId
      );
      res.json({
        reason,
        session_id: session.id,
        // Wave 11.2: surface the new "Today's session" framing to
        // clients without an authoring lesson title.
        title: 'Today\u2019s session',
        level: 'B2',
        exercise_count: session.exerciseCount,
        started_at: session.startedAt.toISOString(),
        first_exercise: projectExerciseForClient(firstExercise.exercise),
      });
    } catch (err) {
      if (handleError(err, res)) return;
      next(err);
    }
  });

  router.post(
    '/lesson-sessions/:sessionId/next',
    auth,
    async (req, res, next) => {
      try {
        const userId = (req as AuthedRequest).auth.userId;
        const sessionId = req.params.sessionId;
        const result = await pickNextForSession(db, userId, sessionId);
        res.json({
          reason: result.reason,
          position: result.position,
          next_exercise: result.next
            ? projectExerciseForClient(result.next.exercise)
            : null,
        });
      } catch (err) {
        if (handleError(err, res)) return;
        next(err);
      }
    }
  );

  return router;
}
