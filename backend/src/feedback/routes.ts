import { Router } from 'express';
import { z } from 'zod';
import { sql } from 'drizzle-orm';
import { requireAuth, type AuthedRequest } from '../auth/middleware';
import { feedbackResponses } from '../db/schema';
import type { AppDatabase } from '../db/client';

/// Wave 14.3 — V1.5 feedback system. Two prompt surfaces:
///
///   - `after_summary` — fires after a session completes. Asks the
///     learner to rate the session (1..5) with optional comment.
///   - `after_friction` — fires mid-session when a friction event has
///     just been written to `exercise_attempts.friction_event`. Asks
///     a single short question ("did this exercise feel right?").
///
/// Cooldown: at most one record per user per prompt_kind per 24h,
/// counted regardless of outcome. The `outcome` column distinguishes
/// "submitted" (rated / commented) from "dismissed" (swiped away).
/// Both consume cooldown so a dismissive learner is not pestered;
/// a curious-but-private learner can dismiss once and gets quiet.
///
/// V1 ships POST + a quiet GET that returns the cooldown gates so
/// the client can decide whether to render the prompt before it
/// asks the learner anything. The GET is idempotent and read-only.

const PROMPT_KINDS = ['after_summary', 'after_friction'] as const;
type PromptKind = (typeof PROMPT_KINDS)[number];

const COOLDOWN_HOURS = 24;

const FeedbackPostSchema = z.object({
  prompt_kind: z.enum(PROMPT_KINDS),
  outcome: z.enum(['submitted', 'dismissed']),
  rating: z.number().int().min(1).max(5).optional(),
  comment_text: z.string().max(1000).optional(),
  context: z.record(z.unknown()).optional(),
});

interface CooldownRow extends Record<string, unknown> {
  prompt_kind: string;
  created_at: Date | string;
}

async function lastResponseAt(
  db: AppDatabase,
  userId: string
): Promise<Map<PromptKind, Date>> {
  // Bound by `cooldown_hours` so the GROUP BY scans the relevant
  // slice instead of every row this user has ever submitted. Older
  // rows can never make a gate flip to closed (they're past the
  // cooldown window by definition), so excluding them is safe — the
  // computed boolean is identical with or without the bound.
  const cutoffMs = Date.now() - COOLDOWN_HOURS * 3_600_000;
  const cutoff = new Date(cutoffMs);
  const result = await db.execute<CooldownRow>(sql`
    SELECT prompt_kind, MAX(created_at) AS created_at
    FROM feedback_responses
    WHERE user_id = ${userId}
      AND created_at >= ${cutoff.toISOString()}
    GROUP BY prompt_kind
  `);
  const rows: CooldownRow[] = Array.isArray(result)
    ? (result as CooldownRow[])
    : ((result as { rows: CooldownRow[] }).rows ?? []);
  const out = new Map<PromptKind, Date>();
  for (const r of rows) {
    if (!PROMPT_KINDS.includes(r.prompt_kind as PromptKind)) continue;
    const ts = r.created_at instanceof Date ? r.created_at : new Date(r.created_at);
    out.set(r.prompt_kind as PromptKind, ts);
  }
  return out;
}

function cooldownAllows(lastAt: Date | undefined, now: Date): boolean {
  if (!lastAt) return true;
  return now.getTime() - lastAt.getTime() >= COOLDOWN_HOURS * 3_600_000;
}

export function makeFeedbackRouter(db: AppDatabase): Router {
  const router = Router();
  const authed = requireAuth(db);

  router.get('/me/feedback/cooldown', authed, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const last = await lastResponseAt(db, userId);
      const now = new Date();
      res.json({
        cooldown_hours: COOLDOWN_HOURS,
        after_summary_allowed: cooldownAllows(last.get('after_summary'), now),
        after_friction_allowed: cooldownAllows(last.get('after_friction'), now),
      });
    } catch (err) {
      next(err);
    }
  });

  router.post('/me/feedback', authed, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const parsed = FeedbackPostSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({ error: 'invalid_payload' });
        return;
      }
      const { prompt_kind, outcome, rating, comment_text, context } =
        parsed.data;
      // Submitted-without-rating-or-comment is a programmer error in
      // the client — refuse it so analytics rows are unambiguous.
      if (outcome === 'submitted' && rating === undefined && !comment_text) {
        res.status(400).json({ error: 'submitted_requires_content' });
        return;
      }
      const last = await lastResponseAt(db, userId);
      const now = new Date();
      if (!cooldownAllows(last.get(prompt_kind), now)) {
        res.status(429).json({
          error: 'cooldown',
          retry_after_seconds: Math.max(
            0,
            Math.ceil(
              (last.get(prompt_kind)!.getTime() +
                COOLDOWN_HOURS * 3_600_000 -
                now.getTime()) /
                1000
            )
          ),
        });
        return;
      }
      const inserted = await db
        .insert(feedbackResponses)
        .values({
          userId,
          promptKind: prompt_kind,
          outcome,
          rating: rating ?? null,
          commentText: comment_text ?? null,
          context: (context ?? {}) as Record<string, unknown>,
        })
        .returning({ id: feedbackResponses.id });
      res.status(201).json({ id: inserted[0]?.id });
    } catch (err) {
      next(err);
    }
  });

  return router;
}
