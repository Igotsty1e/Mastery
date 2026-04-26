import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { eq } from 'drizzle-orm';
import { inject } from './helpers/inject';
import { makeTestApp, type TestApp } from './helpers/db';
import {
  auditEvents,
  authIdentities,
  authSessions,
  integrationEvents,
  userProfiles,
  users,
} from '../src/db/schema';

let h: TestApp;

beforeAll(async () => {
  h = await makeTestApp();
});

afterAll(async () => {
  await h.close();
});

async function login(subject: string, displayName?: string) {
  const res = await inject(h.app, {
    method: 'POST',
    path: '/auth/apple/stub/login',
    json: { subject, displayName },
  });
  return res;
}

describe('POST /auth/apple/stub/login', () => {
  it('rejects an invalid payload with 400', async () => {
    const res = await inject(h.app, {
      method: 'POST',
      path: '/auth/apple/stub/login',
      json: { subject: '' },
    });
    expect(res.status).toBe(400);
    expect(res.json).toEqual({ error: 'invalid_payload' });
  });

  it('creates a user, identity, profile, and session on first login', async () => {
    const res = await login('apple-sub-001', 'Ada');
    expect(res.status).toBe(200);
    const body = res.json as Record<string, string | { id: string }>;
    expect(body.user).toMatchObject({ id: expect.any(String) });
    expect(typeof body.accessToken).toBe('string');
    expect(typeof body.refreshToken).toBe('string');
    expect(typeof body.accessTokenExpiresAt).toBe('string');
    expect(typeof body.refreshTokenExpiresAt).toBe('string');

    const userId = (body.user as { id: string }).id;
    const idents = await h.database.orm
      .select()
      .from(authIdentities)
      .where(eq(authIdentities.userId, userId));
    expect(idents).toHaveLength(1);
    expect(idents[0]).toMatchObject({
      provider: 'apple_stub',
      subject: 'apple-sub-001',
    });

    const profile = await h.database.orm
      .select()
      .from(userProfiles)
      .where(eq(userProfiles.userId, userId));
    expect(profile[0]?.displayName).toBe('Ada');

    const sessions = await h.database.orm
      .select()
      .from(authSessions)
      .where(eq(authSessions.userId, userId));
    expect(sessions).toHaveLength(1);
    expect(sessions[0]?.refreshTokenHash).toMatch(/^[a-f0-9]{64}$/);

    const audits = await h.database.orm
      .select()
      .from(auditEvents)
      .where(eq(auditEvents.userId, userId));
    const types = audits.map((a) => a.eventType).sort();
    expect(types).toEqual(['auth.session.created', 'user.created']);

    const integrations = await h.database.orm
      .select()
      .from(integrationEvents);
    const linked = integrations.find(
      (i) => i.externalId === 'apple_stub:apple-sub-001'
    );
    expect(linked?.eventType).toBe('identity.linked');
  });

  it('returns the same user on repeat login with the same subject', async () => {
    const first = await login('apple-sub-002');
    const second = await login('apple-sub-002');
    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    const firstUser = (first.json as { user: { id: string } }).user.id;
    const secondUser = (second.json as { user: { id: string } }).user.id;
    expect(firstUser).toBe(secondUser);

    const sessions = await h.database.orm
      .select()
      .from(authSessions)
      .where(eq(authSessions.userId, firstUser));
    // One per login.
    expect(sessions.length).toBeGreaterThanOrEqual(2);
  });

  it('issues a working access token (verified by /me)', async () => {
    const login1 = await login('apple-sub-003');
    const accessToken = (login1.json as { accessToken: string }).accessToken;
    const me = await inject(h.app, {
      method: 'GET',
      path: '/me',
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(me.status).toBe(200);
    const body = me.json as { user: { id: string }; profile: unknown };
    expect(body.user.id).toBe(
      (login1.json as { user: { id: string } }).user.id
    );
  });
});

describe('POST /auth/refresh', () => {
  it('rotates a valid refresh token and revokes the old one', async () => {
    const start = await login('apple-sub-100');
    const original = (start.json as { refreshToken: string }).refreshToken;
    const res = await inject(h.app, {
      method: 'POST',
      path: '/auth/refresh',
      json: { refreshToken: original },
    });
    expect(res.status).toBe(200);
    const body = res.json as { refreshToken: string; accessToken: string };
    expect(body.refreshToken).not.toBe(original);
    expect(typeof body.accessToken).toBe('string');

    // The original token can no longer be reused.
    const replay = await inject(h.app, {
      method: 'POST',
      path: '/auth/refresh',
      json: { refreshToken: original },
    });
    expect(replay.status).toBe(401);
  });

  it('rejects an unknown refresh token with 401', async () => {
    const res = await inject(h.app, {
      method: 'POST',
      path: '/auth/refresh',
      json: { refreshToken: 'definitely-not-a-real-token' },
    });
    expect(res.status).toBe(401);
    expect(res.json).toEqual({ error: 'invalid_refresh_token' });
  });

  it('rejects an empty payload with 400', async () => {
    const res = await inject(h.app, {
      method: 'POST',
      path: '/auth/refresh',
      json: {},
    });
    expect(res.status).toBe(400);
  });
});

describe('POST /auth/logout', () => {
  it('revokes the session for the presented refresh token', async () => {
    const start = await login('apple-sub-200');
    const refreshToken = (start.json as { refreshToken: string }).refreshToken;

    const out = await inject(h.app, {
      method: 'POST',
      path: '/auth/logout',
      json: { refreshToken },
    });
    expect(out.status).toBe(204);

    const refresh = await inject(h.app, {
      method: 'POST',
      path: '/auth/refresh',
      json: { refreshToken },
    });
    expect(refresh.status).toBe(401);
  });

  it('returns 204 even for an unknown refresh token (no enumeration)', async () => {
    const out = await inject(h.app, {
      method: 'POST',
      path: '/auth/logout',
      json: { refreshToken: 'unknown-token' },
    });
    expect(out.status).toBe(204);
  });
});

describe('POST /auth/logout-all', () => {
  it('revokes every active session for the user', async () => {
    const a = await login('apple-sub-300');
    const b = await login('apple-sub-300');
    const accessB = (b.json as { accessToken: string }).accessToken;
    const refreshA = (a.json as { refreshToken: string }).refreshToken;
    const refreshB = (b.json as { refreshToken: string }).refreshToken;

    const out = await inject(h.app, {
      method: 'POST',
      path: '/auth/logout-all',
      headers: { authorization: `Bearer ${accessB}` },
    });
    expect(out.status).toBe(204);

    for (const refreshToken of [refreshA, refreshB]) {
      const refresh = await inject(h.app, {
        method: 'POST',
        path: '/auth/refresh',
        json: { refreshToken },
      });
      expect(refresh.status).toBe(401);
    }

    // The access token's session is revoked, so /me must reject it too.
    const me = await inject(h.app, {
      method: 'GET',
      path: '/me',
      headers: { authorization: `Bearer ${accessB}` },
    });
    expect(me.status).toBe(401);
  });

  it('rejects unauthenticated requests with 401', async () => {
    const out = await inject(h.app, {
      method: 'POST',
      path: '/auth/logout-all',
    });
    expect(out.status).toBe(401);
  });
});
