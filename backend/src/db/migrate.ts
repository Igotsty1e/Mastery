// Tiny migration runner. We deliberately do NOT pull in drizzle-kit's
// journal/.sql file format yet — Wave 1 ships one initial migration, and an
// embedded TS module avoids needing a copy step in `tsc` builds.
//
// Wave 2 may switch to drizzle-kit if/when migrations become numerous.

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

const MIGRATIONS: Migration[] = [{ id: '0001_init', sql: INIT_SQL }];

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
