import { Router } from 'express';
import { z } from 'zod';

import { requireAuth, type AuthedRequest } from '../auth/middleware';
import { analyticsEvents } from '../db/schema';
import type { AppDatabase } from '../db/client';

/// Wave G4 — product analytics ingest. Frontend tracker batches up
/// events and POSTs them here. Routes are intentionally small:
///
///   POST /me/events   — auth-required, batched ingest (1..50 rows)
///
/// No GET / list / aggregate endpoints in V1 — analytics queries
/// run directly against the `analytics_events` table from the
/// operator's psql shell or a future admin surface. Keeping the
/// public surface tiny means the schema can evolve freely as we
/// learn what to measure without breaking shipped clients.

const MAX_EVENTS_PER_BATCH = 50;
const MAX_NAME_LEN = 80;
const MAX_SCREEN_LEN = 80;

const EventSchema = z.object({
  /// 'screen_view' / 'button_click' / freeform after V1.
  name: z.string().min(1).max(MAX_NAME_LEN),
  /// Logical screen ('dashboard', 'exercise', 'summary', ...).
  screen: z.string().max(MAX_SCREEN_LEN).optional(),
  /// Open-ended dict for button_id, skill_id, score, etc. Not
  /// recursively validated — the analytics layer never reads
  /// individual keys from request data, only persists the blob.
  metadata: z.record(z.unknown()).optional(),
  /// Client clock — what the learner's device thought the time
  /// was when the event fired. ISO 8601.
  occurred_at: z.string().datetime(),
});

const BatchSchema = z.object({
  events: z.array(EventSchema).min(1).max(MAX_EVENTS_PER_BATCH),
});

export function makeAnalyticsRouter(db: AppDatabase): Router {
  const router = Router();
  const authed = requireAuth(db);

  router.post('/me/events', authed, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const parsed = BatchSchema.safeParse(req.body);
      if (!parsed.success) {
        return res.status(400).json({
          error: 'invalid_payload',
          detail: parsed.error.flatten(),
        });
      }
      const rows = parsed.data.events.map((e) => ({
        userId,
        eventName: e.name,
        screen: e.screen ?? null,
        metadata: (e.metadata ?? null) as unknown,
        occurredAt: new Date(e.occurred_at),
      }));
      await db.insert(analyticsEvents).values(rows);
      return res.json({ accepted: rows.length });
    } catch (err) {
      return next(err);
    }
  });

  return router;
}
