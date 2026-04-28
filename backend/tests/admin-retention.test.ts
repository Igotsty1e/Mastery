// Wave 14.1 — D1/D7 cohort retention coverage.
//
// Two layers:
//   1. `cohortRetention` SQL aggregation — does the cohort + activity
//      math come out right for hand-built fixtures?
//   2. `GET /admin/retention` route — auth gate (401 / 403 / 200)
//      and window-clamp behavior.
//
// We seed users + exercise_attempts directly via Drizzle so each test
// case is reproducible without driving the full session lifecycle.

import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';

import { inject } from './helpers/inject';
import { makeTestApp, type TestApp } from './helpers/db';
import { cohortRetention } from '../src/admin/retention';
import {
  exerciseAttempts,
  lessonSessions,
  users,
} from '../src/db/schema';

let h: TestApp;
let originalAdminEnv: string | undefined;

beforeEach(async () => {
  h = await makeTestApp();
  originalAdminEnv = process.env.ADMIN_USER_IDS;
  delete process.env.ADMIN_USER_IDS;
});

afterEach(async () => {
  if (originalAdminEnv === undefined) {
    delete process.env.ADMIN_USER_IDS;
  } else {
    process.env.ADMIN_USER_IDS = originalAdminEnv;
  }
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

async function backdateUser(userId: string, when: Date) {
  await h.database.exec(
    `UPDATE users SET created_at = '${when.toISOString()}' WHERE id = '${userId}'`
  );
}

async function insertSession(userId: string): Promise<string> {
  const id = randomUUID();
  await h.database.orm.insert(lessonSessions).values({
    id,
    userId,
    lessonId: randomUUID(),
    lessonVersion: 'v1',
    contentHash: 'h',
    status: 'in_progress',
    exerciseCount: 1,
    correctCount: 0,
  });
  return id;
}

async function insertAttempt(opts: {
  sessionId: string;
  userId: string;
  submittedAt: Date;
}) {
  await h.database.orm.insert(exerciseAttempts).values({
    sessionId: opts.sessionId,
    userId: opts.userId,
    lessonId: randomUUID(),
    lessonVersion: 'v1',
    contentHash: 'h',
    exerciseId: randomUUID(),
    exerciseType: 'multiple_choice',
    userAnswer: 'a',
    correct: true,
    canonicalAnswer: 'a',
    evaluationSource: 'deterministic',
    submittedAt: opts.submittedAt,
  });
}

describe('Wave 14.1 — cohortRetention SQL', () => {
  it('returns no rows when there are no users', async () => {
    const rows = await cohortRetention(h.database.orm, {
      now: new Date('2026-04-28T12:00:00Z'),
    });
    expect(rows).toEqual([]);
  });

  it('reports cohort_size = signups per UTC day, no activity yet', async () => {
    const now = new Date('2026-04-28T12:00:00Z');
    const day = new Date('2026-04-25T08:00:00Z');
    const a = await login('cohort-a');
    const b = await login('cohort-b');
    await backdateUser(a.userId, day);
    await backdateUser(b.userId, day);
    const rows = await cohortRetention(h.database.orm, { now });
    const apr25 = rows.find((r) => r.cohortDay === '2026-04-25');
    expect(apr25?.cohortSize).toBe(2);
    expect(apr25?.d1Active).toBe(0);
    expect(apr25?.d7Active).toBe(0);
    expect(apr25?.d1Rate).toBeCloseTo(0);
    expect(apr25?.d1Complete).toBe(true);
  });

  it('counts D1 activity strictly on cohort_day + 1 (not day-of)', async () => {
    const now = new Date('2026-04-28T12:00:00Z');
    const cohort = new Date('2026-04-20T08:00:00Z');
    const sameDayAttempt = new Date('2026-04-20T20:00:00Z'); // not D1
    const d1Attempt = new Date('2026-04-21T09:00:00Z');
    const a = await login('strict-a');
    const b = await login('strict-b');
    await backdateUser(a.userId, cohort);
    await backdateUser(b.userId, cohort);

    const sessA = await insertSession(a.userId);
    await insertAttempt({
      sessionId: sessA,
      userId: a.userId,
      submittedAt: sameDayAttempt,
    });

    const sessB = await insertSession(b.userId);
    await insertAttempt({
      sessionId: sessB,
      userId: b.userId,
      submittedAt: d1Attempt,
    });

    const rows = await cohortRetention(h.database.orm, { now });
    const r = rows.find((x) => x.cohortDay === '2026-04-20');
    expect(r?.cohortSize).toBe(2);
    expect(r?.d1Active).toBe(1);
    expect(r?.d1Rate).toBeCloseTo(0.5, 5);
  });

  it('flips d1Complete to false when the window has not closed yet', async () => {
    const now = new Date('2026-04-28T01:00:00Z'); // ~1h into Apr 28
    const cohort = new Date('2026-04-27T08:00:00Z');
    const a = await login('young-a');
    await backdateUser(a.userId, cohort);
    const rows = await cohortRetention(h.database.orm, { now });
    const r = rows.find((x) => x.cohortDay === '2026-04-27');
    // Cohort_day + 1 = Apr 28; today is Apr 28 → window not closed yet.
    expect(r?.d1Complete).toBe(false);
    expect(r?.d7Complete).toBe(false);
  });
});

describe('Wave 14.1 — GET /admin/retention auth gate', () => {
  it('401 without bearer token', async () => {
    const res = await inject(h.app, {
      method: 'GET',
      path: '/admin/retention',
    });
    expect(res.status).toBe(401);
  });

  it('403 when authed but user is not in ADMIN_USER_IDS', async () => {
    const { accessToken } = await login('non-admin');
    process.env.ADMIN_USER_IDS = ''; // explicit empty
    const res = await inject(h.app, {
      method: 'GET',
      path: '/admin/retention',
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(res.status).toBe(403);
  });

  it('200 + JSON when ADMIN_USER_IDS contains the caller', async () => {
    const { accessToken, userId } = await login('admin-1');
    process.env.ADMIN_USER_IDS = userId;
    const res = await inject(h.app, {
      method: 'GET',
      path: '/admin/retention',
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(res.status).toBe(200);
    const body = res.json as {
      window_days: number;
      cohorts: Array<{ cohort_day?: string; cohortDay?: string }>;
    };
    expect(body.window_days).toBe(30);
    expect(Array.isArray(body.cohorts)).toBe(true);
  });

  it('window query is clamped to [1, 180]', async () => {
    const { accessToken, userId } = await login('admin-2');
    process.env.ADMIN_USER_IDS = userId;
    const tooLow = await inject(h.app, {
      method: 'GET',
      path: '/admin/retention?window=0',
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect((tooLow.json as { window_days: number }).window_days).toBe(1);
    const tooHigh = await inject(h.app, {
      method: 'GET',
      path: '/admin/retention?window=9999',
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect((tooHigh.json as { window_days: number }).window_days).toBe(180);
  });
});

describe('Wave 14.1 — GET /admin/retention.html', () => {
  it('serves an HTML page with one table row per cohort', async () => {
    const { accessToken, userId } = await login('admin-html');
    process.env.ADMIN_USER_IDS = userId;
    const cohortDay = new Date('2026-04-22T08:00:00Z');
    await backdateUser(userId, cohortDay);
    const res = await inject(h.app, {
      method: 'GET',
      path: '/admin/retention.html',
      headers: { authorization: `Bearer ${accessToken}` },
    });
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/html/);
    expect(res.text).toContain('<table');
    expect(res.text).toContain('2026-04-22');
    expect(res.text).toContain('D1/D7 Retention');
  });
});
