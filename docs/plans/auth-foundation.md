# Auth & Identity Foundation

**Status — Wave 1 shipped 2026-04-26.** Backend persistence + auth
endpoints only. Flutter client is **not** wired in this wave.

**Status — Wave 2 shipped 2026-04-26.** Server-owned lesson sessions,
immutable attempt history, per-lesson progress aggregate, and the
`/dashboard` endpoint. Flutter client wiring is still pending — see
"Wave 3 — remaining" below.

## Why this lives in the backend before the UI

We want to land the identity model and session contract before mobile
designs and product flows depend on it. Once Wave 2 wires the client we
do not want to be reshaping refresh-token rotation, profile fields, or
deletion semantics under deadline pressure.

Wave 1 ships only what is needed to make Wave 2 a clean swap.

## Wave 1 — what shipped (2026-04-26)

### Persistence (Drizzle ORM, Postgres-compatible)

| Table | Purpose |
|---|---|
| `users` | Opaque user row (`id`, `created_at`). No email field. |
| `auth_identities` | One row per `(provider, subject)`. Future-proof: a single user can link multiple providers later. Provider values today: `apple_stub`. |
| `auth_sessions` | One row per refresh token. Refresh tokens stored as `sha256` hex hash. Tracks `expires_at`, `revoked_at`, `user_agent`, `ip_address`. |
| `user_profiles` | `display_name`, `level`. Created on first login. |
| `audit_events` | Append-only audit log. `user_id` is nullable so tombstones survive a hard-delete. |
| `integration_events` | Inbox/outbox for upstream webhooks. Wave 1 only writes `identity.linked` on user creation. |

Drivers:

- **Production** — `node-postgres` against `DATABASE_URL`.
- **Tests / dev fallback** — `@electric-sql/pglite` (in-process Postgres-compatible engine). Each test gets a fresh in-memory DB via `tests/helpers/db.ts:makeTestApp`.
- **Migrations** — single embedded init script in `src/db/migrate.ts`. Drizzle-kit takes over once we have multiple migrations.

### Auth surface

- Stateless HMAC access token (15-minute TTL, `AUTH_SECRET` env).
- Opaque random refresh token (30-day TTL, rotated on every refresh, hashed at rest).
- Middleware re-checks the session row on every request so `logout` and `logout-all` invalidate immediately.

| Method | Path | Notes |
|---|---|---|
| POST | `/auth/apple/stub/login` | Stub sign-in. **Not registered when `NODE_ENV=production`** unless `APPLE_STUB_ENABLED=1`. Real Apple verifier replaces the body parser later — response shape stays stable. First-login create path runs in a transaction so a race on `(provider, subject)` cannot leave an orphan `users` row. |
| POST | `/auth/refresh` | Rotate via conditional UPDATE inside a transaction; concurrent refreshes with the same token only mint one new pair. Replay → 401. |
| POST | `/auth/logout` | Revoke single session. Always 204 (no enumeration). |
| POST | `/auth/logout-all` | Revoke every active session for the caller. |
| GET | `/me` | User + profile. |
| PATCH | `/me/profile` | Strict body — only `displayName`, `level`. |
| DELETE | `/me` | Hard-delete + audit tombstone in one transaction. Cascades through identities / sessions / profile. |

Full request/response shapes live in `docs/backend-contract.md §Authentication & Sessions`.

### Tests

- `backend/tests/auth.tokens.test.ts` — HMAC sign/verify, expiry, tampering, plus the production-mode AUTH_SECRET guard (`assertAuthSecretConfigured`, sign/verify refusal).
- `backend/tests/auth.route.test.ts` — login (new / repeat user), refresh rotation, logout, logout-all, audit + integration trail.
- `backend/tests/me.route.test.ts` — `/me` happy path, profile update (strict body, level enum), partial update, hard-delete cascade + audit tombstone + re-login as a fresh user.
- `backend/tests/auth.security.test.ts` — Apple-stub production gating, concurrent `/auth/refresh` atomicity, concurrent first-login dedupe, IP trust boundary on `auth_sessions.ipAddress`.

### Env vars

- `DATABASE_URL` — Postgres connection. Unset → in-memory PGlite (data lost on restart). Production must set this.
- `AUTH_SECRET` — HMAC key for access tokens. **Required when `NODE_ENV=production`.** Boot fails loudly when missing; signing/verification also throws rather than fall back to the dev-only constant. Outside of production, a dev fallback key is used so unit tests work out of the box.
- `APPLE_STUB_ENABLED` — set to `1` to expose `/auth/apple/stub/login` when `NODE_ENV=production` (e.g. for staging smoke tests). Unset in real production deploys; the route is not registered and the catchall returns `404 not_found`.

### Migrations & extensions

`runMigrations` issues `CREATE EXTENSION IF NOT EXISTS pgcrypto` against
real Postgres before the init script so `gen_random_uuid()` resolves on
managed-Postgres flavours that don't pre-create the extension. PGlite
ships `gen_random_uuid` in core and rejects `CREATE EXTENSION pgcrypto`,
so the helper skips the call on the in-memory driver.

## Wave 2 — what shipped (2026-04-26)

### Persistence (migration `0002_lesson_sessions`)

| Table | Purpose |
|---|---|
| `lesson_sessions` | One row per lesson attempt arc. Tracks `status` (`in_progress` / `completed`), `lesson_version` + `content_hash` (sha256 of canonical lesson JSON), `unit_id` / `rule_tag` / `micro_rule_tag` (nullable), `started_at` / `last_activity_at` / `completed_at`, denormalized `correct_count` (set on completion), and the `debrief_snapshot` JSON column. **Partial unique index** on `(user_id, lesson_id) WHERE status = 'in_progress'` enforces the "at most one active session per user+lesson" invariant. |
| `exercise_attempts` | Append-only attempt history. One row per submission; the latest row per `(session, exercise)` wins for scoring. Carries `lesson_version` / `content_hash` / `unit_id` / rule tags so attempts survive content edits without losing their context. |
| `lesson_progress` | Per `(user_id, lesson_id)` aggregate. `attempts_count`, `completed`, `latest_correct/total`, `best_correct/total`, `last_session_id`, `first/last_completed_at`. Updated transactionally on `/complete`. |

### API surface (auth-protected)

| Method | Path | Notes |
|---|---|---|
| POST | `/lessons/:lessonId/sessions/start` | Resume-or-create. Concurrent first calls race against the partial unique index; loser re-reads the winner's row. |
| GET | `/lessons/:lessonId/sessions/current` | Return active session or `404 no_active_session`. |
| POST | `/lesson-sessions/:sessionId/answers` | Persist attempt, update `last_activity_at`. Latest attempt per exercise wins for scoring. AI rate limiter and AI cache (`(session_id, exercise_id, normalised_answer)`) reused from the legacy route. |
| POST | `/lesson-sessions/:sessionId/complete` | Idempotent. Builds debrief, persists snapshot, upserts `lesson_progress`. |
| GET | `/lesson-sessions/:sessionId/result` | Live view for `in_progress`; persisted snapshot for `completed`. |
| GET | `/dashboard` | Lesson list with statuses, recommended-next, active sessions, last lesson report. |

Full request/response shapes live in
`docs/backend-contract.md §Lesson Sessions (Wave 2)`.

### Tests

`backend/tests/lesson-sessions.test.ts` covers: start/resume, foreign-user
rejection, exercise / type validation, attempt-history immutability,
latest-attempt-wins scoring, completion + idempotent replay, progress
aggregate including best-score retention across lower scores, dashboard
empty / in-progress / done states, and recommended-next selection.

### Lesson content metadata

- `backend/src/data/lessons.ts` now also exports `LessonMeta` with
  `content_hash` (sha256 of the canonical lesson JSON, key-sorted) and
  `lesson_version` (today equal to `content_hash`; left as a separate
  field so a future authoring system can promote opaque versions).
- The persistence layer captures these on session start so attempt
  history survives content edits.

### What stayed transitional

- `POST /lessons/:id/answers` and `GET /lessons/:id/result` (legacy
  anonymous routes) still use the in-memory store at
  `backend/src/store/memory.ts`. They are kept while the Flutter client
  is unwired and will retire once the client cuts over.

### Wave 2 — review-pass hardening (2026-04-26)

Post-merge review surfaced concurrency and contract gaps in the first
Wave 2 cut. Fixed in the same wave:

1. **Route-level UUID validation.** `:sessionId` is now rejected at the
   route boundary (`404 session_not_found`) so a non-UUID path can never
   reach a `WHERE id = ?` against a `uuid` column and surface as 500.
2. **Tighter `startSession` race-loser handling.** Only PostgreSQL
   `unique_violation` (`SQLSTATE 23505`) is treated as "race lost, read
   the winner". Any other error from the insert path now propagates as
   a real failure instead of being silently absorbed.
3. **Stale lesson content detection.** `loadOwnedSession` compares the
   live `content_hash` against the session's stored hash. Write paths
   (`/answers`, `/complete`) on an `in_progress` session whose lesson
   fixture has been edited since start now return
   `409 lesson_content_changed` instead of grading against a different
   question set. Read paths on already-completed sessions still serve
   the persisted snapshot so the learner can always see their report.
4. **Real `attempt_id` idempotency.** Migration `0003_attempt_idempotency`
   adds `exercise_attempts.client_attempt_id` plus a partial unique
   index on `(session_id, client_attempt_id)`. Replays of the same
   `attempt_id` return the original verdict; concurrent retries that
   cross the wire resolve through the unique-violation handler in
   `insertAttempt`.
5. **Atomic `/complete`.** Finalisation is now a single conditional
   UPDATE (`status = 'in_progress' → 'completed'`) inside a transaction
   that also runs the `lesson_progress` upsert. Concurrent `/complete`
   calls cannot both finalise the session, both write the debrief
   snapshot, or both increment `attempts_count`.
6. **Concurrency-safe `lesson_progress`.** The aggregate upsert reads
   the existing row with `FOR UPDATE` so two completions on different
   sessions for the same `(user, lesson)` serialise on the row lock
   instead of stomping each other's `attempts_count` /
   `best_correct/total`.
7. **Honest dashboard `answered_count`.** The dashboard now derives
   `active_sessions[].answered_count` from a `count(distinct
   exercise_id)` over `exercise_attempts`, instead of reusing the
   session row's `correct_count` (which is only refreshed on
   completion).
8. **Restored debrief caching.** `/result` on an in-progress session
   now reuses the existing `(session_id, lesson_id, fingerprint)` debrief
   cache so repeated polls do not rebuild the AI debrief on every call.
9. **Consistent `total_exercises`.** Both `/result` and the dashboard's
   `last_lesson_report` now read `session.exerciseCount`, so the two
   endpoints cannot disagree about the lesson size.

## Wave 3 — remaining

> Status update (2026-05-01):
> - Item 2 (Flutter client wiring) — **shipped Wave 7.4**: login,
>   refresh, account, logout-all, delete-account all wired.
> - Item 3 (lesson UX cutover) — **partially shipped Wave 7.4 part 2B**:
>   `SessionController` runs on `/sessions/start` +
>   `/lesson-sessions/:sid/answers` + `/complete` + `/next`;
>   `LearnerSkillStore` is dual-mode. The **`/dashboard` last-lesson-
>   report rebind is still open** — `LastLessonStore` remains in-memory
>   device-local. See `app/lib/session/last_lesson_store.dart` and
>   the CLAUDE.md project-entry note.
> - Item 4 partial — Wave 8 legacy drop (2026-04-26) removed the
>   unauth `/lessons/:id/answers` + `/result` routes.

1. **Real Sign In with Apple.** Replace `/auth/apple/stub/login` with
   `/auth/apple/login`, which verifies Apple's `identityToken` JWT
   against the public JWKS and extracts `sub` for the existing identity
   model. The stub route stays on a feature flag for testing.
2. ~~Flutter client wiring.~~ Shipped Wave 7.4.
3. **Lesson UX cutover (residual).** `SessionController` cutover and
   the per-skill state migration are done; the **`/dashboard`
   last-lesson-report rebind on the home screen remains open** —
   today the Last lesson card reads from the in-memory
   `LastLessonStore`, not from `GET /dashboard`. Tracked in this
   doc until the Flutter client reads `/dashboard` for the
   persistent surface.
4. **Retire transitional anonymous routes (residual).** Wave 8
   legacy drop removed the unauth `/lessons/:id/answers` and
   `/result` paths. Any Wave 1 in-memory store callers still wired
   should be inventoried and cut.
5. **Migration tooling.** Switch the embedded migrations to
   drizzle-kit's journal/.sql layout when migration count exceeds
   the current two.
