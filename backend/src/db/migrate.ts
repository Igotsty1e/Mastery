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

// Wave 7.1.1 Codex P2.2 fix: snapshot the prompt + curated explanation at
// attempt insert time so completed-session result reads stay stable when
// the lesson fixture is edited later. For listening_discrimination items
// the snapshot stores the audio transcript (the only review-friendly text
// we have). Old rows pre-dating the migration carry NULL — buildAnswers
// falls back to the live lesson for those, which is both safe (no real
// in-progress drift in practice on shipped data) and the previous
// behaviour.
const ATTEMPT_REVIEW_SNAPSHOT_SQL = `
ALTER TABLE exercise_attempts
  ADD COLUMN IF NOT EXISTS prompt_snapshot text;
ALTER TABLE exercise_attempts
  ADD COLUMN IF NOT EXISTS explanation_snapshot text;
`;

// Wave 7.3 — engine state migration. Mirrors the device-scoped Flutter
// LearnerSkillStore + ReviewScheduler so the same state persists across
// devices once Wave 7.4 wires the client.
const LEARNER_STATE_SQL = `
CREATE TABLE IF NOT EXISTS learner_skills (
  user_id                  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  skill_id                 text NOT NULL,
  mastery_score            integer NOT NULL DEFAULT 0,
  last_attempt_at          timestamptz,
  evidence_summary         jsonb NOT NULL DEFAULT '{}'::jsonb,
  recent_errors            jsonb NOT NULL DEFAULT '[]'::jsonb,
  production_gate_cleared  boolean NOT NULL DEFAULT false,
  gate_cleared_at_version  integer,
  updated_at               timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, skill_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS learner_skills_pk
  ON learner_skills(user_id, skill_id);

CREATE TABLE IF NOT EXISTS learner_review_schedule (
  user_id                uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  skill_id               text NOT NULL,
  step                   integer NOT NULL DEFAULT 1,
  due_at                 timestamptz NOT NULL,
  last_outcome_at        timestamptz NOT NULL,
  last_outcome_mistakes  integer NOT NULL DEFAULT 0,
  graduated              boolean NOT NULL DEFAULT false,
  updated_at             timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, skill_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS learner_review_schedule_pk
  ON learner_review_schedule(user_id, skill_id);
CREATE INDEX IF NOT EXISTS learner_review_schedule_due_idx
  ON learner_review_schedule(user_id, due_at);
`;

// Wave 11.2 — dynamic sessions (V1 spec). Rather than make `lesson_id`
// nullable (which cascades type changes through every consumer), the
// runtime writes a sentinel UUID (`DYNAMIC_SESSION_LESSON_ID`) on
// dynamic-mode sessions. We update the partial unique index so the
// "at most one in_progress per (user, lesson)" rule still holds for
// authoring-bound sessions but multiple in-flight dynamic sessions
// (sentinel id) per user are allowed — concurrent dynamic sessions
// are guarded by the service layer instead.
const DYNAMIC_SESSIONS_SQL = `
DROP INDEX IF EXISTS lesson_sessions_active_idx;

CREATE UNIQUE INDEX IF NOT EXISTS lesson_sessions_active_idx
  ON lesson_sessions(user_id, lesson_id)
  WHERE status = 'in_progress'
        AND lesson_id <> '00000000-0000-0000-0000-000000000000';
`;

// Wave 10 — Mastery V1 inputs (rule-based gate per V1 spec §10).
// Adds the four counters the new gate reads: total attempts, set of
// exercise types seen, last-attempt outcome, repeated-conceptual count.
// `mastery_score` stays in the row for now (used only by status
// derivation as a coarse hint); Wave 11 cleanup may remove it.
const MASTERY_V1_SQL = `
ALTER TABLE learner_skills
  ADD COLUMN IF NOT EXISTS attempts_count integer NOT NULL DEFAULT 0;
ALTER TABLE learner_skills
  ADD COLUMN IF NOT EXISTS exercise_types_seen jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE learner_skills
  ADD COLUMN IF NOT EXISTS last_outcome text;
ALTER TABLE learner_skills
  ADD COLUMN IF NOT EXISTS repeated_conceptual_count integer NOT NULL DEFAULT 0;
ALTER TABLE learner_skills
  ADD COLUMN IF NOT EXISTS weighted_correct_sum numeric(10,2) NOT NULL DEFAULT 0;
ALTER TABLE learner_skills
  ADD COLUMN IF NOT EXISTS weighted_total_sum numeric(10,2) NOT NULL DEFAULT 0;
`;

// Wave 9 — observability infra. Append-only Decision Log per
// `LEARNING_ENGINE.md §18` so every Decision Engine call is replayable
// from the audit trail. `friction_event` enum on attempts so we can
// derive D1/D7 retention drivers without instrumenting the client.
// `exercise_stats` rolls up daily counters per exercise so the
// bad-exercise gate (Wave 11+) has data to flag on. Versioning columns
// land here so future schema changes can pivot off them without a new
// migration.
const OBSERVABILITY_V1_SQL = `
CREATE TABLE IF NOT EXISTS decision_log (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_id      uuid REFERENCES lesson_sessions(id) ON DELETE SET NULL,
  skill_id        text,
  decision        text NOT NULL,
  reason          text,
  previous_state  jsonb NOT NULL DEFAULT '{}'::jsonb,
  next_exercise_id uuid,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS decision_log_user_idx ON decision_log(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS decision_log_session_idx ON decision_log(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS decision_log_skill_idx ON decision_log(skill_id) WHERE skill_id IS NOT NULL;

ALTER TABLE exercise_attempts
  ADD COLUMN IF NOT EXISTS friction_event text;

CREATE TABLE IF NOT EXISTS exercise_stats (
  exercise_id          uuid NOT NULL,
  stat_date            date NOT NULL,
  attempts_count       integer NOT NULL DEFAULT 0,
  correct_count        integer NOT NULL DEFAULT 0,
  partial_count        integer NOT NULL DEFAULT 0,
  wrong_count          integer NOT NULL DEFAULT 0,
  total_time_to_answer_ms bigint NOT NULL DEFAULT 0,
  qa_review_pending    boolean NOT NULL DEFAULT false,
  exercise_version     integer NOT NULL DEFAULT 1,
  updated_at           timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (exercise_id, stat_date)
);
CREATE INDEX IF NOT EXISTS exercise_stats_pending_idx
  ON exercise_stats(qa_review_pending) WHERE qa_review_pending = true;
`;

// Wave 12.2 — diagnostic probe runs (V1 spec §15). Separate table from
// lesson_sessions because the probe lifecycle is different: 5–7 fixed
// items, no day-to-day resume, scored into a CEFR derivation rather
// than a per-lesson aggregate. Partial unique index on
// `(user_id) WHERE status = 'in_progress'` enforces "at most one
// active run per user" so /diagnostic/start can resume an existing run
// idempotently.
const DIAGNOSTIC_RUNS_SQL = `
CREATE TABLE IF NOT EXISTS diagnostic_runs (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status        text NOT NULL DEFAULT 'in_progress',
  exercise_ids  jsonb NOT NULL DEFAULT '[]'::jsonb,
  responses     jsonb NOT NULL DEFAULT '[]'::jsonb,
  cefr_level    text,
  skill_map     jsonb,
  started_at    timestamptz NOT NULL DEFAULT now(),
  completed_at  timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS diagnostic_runs_user_idx
  ON diagnostic_runs(user_id, started_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS diagnostic_runs_active_idx
  ON diagnostic_runs(user_id) WHERE status = 'in_progress';
`;

// Wave 14.3 — V1.5 feedback system. Two prompt surfaces (after-session
// summary, after-friction) write into one append-only table. The
// outcome column distinguishes "submitted" (the learner rated) from
// "dismissed" (swiped the prompt away) so analytics can read response
// rate without conflating disengagement with negative sentiment. The
// cooldown query reads `created_at` directly — the row is enough,
// regardless of outcome.
const FEEDBACK_RESPONSES_SQL = `
CREATE TABLE IF NOT EXISTS feedback_responses (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  prompt_kind   text NOT NULL,
  outcome       text NOT NULL,
  rating        smallint,
  comment_text  text,
  context       jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS feedback_responses_user_idx
  ON feedback_responses(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS feedback_responses_kind_idx
  ON feedback_responses(prompt_kind, created_at DESC);
`;

const MIGRATIONS: Migration[] = [
  { id: '0001_init', sql: INIT_SQL },
  { id: '0002_lesson_sessions', sql: LESSON_SESSIONS_SQL },
  { id: '0003_attempt_idempotency', sql: ATTEMPT_IDEMPOTENCY_SQL },
  { id: '0004_attempt_review_snapshot', sql: ATTEMPT_REVIEW_SNAPSHOT_SQL },
  { id: '0005_learner_state', sql: LEARNER_STATE_SQL },
  { id: '0006_observability_v1', sql: OBSERVABILITY_V1_SQL },
  { id: '0007_mastery_v1', sql: MASTERY_V1_SQL },
  { id: '0008_dynamic_sessions', sql: DYNAMIC_SESSIONS_SQL },
  { id: '0009_diagnostic_runs', sql: DIAGNOSTIC_RUNS_SQL },
  { id: '0010_feedback_responses', sql: FEEDBACK_RESPONSES_SQL },
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
