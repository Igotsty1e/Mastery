import {
  pgTable,
  uuid,
  text,
  timestamp,
  jsonb,
  index,
  uniqueIndex,
} from 'drizzle-orm/pg-core';

// Mastery's persistence layer (Wave 1 — auth/identity foundation only).
//
// Lesson sessions and exercise attempts intentionally do NOT live here yet;
// they remain in src/store/memory.ts until Wave 2 migrates them. See
// docs/plans/auth-foundation.md for the staging.

export const users = pgTable('users', {
  id: uuid('id').primaryKey().defaultRandom(),
  createdAt: timestamp('created_at', { withTimezone: true, mode: 'date' })
    .defaultNow()
    .notNull(),
});

// One row per (provider, subject). A user can have multiple identities — e.g.
// Apple sign-in today, an additional provider tomorrow — by linking more
// rows to the same user_id. No email is stored on this layer; provider
// subjects are the only stable identifier.
export const authIdentities = pgTable(
  'auth_identities',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    provider: text('provider').notNull(),
    subject: text('subject').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true, mode: 'date' })
      .defaultNow()
      .notNull(),
  },
  (t) => ({
    providerSubjectIdx: uniqueIndex('auth_identities_provider_subject_idx').on(
      t.provider,
      t.subject
    ),
    userIdx: index('auth_identities_user_idx').on(t.userId),
  })
);

// Opaque refresh-token sessions. The refresh token itself is never stored —
// only its sha256 hex hash. Access tokens are stateless HMAC and do not get
// rows here.
export const authSessions = pgTable(
  'auth_sessions',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    refreshTokenHash: text('refresh_token_hash').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true, mode: 'date' })
      .defaultNow()
      .notNull(),
    lastUsedAt: timestamp('last_used_at', { withTimezone: true, mode: 'date' })
      .defaultNow()
      .notNull(),
    expiresAt: timestamp('expires_at', {
      withTimezone: true,
      mode: 'date',
    }).notNull(),
    revokedAt: timestamp('revoked_at', { withTimezone: true, mode: 'date' }),
    userAgent: text('user_agent'),
    ipAddress: text('ip_address'),
  },
  (t) => ({
    hashIdx: uniqueIndex('auth_sessions_hash_idx').on(t.refreshTokenHash),
    userIdx: index('auth_sessions_user_idx').on(t.userId),
  })
);

export const userProfiles = pgTable('user_profiles', {
  userId: uuid('user_id')
    .primaryKey()
    .references(() => users.id, { onDelete: 'cascade' }),
  displayName: text('display_name'),
  level: text('level'),
  createdAt: timestamp('created_at', { withTimezone: true, mode: 'date' })
    .defaultNow()
    .notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true, mode: 'date' })
    .defaultNow()
    .notNull(),
});

// User-scoped audit log. user_id is nullable so that records survive a
// hard-delete of the user (set null on cascade) and can still be inspected
// when investigating GDPR/compliance asks.
export const auditEvents = pgTable(
  'audit_events',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id').references(() => users.id, {
      onDelete: 'set null',
    }),
    eventType: text('event_type').notNull(),
    payload: jsonb('payload').notNull().default({}),
    createdAt: timestamp('created_at', { withTimezone: true, mode: 'date' })
      .defaultNow()
      .notNull(),
  },
  (t) => ({
    userIdx: index('audit_events_user_idx').on(t.userId),
    typeIdx: index('audit_events_type_idx').on(t.eventType),
  })
);

// Inbox/outbox-style log for async integrations (Apple webhooks, future
// payment events, etc). Wave 1 only writes to this table from the stub
// login flow as a placeholder for the production webhook surface.
export const integrationEvents = pgTable(
  'integration_events',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    source: text('source').notNull(),
    eventType: text('event_type').notNull(),
    externalId: text('external_id'),
    payload: jsonb('payload').notNull().default({}),
    processedAt: timestamp('processed_at', {
      withTimezone: true,
      mode: 'date',
    }),
    createdAt: timestamp('created_at', { withTimezone: true, mode: 'date' })
      .defaultNow()
      .notNull(),
  },
  (t) => ({
    sourceIdx: index('integration_events_source_idx').on(t.source),
  })
);
