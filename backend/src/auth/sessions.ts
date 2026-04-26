import { and, eq, gt, isNull } from 'drizzle-orm';
import type { AppDatabase } from '../db/client';
import { authSessions } from '../db/schema';
import {
  generateRefreshToken,
  hashRefreshToken,
  REFRESH_TOKEN_TTL_SECONDS,
  signAccessToken,
} from './tokens';

export interface SessionTokens {
  accessToken: string;
  accessTokenExpiresAt: string;
  refreshToken: string;
  refreshTokenExpiresAt: string;
}

export interface SessionContext {
  userAgent?: string | null;
  ipAddress?: string | null;
}

export interface AuthedSession {
  sessionId: string;
  userId: string;
}

const REFRESH_TOKEN_TTL_MS = REFRESH_TOKEN_TTL_SECONDS * 1000;

export async function createSession(
  db: AppDatabase,
  userId: string,
  ctx: SessionContext = {}
): Promise<SessionTokens> {
  const refreshToken = generateRefreshToken();
  const refreshHash = hashRefreshToken(refreshToken);
  const refreshExpiresAt = new Date(Date.now() + REFRESH_TOKEN_TTL_MS);

  const inserted = await db
    .insert(authSessions)
    .values({
      userId,
      refreshTokenHash: refreshHash,
      expiresAt: refreshExpiresAt,
      userAgent: ctx.userAgent ?? null,
      ipAddress: ctx.ipAddress ?? null,
    })
    .returning({ id: authSessions.id });

  const session = inserted[0];
  if (!session) {
    throw new Error('failed_to_create_session');
  }

  const access = signAccessToken(userId, session.id);
  return {
    accessToken: access.token,
    accessTokenExpiresAt: access.expiresAt.toISOString(),
    refreshToken,
    refreshTokenExpiresAt: refreshExpiresAt.toISOString(),
  };
}

/**
 * Rotate a refresh token: revoke the presented one, issue a fresh pair.
 * Returns null when the token is unknown, expired, or already revoked.
 *
 * Concurrency: the previous implementation read-then-updated, so two racing
 * `/auth/refresh` calls with the same token could both pass the read gate
 * and each issue a live session. The conditional UPDATE here is atomic at
 * the row level — only the call that flips `revoked_at` first sees the
 * RETURNING row and is allowed to mint the new pair. The whole thing runs
 * inside a transaction so a crash between revoke and create cannot leave
 * the user with no live session.
 */
export async function rotateSession(
  db: AppDatabase,
  refreshToken: string,
  ctx: SessionContext = {}
): Promise<SessionTokens | null> {
  const hash = hashRefreshToken(refreshToken);
  return db.transaction(async (tx) => {
    const now = new Date();
    const revoked = await tx
      .update(authSessions)
      .set({ revokedAt: now })
      .where(
        and(
          eq(authSessions.refreshTokenHash, hash),
          isNull(authSessions.revokedAt),
          gt(authSessions.expiresAt, now)
        )
      )
      .returning({
        id: authSessions.id,
        userId: authSessions.userId,
      });
    const session = revoked[0];
    if (!session) return null;
    return createSession(tx, session.userId, ctx);
  });
}

export async function revokeSessionByRefreshToken(
  db: AppDatabase,
  refreshToken: string
): Promise<boolean> {
  const hash = hashRefreshToken(refreshToken);
  const rows = await db
    .update(authSessions)
    .set({ revokedAt: new Date() })
    .where(
      and(
        eq(authSessions.refreshTokenHash, hash),
        isNull(authSessions.revokedAt)
      )
    )
    .returning({ id: authSessions.id });
  return rows.length > 0;
}

export async function revokeAllSessions(
  db: AppDatabase,
  userId: string
): Promise<number> {
  const rows = await db
    .update(authSessions)
    .set({ revokedAt: new Date() })
    .where(
      and(eq(authSessions.userId, userId), isNull(authSessions.revokedAt))
    )
    .returning({ id: authSessions.id });
  return rows.length;
}

/**
 * Look up an active (non-revoked, non-expired) session by id. Used by the
 * auth middleware to validate that an access token still corresponds to a
 * live session — even though access tokens are stateless, we want logout
 * and logout-all to invalidate immediately.
 */
export async function getActiveSession(
  db: AppDatabase,
  sessionId: string
): Promise<AuthedSession | null> {
  const rows = await db
    .select({
      id: authSessions.id,
      userId: authSessions.userId,
      revokedAt: authSessions.revokedAt,
      expiresAt: authSessions.expiresAt,
    })
    .from(authSessions)
    .where(eq(authSessions.id, sessionId))
    .limit(1);
  const session = rows[0];
  if (!session) return null;
  if (session.revokedAt) return null;
  if (session.expiresAt.getTime() < Date.now()) return null;
  return { sessionId: session.id, userId: session.userId };
}
