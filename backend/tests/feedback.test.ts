// Wave 14.3 — V1.5 feedback system route + cooldown coverage.
//
// Two layers:
//   1. POST /me/feedback shape: auth gate, payload validation,
//      cooldown enforcement, outcome semantics.
//   2. GET /me/feedback/cooldown gate booleans flip correctly after
//      a recorded response.
//
// We seed `feedback_responses` directly via Drizzle when the test
// needs a stale-cooldown precondition (so we don't need to advance
// `Date.now()`).

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { eq } from 'drizzle-orm';

import { inject } from './helpers/inject';
import { makeTestApp, type TestApp } from './helpers/db';
import { feedbackResponses } from '../src/db/schema';

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

async function backdateRow(userId: string, kind: string, when: Date) {
  await h.database.exec(
    `UPDATE feedback_responses SET created_at = '${when.toISOString()}'
     WHERE user_id = '${userId}' AND prompt_kind = '${kind}'`
  );
}

describe('POST /me/feedback', () => {
  it('401 without bearer token', async () => {
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/feedback',
      json: { prompt_kind: 'after_summary', outcome: 'submitted', rating: 5 },
    });
    expect(res.status).toBe(401);
  });

  it('400 on invalid prompt_kind', async () => {
    const { accessToken } = await login('fb-bad-kind');
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/feedback',
      headers: { authorization: `Bearer ${accessToken}` },
      json: { prompt_kind: 'random_thing', outcome: 'submitted', rating: 5 },
    });
    expect(res.status).toBe(400);
    expect((res.json as { error: string }).error).toBe('invalid_payload');
  });

  it('400 on rating out of [1,5]', async () => {
    const { accessToken } = await login('fb-bad-rating');
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/feedback',
      headers: { authorization: `Bearer ${accessToken}` },
      json: {
        prompt_kind: 'after_summary',
        outcome: 'submitted',
        rating: 7,
      },
    });
    expect(res.status).toBe(400);
  });

  it('400 when outcome=submitted and content is empty', async () => {
    const { accessToken } = await login('fb-empty-submit');
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/feedback',
      headers: { authorization: `Bearer ${accessToken}` },
      json: { prompt_kind: 'after_summary', outcome: 'submitted' },
    });
    expect(res.status).toBe(400);
    expect((res.json as { error: string }).error).toBe(
      'submitted_requires_content'
    );
  });

  it('201 + writes a row on first submission', async () => {
    const { accessToken, userId } = await login('fb-first');
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/feedback',
      headers: { authorization: `Bearer ${accessToken}` },
      json: {
        prompt_kind: 'after_summary',
        outcome: 'submitted',
        rating: 4,
        comment_text: 'felt good',
        context: { session_id: 'abc' },
      },
    });
    expect(res.status).toBe(201);
    expect((res.json as { id: string }).id).toBeDefined();

    const rows = await h.database.orm
      .select()
      .from(feedbackResponses)
      .where(eq(feedbackResponses.userId, userId));
    expect(rows).toHaveLength(1);
    expect(rows[0].promptKind).toBe('after_summary');
    expect(rows[0].rating).toBe(4);
    expect(rows[0].commentText).toBe('felt good');
  });

  it('201 + writes a dismissal row with no rating', async () => {
    const { accessToken, userId } = await login('fb-dismiss');
    const res = await inject(h.app, {
      method: 'POST',
      path: '/me/feedback',
      headers: { authorization: `Bearer ${accessToken}` },
      json: { prompt_kind: 'after_friction', outcome: 'dismissed' },
    });
    expect(res.status).toBe(201);
    const rows = await h.database.orm
      .select()
      .from(feedbackResponses)
      .where(eq(feedbackResponses.userId, userId));
    expect(rows[0].outcome).toBe('dismissed');
    expect(rows[0].rating).toBeNull();
  });

  it('429 on a second submission within the cooldown', async () => {
    const { accessToken } = await login('fb-cooldown');
    const first = await inject(h.app, {
      method: 'POST',
      path: '/me/feedback',
      headers: { authorization: `Bearer ${accessToken}` },
      json: { prompt_kind: 'after_summary', outcome: 'submitted', rating: 5 },
    });
    expect(first.status).toBe(201);
    const second = await inject(h.app, {
      method: 'POST',
      path: '/me/feedback',
      headers: { authorization: `Bearer ${accessToken}` },
      json: { prompt_kind: 'after_summary', outcome: 'submitted', rating: 4 },
    });
    expect(second.status).toBe(429);
    const body = second.json as { error: string; retry_after_seconds: number };
    expect(body.error).toBe('cooldown');
    expect(body.retry_after_seconds).toBeGreaterThan(0);
  });

  it('cooldown is per-prompt-kind (after_summary submission does not block after_friction)', async () => {
    const { accessToken } = await login('fb-per-kind');
    await inject(h.app, {
      method: 'POST',
      path: '/me/feedback',
      headers: { authorization: `Bearer ${accessToken}` },
      json: { prompt_kind: 'after_summary', outcome: 'submitted', rating: 5 },
    });
    const friction = await inject(h.app, {
      method: 'POST',
      path: '/me/feedback',
      headers: { authorization: `Bearer ${accessToken}` },
      json: { prompt_kind: 'after_friction', outcome: 'dismissed' },
    });
    expect(friction.status).toBe(201);
  });

  it('a 25-hour-old row releases the cooldown', async () => {
    const { accessToken, userId } = await login('fb-stale');
    const seed = await inject(h.app, {
      method: 'POST',
      path: '/me/feedback',
      headers: { authorization: `Bearer ${accessToken}` },
      json: { prompt_kind: 'after_summary', outcome: 'submitted', rating: 5 },
    });
    expect(seed.status).toBe(201);
    await backdateRow(
      userId,
      'after_summary',
      new Date(Date.now() - 25 * 60 * 60 * 1000)
    );
    const second = await inject(h.app, {
      method: 'POST',
      path: '/me/feedback',
      headers: { authorization: `Bearer ${accessToken}` },
      json: { prompt_kind: 'after_summary', outcome: 'submitted', rating: 3 },
    });
    expect(second.status).toBe(201);
  });
});

describe('GET /me/feedback/cooldown', () => {
  it('401 without bearer', async () => {
    const res = await inject(h.app, {
      method: 'GET',
      path: '/me/feedback/cooldown',
    });
    expect(res.status).toBe(401);
  });

  it('returns both gates open for a user who has never responded', async () => {
    const { accessToken } = await login('fb-cd-fresh');
    const res = await inject(h.app, {
      method: 'GET',
      path: '/me/feedback/cooldown',
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(res.status).toBe(200);
    const body = res.json as {
      cooldown_hours: number;
      after_summary_allowed: boolean;
      after_friction_allowed: boolean;
    };
    expect(body.cooldown_hours).toBe(24);
    expect(body.after_summary_allowed).toBe(true);
    expect(body.after_friction_allowed).toBe(true);
  });

  it('flips after_summary_allowed to false after a fresh response', async () => {
    const { accessToken } = await login('fb-cd-recent');
    await inject(h.app, {
      method: 'POST',
      path: '/me/feedback',
      headers: { authorization: `Bearer ${accessToken}` },
      json: { prompt_kind: 'after_summary', outcome: 'submitted', rating: 5 },
    });
    const cd = await inject(h.app, {
      method: 'GET',
      path: '/me/feedback/cooldown',
      headers: { authorization: `Bearer ${accessToken}` },
    });
    const body = cd.json as {
      after_summary_allowed: boolean;
      after_friction_allowed: boolean;
    };
    expect(body.after_summary_allowed).toBe(false);
    expect(body.after_friction_allowed).toBe(true);
  });
});
