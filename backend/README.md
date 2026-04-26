# mastery-backend

REST API for Mastery English practice. Node.js + TypeScript + Express.

The backend is the pedagogical authority for:
- lesson rule/explanation content
- canonical answers
- correctness decisions
- rule-specific explanations returned after each attempt

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Liveness check |
| GET | `/lessons` | Lightweight lesson summary list (`id`, `title`, `slug`, `order`) |
| GET | `/lessons/:lessonId` | Lesson definition (secrets stripped) |
| POST | `/lessons/:lessonId/answers` | Submit answer, get evaluation result |
| GET | `/lessons/:lessonId/result` | Lesson score summary |
| POST | `/auth/apple/stub/login` | Stub Apple sign-in — issues an access + refresh token pair |
| POST | `/auth/refresh` | Rotate a refresh token, returning a new pair |
| POST | `/auth/logout` | Revoke a single session by refresh token |
| POST | `/auth/logout-all` | Revoke every active session for the caller |
| GET | `/me` | Current user + profile (auth required) |
| PATCH | `/me/profile` | Update `displayName` / `level` (auth required) |
| DELETE | `/me` | Hard-delete the user and cascade-delete identities, sessions, profile |

See `../docs/backend-contract.md §Authentication & Sessions` for full
request/response shapes, error codes, and threat-model notes. Wave 1
ships only the backend foundation — the Flutter client is wired in a
later wave.

## Evaluation rules

- `fill_blank`: deterministic exact match after normalization. AI never called.
- `multiple_choice`: deterministic option ID match. AI never called.
- `sentence_correction`: deterministic first; AI fallback only when Levenshtein ≤ 3 and length within 50–200% of shortest accepted answer.

AI fallback on timeout (5s) or error defaults to `correct=false, evaluation_source=deterministic`.

### Answer response fields

`POST /lessons/:lessonId/answers` returns:

```json
{
  "attempt_id": "...",
  "exercise_id": "...",
  "correct": true,
  "result": "correct",            // Wave 5: "correct" | "partial" | "wrong"
  "response_units": [],            // Wave 5: per-unit results, [] for single-decision items
  "evaluation_version": 1,         // Wave 5: bumps when evaluator semantics change
  "evaluation_source": "deterministic | ai_fallback",
  "canonical_answer": "...",
  "explanation": "..."             // optional — always from exercise feedback.explanation
}
```

`correct: bool` is preserved on the wire for backwards compat. Mirror of `result === "correct"`. See `docs/backend-contract.md` and `LEARNING_ENGINE.md §8.7` for the full Wave 5 contract.

`GET /lessons/:lessonId/result` returns:

```json
{
  "lesson_id": "...",
  "total_exercises": 10,
  "correct_count": 7,
  "conclusion": "Strong performance. Review the mistakes below to close the gaps.",
  "answers": [
    {
      "exercise_id": "...",
      "correct": false,
      "prompt": "...",
      "canonical_answer": "...",
      "explanation": "..."
    }
  ]
}
```

## Runtime constraints

- **AI result cache:** in-memory, keyed by `(session_id, exercise_id, normalizedAnswer)`. TTL 4h, LRU cap 10K entries. Repeat submissions with the same answer return cached result — no AI call, no rate-limit consumption.
- **AI rate limit:** 10 AI-eligible submissions per IP per 60s sliding window. Checked only after deterministic gate and cache miss. Returns `429 rate_limit_exceeded`.
- **XFF trust boundary:** X-Forwarded-For accepted only when socket originates from loopback or RFC 1918 address. Rightmost entry used to prevent client spoofing.
- **Lesson session store:** attempts keyed by `session_id:lesson_id`. TTL 4h, LRU cap 10K. Resets on server restart — no persistence across deploys. Wave 2 will move this to Postgres alongside `lesson_sessions` / `exercise_attempts`.

## Persistence

Wave 1 introduces the auth/identity persistence layer (Drizzle ORM over
Postgres-compatible storage):

- `users`, `auth_identities (provider, subject)`, `auth_sessions`,
  `user_profiles`, `audit_events`, `integration_events`.
- Production uses `node-postgres` against `DATABASE_URL`. Local dev /
  tests use [`@electric-sql/pglite`](https://pglite.dev) — an in-process
  Postgres-compatible engine — so tests remain hermetic.
- Migrations live in `src/db/migrate.ts` (single embedded init script
  for now; drizzle-kit will take over once we have multiple).
- Run `npm start` to bootstrap the DB and apply migrations on boot.

### Auth env vars

- `DATABASE_URL` — postgres connection string. If unset, the server
  falls back to an in-memory PGlite instance (data lost on restart). Set
  this in production.
- `AUTH_SECRET` — HMAC key for signing access tokens. **Required when
  `NODE_ENV=production`.** Boot fails loudly when missing, and
  `signAccessToken` / `verifyAccessToken` also refuse to fall back to
  the dev-only constant in production. Outside of production a dev
  fallback key is used so unit tests work out-of-the-box.
- `APPLE_STUB_ENABLED` — set to `1` to keep `/auth/apple/stub/login`
  exposed when `NODE_ENV=production` (only useful for staging smoke
  tests). Unset in real production deploys; the route is not registered
  and the catchall returns `404 not_found`.

### Postgres extension

Migrations run `CREATE EXTENSION IF NOT EXISTS pgcrypto` against real
Postgres so `gen_random_uuid()` resolves on managed-Postgres flavours
that don't pre-create the extension. PGlite ships `gen_random_uuid` in
core and rejects `CREATE EXTENSION pgcrypto`, so the helper skips the
call on the in-memory driver.

## Setup

```sh
npm install
npm run dev       # tsx watch
npm test          # vitest
npm run build     # tsc → dist/
npm start         # node dist/server.js
```

## AI provider

Default is `StubAiProvider` (always returns incorrect). Production uses
`OpenAiProvider` (Responses API, structured outputs) for both
`sentence_correction` borderline evaluation and the post-lesson debrief.

Active references:
- `src/ai/openai.ts` — provider implementation (prompts, schemas)
- `../docs/backend-contract.md` — request/response contract + debrief generation flow
- `.env.example`, `.env`, `scripts/dev-local-openai.sh` — local-dev env

Historical AI-prep notes (rubric, dataset, smoke pack) live in
`../docs/archive/`.

To enable the built-in OpenAI provider (Responses API structured outputs):

```sh
AI_PROVIDER=openai \
OPENAI_API_KEY=... \
OPENAI_MODEL=gpt-4o-mini \
npm run dev
```

Optional:
- `OPENAI_BASE_URL` (defaults to `https://api.openai.com/v1`)

For local-only setup without exporting shell variables manually:

1. put the real key into `backend/.env`
2. run `./scripts/dev-local-openai.sh`

## Lesson data

Lesson fixtures live in `data/` and are loaded via `src/data/lessons.ts`. Server owns all exercise definitions including accepted answers — these are never sent to clients.
