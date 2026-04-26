import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { eq } from 'drizzle-orm';
import { inject } from './helpers/inject';
import { makeTestApp, type TestApp } from './helpers/db';
import { authIdentities, authSessions, users } from '../src/db/schema';

// Apple-stub gating happens at router-construction time (the route is not
// registered when production gating is on), so each gating case needs a
// freshly built app. We rebuild inside the test bodies and restore env on
// teardown.

describe('apple-stub gating', () => {
  const originalNodeEnv = process.env.NODE_ENV;
  const originalFlag = process.env.APPLE_STUB_ENABLED;

  function restoreEnv() {
    if (originalNodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = originalNodeEnv;
    if (originalFlag === undefined) delete process.env.APPLE_STUB_ENABLED;
    else process.env.APPLE_STUB_ENABLED = originalFlag;
  }

  it('is reachable in non-production environments without an opt-in flag', async () => {
    delete process.env.NODE_ENV;
    delete process.env.APPLE_STUB_ENABLED;
    const h = await makeTestApp();
    try {
      const res = await inject(h.app, {
        method: 'POST',
        path: '/auth/apple/stub/login',
        json: { subject: 'gate-dev' },
      });
      expect(res.status).toBe(200);
    } finally {
      await h.close();
      restoreEnv();
    }
  });

  it('returns 404 in production when the opt-in flag is unset', async () => {
    process.env.NODE_ENV = 'production';
    process.env.AUTH_SECRET = 'gate-prod-secret';
    delete process.env.APPLE_STUB_ENABLED;
    const h = await makeTestApp();
    try {
      const res = await inject(h.app, {
        method: 'POST',
        path: '/auth/apple/stub/login',
        json: { subject: 'gate-prod' },
      });
      expect(res.status).toBe(404);
      expect(res.json).toEqual({ error: 'not_found' });
    } finally {
      await h.close();
      restoreEnv();
      delete process.env.AUTH_SECRET;
    }
  });

  it('is reachable in production when explicitly enabled via APPLE_STUB_ENABLED=1', async () => {
    process.env.NODE_ENV = 'production';
    process.env.AUTH_SECRET = 'gate-prod-secret';
    process.env.APPLE_STUB_ENABLED = '1';
    const h = await makeTestApp();
    try {
      const res = await inject(h.app, {
        method: 'POST',
        path: '/auth/apple/stub/login',
        json: { subject: 'gate-prod-on' },
      });
      expect(res.status).toBe(200);
    } finally {
      await h.close();
      restoreEnv();
      delete process.env.AUTH_SECRET;
    }
  });
});

let h: TestApp;

beforeAll(async () => {
  h = await makeTestApp();
});

afterAll(async () => {
  await h.close();
});

async function login(subject: string) {
  return inject(h.app, {
    method: 'POST',
    path: '/auth/apple/stub/login',
    json: { subject },
  });
}

describe('refresh-token rotation atomicity', () => {
  it('two concurrent refreshes with the same token issue exactly one new pair', async () => {
    const start = await login('rotate-race');
    const original = (start.json as { refreshToken: string }).refreshToken;
    const userId = (start.json as { user: { id: string } }).user.id;

    const [a, b] = await Promise.all([
      inject(h.app, {
        method: 'POST',
        path: '/auth/refresh',
        json: { refreshToken: original },
      }),
      inject(h.app, {
        method: 'POST',
        path: '/auth/refresh',
        json: { refreshToken: original },
      }),
    ]);

    const successes = [a, b].filter((r) => r.status === 200);
    const failures = [a, b].filter((r) => r.status === 401);
    expect(successes).toHaveLength(1);
    expect(failures).toHaveLength(1);

    // The single winner must have minted exactly one new live session.
    const liveSessions = await h.database.orm
      .select()
      .from(authSessions)
      .where(eq(authSessions.userId, userId));
    const live = liveSessions.filter((s) => s.revokedAt === null);
    expect(live).toHaveLength(1);
  });
});

describe('concurrent first-login safety', () => {
  it('two concurrent first-logins for the same identity resolve to one user with no orphan rows', async () => {
    const subject = 'concurrent-first-login';
    const [a, b] = await Promise.all([login(subject), login(subject)]);
    expect(a.status).toBe(200);
    expect(b.status).toBe(200);
    const idA = (a.json as { user: { id: string } }).user.id;
    const idB = (b.json as { user: { id: string } }).user.id;
    expect(idA).toBe(idB);

    const idents = await h.database.orm
      .select()
      .from(authIdentities)
      .where(eq(authIdentities.subject, subject));
    expect(idents).toHaveLength(1);

    const userRows = await h.database.orm
      .select()
      .from(users)
      .where(eq(users.id, idA));
    expect(userRows).toHaveLength(1);
  });
});

describe('session IP trust boundary', () => {
  it('uses the public socket IP, not a spoofed X-Forwarded-For, when storing session metadata', async () => {
    // Public socket → XFF must be ignored.
    const res = await inject(h.app, {
      method: 'POST',
      path: '/auth/apple/stub/login',
      json: { subject: 'ip-spoof' },
      socketRemoteAddress: '5.5.5.5',
      headers: { 'x-forwarded-for': '8.8.8.8' },
    });
    expect(res.status).toBe(200);
    const userId = (res.json as { user: { id: string } }).user.id;
    const sess = await h.database.orm
      .select()
      .from(authSessions)
      .where(eq(authSessions.userId, userId));
    expect(sess[0]?.ipAddress).toBe('5.5.5.5');
  });

  it('honours X-Forwarded-For when the socket itself is a trusted RFC 1918 proxy', async () => {
    const res = await inject(h.app, {
      method: 'POST',
      path: '/auth/apple/stub/login',
      json: { subject: 'ip-trusted' },
      socketRemoteAddress: '10.0.0.1',
      headers: { 'x-forwarded-for': '203.0.113.5' },
    });
    expect(res.status).toBe(200);
    const userId = (res.json as { user: { id: string } }).user.id;
    const sess = await h.database.orm
      .select()
      .from(authSessions)
      .where(eq(authSessions.userId, userId));
    expect(sess[0]?.ipAddress).toBe('203.0.113.5');
  });
});
