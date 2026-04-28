import { Router } from 'express';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import type { AppDatabase } from '../db/client';
import { auditEvents, userProfiles, users } from '../db/schema';
import { requireAuth, type AuthedRequest } from '../auth/middleware';
import { logAuditEvent } from '../auth/events';
import {
  DEFAULT_UI_LANGUAGE,
  UI_LANGUAGES,
  parseUiLanguage,
  type UiLanguage,
} from './uiLanguage';

const ALLOWED_LEVELS = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'] as const;

const ProfilePatchSchema = z
  .object({
    displayName: z.string().min(1).max(80).nullable().optional(),
    level: z.enum(ALLOWED_LEVELS).nullable().optional(),
    uiLanguage: z.enum(UI_LANGUAGES).optional(),
  })
  .strict();

interface ProfileDto {
  displayName: string | null;
  level: string | null;
  uiLanguage: UiLanguage;
  updatedAt: string;
}

interface MeDto {
  user: { id: string; createdAt: string };
  profile: ProfileDto | null;
}

async function loadProfile(
  db: AppDatabase,
  userId: string
): Promise<ProfileDto | null> {
  const rows = await db
    .select()
    .from(userProfiles)
    .where(eq(userProfiles.userId, userId))
    .limit(1);
  const row = rows[0];
  if (!row) return null;
  return {
    displayName: row.displayName ?? null,
    level: row.level ?? null,
    uiLanguage: parseUiLanguage(row.uiLanguage) ?? DEFAULT_UI_LANGUAGE,
    updatedAt: row.updatedAt.toISOString(),
  };
}

export function makeUsersRouter(db: AppDatabase): Router {
  const router = Router();
  const auth = requireAuth(db);

  router.get('/me', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const userRows = await db
        .select()
        .from(users)
        .where(eq(users.id, userId))
        .limit(1);
      const user = userRows[0];
      if (!user) {
        res.status(404).json({ error: 'user_not_found' });
        return;
      }
      const profile = await loadProfile(db, userId);
      const dto: MeDto = {
        user: { id: user.id, createdAt: user.createdAt.toISOString() },
        profile,
      };
      res.json(dto);
    } catch (err) {
      next(err);
    }
  });

  router.patch('/me/profile', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const parsed = ProfilePatchSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({ error: 'invalid_payload' });
        return;
      }
      const updates: Record<string, unknown> = {};
      if (parsed.data.displayName !== undefined)
        updates.displayName = parsed.data.displayName;
      if (parsed.data.level !== undefined) updates.level = parsed.data.level;
      if (parsed.data.uiLanguage !== undefined)
        updates.uiLanguage = parsed.data.uiLanguage;

      const existing = await db
        .select({ userId: userProfiles.userId })
        .from(userProfiles)
        .where(eq(userProfiles.userId, userId))
        .limit(1);

      if (existing[0]) {
        if (Object.keys(updates).length > 0) {
          await db
            .update(userProfiles)
            .set({ ...updates, updatedAt: new Date() })
            .where(eq(userProfiles.userId, userId));
        }
      } else {
        await db.insert(userProfiles).values({
          userId,
          displayName: (updates.displayName as string | null | undefined) ?? null,
          level: (updates.level as string | null | undefined) ?? null,
          uiLanguage:
            (updates.uiLanguage as UiLanguage | undefined) ??
            DEFAULT_UI_LANGUAGE,
        });
      }

      await logAuditEvent(db, {
        userId,
        eventType: 'profile.updated',
        payload: { fields: Object.keys(updates) },
      });

      const profile = await loadProfile(db, userId);
      res.json({ profile });
    } catch (err) {
      next(err);
    }
  });

  router.delete('/me', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      // Hard delete the user row + write the tombstone in one transaction.
      // ON DELETE CASCADE removes identities, sessions, and profile;
      // audit_events.user_id is ON DELETE SET NULL, so the tombstone row
      // we write here outlives the user. If either statement fails we want
      // both to roll back so we never end up with a deleted user and no
      // audit trail (or vice-versa).
      await db.transaction(async (tx) => {
        await tx.delete(users).where(eq(users.id, userId));
        await tx.insert(auditEvents).values({
          userId: null,
          eventType: 'user.deleted',
          payload: { deleted_user_id: userId },
        });
      });
      res.status(204).end();
    } catch (err) {
      next(err);
    }
  });

  return router;
}
