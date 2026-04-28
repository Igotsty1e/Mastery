import type { NextFunction, Request, RequestHandler, Response } from 'express';
import { requireAuth, type AuthedRequest } from '../auth/middleware';
import type { AppDatabase } from '../db/client';

/// Wave 14.1 — admin gate built on top of `requireAuth`. The set of
/// admin user UUIDs is read from `ADMIN_USER_IDS` (comma-separated).
/// Empty / unset = no admins, every admin route returns 403. We keep
/// the gate environment-driven so a fresh prod deploy starts in the
/// "nobody can read retention" state and the founder explicitly opts
/// themselves in via the Render dashboard.
///
/// 401 vs 403:
///   - 401 means the bearer token is missing / invalid (delegated to
///     `requireAuth`).
///   - 403 means the token is valid but the subject is not an admin.
function readAdminIds(): Set<string> {
  const raw = process.env.ADMIN_USER_IDS ?? '';
  const ids = raw
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter((s) => s.length > 0);
  return new Set(ids);
}

export function requireAdmin(db: AppDatabase): RequestHandler {
  const authed = requireAuth(db);
  return (req: Request, res: Response, next: NextFunction) => {
    authed(req, res, (err?: unknown) => {
      if (err) return next(err);
      const ar = req as AuthedRequest;
      if (!ar.auth) return; // requireAuth already responded
      const adminIds = readAdminIds();
      if (!adminIds.has(ar.auth.userId.toLowerCase())) {
        res.status(403).json({ error: 'forbidden' });
        return;
      }
      next();
    });
  };
}
