import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { eq } from 'drizzle-orm';
import { inject } from './helpers/inject';
import { makeTestApp, type TestApp } from './helpers/db';
import {
  auditEvents,
  authIdentities,
  authSessions,
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

async function loginAs(subject: string, displayName?: string) {
  const res = await inject(h.app, {
    method: 'POST',
    path: '/auth/apple/stub/login',
    json: { subject, displayName },
  });
  return {
    accessToken: (res.json as { accessToken: string }).accessToken,
    refreshToken: (res.json as { refreshToken: string }).refreshToken,
    userId: (res.json as { user: { id: string } }).user.id,
  };
}

describe('GET /me', () => {
  it('returns 401 with no Authorization header', async () => {
    const res = await inject(h.app, { method: 'GET', path: '/me' });
    expect(res.status).toBe(401);
    expect(res.json).toEqual({ error: 'unauthorized' });
  });

  it('returns 401 with a tampered access token', async () => {
    const { accessToken } = await loginAs('me-sub-tamper');
    const tampered = accessToken.replace(/[a-z0-9]$/i, (c) =>
      c === 'a' ? 'b' : 'a'
    );
    const res = await inject(h.app, {
      method: 'GET',
      path: '/me',
      headers: { authorization: `Bearer ${tampered}` },
    });
    expect(res.status).toBe(401);
  });

  it('returns user + profile with valid auth', async () => {
    const { accessToken, userId } = await loginAs('me-sub-001', 'Babbage');
    const res = await inject(h.app, {
      method: 'GET',
      path: '/me',
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(res.status).toBe(200);
    const body = res.json as {
      user: { id: string; createdAt: string };
      profile: { displayName: string | null; level: string | null };
    };
    expect(body.user.id).toBe(userId);
    expect(body.profile?.displayName).toBe('Babbage');
    expect(body.profile?.level).toBeNull();
  });
});

describe('PATCH /me/profile', () => {
  it('updates display name and level for the authenticated user', async () => {
    const { accessToken, userId } = await loginAs('me-sub-patch');
    const res = await inject(h.app, {
      method: 'PATCH',
      path: '/me/profile',
      headers: { authorization: `Bearer ${accessToken}` },
      json: { displayName: 'Curie', level: 'B2' },
    });
    expect(res.status).toBe(200);
    const body = res.json as { profile: { displayName: string; level: string } };
    expect(body.profile).toMatchObject({ displayName: 'Curie', level: 'B2' });

    const reloaded = await h.database.orm
      .select()
      .from(userProfiles)
      .where(eq(userProfiles.userId, userId));
    expect(reloaded[0]?.displayName).toBe('Curie');
    expect(reloaded[0]?.level).toBe('B2');

    const audit = await h.database.orm
      .select()
      .from(auditEvents)
      .where(eq(auditEvents.userId, userId));
    expect(audit.find((a) => a.eventType === 'profile.updated')).toBeDefined();
  });

  it('rejects unknown fields with 400', async () => {
    const { accessToken } = await loginAs('me-sub-strict');
    const res = await inject(h.app, {
      method: 'PATCH',
      path: '/me/profile',
      headers: { authorization: `Bearer ${accessToken}` },
      json: { displayName: 'ok', isAdmin: true },
    });
    expect(res.status).toBe(400);
  });

  it('rejects invalid level values with 400', async () => {
    const { accessToken } = await loginAs('me-sub-level');
    const res = await inject(h.app, {
      method: 'PATCH',
      path: '/me/profile',
      headers: { authorization: `Bearer ${accessToken}` },
      json: { level: 'D9' },
    });
    expect(res.status).toBe(400);
  });

  it('accepts a partial update', async () => {
    const { accessToken } = await loginAs('me-sub-partial', 'Initial');
    const res = await inject(h.app, {
      method: 'PATCH',
      path: '/me/profile',
      headers: { authorization: `Bearer ${accessToken}` },
      json: { level: 'C1' },
    });
    expect(res.status).toBe(200);
    const body = res.json as {
      profile: { displayName: string | null; level: string };
    };
    expect(body.profile.level).toBe('C1');
    expect(body.profile.displayName).toBe('Initial');
  });
});

describe('DELETE /me', () => {
  it('hard-deletes the user, identities, sessions, and profile', async () => {
    const { accessToken, refreshToken, userId } = await loginAs(
      'me-sub-delete',
      'Hopper'
    );

    const out = await inject(h.app, {
      method: 'DELETE',
      path: '/me',
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(out.status).toBe(204);

    const remainingUsers = await h.database.orm
      .select()
      .from(users)
      .where(eq(users.id, userId));
    expect(remainingUsers).toHaveLength(0);

    const remainingIdents = await h.database.orm
      .select()
      .from(authIdentities)
      .where(eq(authIdentities.userId, userId));
    expect(remainingIdents).toHaveLength(0);

    const remainingSessions = await h.database.orm
      .select()
      .from(authSessions)
      .where(eq(authSessions.userId, userId));
    expect(remainingSessions).toHaveLength(0);

    const remainingProfiles = await h.database.orm
      .select()
      .from(userProfiles)
      .where(eq(userProfiles.userId, userId));
    expect(remainingProfiles).toHaveLength(0);

    // Audit tombstone survives — older entries had user_id NULLed.
    const tombstone = await h.database.orm
      .select()
      .from(auditEvents)
      .where(eq(auditEvents.eventType, 'user.deleted'));
    expect(
      tombstone.some(
        (row) =>
          (row.payload as { deleted_user_id?: string } | null)
            ?.deleted_user_id === userId
      )
    ).toBe(true);

    // Re-login with the same provider+subject creates a fresh user row.
    const reLogin = await inject(h.app, {
      method: 'POST',
      path: '/auth/apple/stub/login',
      json: { subject: 'me-sub-delete' },
    });
    expect(reLogin.status).toBe(200);
    const newUser = (reLogin.json as { user: { id: string } }).user.id;
    expect(newUser).not.toBe(userId);

    // Old refresh token must not work after deletion.
    const refresh = await inject(h.app, {
      method: 'POST',
      path: '/auth/refresh',
      json: { refreshToken },
    });
    expect(refresh.status).toBe(401);
  });
});
