import { Router, type Request } from 'express';
import { and, eq } from 'drizzle-orm';
import { z } from 'zod';
import type { AppDatabase } from '../db/client';
import {
  auditEvents,
  authIdentities,
  integrationEvents,
  userProfiles,
  users,
} from '../db/schema';
import {
  createSession,
  revokeAllSessions,
  revokeSessionByRefreshToken,
  rotateSession,
  type SessionContext,
} from './sessions';
import { requireAuth, type AuthedRequest } from './middleware';
import { logAuditEvent, recordIntegrationEvent } from './events';
import { resolveClientIp } from '../middleware/clientIp';

// Stub Apple login. Production will replace this surface with verified
// `identityToken` parsing; the *output* contract (access + refresh tokens)
// stays stable, so the mobile client codes against this shape today.
const AppleStubLoginSchema = z.object({
  subject: z.string().min(1).max(256),
  displayName: z.string().min(1).max(80).optional(),
});

const RefreshSchema = z.object({
  refreshToken: z.string().min(1).max(256),
});

const LogoutSchema = z.object({
  refreshToken: z.string().min(1).max(256),
});

function sessionContextFromReq(req: Request): SessionContext {
  const ua = req.headers['user-agent'];
  return {
    userAgent: typeof ua === 'string' ? ua.slice(0, 256) : null,
    // Resolve via the trusted-proxy helper so we never store a spoofable
    // XFF value when the socket itself sits on a public IP.
    ipAddress: resolveClientIp(req) ?? null,
  };
}

/**
 * The Apple-stub login bypasses any real identity verification and is only
 * intended for local dev, tests, and staging smoke checks. Production must
 * not expose it unless an operator explicitly opts in via env flag.
 */
function isAppleStubEnabled(): boolean {
  if (process.env.NODE_ENV !== 'production') return true;
  return process.env.APPLE_STUB_ENABLED === '1';
}

interface ResolveUserResult {
  userId: string;
  isNew: boolean;
}

/**
 * Resolve (or create) the user behind a (provider, subject) pair atomically.
 *
 * Two concurrent first-time logins for the same identity used to race
 * between the SELECT and the INSERT, leaking a half-built user row when the
 * unique-index on (provider, subject) rejected the second insert. Wrapping
 * everything in a transaction lets us roll the orphan user back and retry
 * the read-only path so the loser of the race lands on the winner's user.
 */
async function resolveUserForIdentity(
  db: AppDatabase,
  provider: string,
  subject: string,
  displayName: string | null
): Promise<ResolveUserResult> {
  const findExisting = async (): Promise<string | null> => {
    const rows = await db
      .select({ userId: authIdentities.userId })
      .from(authIdentities)
      .where(
        and(
          eq(authIdentities.provider, provider),
          eq(authIdentities.subject, subject)
        )
      )
      .limit(1);
    return rows[0]?.userId ?? null;
  };

  const existing = await findExisting();
  if (existing) return { userId: existing, isNew: false };

  try {
    return await db.transaction(async (tx) => {
      const [user] = await tx
        .insert(users)
        .values({})
        .returning({ id: users.id });
      // Unique index on (provider, subject) is the race gate. If a
      // concurrent transaction inserted first, this throws and the whole
      // transaction (including the new `users` row) is rolled back.
      await tx.insert(authIdentities).values({
        userId: user.id,
        provider,
        subject,
      });
      await tx.insert(userProfiles).values({
        userId: user.id,
        displayName,
      });
      await tx.insert(auditEvents).values({
        userId: user.id,
        eventType: 'user.created',
        payload: { provider },
      });
      await tx.insert(integrationEvents).values({
        source: provider,
        eventType: 'identity.linked',
        externalId: `${provider}:${subject}`,
        payload: {},
        processedAt: null,
      });
      return { userId: user.id, isNew: true };
    });
  } catch (err) {
    // Concurrent insert won. Re-read and use the surviving user. Any other
    // error bubbles up.
    const after = await findExisting();
    if (after) return { userId: after, isNew: false };
    throw err;
  }
}

export function makeAuthRouter(db: AppDatabase): Router {
  const router = Router();
  const auth = requireAuth(db);

  if (isAppleStubEnabled()) {
    router.post('/auth/apple/stub/login', async (req, res, next) => {
      try {
        const parsed = AppleStubLoginSchema.safeParse(req.body);
        if (!parsed.success) {
          res.status(400).json({ error: 'invalid_payload' });
          return;
        }
        const { subject, displayName } = parsed.data;
        const provider = 'apple_stub';

        const { userId, isNew } = await resolveUserForIdentity(
          db,
          provider,
          subject,
          displayName ?? null
        );

        const tokens = await createSession(
          db,
          userId,
          sessionContextFromReq(req)
        );
        await logAuditEvent(db, {
          userId,
          eventType: 'auth.session.created',
          payload: { provider, new_user: isNew },
        });

        res.json({
          user: { id: userId },
          ...tokens,
        });
      } catch (err) {
        next(err);
      }
    });
  }

  router.post('/auth/refresh', async (req, res, next) => {
    try {
      const parsed = RefreshSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({ error: 'invalid_payload' });
        return;
      }
      const tokens = await rotateSession(
        db,
        parsed.data.refreshToken,
        sessionContextFromReq(req)
      );
      if (!tokens) {
        res.status(401).json({ error: 'invalid_refresh_token' });
        return;
      }
      res.json(tokens);
    } catch (err) {
      next(err);
    }
  });

  router.post('/auth/logout', async (req, res, next) => {
    try {
      const parsed = LogoutSchema.safeParse(req.body);
      if (!parsed.success) {
        res.status(400).json({ error: 'invalid_payload' });
        return;
      }
      await revokeSessionByRefreshToken(db, parsed.data.refreshToken);
      // Always 204: don't leak whether the token was valid.
      res.status(204).end();
    } catch (err) {
      next(err);
    }
  });

  router.post('/auth/logout-all', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const revoked = await revokeAllSessions(db, userId);
      await logAuditEvent(db, {
        userId,
        eventType: 'auth.logout_all',
        payload: { revoked_count: revoked },
      });
      res.status(204).end();
    } catch (err) {
      next(err);
    }
  });

  return router;
}
