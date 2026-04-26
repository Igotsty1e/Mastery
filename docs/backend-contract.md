# Backend Contract — Roundups AI Assistant MVP

## Endpoints

### GET /lessons/{lesson_id}

Returns full lesson definition for client to render.

**Response 200:**
```json
{
  "lesson_id": "uuid",
  "title": "string",
  "language": "en",
  "level": "A1|A2|B1|B2|C1|C2",
  "intro_rule": "string",
  "intro_examples": ["string"],
  "exercises": [
    {
      "exercise_id": "uuid",
      "type": "fill_blank|multiple_choice|sentence_correction",
      "prompt": "string",
      ...type-specific fields (see content-contract.md)
    }
  ]
}
```

Client never receives `accepted_answers`, `accepted_corrections`, or `correct_option_id`. These stay server-side.

**Wave 1 engine metadata pass-through.** When an exercise declares the
optional Wave 1 metadata fields (`skill_id`, `primary_target_error`,
`evidence_tier`, `meaning_frame` — see `docs/content-contract.md §1.2`),
the route emits them on the wire unchanged. Today's runtime does not
otherwise consume these fields; they exist so future engine waves
(Mastery Model, Decision Engine, Transparency Layer) can use them on
the client.

**Response 404:** `{ "error": "lesson_not_found" }`

---

### POST /lessons/{lesson_id}/answers

Submit one answer. Backend evaluates and returns result.

**Request body:**
```json
{
  "session_id": "uuid (client-generated, scopes results for this lesson visit)",
  "attempt_id": "uuid (client-generated, unique per submission)",
  "exercise_id": "uuid",
  "exercise_type": "fill_blank|multiple_choice|sentence_correction",
  "user_answer": "string (max 500 chars)",
  "submitted_at": "ISO 8601 UTC"
}
```

**Response 200:**
```json
{
  "attempt_id": "uuid",
  "exercise_id": "uuid",
  "correct": true|false,
  "result": "correct|partial|wrong",
  "response_units": [],
  "evaluation_version": 1,
  "evaluation_source": "deterministic|ai_fallback",
  "explanation": "string|null",
  "canonical_answer": "string"
}
```

- `correct`: legacy boolean field, preserved for backwards compat. Mirrors `result === "correct"`.
- `result` (Wave 5): forward-looking three-valued evaluation outcome per `LEARNING_ENGINE.md §8.7`. Single-decision items shipped today emit only `"correct"` or `"wrong"`; the `"partial"` value is reserved for the multi-unit families introduced in Wave 6 (`multi_blank`, `multi_error_correction`, `multi_select`).
- `response_units` (Wave 5): per-unit results for multi-unit items. Always `[]` for the single-decision families shipped today; populated for Wave 6 multi-unit families with one entry per `response_unit_id`.
- `evaluation_version` (Wave 5): integer that gets bumped when the evaluator's contract changes in a way clients should re-route on. Initial release = `1`. The Mastery Model uses this to invalidate per-skill production-gate state when the evaluator semantics move under it (`LEARNING_ENGINE.md §12.3`).
- `explanation`: curated rule-specific explanation from the exercise's `feedback.explanation`.
- `canonical_answer`: first entry from `accepted_answers` or `accepted_corrections`.
- `evaluation_source`: always `deterministic` when AI not called; `ai_fallback` when AI decided outcome.

**Response 400:** `{ "error": "invalid_payload" }` — missing fields, unknown `exercise_type`.
**Response 404:** `{ "error": "exercise_not_found" }`
**Response 429:** `{ "error": "rate_limit_exceeded" }` — AI rate limit exceeded (10 `sentence_correction` submissions per IP per 60s). Client should show a transient error and allow retry.

---

### GET /lessons/{lesson_id}/result

Returns final score after all exercises submitted.

**Query params:**
- `session_id` (required): UUID passed by client; must match the `session_id` used during answer submissions. Without it, `correct_count` is 0 and `answers` is empty.

**Response 200:**
```json
{
  "lesson_id": "uuid",
  "total_exercises": 10,
  "correct_count": 7,
  "conclusion": "string",
  "answers": [
    {
      "exercise_id": "uuid",
      "correct": true|false,
      "prompt": "string|null",
      "canonical_answer": "string|null",
      "explanation": "string|null"
    }
  ],
  "debrief": {
    "debrief_type": "strong|mixed|needs_work",
    "headline": "string (≤ 80 chars, teacher voice)",
    "body": "string (2–4 sentences, ≤ 75 words target, ≤ 600 chars hard cap)",
    "watch_out": "string|null (≤ 140 chars micro-rule)",
    "next_step": "string|null (≤ 140 chars concrete action)",
    "source": "ai|fallback|deterministic_perfect"
  }
}
```

- `debrief` is `null` when no attempts have been recorded for this `session_id`.
- `debrief.debrief_type` is deterministic from the score: `strong` only at full score (correct_count == total_exercises), `mixed` at ≥ 60%, `needs_work` below 60%.
- `debrief.source` indicates the origin of the copy: `deterministic_perfect` (zero-error short-circuit, never calls AI), `ai` (provider returned a valid debrief), or `fallback` (AI was disabled, timed out, errored, or returned malformed/empty fields — deterministic copy was used instead).
- See **Debrief Generation** below for the full contract.

---

## Evaluation Logic

### Step 1 — Input validation (all types)

- If `user_answer` is empty after trim: treat as incorrect immediately (not a 400). Skip all evaluation. Return `correct=false`, `evaluation_source=deterministic`.

### Step 2 — Normalization (all types)

Apply in order:
1. Unicode NFC
2. Trim leading/trailing whitespace
3. Collapse internal whitespace to single space
4. Lowercase
5. Strip `. , ! ? ; : ' "` at string boundaries only (not mid-word apostrophes)

Apply to `user_answer` and each entry in the comparison list.

### Step 3 — Deterministic match

**fill_blank:** normalized `user_answer` == any normalized entry in `accepted_answers[]` → correct.

**multiple_choice:** trim + lowercase `user_answer` == trim + lowercase `correct_option_id` → correct.

**sentence_correction:** normalized `user_answer` == any normalized entry in `accepted_corrections[]` → correct.

### Step 4 — Borderline check (sentence_correction only)

If deterministic fails, check all three:
1. Levenshtein distance between normalized `user_answer` and nearest normalized entry in `accepted_corrections[]` ≤ 3.
2. `len(user_answer_normalized)` between 50% and 200% of `len(shortest_accepted_correction_normalized)`.
3. (Implicit: deterministic already failed.)

If all pass → AI fallback. If any fail → incorrect, skip AI.

### Step 5 — AI fallback (sentence_correction borderline only)

**Before calling AI:** the route checks the in-memory AI result cache keyed by `(session_id, exercise_id, normalizedAnswer)`. A cache hit returns the stored result immediately — no AI call, no rate-limit consumption. TTL 4h; LRU cap 10K entries.

**Rate limit check:** if no cache hit, the route resolves the client IP and checks the sliding-window limiter (10 AI-eligible submissions per IP per 60s). If exceeded, returns `429` immediately. No AI call is made. The client may retry later.

**IP resolution:** X-Forwarded-For is trusted only when the socket connection originates from a loopback or RFC 1918 address. The rightmost XFF entry is used to prevent client bucket-spoofing.

**Request to AI:**
```json
{
  "prompt_template": "...",
  "user_answer": "normalized user answer",
  "exercise_context": {
    "prompt": "original exercise prompt",
    "accepted_corrections": ["..."]
  }
}
```

**Expected AI response:**
```json
{ "correct": bool, "feedback": "string (max 80 chars)" }
```

**Timeout:** 5 seconds. On timeout or any error: `correct=false`, `evaluation_source=deterministic`, while the response may still include the exercise's curated `explanation`.

**Validation:** backend validates response schema before using it. Invalid schema treated same as timeout.

---

## AI Prompt Template

```
You are an English language evaluator.
The user was asked to correct a grammatically incorrect sentence.

Original sentence: {exercise_prompt}
Known correct answers: {accepted_corrections}
User's answer: {user_answer}

Evaluate whether the user's answer is a valid grammatical correction that preserves the original meaning.
Respond with JSON only: { "correct": true|false, "feedback": "<one sentence, max 80 chars>" }
Be strict. Accept valid rephrasings. Reject answers that change meaning or introduce new errors.
Do not explain more than one thing. Do not encourage.
```

Token budget: max 200 output tokens.

---

## Debrief Generation

A short, teacher-voice debrief is generated on `GET /lessons/{lesson_id}/result`
when the session has at least one attempt. It synthesizes ONE diagnostic
pattern from the missed items rather than enumerating every mistake.

### Decision flow

1. **Aggregate.** The route reads all attempts for `(session_id, lesson_id)`,
   computes `correct_count / total_exercises`, derives `debrief_type` from
   the score bucket, and builds `missed_items` — a list of
   `{ canonical_answer, explanation }` for incorrect attempts whose
   exercise has a curated `feedback.explanation`.

2. **Zero-error short-circuit.** If `debrief_type == "strong"`, the route
   returns deterministic celebration copy referencing the lesson title
   (`source = "deterministic_perfect"`) and **does not call AI**.

3. **AI generation.** Otherwise, the route calls
   `AiProvider.generateDebrief({ lessonTitle, level, targetRule,
   correctCount, totalExercises, debriefType, missedItems })` with a
   6-second timeout (configurable). The provider is required to return
   structured JSON matching the `lesson_debrief` schema (strict mode).

4. **Fallback.** If the AI call times out, throws, the response is empty
   (refusal), the JSON is malformed, or the headline/body fields are
   blank after sanitisation, the route returns a deterministic fallback
   debrief (`source = "fallback"`) bucketed to the same `debrief_type`.

5. **Cache.** Successful debriefs (any source) are cached per
   `(session_id, lesson_id, fingerprint)` with a 4h TTL. The fingerprint
   is the sorted list of `(exercise_id:correct)` pairs, so subsequent
   GETs of the same session+lesson return instantly without an AI call.
   New attempts invalidate the cache automatically.

### Groundedness

The AI sees only:
- `lessonTitle`, `level`, `targetRule` (first sentence of `intro_rule`)
- score ratio + bucket label
- `missedItems[]` — canonical answer + curated rule explanation only

The student's free-text answers are **never** sent. Authoring-supplied
strings are JSON-quoted in the user message and the system prompt
explicitly labels them as untrusted, so any instruction-like phrases
inside lesson content are treated as literal text, not directives.

### Constraints in the prompt

- 5–9 word headline; 2–4 sentence body, ≤ 75 word target.
- One diagnostic pattern, not item-by-item enumeration.
- No emojis, no exclamation marks, no generic praise, no hedging.
- `watch_out` and `next_step` are optional (≤ 14 words each, or null).
- The model is instructed not to invent grammar facts beyond what is
  implied by `targetRule` or `missedItems[]`.

### AI provider responsibilities

`OpenAiProvider.generateDebrief` posts to `/v1/responses` with
`text.format = json_schema` (strict mode) and the `lesson_debrief`
schema. Refusal, non-OK status, empty body, JSON parse error, or schema
mismatch all surface as thrown errors so the route can apply the
fallback path.

The stub provider returns empty fields on purpose; the route's
sanitiser detects this and falls back. Production debrief copy ships
only when `AI_PROVIDER=openai` is configured.

---

## CORS Policy

The backend enforces a strict origin allowlist for cross-origin requests. Wildcard `*` is not used.

### Default Allowed Origins

- `https://mastery-web-igotsty1e.onrender.com` (production frontend)
- `http://localhost:3000` (local dev - typical Flutter web)
- `http://localhost:8080` (alternate local dev port)
- `http://localhost:57450` (Flutter web dev server)

### Configuration

Override the default allowlist by setting the `ALLOWED_ORIGINS` environment variable:
```
ALLOWED_ORIGINS=https://custom-domain.com,http://localhost:5000
```

Separate multiple origins with commas. Each will be trimmed of whitespace.

### Behavior

- **Request with allowed origin:** Response includes `Access-Control-Allow-Origin: <origin>` and `Vary: Origin` headers.
- **Request with unknown origin:** No `Access-Control-Allow-Origin` header is set. The request proceeds but the browser will block any response per CORS policy.
- **Request with no `Origin` header:** No CORS headers are set. The request proceeds normally (used by Flutter PWA, health checks, direct API calls).
- **OPTIONS preflight:** Always returns 204. If the origin is allowed, `Access-Control-Allow-Origin` is set; otherwise, it is omitted.

---

## Error Response Shape

All errors return HTTP 4xx/5xx with body: `{ "error": "snake_case_error_code" }`.

| Code | HTTP | Meaning |
|---|---|---|
| `lesson_not_found` | 404 | Unknown lesson_id |
| `exercise_not_found` | 404 | Unknown exercise_id |
| `invalid_payload` | 400 | Malformed request |
| `rate_limit_exceeded` | 429 | Too many AI-eligible submissions from this IP (10/60s) |
| `unauthorized` | 401 | Missing, malformed, or revoked access token |
| `invalid_refresh_token` | 401 | Refresh token unknown, expired, or already revoked |
| `user_not_found` | 404 | Authenticated session points at a deleted user row |
| `internal_error` | 500 | Unexpected server failure |

---

## Authentication & Sessions (Wave 1)

Wave 1 ships the backend identity foundation. The Flutter client is not
wired yet; these endpoints exist so Wave 2 can ship login UX without
re-shaping the contract.

### Identity model

- `users(id, created_at)` — opaque user row. No email field.
- `auth_identities(id, user_id, provider, subject, created_at)` — one
  row per upstream identity. Unique on `(provider, subject)`. Multiple
  rows per user are supported so the same person can link additional
  providers later. Provider values today: `apple_stub`. Production will
  add `apple` once the real Sign In with Apple verifier ships.
- `user_profiles(user_id PK, display_name, level, created_at, updated_at)`
  — single profile row per user. Created on first login.
- `auth_sessions(id, user_id, refresh_token_hash, created_at,
  last_used_at, expires_at, revoked_at, user_agent, ip_address)` — one
  row per refresh token. Refresh tokens are stored as their `sha256`
  hex hash; the raw token only exists in transit and on the client.
- `audit_events(id, user_id NULLABLE, event_type, payload, created_at)`
  — append-only log. `user_id` is nullable so tombstone rows survive a
  user hard-delete.
- `integration_events(id, source, event_type, external_id, payload,
  processed_at, created_at)` — placeholder inbox/outbox for upstream
  webhooks (Apple notifications, future payment events). Wave 1 only
  writes a single `identity.linked` row on user creation.

### Token model

- **Access token** — stateless HMAC-SHA256, payload `{ userId,
  sessionId, exp }`, base64url-encoded. TTL 15 minutes. Verified on
  every request via `requireAuth`, which also looks up the session row
  to enforce immediate revocation on logout.
- **Refresh token** — opaque random 32-byte url-safe string. TTL 30
  days. Stored hashed; rotated on every `/auth/refresh`. Rotation runs
  inside a transaction with a conditional UPDATE on
  `(refresh_token_hash, revoked_at IS NULL, expires_at > now())`, so two
  concurrent refreshes with the same token can never both mint a live
  session — exactly one wins, the other gets `401 invalid_refresh_token`.
- **HMAC secret** — `AUTH_SECRET` env var. **Required in production.**
  Boot fails with a clear error if `NODE_ENV=production` and the var is
  unset. Token signing/verification will also throw rather than fall
  back to the dev-only constant.

### Trust boundary for caller IP

Both the lessons routes (rate limiting) and the auth routes (session
metadata) resolve the caller IP through the same helper
(`src/middleware/clientIp.ts:resolveClientIp`). `X-Forwarded-For` is
honoured only when the socket itself sits on a loopback or RFC 1918
address, and the rightmost XFF entry is used. A public client cannot
spoof its session IP or rate-limit bucket via XFF.

Authenticated requests must send `Authorization: Bearer <accessToken>`.

### POST /auth/apple/stub/login

Stub Apple sign-in for Wave 1. The real Apple verifier replaces the
body parser in a later wave; the **response shape stays stable** so
mobile can code against it now.

**Production gating.** This route is **not registered** when
`NODE_ENV=production` unless an operator explicitly opts in by setting
`APPLE_STUB_ENABLED=1` (e.g. for staging smoke checks). When unregistered
the catchall returns `404 not_found`, so the stub cannot be used to mint
sessions on the production backend.

**First-login concurrency.** The create path (insert `users`, identity,
profile, audit, integration event) runs inside a single transaction. If
two concurrent first-logins for the same `(provider, subject)` race, the
unique index on `(provider, subject)` rejects the loser; the
transaction rolls back so no orphan `users` row is left behind, and the
loser re-reads and lands on the winner's user.

**Request body:**
```json
{ "subject": "string", "displayName": "string|optional" }
```

**Response 200:**
```json
{
  "user": { "id": "uuid" },
  "accessToken": "base64url.body.base64url.sig",
  "accessTokenExpiresAt": "ISO 8601 UTC",
  "refreshToken": "base64url-32-bytes",
  "refreshTokenExpiresAt": "ISO 8601 UTC"
}
```

Repeat logins with the same `subject` resolve to the existing user and
issue a fresh session pair. First-time logins also create the matching
`user_profiles` row and emit `user.created` + `auth.session.created`
audit entries plus an `identity.linked` integration event.

### POST /auth/refresh

**Request body:** `{ "refreshToken": "string" }`

**Response 200:** same shape as login (minus `user`). The presented
refresh token is revoked via a conditional UPDATE inside a single
transaction, so concurrent refreshes with the same token are
serialised — exactly one wins and gets the new pair, the other gets
`401 invalid_refresh_token`. Replay also returns 401.

### POST /auth/logout

**Request body:** `{ "refreshToken": "string" }` → `204 No Content`.

Always returns 204 — even for unknown tokens — to avoid token
enumeration.

### POST /auth/logout-all

Auth required. Revokes every non-revoked session for the caller. The
caller's own access token is invalidated on next request because the
middleware re-checks the session row.

**Response:** `204 No Content`.

### GET /me

Auth required.

**Response 200:**
```json
{
  "user": { "id": "uuid", "createdAt": "ISO 8601 UTC" },
  "profile": {
    "displayName": "string|null",
    "level": "A1|A2|B1|B2|C1|C2|null",
    "updatedAt": "ISO 8601 UTC"
  }
}
```

### PATCH /me/profile

Auth required. Strict body: only `displayName` and `level` are
accepted. Unknown fields → 400.

```json
{ "displayName": "string|null|optional",
  "level": "A1|A2|B1|B2|C1|C2|null|optional" }
```

**Response 200:** `{ "profile": { ... } }`.

### DELETE /me

Auth required. Hard-deletes the user row. The schema's
`ON DELETE CASCADE` clears `auth_identities`, `auth_sessions`, and
`user_profiles`. `audit_events.user_id` is `ON DELETE SET NULL`, so the
audit trail (including the `user.deleted` tombstone) survives. The
delete and the tombstone insert run in the same transaction so the
audit trail and the deletion can never disagree.

**Response:** `204 No Content`.

### Wave 2 transition notes

- `lesson_sessions` and `exercise_attempt` persistence remain
  in-memory in Wave 1. Wave 2 introduces those tables and migrates the
  `/lessons/:id/answers` + `/result` paths to read/write the database
  with the authenticated `userId` as the scope key.
- `apple_stub` is replaced by a verified `apple` provider; the route
  will validate the `identityToken` JWT against Apple's JWKS before
  inserting `auth_identities`.
