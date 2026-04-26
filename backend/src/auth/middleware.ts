import type { NextFunction, Request, RequestHandler, Response } from 'express';
import type { AppDatabase } from '../db/client';
import { getActiveSession } from './sessions';
import { verifyAccessToken } from './tokens';

export interface AuthedRequest extends Request {
  auth: { userId: string; sessionId: string };
}

export function requireAuth(db: AppDatabase): RequestHandler {
  return async (req: Request, res: Response, next: NextFunction) => {
    const header = req.headers.authorization;
    if (!header || !header.startsWith('Bearer ')) {
      res.status(401).json({ error: 'unauthorized' });
      return;
    }
    const token = header.slice(7).trim();
    const payload = verifyAccessToken(token);
    if (!payload) {
      res.status(401).json({ error: 'unauthorized' });
      return;
    }
    try {
      const session = await getActiveSession(db, payload.sessionId);
      if (!session || session.userId !== payload.userId) {
        res.status(401).json({ error: 'unauthorized' });
        return;
      }
      (req as AuthedRequest).auth = {
        userId: payload.userId,
        sessionId: payload.sessionId,
      };
      next();
    } catch (err) {
      next(err);
    }
  };
}
