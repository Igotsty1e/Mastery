import { Router } from 'express';
import { z } from 'zod';
import type { AppDatabase } from '../db/client';
import { requireAuth, type AuthedRequest } from '../auth/middleware';
import type { AiProvider } from '../ai/interface';
import {
  completeSession,
  getResult,
  LessonSessionError,
  submitAnswer,
} from './service';
import {
  resolveRateLimitIp,
} from '../middleware/aiRateLimit';
import {
  type ExerciseAttemptRow,
  type LessonSessionRow,
} from './repository';

const Wave2AnswerSchema = z.object({
  attempt_id: z.string().uuid(),
  exercise_id: z.string().uuid(),
  exercise_type: z.enum([
    'fill_blank',
    'multiple_choice',
    'sentence_correction',
    'listening_discrimination',
  ]),
  user_answer: z.string().max(500),
  submitted_at: z.string().datetime(),
});

const UuidSchema = z.string().uuid();

// Anything that doesn't parse as a UUID can never match a real session
// row, so route-level rejection saves the DB a `WHERE id = ?` against a
// uuid column that would otherwise raise an `invalid_text_representation`
// 22P02 and surface as 500. Returning 404 mirrors the foreign-session
// case — same error code the client already handles.
function rejectIfNotUuid(value: string, res: import('express').Response): boolean {
  if (UuidSchema.safeParse(value).success) return false;
  res.status(404).json({ error: 'session_not_found' });
  return true;
}

interface SessionDto {
  session_id: string;
  lesson_id: string;
  lesson_version: string;
  status: 'in_progress' | 'completed' | string;
  started_at: string;
  last_activity_at: string;
  completed_at: string | null;
  exercise_count: number;
  answers_so_far: Array<{
    exercise_id: string;
    correct: boolean;
    canonical_answer: string;
    evaluation_source: string;
    explanation: string | null;
    submitted_at: string;
  }>;
}

function sessionToDto(
  session: LessonSessionRow,
  latestAttempts: ExerciseAttemptRow[]
): SessionDto {
  return {
    session_id: session.id,
    lesson_id: session.lessonId,
    lesson_version: session.lessonVersion,
    status: session.status,
    started_at: session.startedAt.toISOString(),
    last_activity_at: session.lastActivityAt.toISOString(),
    completed_at: session.completedAt ? session.completedAt.toISOString() : null,
    exercise_count: session.exerciseCount,
    answers_so_far: latestAttempts.map((a) => ({
      exercise_id: a.exerciseId,
      correct: a.correct,
      canonical_answer: a.canonicalAnswer,
      evaluation_source: a.evaluationSource,
      explanation: a.explanation,
      submitted_at: a.submittedAt.toISOString(),
    })),
  };
}

function handleError(err: unknown, res: import('express').Response): boolean {
  if (err instanceof LessonSessionError) {
    res.status(err.status).json({ error: err.code });
    return true;
  }
  return false;
}

export function makeLessonSessionsRouter(
  db: AppDatabase,
  ai: AiProvider
): Router {
  const router = Router();
  const auth = requireAuth(db);

  // Wave 11.4 (2026-04-26): the legacy lesson-bound session-start
  // endpoints are gone. Every session now boots through the dynamic
  // `POST /sessions/start` route in `sessions/routes.ts`, which the
  // Decision Engine drives off the bank.

  router.post('/lesson-sessions/:sessionId/answers', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const sessionId = req.params.sessionId;
      if (rejectIfNotUuid(sessionId, res)) return;
      const parsed = Wave2AnswerSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({ error: 'invalid_payload' });
        return;
      }
      const submittedAt = new Date(parsed.data.submitted_at);
      if (Number.isNaN(submittedAt.getTime())) {
        res.status(400).json({ error: 'invalid_payload' });
        return;
      }

      // Rate-limit consumption is now lazy inside the service: it only
      // fires when AI is actually about to be called (deterministic miss
      // + cache miss). Resolving the IP here just hands the limiter
      // context to the service so it can consume the budget at the
      // right moment. Codex P1 fix: deterministic-correct
      // sentence_correction submissions no longer burn quota.
      let clientIp: string | null = null;
      if (parsed.data.exercise_type === 'sentence_correction') {
        const ip = resolveRateLimitIp(req);
        if (!ip) {
          res.status(400).json({ error: 'invalid_request' });
          return;
        }
        clientIp = ip;
      }

      const result = await submitAnswer(db, userId, sessionId, ai, {
        exerciseId: parsed.data.exercise_id,
        exerciseType: parsed.data.exercise_type,
        userAnswer: parsed.data.user_answer,
        submittedAt,
        clientAttemptId: parsed.data.attempt_id,
        clientIp,
      });

      res.json({
        attempt_id: parsed.data.attempt_id,
        exercise_id: result.attempt.exerciseId,
        correct: result.evaluation.correct,
        evaluation_source: result.evaluation.evaluation_source,
        explanation: result.explanation,
        canonical_answer: result.evaluation.canonical_answer,
      });
    } catch (err) {
      if (handleError(err, res)) return;
      next(err);
    }
  });

  router.post('/lesson-sessions/:sessionId/complete', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const sessionId = req.params.sessionId;
      if (rejectIfNotUuid(sessionId, res)) return;
      const payload = await completeSession(db, userId, sessionId, ai);
      res.json(payload);
    } catch (err) {
      if (handleError(err, res)) return;
      next(err);
    }
  });

  router.get('/lesson-sessions/:sessionId/result', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const sessionId = req.params.sessionId;
      if (rejectIfNotUuid(sessionId, res)) return;
      const payload = await getResult(db, userId, sessionId, ai);
      res.json(payload);
    } catch (err) {
      if (handleError(err, res)) return;
      next(err);
    }
  });

  return router;
}
