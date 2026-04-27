import {
  pgTable,
  uuid,
  text,
  timestamp,
  jsonb,
  integer,
  boolean,
  bigint,
  date,
  numeric,
  index,
  uniqueIndex,
} from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';

// Mastery's persistence layer.
//
// Wave 1 — auth/identity foundation (users, identities, sessions, profiles,
// audit/integration logs).
// Wave 2 — server-owned lesson sessions, immutable attempt history, and the
// per-lesson progress aggregate (`lesson_sessions`, `exercise_attempts`,
// `lesson_progress`). Lesson content itself stays in `backend/data/lessons/`
// fixtures; the DB only records who attempted what, when, and how it scored.

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

// Wave 2 — server-owned lesson sessions.
//
// One row per user lesson attempt arc. The `(user_id, lesson_id)` pair is
// allowed to repeat across history; the partial unique index on the
// `in_progress` slice enforces the "at most one active session per
// user+lesson" invariant required by the resume contract.
export const lessonSessions = pgTable(
  'lesson_sessions',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    lessonId: uuid('lesson_id').notNull(),
    // `lesson_version` mirrors the content fingerprint of the lesson fixture
    // at session-start. Stored independently from `content_hash` so a
    // future authoring system can promote opaque versions ("v3") without
    // needing to rehash. For Wave 2 the two are equal.
    lessonVersion: text('lesson_version').notNull(),
    contentHash: text('content_hash').notNull(),
    unitId: text('unit_id'),
    ruleTag: text('rule_tag'),
    microRuleTag: text('micro_rule_tag'),
    status: text('status').notNull().default('in_progress'),
    exerciseCount: integer('exercise_count').notNull(),
    correctCount: integer('correct_count').notNull().default(0),
    startedAt: timestamp('started_at', { withTimezone: true, mode: 'date' })
      .defaultNow()
      .notNull(),
    lastActivityAt: timestamp('last_activity_at', {
      withTimezone: true,
      mode: 'date',
    })
      .defaultNow()
      .notNull(),
    completedAt: timestamp('completed_at', {
      withTimezone: true,
      mode: 'date',
    }),
    // Snapshot of the debrief at completion time. Null while the session is
    // in_progress; populated once on /complete and returned verbatim from
    // /result so the user-facing report is stable across content edits.
    debriefSnapshot: jsonb('debrief_snapshot'),
  },
  (t) => ({
    userLessonIdx: index('lesson_sessions_user_lesson_idx').on(
      t.userId,
      t.lessonId
    ),
    // Partial unique index: at most one in_progress row per (user, lesson).
    // The migration emits this with a `WHERE` clause; the Drizzle table
    // declaration is the static-schema view used by the ORM.
    activeIdx: uniqueIndex('lesson_sessions_active_idx')
      .on(t.userId, t.lessonId)
      .where(sql`status = 'in_progress'`),
    statusIdx: index('lesson_sessions_status_idx').on(t.status),
  })
);

// Wave 2 — immutable attempt history.
//
// Every submission writes a new row. The latest row per `(session, exercise)`
// is the "current" answer for scoring; older rows survive as history so we
// can audit how the learner converged on the answer.
export const exerciseAttempts = pgTable(
  'exercise_attempts',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    sessionId: uuid('session_id')
      .notNull()
      .references(() => lessonSessions.id, { onDelete: 'cascade' }),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    lessonId: uuid('lesson_id').notNull(),
    lessonVersion: text('lesson_version').notNull(),
    contentHash: text('content_hash').notNull(),
    unitId: text('unit_id'),
    ruleTag: text('rule_tag'),
    microRuleTag: text('micro_rule_tag'),
    exerciseId: uuid('exercise_id').notNull(),
    exerciseType: text('exercise_type').notNull(),
    userAnswer: text('user_answer').notNull(),
    correct: boolean('correct').notNull(),
    canonicalAnswer: text('canonical_answer').notNull(),
    evaluationSource: text('evaluation_source').notNull(),
    explanation: text('explanation'),
    // Wave 7.1.1 Codex P2.2: snapshot of the exercise's prompt + curated
    // explanation at attempt time so completed-session result reads
    // remain stable when the lesson fixture is edited later. Nullable —
    // legacy rows that pre-date the migration carry NULL and the service
    // falls back to the live lesson for those.
    promptSnapshot: text('prompt_snapshot'),
    explanationSnapshot: text('explanation_snapshot'),
    // Wave 9 — `LEARNING_ENGINE.md §17` friction event tag. Null when
    // the attempt was unremarkable; one of `repeated_error`,
    // `abandon_after_error`, `retry_loop`, `time_spike` when the
    // service detected a friction signal worth surfacing in retention
    // analytics.
    frictionEvent: text('friction_event'),
    // Client-supplied idempotency key. When provided, a partial unique index
    // on (session_id, client_attempt_id) makes resubmits of the same
    // attempt_id return the original row rather than insert a duplicate.
    clientAttemptId: uuid('client_attempt_id'),
    submittedAt: timestamp('submitted_at', {
      withTimezone: true,
      mode: 'date',
    }).notNull(),
    createdAt: timestamp('created_at', { withTimezone: true, mode: 'date' })
      .defaultNow()
      .notNull(),
  },
  (t) => ({
    sessionIdx: index('exercise_attempts_session_idx').on(t.sessionId),
    userLessonIdx: index('exercise_attempts_user_lesson_idx').on(
      t.userId,
      t.lessonId
    ),
    exerciseIdx: index('exercise_attempts_exercise_idx').on(
      t.sessionId,
      t.exerciseId
    ),
    attemptIdIdx: uniqueIndex('exercise_attempts_attempt_id_idx')
      .on(t.sessionId, t.clientAttemptId)
      .where(sql`client_attempt_id IS NOT NULL`),
  })
);

// Wave 2 — per-lesson aggregate, one row per `(user, lesson)` pair.
//
// Updated on session completion. Lets the dashboard render lesson statuses
// and recommended-next without scanning the attempt history table.
export const lessonProgress = pgTable(
  'lesson_progress',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    lessonId: uuid('lesson_id').notNull(),
    attemptsCount: integer('attempts_count').notNull().default(0),
    completed: boolean('completed').notNull().default(false),
    latestCorrect: integer('latest_correct'),
    latestTotal: integer('latest_total'),
    bestCorrect: integer('best_correct'),
    bestTotal: integer('best_total'),
    lastSessionId: uuid('last_session_id').references(() => lessonSessions.id, {
      onDelete: 'set null',
    }),
    firstCompletedAt: timestamp('first_completed_at', {
      withTimezone: true,
      mode: 'date',
    }),
    lastCompletedAt: timestamp('last_completed_at', {
      withTimezone: true,
      mode: 'date',
    }),
    createdAt: timestamp('created_at', { withTimezone: true, mode: 'date' })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true, mode: 'date' })
      .defaultNow()
      .notNull(),
  },
  (t) => ({
    userLessonIdx: uniqueIndex('lesson_progress_user_lesson_idx').on(
      t.userId,
      t.lessonId
    ),
  })
);


// Wave 7.3 — engine state migration. The Flutter LearnerSkillStore +
// ReviewScheduler already encode this state per LEARNING_ENGINE.md §§7,
// 9.3 in SharedPreferences; this is the server-side mirror so state
// follows the learner across devices instead of resetting on
// reinstall. Same field shape as the Dart model on purpose, so the
// Wave 7.4 client rewrite is a thin API transport.

/// Per-learner per-skill mastery state per LEARNING_ENGINE.md §7.1.
export const learnerSkills = pgTable(
  'learner_skills',
  {
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    skillId: text('skill_id').notNull(),
    /// Internal 0–100 score per §7.1. V0 deltas weighted by evidence
    /// tier (weak 5, medium 10, strong 15, strongest 20).
    masteryScore: integer('mastery_score').notNull().default(0),
    /// Recency for §9.3 review scheduling. Null until the first attempt
    /// is recorded for this skill.
    lastAttemptAt: timestamp('last_attempt_at', {
      withTimezone: true,
      mode: 'date',
    }),
    /// Counts of attempts at each evidence tier per §6.1. Stored as a
    /// JSON object keyed by tier ("weak"|"medium"|"strong"|"strongest")
    /// so additive tier extensions don't require a schema change.
    evidenceSummary: jsonb('evidence_summary')
      .$type<Record<string, number>>()
      .notNull()
      .default({}),
    /// Last N target-error codes seen on this skill per §7.1. Stored
    /// as a stringly array; `LearnerSkillStore.recentErrorsCap` (5)
    /// applied at write time.
    recentErrors: jsonb('recent_errors')
      .$type<string[]>()
      .notNull()
      .default([]),
    /// Sticky per §6.4. Set to true the first time the learner records
    /// a strongest-tier correct attempt that satisfies §6.3 (meaning +
    /// form). Invalidated only by an evaluation_version bump per §12.3.
    productionGateCleared: boolean('production_gate_cleared')
      .notNull()
      .default(false),
    /// `evaluation_version` at which the gate cleared. Null when never
    /// cleared. Used to invalidate the gate when the evaluator
    /// semantics move under a previously-cleared learner.
    gateClearedAtVersion: integer('gate_cleared_at_version'),

    /// Wave 10 — Mastery V1 inputs per V1 spec §10.
    /// Total attempts on this skill, ever. The V1 gate reads `≥6` (or
    /// `≥4` with at least one correction/production type seen).
    attemptsCount: integer('attempts_count').notNull().default(0),
    /// Distinct exercise-type codes the learner has attempted on this
    /// skill. Stored as a JSON array of strings (e.g.
    /// `["fill_blank", "sentence_correction"]`). The V1 gate reads
    /// `length ≥ 2` and "≥1 correction or production".
    exerciseTypesSeen: jsonb('exercise_types_seen')
      .$type<string[]>()
      .notNull()
      .default([]),
    /// Outcome of the most recent attempt: `'correct' | 'partial' |
    /// 'wrong'`. The V1 gate refuses promotion when the last attempt
    /// was wrong, so this column is checked on every read.
    lastOutcome: text('last_outcome'),
    /// Count of repeated `conceptual_error` events in the rolling
    /// last-5 window of `recent_errors`. The V1 gate refuses promotion
    /// when this is ≥ 2.
    repeatedConceptualCount: integer('repeated_conceptual_count')
      .notNull()
      .default(0),
    /// Sum of evidence-weighted correct outcomes for this skill.
    /// `weighted_correct_sum / weighted_total_sum` is the "weighted
    /// accuracy" the V1 gate compares against the 80% threshold.
    /// `numeric(10,2)` is overkill but keeps Postgres + PGlite arithmetic
    /// stable across drivers.
    weightedCorrectSum: numeric('weighted_correct_sum', {
      precision: 10,
      scale: 2,
    })
      .notNull()
      .default('0'),
    weightedTotalSum: numeric('weighted_total_sum', {
      precision: 10,
      scale: 2,
    })
      .notNull()
      .default('0'),

    updatedAt: timestamp('updated_at', { withTimezone: true, mode: 'date' })
      .defaultNow()
      .notNull(),
  },
  (t) => ({
    pk: uniqueIndex('learner_skills_pk').on(t.userId, t.skillId),
  })
);

/// Per-learner per-skill review cadence per LEARNING_ENGINE.md §§9.3, 9.4.
export const learnerReviewSchedule = pgTable(
  'learner_review_schedule',
  {
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    skillId: text('skill_id').notNull(),
    /// Cadence step. 1=1d, 2=3d, 3=7d, 4+=21d capped. Step 5 = graduated.
    step: integer('step').notNull().default(1),
    /// UTC timestamp when this skill is next due for review.
    dueAt: timestamp('due_at', { withTimezone: true, mode: 'date' })
      .notNull(),
    /// Most recent session that touched this skill.
    lastOutcomeAt: timestamp('last_outcome_at', {
      withTimezone: true,
      mode: 'date',
    }).notNull(),
    /// Mistakes recorded on this skill during the most recent session.
    lastOutcomeMistakes: integer('last_outcome_mistakes')
      .notNull()
      .default(0),
    /// §9.4 graduated flag. Soft signal — a graduated skill that fails
    /// in mixed review or contrast loses the flag and drops back into
    /// the cadence at step 1.
    graduated: boolean('graduated').notNull().default(false),
    updatedAt: timestamp('updated_at', { withTimezone: true, mode: 'date' })
      .defaultNow()
      .notNull(),
  },
  (t) => ({
    pk: uniqueIndex('learner_review_schedule_pk').on(t.userId, t.skillId),
    dueIdx: index('learner_review_schedule_due_idx').on(t.userId, t.dueAt),
  })
);

/// Wave 9 — append-only Decision Log per `LEARNING_ENGINE.md §18`.
/// One row per Decision Engine call. Lets us replay why the engine
/// chose the next exercise / promoted a skill / scheduled a review,
/// post-hoc. `previous_state` is the small jsonb snapshot of the inputs
/// the engine read (mastery, recent_errors, in-session mistakes); we
/// keep it tight so the table stays cheap.
export const decisionLog = pgTable(
  'decision_log',
  {
    id: uuid('id').primaryKey().default(sql`gen_random_uuid()`),
    userId: uuid('user_id')
      .notNull()
      .references(() => users.id, { onDelete: 'cascade' }),
    /// Nullable so diagnostic-mode decisions (no lesson_session row) still
    /// log under the same table.
    sessionId: uuid('session_id').references(() => lessonSessions.id, {
      onDelete: 'set null',
    }),
    /// Nullable so session-level decisions (e.g. session-end summary)
    /// can log without a single dominant skill.
    skillId: text('skill_id'),
    /// Decision code. One of: `next_exercise`, `reorder_queue`,
    /// `mark_weak`, `schedule_review`, `mastery_promoted`,
    /// `mastery_invalidated`, `production_gate_cleared`. Open-ended on
    /// purpose so new decision types can be added without a migration.
    decision: text('decision').notNull(),
    /// Short reason code matching `LEARNING_ENGINE.md §11.3` strings
    /// when the decision feeds the transparency layer; free-form
    /// otherwise.
    reason: text('reason'),
    /// Small jsonb snapshot of the inputs read by the engine. Designed
    /// to be small — we do not dump the whole learner_skill record.
    previousState: jsonb('previous_state').notNull().default(sql`'{}'::jsonb`),
    /// Set when the decision picked an exercise. Null otherwise.
    nextExerciseId: uuid('next_exercise_id'),
    createdAt: timestamp('created_at', { withTimezone: true, mode: 'date' })
      .defaultNow()
      .notNull(),
  },
  (t) => ({
    userIdx: index('decision_log_user_idx').on(t.userId, t.createdAt),
    sessionIdx: index('decision_log_session_idx').on(t.sessionId),
    skillIdx: index('decision_log_skill_idx').on(t.skillId),
  })
);

/// Wave 9 — daily exercise health counters. Per
/// `LEARNING_ENGINE.md §17`, an exercise needs ≥30 attempts before
/// metric-driven decisions can be made on it. We aggregate by date so
/// the time series is readable and rotating older buckets is cheap.
/// `qa_review_pending` lives here (and not on a fixture file) so the
/// flag-flip can be done via SQL when Wave 11 lands the bad-exercise
/// detector — no JSON edits required.
export const exerciseStats = pgTable(
  'exercise_stats',
  {
    exerciseId: uuid('exercise_id').notNull(),
    statDate: date('stat_date').notNull(),
    attemptsCount: integer('attempts_count').notNull().default(0),
    correctCount: integer('correct_count').notNull().default(0),
    partialCount: integer('partial_count').notNull().default(0),
    wrongCount: integer('wrong_count').notNull().default(0),
    /// Sum of (submitted_at - exercise_started_at) in ms for every
    /// attempt that landed in this bucket. Average is computed at
    /// read-time to avoid the float-precision drift of a running mean.
    totalTimeToAnswerMs: bigint('total_time_to_answer_ms', {
      mode: 'number',
    })
      .notNull()
      .default(0),
    /// Wave 11+ will flip this when the bad-exercise detector fires;
    /// Wave 9 only ships the column.
    qaReviewPending: boolean('qa_review_pending').notNull().default(false),
    /// Pinned to the exercise version the bucket aggregates. When the
    /// exercise is rewritten (`exercise_version` bumps), older buckets
    /// stay tied to the old version for replay; new buckets start
    /// fresh under the new version.
    exerciseVersion: integer('exercise_version').notNull().default(1),
    updatedAt: timestamp('updated_at', { withTimezone: true, mode: 'date' })
      .defaultNow()
      .notNull(),
  },
  (t) => ({
    pk: uniqueIndex('exercise_stats_pk').on(t.exerciseId, t.statDate),
    pendingIdx: index('exercise_stats_pending_idx').on(t.qaReviewPending),
  })
);
