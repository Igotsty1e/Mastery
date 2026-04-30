# Wave 7 — Auth + Server-Side Engine State

> Status (2026-04-26): **Wave 7 fully shipped on `main`.** 7.1 + 7.2 +
> 7.3 + 7.4 (parts 1, 2A, 2B) all live. The `codex/auth-backend-foundation`
> branch was rebased + merged via PR #13; the source branch was deleted
> afterwards. Wave 7.1.1 (PR #14) closed four Codex deferred bugs in the
> lesson-sessions endpoints. Wave 7.3 (PR #15) shipped the engine state
> migration. Wave 7.4 part 1 shipped the AuthClient infra (no UI gate).
> Wave 7.4 part 2A (PR #17) shipped the sign-in surface (`SignInScreen`,
> auth gate routing in `HomeScreen`) + `POST /me/state/bulk-import`.
> Wave 7.4 part 2B shipped the dual-mode `LearnerSkillStore` +
> `ReviewScheduler` facades, the bulk-migration trigger on signed-in
> transition, and `MASTERY_AUTH_ENABLED=true` in
> `scripts/render-build-web.sh` so production sees the sign-in gate.

## Why this is the next wave

Engine waves 1–5 shipped a working `LearnerSkillStore` + `ReviewScheduler`
+ `DecisionEngine` chain. Every piece is **device-scoped** —
SharedPreferences only. Concretely:

- Reinstall the app or open it on a second device → mastery state, review
  cadence, production-gate flags all reset to zero.
- Decision Engine reorders only fire when the learner is mid-session
  with their current device context.
- The `LEARNING_ENGINE.md §6.4` production gate is sticky per-device, not
  per-learner.

The runtime contracts already say "server-side learner storage is a
follow-up wave once accounts exist" three times. Each subsequent engine
wave hardens that assumption further. The longer this is deferred the
harder the migration.

This wave closes that gap by introducing identities + server-owned state
+ migrating `LearnerSkillStore` and `ReviewScheduler` from device-scoped
SharedPreferences to authenticated server endpoints.

## Existing work on `codex/auth-backend-foundation`

The branch already contains a substantial amount of well-scoped backend
work, written before the engine waves shipped. Snapshot:

### Persistence (Drizzle ORM, Postgres + PGlite for tests)

| Table | Purpose |
|---|---|
| `users` | Opaque user row (`id`, `created_at`). No email field. |
| `auth_identities` | `(provider, subject)` rows. Future-proof for multi-provider linking. Today: `apple_stub`. |
| `auth_sessions` | One row per refresh token (sha256 hashed at rest). `expires_at`, `revoked_at`, `user_agent`, `ip_address`. |
| `user_profiles` | `display_name`, `level`. Created on first login. |
| `audit_events` | Append-only log. Nullable `user_id` so tombstones survive hard-delete. |
| `integration_events` | Inbox/outbox for upstream webhooks. Wave 1 only writes `identity.linked` on user creation. |
| `lesson_sessions` | Server-owned lesson attempt arc. `status`, `lesson_version`, `content_hash`, rule tags, `debrief_snapshot`. Partial unique index on `(user_id, lesson_id) WHERE status = 'in_progress'`. |
| `exercise_attempts` | Append-only attempt history. `client_attempt_id` partial unique index for replay idempotency. Latest row wins for scoring. |
| `lesson_progress` | Per `(user_id, lesson_id)` aggregate. `attempts_count`, `best_correct/total`, etc. Concurrency-safe upsert with `FOR UPDATE`. |

### Auth surface

- Stateless HMAC access token (15-minute TTL, `AUTH_SECRET` env).
- Opaque random refresh token (30-day TTL, rotated on every refresh, sha256 at rest).
- Middleware re-checks the session row on every request — `logout` and `logout-all` invalidate immediately.

| Method | Path | Notes |
|---|---|---|
| POST | `/auth/apple/stub/login` | Stub sign-in. Not registered when `NODE_ENV=production` unless `APPLE_STUB_ENABLED=1`. Real Apple verifier swaps in later; response shape stays stable. |
| POST | `/auth/refresh` | Conditional UPDATE inside a transaction; replay → 401. |
| POST | `/auth/logout` | Revoke single session. Always 204 (no enumeration). |
| POST | `/auth/logout-all` | Revoke every active session for the caller. |
| GET | `/me` | User + profile. |
| PATCH | `/me/profile` | Strict body — only `displayName`, `level`. |
| DELETE | `/me` | Hard-delete + audit tombstone in one transaction. |

### Lesson session surface (auth-protected)

| Method | Path | Notes |
|---|---|---|
| POST | `/lessons/:lessonId/sessions/start` | Resume-or-create. Concurrent first calls race against the partial unique index. |
| GET | `/lessons/:lessonId/sessions/current` | `404 no_active_session` when none. |
| POST | `/lesson-sessions/:sessionId/answers` | Persist attempt, latest-wins scoring. Reuses AI rate limiter + cache from legacy route. |
| POST | `/lesson-sessions/:sessionId/complete` | Idempotent. Builds debrief, persists snapshot, upserts `lesson_progress`. Atomic conditional UPDATE. |
| GET | `/lesson-sessions/:sessionId/result` | Live view for `in_progress`, persisted snapshot for `completed`. Reuses debrief cache. |
| GET | `/dashboard` | Lesson list + statuses + recommended-next + active sessions + last lesson report. `answered_count` derived from `count(distinct exercise_id)`. |

### Tests

- `backend/tests/auth.tokens.test.ts` — HMAC sign/verify, expiry, tampering, production-mode `AUTH_SECRET` guard.
- `backend/tests/auth.route.test.ts` — login (new / repeat user), refresh rotation, logout, logout-all, audit + integration trail.
- `backend/tests/me.route.test.ts` — happy path, profile update strict body, level enum, hard-delete cascade + tombstone.
- `backend/tests/auth.security.test.ts` — Apple-stub production gating, concurrent `/auth/refresh` atomicity, concurrent first-login dedupe, IP trust boundary.
- `backend/tests/lesson-sessions.test.ts` — start/resume, foreign-user rejection, exercise/type validation, attempt-history immutability, latest-attempt-wins scoring, completion idempotency, progress aggregate including best-score retention, dashboard states, recommended-next.

### Hardening already addressed on the branch

Wave 2 review-pass surfaced and fixed: route-level UUID validation,
tighter race-loser detection (only `unique_violation` SQLSTATE 23505),
stale-content detection (`409 lesson_content_changed`), real
`client_attempt_id` idempotency via partial unique index, atomic
`/complete` with `FOR UPDATE` upsert, honest `answered_count`, restored
debrief cache, consistent `total_exercises`.

Read `docs/plans/auth-foundation.md` on the
`codex/auth-backend-foundation` branch for the full audit trail.

## What this wave adds on top

Beyond what the foundation branch already covers:

### Engine state migration (the new contract this wave introduces)

The current device-scoped stores need server endpoints. Outline:

| Today (device) | After Wave 7 (server-backed) |
|---|---|
| `LearnerSkillStore.recordAttempt(...)` writes to SharedPreferences key `learner_skill_v1_<skill_id>` | `POST /me/skills/:skill_id/attempts` body = `{evidenceTier, correct, primaryTargetError?, meaningFrame?, evaluationVersion}` |
| `LearnerSkillStore.getRecord(skillId)` reads SharedPreferences | `GET /me/skills/:skill_id` |
| `LearnerSkillStore.allRecords()` enumerates the index list | `GET /me/skills` |
| `ReviewScheduler.recordSessionEnd({skillId, mistakesInSession})` writes SharedPreferences key `review_schedule_v1_<skill_id>` | `POST /me/skills/:skill_id/review-cadence` body = `{mistakesInSession, occurredAt}` |
| `ReviewScheduler.dueAt(now)` reads index + filters | `GET /me/reviews/due?at={iso}` (server filters by `dueAt <= at` and excludes graduated) |

Schema additions (proposed):

```sql
-- Per-learner per-skill mastery state per LEARNING_ENGINE.md §7.1.
CREATE TABLE learner_skills (
  user_id           uuid REFERENCES users(id) ON DELETE CASCADE,
  skill_id          text NOT NULL,
  mastery_score     int NOT NULL DEFAULT 0,
  last_attempt_at   timestamptz,
  evidence_summary  jsonb NOT NULL DEFAULT '{}',
  recent_errors     text[] NOT NULL DEFAULT '{}',
  production_gate_cleared bool NOT NULL DEFAULT false,
  gate_cleared_at_version int,
  PRIMARY KEY (user_id, skill_id)
);

-- Per-learner per-skill review cadence per LEARNING_ENGINE.md §9.3.
CREATE TABLE learner_review_schedule (
  user_id            uuid REFERENCES users(id) ON DELETE CASCADE,
  skill_id           text NOT NULL,
  step               int NOT NULL DEFAULT 1,
  due_at             timestamptz NOT NULL,
  last_outcome_at    timestamptz NOT NULL,
  last_outcome_mistakes int NOT NULL DEFAULT 0,
  graduated          bool NOT NULL DEFAULT false,
  PRIMARY KEY (user_id, skill_id)
);
```

### Flutter client wire-up

The `codex/auth-backend-foundation` branch ships only backend. Wave 7 on
top of it must:

1. Add an `AuthClient` to Flutter that handles the access/refresh token
   pair, persists the refresh token in `flutter_secure_storage` (NOT
   SharedPreferences — refresh tokens are bearer secrets), and refreshes
   transparently on 401.
2. Replace `LearnerSkillStore` calls with API calls. Keep the same
   public Dart API (`recordAttempt`, `getRecord`, `allRecords`) so the
   `SessionController` and Wave 4 widgets do not need to change.
3. Replace `ReviewScheduler` calls with API calls. Same public API.
4. Add a sign-in flow gate: first launch → Apple Sign In → land on
   onboarding ritual → dashboard. (Apple Sign In is required by
   App Store policy when ANY social login exists; we only have stub
   today, but the contract is the right one to lock in early.)

### Render infrastructure

- Add a Render Postgres instance (Free tier covers MVP).
- `DATABASE_URL` env var on the backend service.
- Bump Render Blueprint to provision the DB alongside the web service.

### Migration of existing learners

The shipped device-scoped state needs to either be:

- **(A) Discarded.** Today's userbase is dev/internal; no real learners
  to migrate. Cleanest. Recommended.
- **(B) Migrated.** First-launch with auth detects existing
  SharedPreferences keys, calls a one-shot bulk-upload endpoint,
  clears local store. More code; only worth it if there is a real
  learner cohort to preserve.

## Sequence proposal

1. **Branch hygiene (this wave's prep):** rebase `codex/auth-backend-foundation` onto current `main`. Resolve conflicts (the foundation branch was written before Waves 1–5; the conflicts will mostly be in `docs/`, `lessons.ts`, route file). Land it as a single PR or a sequence of PRs that lines up with Wave 7.1 / 7.2 below.
2. **Wave 7.1 — auth surface only.** Apple stub + refresh + `/me` + `/me/profile` + hard-delete. No engine state yet. Flutter not wired (just like the foundation branch's Wave 1).
3. **Wave 7.2 — lesson sessions.** Server-owned `lesson_sessions` + `exercise_attempts` + `lesson_progress`. Migrate the legacy `/lessons/:id/answers` and `/lessons/:id/result` routes to the new auth-protected paths. Flutter still not wired here either; legacy routes stay alongside until 7.3.
4. **Wave 7.3 — engine state migration.** New tables `learner_skills` and `learner_review_schedule` + `/me/skills/...` + `/me/reviews/due` endpoints. Flutter `LearnerSkillStore` and `ReviewScheduler` rewritten as thin API clients. Discard the SharedPreferences keys (option A above).
5. **Wave 7.4 part 1 — AuthClient infra.** `AuthTokens` + `AuthStorage` (flutter_secure_storage 9.2.2) + `AuthClient` with refresh-on-401 retry-once. No UI gate yet. Build flag `MASTERY_AUTH_ENABLED` defaults to false.
6. **Wave 7.4 part 2A — Sign-in surface + bulk-import endpoint.** `SignInScreen` (Apple stub + Skip), `HomeScreen` routes through it when `authEnabled && no token`, server `POST /me/state/bulk-import` with idempotent skip-if-server-row-exists semantics. `APPLE_STUB_ENABLED=1` set on Render. All dormant in default builds.
7. **Wave 7.4 part 2B — Dual-mode storage + migration trigger (shipped 2026-04-26).** `LearnerSkillStore` + `ReviewScheduler` are now static facades over `LocalLearnerSkillBackend` / `RemoteLearnerSkillBackend` and `LocalReviewSchedulerBackend` / `RemoteReviewSchedulerBackend` respectively. On the `signedIn` outcome of `SignInScreen`, `LearnerStateMigrator` collects the local snapshot via the local backend, POSTs it through `/me/state/bulk-import`, then flips both facades to remote (idempotent — second device's import is reported in the `skipped_*` arrays). On the `skipped` outcome the facades stay local so guest mode keeps working. `scripts/render-build-web.sh` now bakes `MASTERY_AUTH_ENABLED=true` into the prod build. Legacy unauthenticated routes still live alongside as the engine waves 1–5 evaluator + dashboard wire-up; dropping them is tracked as a follow-up cleanup once production telemetry confirms zero unauthenticated traffic.

## Out of scope (explicit)

- Real Apple Sign In verifier (replaces the `apple_stub` provider when we ship to App Store; orthogonal scope).
- Email-based auth, password recovery, social providers other than Apple.
- Cross-device sync conflict resolution beyond "last write wins" (rare given engine state is largely additive).
- Server-side enforcement of the §6.4 production gate (still client-derived in Wave 7; server stores it but the source of truth is the evaluator that wrote the strongest+correct attempt).

## Linked artifacts

- `LEARNING_ENGINE.md §§7.1, 9.3, 12.3` — engine spec for the state we are migrating.
- `docs/plans/learning-engine-mvp-2.md` Waves 2 + 3 — the device-scoped contract Wave 7 supersedes.
- `docs/mobile-architecture.md` — three places say "server-side learner storage is a follow-up wave once accounts exist". This is that wave.
- Branch `codex/auth-backend-foundation` — existing implementation; rebase target.
- Within that branch: `docs/plans/auth-foundation.md`, `docs/backend-contract.md` (Auth + Lesson Sessions sections), `backend/src/auth/`, `backend/src/db/`, `backend/src/lessonSessions/`, `backend/src/dashboard/`, `backend/src/users/`.
