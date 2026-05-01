// Wave G4 — analytics ingest coverage.
//
// Route: POST /me/events. Auth-required. Batch size 1..50. Body
// validation by zod. Inserts into `analytics_events` directly.

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { eq } from 'drizzle-orm';

import { inject } from './helpers/inject';
import { makeTestApp, type TestApp } from './helpers/db';
import { analyticsEvents } from '../src/db/schema';

let h: TestApp;

beforeEach(async () => {
  h = await makeTestApp();
});

afterEach(async () => {
  await h.close();
});

async function login(subject: string) {
  const res = await inject(h.app, {
    method: 'POST',
    path: '/auth/apple/stub/login',
    json: { subject },
  });
  if (res.status !== 200) throw new Error(`login_${res.status}`);
  const body = res.json as { accessToken: string; user: { id: string } };
  return { accessToken: body.accessToken, userId: body.user.id };
}

describe('POST /me/events', () => {
  it('401 without bearer token', async () => {
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/events',
      json: {
        events: [
          {
            name: 'screen_view',
            screen: 'dashboard',
            occurred_at: '2026-05-01T10:00:00.000Z',
          },
        ],
      },
    });
    expect(res.status).toBe(401);
  });

  it('400 on empty events array', async () => {
    const { accessToken } = await login('analytics-empty');
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/events',
      headers: { authorization: `Bearer ${accessToken}` },
      json: { events: [] },
    });
    expect(res.status).toBe(400);
  });

  it('400 on missing event name', async () => {
    const { accessToken } = await login('analytics-noname');
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/events',
      headers: { authorization: `Bearer ${accessToken}` },
      json: {
        events: [{ occurred_at: '2026-05-01T10:00:00.000Z' }],
      },
    });
    expect(res.status).toBe(400);
  });

  it('400 on non-ISO occurred_at', async () => {
    const { accessToken } = await login('analytics-badtime');
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/events',
      headers: { authorization: `Bearer ${accessToken}` },
      json: {
        events: [{ name: 'screen_view', occurred_at: 'yesterday' }],
      },
    });
    expect(res.status).toBe(400);
  });

  it('400 on batch larger than 50', async () => {
    const { accessToken } = await login('analytics-toobig');
    const events = Array.from({ length: 51 }, (_, i) => ({
      name: 'screen_view',
      occurred_at: '2026-05-01T10:00:00.000Z',
      metadata: { i },
    }));
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/events',
      headers: { authorization: `Bearer ${accessToken}` },
      json: { events },
    });
    expect(res.status).toBe(400);
  });

  it('200 on valid batch + persists rows with correct shape', async () => {
    const { accessToken, userId } = await login('analytics-happy');
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/events',
      headers: { authorization: `Bearer ${accessToken}` },
      json: {
        events: [
          {
            name: 'screen_view',
            screen: 'dashboard',
            occurred_at: '2026-05-01T10:00:00.000Z',
          },
          {
            name: 'button_click',
            screen: 'summary',
            metadata: { button_id: 'practice_more' },
            occurred_at: '2026-05-01T10:00:01.000Z',
          },
        ],
      },
    });
    expect(res.status).toBe(200);
    expect((res.json as { accepted: number }).accepted).toBe(2);

    const rows = await h.database.orm
      .select()
      .from(analyticsEvents)
      .where(eq(analyticsEvents.userId, userId));
    expect(rows.length).toBe(2);
    const byEvent = new Map(rows.map((r) => [r.eventName, r]));
    expect(byEvent.get('screen_view')?.screen).toBe('dashboard');
    expect(byEvent.get('button_click')?.screen).toBe('summary');
    expect(
      (byEvent.get('button_click')?.metadata as { button_id: string } | null)
        ?.button_id,
    ).toBe('practice_more');
  });

  it('handles freeform metadata without erroring', async () => {
    const { accessToken } = await login('analytics-meta');
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/events',
      headers: { authorization: `Bearer ${accessToken}` },
      json: {
        events: [
          {
            name: 'feature_used',
            screen: 'dashboard',
            metadata: {
              skill_id: 'verb-ing-after-gerund-verbs',
              dwell_ms: 420,
              nested: { a: 1, b: [1, 2] },
            },
            occurred_at: '2026-05-01T10:00:00.000Z',
          },
        ],
      },
    });
    expect(res.status).toBe(200);
  });
});
