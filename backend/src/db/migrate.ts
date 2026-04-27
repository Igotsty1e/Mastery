// Tiny migration runner. We deliberately do NOT pull in drizzle-kit's
// journal/.sql file format yet — Wave 2 ships two embedded migrations and an
// inline TS module avoids needing a copy step in `tsc` builds.
//
// Once a third migration lands we can switch to drizzle-kit's journal.

import type { Database } from './client';

interface Migration {
  id: string;
  sql: string;
}

const INIT_SQL = `
CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS auth_identities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider text NOT NULL,
  subject text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS auth_identities_provider_subject_idx
  ON auth_identities(provider, subject);
CREATE INDEX IF NOT EXISTS auth_identities_user_idx ON auth_identities(user_id);

CREATE TABLE IF NOT EXISTS auth_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  refresh_token_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_used_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  user_agent text,
  ip_address text
);
CREATE UNIQUE INDEX IF NOT EXISTS auth_sessions_hash_idx
  ON auth_sessions(refresh_token_hash);
CREATE INDEX IF NOT EXISTS auth_sessions_user_idx ON auth_sessions(user_id);

CREATE TABLE IF NOT EXISTS user_profiles (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  display_name text,
  level text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  event_type text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS audit_events_user_idx ON audit_events(user_id);
CREATE INDEX IF NOT EXISTS audit_events_type_idx ON audit_events(event_type);

CREATE TABLE IF NOT EXISTS integration_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source text NOT NULL,
  event_type text NOT NULL,
  external_id text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  processed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS integration_events_source_idx ON integration_events(source);
`;

// Wave 2 — server-owned lesson sessions, immutable attempt history, and the
// per-lesson aggregate. The partial unique index on `lesson_sessions` is the
// invariant that keeps "at most one in_progress session per (user, lesson)"
// honest at the storage layer; resume semantics in the service layer rely
// on it for race-free upserts.
const LESSON_SESSIONS_SQL = `
CREATE TABLE IF NOT EXISTS lesson_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  lesson_id uuid NOT NULL,
  lesson_version text NOT NULL,
  content_hash text NOT NULL,
  unit_id text,
  rule_tag text,
  micro_rule_tag text,
  status text NOT NULL DEFAULT 'in_progress',
  exercise_count integer NOT NULL,
  correct_count integer NOT NULL DEFAULT 0,
  started_at timestamptz NOT NULL DEFAULT now(),
  last_activity_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  debrief_snapshot jsonb
);
CREATE INDEX IF NOT EXISTS lesson_sessions_user_lesson_idx
  ON lesson_sessions(user_id, lesson_id);
CREATE UNIQUE INDEX IF NOT EXISTS lesson_sessions_active_idx
  ON lesson_sessions(user_id, lesson_id) WHERE status = 'in_progress';
CREATE INDEX IF NOT EXISTS lesson_sessions_status_idx
  ON lesson_sessions(status);

CREATE TABLE IF NOT EXISTS exercise_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES lesson_sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  lesson_id uuid NOT NULL,
  lesson_version text NOT NULL,
  content_hash text NOT NULL,
  unit_id text,
  rule_tag text,
  micro_rule_tag text,
  exercise_id uuid NOT NULL,
  exercise_type text NOT NULL,
  user_answer text NOT NULL,
  correct boolean NOT NULL,
  canonical_answer text NOT NULL,
  evaluation_source text NOT NULL,
  explanation text,
  submitted_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS exercise_attempts_session_idx
  ON exercise_attempts(session_id);
CREATE INDEX IF NOT EXISTS exercise_attempts_user_lesson_idx
  ON exercise_attempts(user_id, lesson_id);
CREATE INDEX IF NOT EXISTS exercise_attempts_exercise_idx
  ON exercise_attempts(session_id, exercise_id);

CREATE TABLE IF NOT EXISTS lesson_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  lesson_id uuid NOT NULL,
  attempts_count integer NOT NULL DEFAULT 0,
  completed boolean NOT NULL DEFAULT false,
  latest_correct integer,
  latest_total integer,
  best_correct integer,
  best_total integer,
  last_session_id uuid REFERENCES lesson_sessions(id) ON DELETE SET NULL,
  first_completed_at timestamptz,
  last_completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS lesson_progress_user_lesson_idx
  ON lesson_progress(user_id, lesson_id);
`;

// Wave 2 hardening — make `client_attempt_id` first-class so the answer
// route can enforce wire-level idempotency at the storage layer instead of
// only echoing the field back. Partial unique index because legacy rows
// (and the few callers still on the transitional anonymous flow) write
// NULL.
const ATTEMPT_IDEMPOTENCY_SQL = `
ALTER TABLE exercise_attempts
  ADD COLUMN IF NOT EXISTS client_attempt_id uuid;
CREATE UNIQUE INDEX IF NOT EXISTS exercise_attempts_attempt_id_idx
  ON exercise_attempts(session_id, client_attempt_id)
  WHERE client_attempt_id IS NOT NULL;
`;

const MIGRATIONS: Migration[] = [
  { id: '0001_init', sql: INIT_SQL },
  { id: '0002_lesson_sessions', sql: LESSON_SESSIONS_SQL },
  { id: '0003_attempt_idempotency', sql: ATTEMPT_IDEMPOTENCY_SQL },
];

export async function runMigrations(database: Database): Promise<void> {
  // Postgres needs `pgcrypto` to provide `gen_random_uuid()` on versions
  // older than 13 and is a no-op on newer ones. We enable it explicitly so
  // the migration is portable across managed-Postgres flavours that don't
  // pre-create the extension. PGlite ships `gen_random_uuid` in its core
  // build and rejects `CREATE EXTENSION pgcrypto`, so we skip this on the
  // in-memory driver used by tests and dev fallback.
  if (database.driver === 'pg') {
    await database.exec(`CREATE EXTENSION IF NOT EXISTS pgcrypto;`);
  }

  await database.exec(`
    CREATE TABLE IF NOT EXISTS _migrations (
      id text PRIMARY KEY,
      applied_at timestamptz NOT NULL DEFAULT now()
    );
  `);
  const applied = await database.query<{ id: string }>(
    `SELECT id FROM _migrations`
  );
  const appliedSet = new Set(applied.map((row) => row.id));
  for (const m of MIGRATIONS) {
    if (appliedSet.has(m.id)) continue;
    await database.exec(m.sql);
    // Use a parameter-free literal — the id is a hard-coded constant.
    await database.exec(
      `INSERT INTO _migrations (id) VALUES ('${m.id.replace(/'/g, "''")}')`
    );
  }
}
