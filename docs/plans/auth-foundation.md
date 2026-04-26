# Auth & Identity Foundation

**Status — Wave 1 shipped 2026-04-26.** Backend persistence + auth
endpoints only. Flutter client is **not** wired in this wave.

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

## Wave 2 — explicit transition notes

These are intentionally **not** in Wave 1:

1. **Lesson session persistence.** `lesson_sessions` and `exercise_attempts` tables. The current `src/store/memory.ts` LRU cache moves to Postgres, scoped by the authenticated `userId` (or by `session_id` for unauthenticated callers if we choose to keep an anonymous mode).
2. **Real Sign In with Apple.** Replace `/auth/apple/stub/login` with `/auth/apple/login`, which verifies Apple's `identityToken` JWT against the public JWKS and extracts `sub` for the existing identity model. The stub route will likely be kept on a feature flag for testing.
3. **Flutter client wiring.** Login screen, secure refresh-token storage (Keychain / Keystore), 401-driven refresh interceptor, account screen with logout / logout-all / delete-account.
4. **Lesson endpoints upgrade.** `/lessons/:id/answers` and `/result` start carrying the auth context and writing to the new persistence tables. The current `session_id` query param can stay during the migration as a fallback.
5. **Migration tooling.** Once we add a second migration, switch from the embedded `src/db/migrate.ts` script to drizzle-kit's journal/.sql layout.
