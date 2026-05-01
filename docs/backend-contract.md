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
  "rule_card": { /* see content-contract.md §1.2 */ } | null,
  "target_form": "string" | null,
  "exercises": [
    {
      "exercise_id": "uuid",
      "type": "fill_blank|multiple_choice|sentence_correction|sentence_rewrite|short_free_sentence|listening_discrimination",
      "prompt": "string",
      ...type-specific fields (see content-contract.md)
    }
  ]
}
```

Client never receives `accepted_answers`, `accepted_corrections`, or `correct_option_id`. These stay server-side.

**Wave H1 — `rule_card` pass-through.** When the lesson declares
`rule_card` (`content-contract.md §1.2`), the route emits the
structured object unchanged so the client renders the textbook-style
`RuleCardView`. `null` when the lesson has no card; the client falls
back to parsing the legacy flat `intro_rule` string.

**Wave H2 — `target_form` pass-through.** Plain English statement of
what the lesson teaches (e.g. `"verb-ing form after gerund-only verbs
(enjoy, avoid, suggest, mind, finish, keep, postpone)."`). Optional
on the lesson; `null` on the wire when absent. Consumed by the
backend dual-verdict judge (see `POST /lesson-sessions/:sid/answers`
below); no client code reads it directly today.

**Wave 1 engine metadata pass-through.** When an exercise declares the
optional Wave 1 metadata fields (`skill_id`, `primary_target_error`,
`evidence_tier`, `meaning_frame` — see `docs/content-contract.md §1.4`),
the route emits them on the wire unchanged. Today's runtime does not
otherwise consume these fields; they exist so future engine waves
(Mastery Model, Decision Engine, Transparency Layer) can use them on
the client.

**Response 404:** `{ "error": "lesson_not_found" }`

---

### GET /skills

Wave 12.7 — public read-only route returning the skill registry joined with each skill's source-lesson rule snapshot. The Flutter `SkillCatalog` (`app/lib/learner/skill_catalog.dart`) fetches this on dashboard mount; surfaces consume it for human-readable titles and the V1.6 Rules card.

**Response 200:**
```json
[
  {
    "skill_id": "verb-ing-after-gerund-verbs",
    "title": "Verb + -ing after gerund-taking verbs",
    "description": "After enjoy, avoid, suggest, mind, keep, finish (and consider in this cluster)…",
    "cefr_level": "B2",
    "intro_rule": "Use\n\nSome verbs are followed directly by the -ing form…",
    "intro_examples": ["I enjoy reading novels…", "She suggested taking a taxi…"],
    "rule_card": { /* see content-contract.md §1.2 */ } | null
  }
]
```

`title`, `description`, `cefr_level` come from `backend/data/skills.json`. `intro_rule`, `intro_examples`, and (Wave H1) `rule_card` are joined from the source lesson — the skill's first `lesson_refs` entry (with the bank-index fallback if `lesson_refs` is missing). The Flutter dashboard `_RuleSheetBody` prefers `rule_card` when present and falls back to the flat strings otherwise.

Public, no auth — same posture as `GET /lessons` and `GET /lessons/:id`. The dashboard reads it on first paint before the AuthClient is attached.

### GET /skills/:skill_id

Same shape as a single element of `GET /skills`. Returns `404 skill_not_found` for an unknown id.

---

### Wave 8 (legacy drop, 2026-04-26)

The unauthenticated `POST /lessons/{lesson_id}/answers` and
`GET /lessons/{lesson_id}/result` routes that used to serve Wave 1 /
pre-auth clients have been **removed**. Every answer + result fetch now
flows through the auth-protected server-owned session endpoints below
(`POST /lessons/:id/sessions/start`, `POST /lesson-sessions/:sid/answers`,
`POST /lesson-sessions/:sid/complete`, `GET /lesson-sessions/:sid/result`).
The Flutter `ApiClient` was rewired in lockstep; `Skip-for-now` on
`SignInScreen` performs a silent stub-login under a stable per-install
subject so guest mode still has a session.

The two read-only public routes — `GET /lessons` (curriculum manifest)
and `GET /lessons/:id` (lesson content) — remain unauthenticated so the
dashboard's first paint and the lesson loader work before the AuthClient
is attached.

---

## Lesson Sessions (Wave 2)

The Wave 2 surface moves session ownership server-side. Every
authenticated request operates against a `lesson_session` row, attempts are
written to the immutable `exercise_attempts` history, and per-lesson
outcomes roll up into `lesson_progress`. Lesson **content** still lives in
repo fixtures (`backend/data/lessons/`); the database stores only the
user's interaction with that content.

All routes below require `Authorization: Bearer <accessToken>`.

### Persistence model

| Table | Purpose |
|---|---|
| `lesson_sessions` | One row per lesson attempt arc. Tracks `status` (`in_progress` / `completed`), `lesson_version` + `content_hash` (sha256 of canonical lesson JSON at start), `unit_id` / `rule_tag` / `micro_rule_tag` (nullable, populated as content gains the metadata), `started_at` / `last_activity_at` / `completed_at`, and the `debrief_snapshot` recorded on `/complete`. A **partial unique index** on `(user_id, lesson_id) WHERE status = 'in_progress'` enforces the "at most one active session per user+lesson" invariant. |
| `exercise_attempts` | Append-only attempt history. One row per submission — re-submitting the same `exercise_id` adds a new row. The "current" answer for scoring is the row with the latest `(submitted_at, created_at)`. |
| `lesson_progress` | Aggregate per `(user_id, lesson_id)` updated on completion: `attempts_count`, `completed`, `latest_correct/total`, `best_correct/total`, `last_session_id`, `first/last_completed_at`. Used by the dashboard. |

`lesson_version` defaults to `content_hash` today; the columns are split so
a future authoring system can use opaque labels (e.g. `"v3"`) without
forcing the persisted attempt history to follow.

### POST /lessons/{lesson_id}/sessions/start

Create a fresh `lesson_session`, or **resume** the existing in-progress
one.

- If an `in_progress` session for `(user, lesson_id)` exists, the call
  returns it untouched (`reason = "resumed"`).
- Otherwise a new session is inserted (`reason = "created"`).
- Concurrent first calls race against the partial unique index — exactly
  one wins, the loser re-reads and returns the winner's session.

**Response 200:**
```json
{
  "reason": "created" | "resumed",
  "session_id": "uuid",
  "lesson_id": "uuid",
  "lesson_version": "sha256-hex",
  "status": "in_progress",
  "started_at": "ISO 8601 UTC",
  "last_activity_at": "ISO 8601 UTC",
  "completed_at": null,
  "exercise_count": 10,
  "answers_so_far": [
    {
      "exercise_id": "uuid",
      "correct": true|false,
      "canonical_answer": "string",
      "evaluation_source": "deterministic|ai_fallback|ai_timeout|ai_error",
      "explanation": "string|null",
      "submitted_at": "ISO 8601 UTC"
    }
  ]
}
```

**Response 404:** `{ "error": "lesson_not_found" }`.
**Response 401:** missing or revoked access token.

### GET /lessons/{lesson_id}/sessions/current

Returns the active in-progress session for `(user, lesson_id)`, if any.
Same payload shape as the `/start` 200 response (without `reason`).

**Response 404:** `{ "error": "no_active_session" }` when none exists.
**Response 404:** `{ "error": "lesson_not_found" }` for an unknown lesson.

### POST /lesson-sessions/{session_id}/answers

Submit one answer to a server-owned session.

**Request body:**
```json
{
  "attempt_id": "uuid (client-generated for idempotency on the wire)",
  "exercise_id": "uuid",
  "exercise_type": "fill_blank|multiple_choice|sentence_correction|sentence_rewrite|short_free_sentence|listening_discrimination",
  "user_answer": "string (max 500 chars)",
  "submitted_at": "ISO 8601 UTC"
}
```

**Response 200:** same shape as the legacy `/lessons/:id/answers` route, plus the Wave 12.6 `skill_rule_snapshot` field (Wave H1 added the optional `rule_card` inside it):

```json
{
  "attempt_id": "uuid",
  "exercise_id": "uuid",
  "correct": true,
  "evaluation_source": "deterministic|ai_fallback|ai_timeout|ai_error",
  "explanation": "string|null",
  "canonical_answer": "string",
  "skill_rule_snapshot": {
    "intro_rule": "string",
    "intro_examples": ["string"],
    "rule_card": { /* see content-contract.md §1.2 */ } | null
  }
}
```

`skill_rule_snapshot` is `null` when the exercise has no `skill_id` (legacy or diagnostic items can be untagged) or the source lesson is unavailable. The snapshot is a verbatim copy of the source lesson's `intro_rule`, `intro_examples`, and (Wave H1) `rule_card` at attempt time. Drives the Flutter `See full rule →` bottom sheet on `ResultPanel` per `docs/plans/wave12.6-rule-access.md`. The bottom sheet renders `RuleCardView` when `rule_card` is non-null and falls back to the flat strings otherwise.

**Wave H2 — dual-verdict for fill_blank.** When the deterministic matcher fails on a `fill_blank` and the source lesson declares `target_form` (see `GET /lessons/:id` above) and the AI provider implements `evaluateTargetVerdict`, the service calls a second AI judge with `{target_form, prompt, accepted_answers, user_answer}` and may flip `correct` to `true` when the judge returns `target_met=true`. When the flip carries an off-target slip note, the judge's `off_target_note` is surfaced in `explanation` so the learner sees `"form is right; small slip on …"` rather than a silent green tick. The judge is **not** invoked on deterministic-correct submissions (no AI burn on success), and any AI error keeps the deterministic verdict (no penalty for an outage).

Behaviour:
- The session must belong to the authenticated user; foreign sessions
  return `404 session_not_found` (no leak across users).
- The session must be `in_progress`; submitting against a completed
  session returns `409 session_not_in_progress`.
- A `:sessionId` path segment that is not a UUID returns
  `404 session_not_found` at the route boundary (no DB roundtrip).
- The lesson fixture must still match the session's stored
  `content_hash`. If the fixture has been edited since the session
  started, the route returns `409 lesson_content_changed` rather than
  silently grading against a different question set; the client must
  abandon the session and start a new one.
- `attempt_id` is the wire-level idempotency key. A partial unique
  index on `(session_id, client_attempt_id)` makes a replay return the
  original attempt's verdict and creates **zero** new rows. A retry that
  crosses with the original write resolves the same way via the
  unique-violation path.
- A non-replay submission writes a new `exercise_attempts` row.
  Re-submitting the same `exercise_id` with a **different** `attempt_id`
  adds another row; the **latest** row wins for scoring (see `/result`).
- For `sentence_correction` borderline submissions the AI rate limiter
  (10 calls per IP per 60s) runs at the route boundary, identical to the
  legacy route. The in-memory AI cache is keyed on
  `(session_id, exercise_id, normalised_answer)`, so resubmitting the
  same wrong answer never re-charges the model.

**Errors:** `404 session_not_found`, `404 lesson_content_missing`,
`404 exercise_not_found`, `400 invalid_payload` (incl. type mismatch),
`409 session_not_in_progress`, `409 lesson_content_changed`,
`429 rate_limit_exceeded`, `401 unauthorized`.

### POST /lesson-sessions/{session_id}/complete

Mark the session completed and persist the debrief snapshot.

- Computes `correct_count` from the latest attempt per exercise.
- Builds the debrief (deterministic perfect-score short-circuit, AI
  fallback, fallback copy on timeout/error — same contract as
  `/lessons/:id/result`) and writes the result to
  `lesson_sessions.debrief_snapshot`.
- Upserts `lesson_progress`:
  - `attempts_count` increments.
  - `latest_correct/total` = this run's score.
  - `best_correct/total` = max ratio across all completed runs.
  - `last_session_id`, `first_completed_at`, `last_completed_at` updated.
- Idempotent under concurrency. The `in_progress → completed` flip is a
  single row-level conditional UPDATE; only the transaction that wins it
  writes the debrief snapshot and the `lesson_progress` upsert.
  Replays — both the same call retried and a concurrent racing call —
  return the persisted payload without rebuilding the debrief or
  re-incrementing `attempts_count`. The `lesson_progress` upsert itself
  takes a `FOR UPDATE` row lock so two completions on different
  sessions for the same `(user, lesson)` cannot lose an
  `attempts_count` increment.

**Response 200:** the same shape as `GET /lesson-sessions/:id/result`
(see below) with `status = "completed"` and `completed_at` populated.

**Errors:** `404 session_not_found`, `409 session_not_in_progress` (only
when the session is `abandoned` or another non-terminal status — the
`completed → completed` replay is silent), `401 unauthorized`.

### GET /lesson-sessions/{session_id}/result

Return the lesson result.

- For `in_progress` sessions: live view computed from the latest
  attempts. The debrief is built on demand and cached in-memory by
  `(session_id, lesson_id, attempt-fingerprint)` — repeated GETs with
  the same outcomes return the cached debrief instantly. The
  fingerprint is the sorted list of `(exercise_id:correct)` pairs, so a
  new submission flips the fingerprint and rebuilds.
- For `completed` sessions: returns the persisted `debrief_snapshot`
  verbatim, so the report stays stable across content edits. The route
  tolerates content-hash drift on completed sessions because the
  snapshot already captures the original outcome.
- `total_exercises` is read from the session's frozen `exercise_count`
  (the value at session-start), so it stays consistent with the
  dashboard's `last_lesson_report.total_exercises`.

**Response 200:**
```json
{
  "session_id": "uuid",
  "lesson_id": "uuid",
  "status": "in_progress|completed",
  "started_at": "ISO 8601 UTC",
  "completed_at": "ISO 8601 UTC|null",
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
  "debrief": { /* same DebriefDto as /lessons/:id/result */ } | null
}
```

`answers` is ordered by lesson sequence. `prompt` for
`listening_discrimination` items is the audio transcript.

**Errors:** `404 session_not_found`, `401 unauthorized`.

### GET /dashboard

Per-user dashboard view. Reads the lesson manifest, `lesson_progress`,
and any active `in_progress` sessions, and returns a recommended-next
lesson hint.

Ordered progression exists, but **any lesson may still be selected** by
the learner — `recommended_next_lesson_id` is a hint, not a hard lock.

**Response 200:**
```json
{
  "level": "B2|null",
  "lessons": [
    {
      "lesson_id": "uuid",
      "title": "string",
      "slug": "string",
      "level": "B2",
      "language": "en",
      "unit_id": "string|null",
      "exercise_count": 10,
      "order": 1,
      "status": "available|in_progress|done",
      "attempts_count": 0,
      "completed": false,
      "latest_correct": null,
      "latest_total": null,
      "best_correct": null,
      "best_total": null,
      "last_completed_at": "ISO 8601 UTC|null",
      "active_session_id": "uuid|null"
    }
  ],
  "recommended_next_lesson_id": "uuid|null",
  "active_sessions": [
    {
      "session_id": "uuid",
      "lesson_id": "uuid",
      "started_at": "ISO 8601 UTC",
      "last_activity_at": "ISO 8601 UTC",
      "exercise_count": 10,
      "answered_count": 3
    }
  ],
  "last_lesson_report": {
    "session_id": "uuid",
    "lesson_id": "uuid",
    "lesson_title": "string",
    "completed_at": "ISO 8601 UTC",
    "total_exercises": 10,
    "correct_count": 7,
    "debrief": { /* DebriefDto snapshot */ }
  } | null
}
```

`recommended_next_lesson_id` selection:
1. The user's only `in_progress` session, if any.
2. Otherwise the lowest-`order` lesson with `completed = false`.
3. Otherwise `null`.

`active_sessions[].answered_count` is the count of distinct
`exercise_id`s with at least one row in `exercise_attempts` for the
session — a true "questions answered so far" indicator. Resubmitting
the same exercise does not double-count. The session row's
`correct_count` is only refreshed at completion and is never used for
this field.

`last_lesson_report.total_exercises` and `/lesson-sessions/:id/result`'s
`total_exercises` both read from the same frozen `session.exercise_count`
column, so the two endpoints cannot disagree.

**Errors:** `401 unauthorized`.

### Resume semantics

- Exactly **one** in-progress session per `(user, lesson)` is enforced
  by the partial unique index on `lesson_sessions`.
- Resume across devices is implicit: any client that authenticates as
  the same user can call `/sessions/start` and pick up where the prior
  device left off — `answers_so_far` lets the client jump to the next
  unanswered exercise.
- Re-submitting an already-answered exercise is allowed and adds a new
  attempt row. The latest attempt wins for scoring; the prior attempt
  rows survive as immutable history (audit trail / future analytics).

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

- production frontend origin (configured via `ALLOWED_ORIGINS`, or `PUBLIC_WEB_ORIGIN` when no explicit allowlist is provided)
- `http://localhost:3000` (local dev - typical Flutter web)
- `http://localhost:8080` (alternate local dev port)
- `http://localhost:57450` (Flutter web dev server)

### Configuration

Override the default allowlist by setting the `ALLOWED_ORIGINS` environment variable:
```
ALLOWED_ORIGINS=https://custom-domain.com,http://localhost:5000
```

Separate multiple origins with commas. Each will be trimmed of whitespace.

If `ALLOWED_ORIGINS` is unset, the backend falls back to `PUBLIC_WEB_ORIGIN` and the localhost development origins above.

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
| `session_not_found` | 404 | Lesson session unknown or owned by another user |
| `no_active_session` | 404 | No in-progress session exists for `(user, lesson)` |
| `lesson_content_missing` | 410 | Session points at a lesson fixture that no longer exists |
| `lesson_content_changed` | 409 | Lesson fixture's `content_hash` no longer matches the session's stored hash; the client must abandon and restart |
| `session_not_in_progress` | 409 | Tried to submit / complete a non-`in_progress` session |
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

**Headers honoured:** `Accept-Language` is parsed on first-login only —
the user row's `user_profiles.ui_language` is seeded from the first
supported tag (region stripped: `en-US` → `en`). Unsupported headers
fall back to `"en"`. Subsequent logins for the same identity ignore
the header (the existing column is preserved); learners change their
language via `PATCH /me/profile`.

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
    "uiLanguage": "en|ru|vi",
    "updatedAt": "ISO 8601 UTC"
  }
}
```

`uiLanguage` (Wave J.1a) is the learner's preferred L1 for UI chrome
and (eventually) localized content. Always defined — defaults to `"en"`
on first login if `Accept-Language` does not name a supported tag.
Seeded from `Accept-Language` on the first login request that creates
the user row (per `docs/plans/roadmap.md §11.6 Workstream J`).

### PATCH /me/profile

Auth required. Strict body: only `displayName`, `level`, and
`uiLanguage` are accepted. Unknown fields → 400.

```json
{ "displayName": "string|null|optional",
  "level": "A1|A2|B1|B2|C1|C2|null|optional",
  "uiLanguage": "en|ru|vi|optional" }
```

`uiLanguage` is **not** nullable — once the column exists, it always
carries one of the three supported tags. Sending `null` returns 400.
Sending an unsupported tag (`"de"`, `"zh"`, etc.) returns 400.

**Response 200:** `{ "profile": { ... } }`.

### DELETE /me

Auth required. Hard-deletes the user row. The schema's
`ON DELETE CASCADE` clears `auth_identities`, `auth_sessions`, and
`user_profiles`. `audit_events.user_id` is `ON DELETE SET NULL`, so the
audit trail (including the `user.deleted` tombstone) survives. The
delete and the tombstone insert run in the same transaction so the
audit trail and the deletion can never disagree.

**Response:** `204 No Content`.

### Wave 2 status (2026-04-26)

- **Shipped**: `lesson_sessions`, `exercise_attempts`, `lesson_progress`
  tables (migration `0002_lesson_sessions`); the
  `/lessons/:id/sessions/start`, `/sessions/current`,
  `/lesson-sessions/:id/answers`, `/lesson-sessions/:id/complete`,
  `/lesson-sessions/:id/result`, and `/dashboard` endpoints — all
  auth-protected.
- **Wave 8 / shipped 2026-04-26**: the legacy anonymous
  `/lessons/:id/answers` and `/lessons/:id/result` routes are **removed**.
  Every mutation flows through the auth-protected
  `/lesson-sessions/...` endpoints. The Flutter `ApiClient` and
  `SessionController` were rewired; `Skip-for-now` on `SignInScreen`
  now performs a silent stub-login under a stable per-install subject
  so guest mode still has a session.
- **Wave 3 / not yet shipped**:
  - `apple_stub` → real `apple` provider (verify `identityToken` JWT
    against Apple's JWKS).
  - In-flow resume UX (the server already supports it via the
    partial unique index on `(user_id, lesson_id) WHERE status =
    'in_progress'` and `GET /lessons/:id/sessions/current`).

## Engine state (Wave 7.3)

Per-learner per-skill mastery + cross-session review cadence — server
mirror of the device-scoped `LearnerSkillStore` and `ReviewScheduler`
in Flutter. All endpoints require auth. Schema lives in migration
`0005_learner_state` (tables `learner_skills` + `learner_review_schedule`).

### POST /me/skills/{skill_id}/attempts

Records one attempt for one skill. Mirrors the Flutter `LearnerSkillStore.recordAttempt` semantics per `LEARNING_ENGINE.md §§7.1, 6.4, 12.3`.

**Request body:**
```json
{
  "evidence_tier": "weak | medium | strong | strongest",
  "correct": true,
  "primary_target_error": "conceptual_error | form_error | contrast_error | careless_error | transfer_error | pragmatic_error",
  "meaning_frame": "string (≤500 chars, optional)",
  "evaluation_version": 1
}
```

`primary_target_error`, `meaning_frame`, `evaluation_version` are optional.

**Response 200** — derived state per §7.2 included on the wire:
```json
{
  "skill_id": "verb-ing-after-gerund-verbs",
  "mastery_score": 10,
  "last_attempt_at": "2026-04-27T13:57:00.000Z",
  "evidence_summary": { "weak": 0, "medium": 1, "strong": 0, "strongest": 0 },
  "recent_errors": [],
  "production_gate_cleared": false,
  "gate_cleared_at_version": null,
  "status": "started"
}
```

Score deltas are V0 and tunable: weak ±5, medium ±10, strong ±15, strongest ±20. Score is clamped to `[0, 100]`.

**Production gate (§6.4)** flips to `true` on the first strongest-tier correct attempt that carries a non-empty `meaning_frame` (the §6.3 meaning+form proof). Sticky thereafter, with one exception: when `evaluation_version` is greater than the version recorded on the existing gate (`gate_cleared_at_version`), the gate is invalidated before this attempt is applied — §12.3 invalidation pivot.

**Recent errors** are FIFO-bounded at 5 per `LearnerSkillStore.recentErrorsCap`. Wrong attempts with no `primary_target_error` field do not push.

**Response 400:** `{ "error": "invalid_skill_id" }` (skill_id outside `[a-zA-Z0-9._-]{1,120}`) or `{ "error": "invalid_payload" }` (missing fields, unknown enum).

### GET /me/skills/{skill_id}

Returns the same DTO as the POST above — the current persisted state for one skill plus the §7.2 status derived from it. Returns the empty record (mastery_score 0, status `started`) when no attempts have been recorded yet.

### GET /me/skills

Returns every skill the caller has touched.

**Response 200:**
```json
{ "skills": [ /* DTOs as above */ ] }
```

### POST /me/skills/{skill_id}/review-cadence

Records the in-session outcome for one skill at session end. Mirrors `ReviewScheduler.recordSessionEnd` per `LEARNING_ENGINE.md §§9.3, 9.4`.

**Request body:**
```json
{ "mistakes_in_session": 0 }
```

**Response 200:**
```json
{
  "skill_id": "verb-ing-after-gerund-verbs",
  "step": 1,
  "due_at": "2026-04-28T13:57:00.000Z",
  "last_outcome_at": "2026-04-27T13:57:00.000Z",
  "last_outcome_mistakes": 0,
  "graduated": false
}
```

Step rules (V0 — over-conservative on the §9.3 "wrong review attempt resets" rule because Wave 7 does not yet differentiate review-session vs first-lesson):
- 0 mistakes → step advances by 1 (capped at 5)
- 1+ mistakes → cadence resets to step 1
- Step 5 reached without resetting → `graduated: true` per §9.4

Intervals: 1 = 1d, 2 = 3d, 3 = 7d, 4+ = 21d (capped).

### GET /me/skills/{skill_id}/review-cadence

Returns the schedule entry for one skill, or 404 `no_schedule` when never recorded.

### GET /me/reviews/due?at=&lt;ISO8601&gt;

Returns every non-graduated skill whose `due_at <= at`, sorted oldest-first. `at` defaults to current server time when the query parameter is omitted.

**Response 200:**
```json
{
  "at": "2026-04-28T13:57:00.000Z",
  "reviews": [ /* schedule DTOs */ ]
}
```

**Response 400:** `{ "error": "invalid_at" }` (unparseable ISO timestamp).

### POST /me/state/bulk-import

Wave 7.4 part 2A — first-sign-in migration of device-scoped learner state. Auth required. Idempotent: any `(user, skill)` row that already exists on the server is preserved and reported back as skipped. Designed to be safe to call again on a follow-up sign-in from a different device.

**Request body** (max 500 entries per array):
```json
{
  "learner_skills": [
    {
      "skill_id": "g.tense.past_simple",
      "mastery_score": 72,
      "last_attempt_at": "2026-04-26T14:30:00.000Z",
      "evidence_summary": { "weak": 0, "medium": 2, "strong": 4, "strongest": 1 },
      "recent_errors": ["wrong_form"],
      "production_gate_cleared": true,
      "gate_cleared_at_version": 3
    }
  ],
  "review_schedules": [
    {
      "skill_id": "g.tense.past_simple",
      "step": 2,
      "due_at": "2026-04-30T00:00:00.000Z",
      "last_outcome_at": "2026-04-27T14:30:00.000Z",
      "last_outcome_mistakes": 1,
      "graduated": false
    }
  ]
}
```

**Response 200:**
```json
{
  "imported_skill_ids": ["g.tense.past_simple"],
  "skipped_skill_ids": [],
  "imported_schedule_skill_ids": ["g.tense.past_simple"],
  "skipped_schedule_skill_ids": []
}
```

`imported_*` are the IDs the server adopted; `skipped_*` are IDs where the server already had a row (the inbound payload was discarded for those skills only — others still imported).

**Response 400:** `{ "error": "invalid_payload" }` for any Zod validation failure (oversized array, malformed timestamp, unknown evidence tier, etc.).

**Audit:** writes one `learner_state.bulk_import` event per call with counts only (`imported_skills`, `skipped_skills`, `imported_schedules`, `skipped_schedules`) — never the raw payload. Used for "I lost my progress" investigations.

### Wave 7.3 status (2026-04-27)

- **Shipped**: `learner_skills`, `learner_review_schedule` tables (migration `0005_learner_state`); the six engine state endpoints above. All auth-protected. 18 new test cases in `tests/learner-state.test.ts` covering recordAttempt + status derivation + cadence + dueAt + user isolation + §12.3 invalidation.

### Wave 7.4 part 2A status (2026-04-26)

- **Shipped (server)**: `POST /me/state/bulk-import` with idempotent skip-if-server-row-exists semantics, full Zod validation, audit log of counts only, max 500 entries per array. 6 new test cases in `tests/learner-state.test.ts` covering auth, fresh import, idempotent skip, schedule-clobber prevention, oversized rejection, malformed payload rejection.
- **Shipped (client)**: `SignInScreen` (Apple Sign-in stub + Skip), `AuthClient` token storage, `HomeScreen` routes through sign-in gate when `MASTERY_AUTH_ENABLED=true`.

### Wave 7.4 part 2B status (2026-04-26)

- **Shipped (client)**: `LearnerSkillStore` and `ReviewScheduler` rewritten as static facades over a pluggable `LearnerSkillBackend` / `ReviewSchedulerBackend` interface. Two implementations: local (the original SharedPreferences keys; used in unauth'd builds and guest mode) and remote (calls the auth-protected `/me/skills/...` and `/me/reviews/due` endpoints). Existing call-sites stay on the static facade — no DI rewrite.
- **Shipped (client)**: `LearnerStateMigrator` (`app/lib/learner/learner_state_migrator.dart`) collects the local snapshot through fresh local backend instances, POSTs it through `/me/state/bulk-import`, then flips both facades to remote. Returning users with a live refresh token also point the facades at remote on app start. Skip-for-now keeps the facades local so guest mode is unchanged. Failures (network or 4xx) still flip the facades — signed-in writes hit the server next.
- **Shipped (build)**: `scripts/render-build-web.sh` now bakes `--dart-define=MASTERY_AUTH_ENABLED=true` into prod web builds, so the sign-in gate is live in production.
- **Tests**: 9 new cases in `app/test/learner_state_migrator_test.dart` covering facade swap, remote backend HTTP shape, empty / non-empty snapshot, 4xx + network error paths, snake_case payload keys.

### Wave 8 status (2026-04-26)

- **Shipped (server)**: legacy unauthenticated `POST /lessons/:id/answers` and `GET /lessons/:id/result` removed. Three legacy test files (`evaluate.route.test.ts`, `result.route.test.ts`, `evaluate-summary.integration.test.ts`) deleted. Two rate-limiter integration `describe` blocks in `backend-hardening.test.ts` skipped (equivalent coverage on `/lesson-sessions/.../answers` already exists in `lesson-sessions.test.ts`). 281/281 backend tests passing (4 skipped).
- **Shipped (client)**: Flutter `ApiClient` rewired through `AuthClient` for every mutation. New methods `startLessonSession`, `submitAnswer(sessionId, ...)`, `completeLessonSession`, `getResult(sessionId)`. `SessionController.loadLesson` now starts a server-owned session in parallel with the lesson content fetch. The build-time `MASTERY_AUTH_ENABLED` flag is gone — auth is mandatory in every shipped build. `SignInScreen.Skip-for-now` performs a silent Apple-stub sign-in under a stable per-install subject (`mastery_stub_subject_v1` in SharedPreferences) so a Skip + later Sign-in lands on the same backend user.
- **Tests**: `session_controller_test.dart` rewired through `mountAuthedApiClient` helper (`app/test/helpers/api_test_helpers.dart`) — 24/24 passing. `widget_test.dart`, `happy_path_lesson_flow_test.dart`, `cross_wave_integration_test.dart` are disabled at runtime with explicit TODOs pending the same rewire (the underlying coverage moved to `session_controller_test.dart` for the SessionController paths). 133/133 active Flutter tests passing.

### Wave 9 status (2026-04-26) — observability infra

Implements the V1 plan's Wave 9 step (`docs/plans/learning-engine-v1.md`). No user-visible behaviour change; pure observability infra so subsequent V1 waves can be measured rather than guessed.

- **Shipped (schema, migration `0006_observability_v1`)**:
  - `decision_log` table — append-only Decision Log per `LEARNING_ENGINE.md §18`. One row per Decision Engine call: `(user_id, session_id?, skill_id?, decision, reason, previous_state jsonb, next_exercise_id?, created_at)`. Indexed by `(user_id, created_at desc)`, `session_id`, `skill_id`.
  - `exercise_attempts.friction_event text` column — null on unremarkable attempts; one of `repeated_error | abandon_after_error | retry_loop | time_spike` once Wave 11 lands the detector. Wave 9 only ships the column.
  - `exercise_stats` table — daily counters per `(exercise_id, stat_date)`: `attempts_count`, `correct_count`, `partial_count`, `wrong_count`, `total_time_to_answer_ms` (bigint), `qa_review_pending` bool, `exercise_version` int. Updated by `recordAttemptStats` on every `submitAnswer` call.
- **Shipped (writers)**:
  - `recordDecision` (`backend/src/observability/decisionLog.ts`) — narrow API: `recordDecision(db, { userId, decision, reason?, previousState?, sessionId?, skillId?, nextExerciseId? })`. Never throws on the happy path; returns the new row id or `null` on a transient error so observability writes never break the lesson flow.
  - `recordAttemptStats` (`backend/src/observability/exerciseStats.ts`) — atomic upsert on `(exercise_id, stat_date)` with `INSERT ... ON CONFLICT ... DO UPDATE`. Time-to-answer is clamped to `[0, 10 min]` so a misbehaving client cannot poison the average.
- **Wired callsites**:
  - `lessonSessions/service.submitAnswer` calls `recordAttemptStats` after every successful insert.
  - `learner/service.recordAttempt` writes `decision_log` rows for `production_gate_cleared` (§6.4) and `mastery_invalidated` (§12.3 evaluator-version bump).
- **Versioning**:
  - `exercise_stats.exercise_version` defaults to 1 — a future exercise rewrite bumps the version so old buckets stay tied to the old content.
  - `skills.json` entries can carry `skill_version` (default 1) — ships as a documented field; not yet read by the runtime.
- **Status thresholds** (Flutter `LearnerSkillRecord.statusAt`):
  - `0–20 → started`, `21–45 → practicing`, `46–70 → getting_there`, `71–84 → almost_mastered`, `85–100 → mastered`. Final per `docs/plans/learning-engine-v1.md` Decisions log #8.
- **Tests**: 8 new cases in `tests/observability.test.ts` covering Decision Log writes (happy path, null fields, error tolerance), exercise-stats counters (insert + upsert + outcome routing + time-to-answer clamp), and the two `recordAttempt` integration paths. 289/289 backend tests passing (4 skipped).

### Wave 10 status (2026-04-26) — Mastery V1 + error model 6→4

Implements the V1 plan's Wave 10 step (`docs/plans/learning-engine-v1.md`).

- **Schema (migration `0007_mastery_v1`)** — `learner_skills` grows six new columns: `attempts_count`, `exercise_types_seen jsonb`, `last_outcome text`, `repeated_conceptual_count`, `weighted_correct_sum numeric(10,2)`, `weighted_total_sum numeric(10,2)`. The legacy `mastery_score` stays in the row as a coarse hint; the new derived status reads exclusively from the V1 inputs.
- **Mastery V1 evaluator** (`backend/src/learner/mastery.ts`) — pure function `evaluateMasteryV1(record, now?)` returns `{ status, gateCleared, blockedBy }`. The seven blocking clauses (attempts floor, no correction/production, weighted accuracy, repeated conceptual, last-outcome wrong, production gate, review-due window) each have a "fails on this rule alone" unit test in `tests/mastery-v1.test.ts`. All thresholds (`MIN_ATTEMPTS_FOR_MASTERY=6`, `MIN_ATTEMPTS_WITH_PRODUCTION=4`, `WEIGHTED_ACCURACY_THRESHOLD=0.8`, `REPEATED_CONCEPTUAL_BLOCK_THRESHOLD=2`, `REVIEW_DUE_AFTER_DAYS=21`) live in one tunable block at the top of the module.
- **Evidence weights** (`EVIDENCE_WEIGHTS` in `mastery.ts`) — V1 spec §6: selection 1, completion 2, correction 3, production 5. The weights drive the "weighted accuracy" the gate compares against.
- **`recordAttempt` updates** — every attempt now writes the V1 inputs (`attemptsCount += 1`, `exerciseTypesSeen ∪= {exerciseType}`, `lastOutcome`, `weightedCorrectSum`, `weightedTotalSum`) atomically with the legacy `mastery_score` upsert. `evaluateMasteryV1` runs before and after the insert; on a transition from `gateCleared=false` to `gateCleared=true` a `mastery_promoted` row is appended to the Decision Log.
- **Status DTO** — `GET /me/skills/:id` now returns the V1-derived status (`deriveStatus` is a thin shim around `evaluateMasteryV1(...).status`). Status thresholds 0–20 / 21–45 / 46–70 / 71–84 / 85–100 still apply on the Flutter side as a coarse mapping; the rule-based gate is the source of truth for "mastered".
- **Error model 6→4** — `TARGET_ERROR_CODES` enum dropped `transfer_error` and `pragmatic_error`. Verified zero references in `backend/data/lessons/*.json`. Persisted `recent_errors` arrays from earlier waves silently filter the dropped codes out on next read.
- **Routes** — `POST /me/skills/:skillId/attempts` accepts two new optional fields: `exercise_type` (string, max 64 chars) and `outcome` (`correct | partial | wrong`).
- **Tests** — 10 new V1-gate unit cases in `tests/mastery-v1.test.ts`, plus the existing learner-state route test was updated for the new "getting_there" outcome under the V1 attempts arm. 299/299 backend tests passing (+ 4 skipped from Wave 8). 133/133 Flutter tests still passing.

### Wave 11.1 status (2026-04-26) — exercise bank + Decision Engine module (off-path)

First half of the V1 plan's Wave 11 step (`docs/plans/learning-engine-v1.md`). Lands the bank loader and the Decision Engine as standalone modules so they can be unit-tested before any routes start consuming them. **No user-visible behaviour change** — the existing `/lessons/:id/sessions/start` flow is unchanged. Wave 11.2 wires the new `/sessions/...` endpoints + Flutter `ApiClient` / `SessionController` rewire.

- **`backend/src/data/exerciseBank.ts`** — runtime bank loader. Reads existing lesson JSON files at boot (authoring format unchanged) and flattens every exercise into a single in-memory index. `getAllBankEntries()`, `getEntriesForSkill(skillId)`, `getBankEntry(exerciseId)`, `getDiagnosticPool()`. Each entry carries its source-lesson stamps (`sourceLessonId`, `sourceLessonVersion`, `sourceContentHash`) so attempt rows can stay traceable to the originating fixture.
- **`backend/src/decision/engine.ts`** — pure `pickNext(ctx)` returns `{ next: BankEntry | null, reason: string | null }`. Implements §9 priorities (mastery → variety → past errors), §9.1 third-mistake skill drop-out, §14 last-N-repeat avoidance, and the V1 default pacing 60/30/10 baked in via `DEFAULT_PACING`. Reason codes match the §11.3 vocabulary (`linear_default`, `same_rule_different_angle`, `same_rule_simpler_ask`, `review_due_lift`, `variety_switch`, `session_complete`, `no_candidates`, `bank_empty`).
- **Tests** — 9 new cases in `tests/decision-engine.test.ts` covering bank load, replay traceability, never-repeat rule, third-mistake drop-out, mastery-aware ordering, reason-code vocabulary. 308/308 backend tests passing (+ 4 skipped from Wave 8).
- **Out of scope (lands in Wave 11.2)**: new `/sessions/...` routes, `lesson_id` nullable on `lesson_sessions`, deletion of `/lessons/:id/sessions/...` endpoints, Flutter `ApiClient` rewire to `startSession()` + `nextExercise()`.

### Wave 11.2 status (2026-04-26) — dynamic session routes (server side)

Server-side activation of the Wave 11.1 modules. **No Flutter changes yet** — the rewire of `ApiClient` + `SessionController` is Wave 11.3. Two new endpoints sit alongside the legacy lesson-bound ones:

- **`POST /sessions/start`** — auth. Creates a dynamic session via `startDynamicSession`. Response: `{ reason, session_id, title: "Today's session", level: "B2", exercise_count: SESSION_LENGTH, started_at, first_exercise }` where `first_exercise` is the same projection shape `GET /lessons/:id` returned for fixture-bound sessions.
- **`POST /lesson-sessions/:sessionId/next`** — auth. Reads the session's attempt history, asks the Decision Engine for the next pick. Response: `{ reason, position, next_exercise }`. `next_exercise` is null when the session has reached `SESSION_LENGTH` or no candidate fits; the client should call `/complete` instead. Rejects 409 `session_not_dynamic` if the session id belongs to a fixture-bound (legacy) session.

Implementation:

- **Sentinel `lesson_id`** — dynamic sessions write `00000000-0000-0000-0000-000000000000` to `lesson_sessions.lesson_id` so the column stays NOT NULL across every shipped row. The partial unique index on `(user_id, lesson_id) WHERE status = 'in_progress'` was rewritten in migration `0008_dynamic_sessions` to skip the sentinel id, allowing concurrent dynamic runs (the runtime ensures at-most-one via the service layer).
- **`loadOwnedSession`** — recognises the sentinel id and returns a synthetic Lesson DTO (empty `exercises` array) + LessonMeta. Existing answer / result / complete paths keep working unchanged.
- **`submitAnswer`** — when the synthetic lesson has no matching exercise, falls through to `getBankEntry(exerciseId)` so the dynamic flow can record attempts the same way fixture-bound flow does.
- **Decision Log** — every `pickNextForSession` call writes a `next_exercise` (or `session_complete`) row, indexed by `(user_id, created_at desc)` and `session_id`.

Tests:
- 4 new cases in `tests/dynamic-sessions.test.ts` covering auth gate, first-pick shape, second-pick differs from first, cross-user 404. 312/312 backend tests passing (+ 4 skipped from Wave 8).

Out of scope (Wave 11.3):
- Flutter `ApiClient.startSession()` + `nextExercise(sessionId)` rewire.
- `SessionController` shift from queue-walking to next-on-demand.
- Dashboard hero "Today's session" copy update.
- Removal of `POST /lessons/:id/sessions/start` and `GET /lessons/:id/sessions/current` once Flutter has cut over.

### Wave 11.3 status (2026-04-26) — Flutter on dynamic sessions

Wires the Wave 11.2 server endpoints into the Flutter client. **Safety mode: legacy paths kept alive.** The dashboard CTA now boots a V1 dynamic session, but `SessionController.loadLesson(lessonId)` and the legacy `POST /lessons/:id/sessions/start` route still work — both are reachable from the test harness and a one-line `_startLesson(lessonId)` fallback in `home_screen.dart`. Removal lands in Wave 11.4 once production telemetry confirms the dynamic flow is healthy.

- **`ApiClient`**: new `startSession()` returns `DynamicSessionStart { sessionId, title, level, exerciseCount, firstExercise }`. New `nextExercise(sessionId)` returns `DynamicNextResult { reason, position, next }`.
- **`SessionController`**: new `loadDynamicSession()` (no `lessonId`). Synthetic `Lesson` seeded with the first picked exercise; `Lesson.copyWith(exercises:)` lets `_fetchNextDynamic` append each subsequent pick. The internal `_dynamicMode` flag drives the post-attempt `nextExercise` fetch; the legacy `loadLesson` path leaves it false so its local DecisionEngine queue still runs.
- **`HomeScreen`**: hero copy is now "Today's session", level "B2", with the dashboard CTA always enabled (no more "content kончился"-style disabled CTA). The CTA pushes `LessonIntroScreen` with `lessonId == null`, which routes the controller to `loadDynamicSession`.
- **`LessonIntroScreen`**: `lessonId` is now optional; null selects the V1 dynamic flow.
- **Tests**: 3 new cases in `app/test/session_controller_test.dart` covering `loadDynamicSession` happy path, dynamic-mode `submitAnswer + advance` appending the next pick, and `/next` returning null ending the session. 136/136 Flutter tests passing. 312/312 backend (+ 4 skipped) — server-side untouched in this PR.

### Wave 11.4 status (2026-04-26) — drop legacy lesson-bound session paths

V1 cleanup. Production telemetry from Wave 11.3 (`/sessions/start` + `/lesson-sessions/.../next` live, smoke green) cleared the way to delete the lesson-bound entry points.

- **Removed**: `POST /lessons/:lessonId/sessions/start`, `GET /lessons/:lessonId/sessions/current` from `lessonSessions/routes.ts`. The two service functions `startSession` and `getCurrentSession` are kept in the file as dead code — no callers — until a tidier sweep.
- **Removed (UI)**: `_CurrentUnitBlock` (curriculum / units listing) is no longer rendered on the dashboard; the V1 dynamic flow makes a fixed unit listing meaningless. Skill-progress UI is V1.5 per `docs/plans/learning-engine-v1.md` decision #12. `_startLesson(lessonId)`, `_currentLesson`, `_nextAfterCurrent`, `_CurriculumEntry` are warned as unused but stay in the file as a one-line roll-back path.
- **Tests**: five `describe` blocks in `tests/lesson-sessions.test.ts` are now `describe.skip` with explicit Wave 11.4 markers — they assert lesson-bound semantics that no longer apply. Equivalent dynamic-flow coverage is in `tests/dynamic-sessions.test.ts` (Wave 11.2) and `app/test/session_controller_test.dart` (Wave 11.3).
- **Counts**: 287 passing / 29 skipped backend tests; 136/136 Flutter tests passing.

V1 MVP cleanup remaining (V1.5 backlog):
- Drop the dead service functions and the `_startLesson` / curriculum scaffolding once we are sure nothing else depends on them.
- Skill-progress UI (skill graph + per-skill cards on dashboard).

### Wave 13 status (2026-04-26) — pacing profiles + max-new-skill cap

Activates the V1 spec §12 pacing splits and §9 mixing rule on top of the dynamic Decision Engine shipped in Wave 11.

- **`backend/src/decision/pacing.ts`** — pure `derivePacingTarget(masteryStatusBySkill) → { target, profile, signal }` returns one of three V1 profiles:
  - `default` 60/30/10 when neither threshold fires.
  - `weak` 40/40/20 when `≥3` skills sit at `started` / `practicing`.
  - `strong` 70/20/10 when `≥3` skills sit at `mastered`.
  Strong wins when both thresholds fire — biases toward new ground when the learner has both old skills warm and new room to grow. `WEAK_THRESHOLD`, `STRONG_THRESHOLD` live in the constants block at the top of the module.
- **`backend/src/decision/engine.ts`** — `MAX_NEW_SKILLS_PER_SESSION = 1` cap (V1 spec §12). Once a session has surfaced one brand-new skill (no mastery record or `status='started'`), every additional new-skill candidate is filtered out so the run can settle on practising the one new rule.
- **`backend/src/sessions/dynamicService.ts`** — `startDynamicSession` and `pickNextForSession` both call `derivePacingTarget` on the learner's snapshot and pass the result via `DecisionContext.pacingTarget`. The chosen profile lands in the Decision Log `previousState` payload (`pacing_profile`, `pacing_signal`) so a regression can be traced back to the input distribution.
- **Tests**: 6 new cases in `tests/pacing.test.ts`. 293/293 active backend tests passing (+ 29 skipped).
- **Skill mixing** — already covered by the `variety_switch` boost in the Decision Engine score (Wave 11.1); no separate constant needed.

### Wave 12.1 status (2026-04-27) — diagnostic schema field

Off-path foundation for Wave 12.2. `LessonSchema` (and the `Exercise`
TS interface) now accepts an optional `is_diagnostic: bool` field on
every variant. Five weak-tier multiple_choice items tagged across the
five shipped skills (one per skill) so `getDiagnosticPool()` returns
a real cross-skill probe instead of the `flat.slice(0, 5)` fallback.
No route surface, no client surface — Wave 12.2 mounts the
`/diagnostic/...` routes that consume the pool.

### Wave 12.2 status (2026-04-28) — diagnostic routes + CEFR derivation

Server-side activation of the diagnostic probe per V1 spec §15 +
`LEARNING_ENGINE.md §10`. **No Flutter changes yet** — the
`DiagnosticScreen` lands in Wave 12.3.

New table: **`diagnostic_runs`** (migration `0009_diagnostic_runs`).
One row per probe. Stores `status` (`in_progress | completed |
abandoned`), the ordered `exercise_ids` surfaced for the run, the
`responses` jsonb (per-attempt outcome + skill_id + evidence_tier),
the derived `cefr_level` (null while in progress) and `skill_map`,
plus `started_at` / `completed_at`. Partial unique index
`diagnostic_runs_active_idx` enforces "at most one in_progress run
per user". Separate from `lesson_sessions` because the probe
lifecycle is different (5–7 fixed items, no day-to-day resume,
scored into a CEFR derivation rather than a per-lesson aggregate).

Four endpoints, all auth-protected via `requireAuth`:

- **`POST /diagnostic/start`** — Creates a fresh run if none is
  active; resumes the active one otherwise. Response: `{ run_id,
  resumed, position, total, next_exercise }`. Status `201` on fresh
  start, `200` on resume. `next_exercise` is the projected
  multiple_choice item at the run's current position.
- **`POST /diagnostic/:runId/answers`** — Records one attempt.
  Body: `{ exercise_id, exercise_type, user_answer, submitted_at? }`.
  The route enforces positional ordering: callers cannot submit an
  answer for an exercise that is not the run's next expected item.
  Evaluates via `evaluateMultipleChoice` (deterministic exact-match
  on `correct_option_id`) and augments `learner_skills` through the
  same `recordAttempt` path lesson sessions use, so every downstream
  invariant (recent_errors, weighted accuracy, exercise_types_seen)
  stays consistent. Response: `{ result: 'correct' | 'wrong',
  evaluation_source: 'deterministic', canonical_answer, explanation,
  run_complete, position, total, next_exercise }`. `next_exercise`
  is null when the run is complete.
- **`POST /diagnostic/:runId/complete`** — Idempotent. Derives a
  CEFR level + per-skill status map via `deriveCefrFromRun`, persists
  on the run, stamps `user_profiles.level`, writes a
  `diagnostic_completed` audit event. V1 thresholds (calibrated to a
  5-item B2 probe, expressed as percentages so a probe-size change
  doesn't require re-tuning): ≥80% correct → B2, 50–79% → B1, <50%
  → A2. C1 is intentionally unreachable from a B2 bank — V1.5
  territory. Response: `{ run_id, cefr_level, skill_map, completed_at,
  already_completed }`.
- **`POST /diagnostic/restart`** — Marks any active run as
  `abandoned`, writes a `diagnostic_abandoned` audit event, then
  starts a fresh run. The probe **augments** `learner_skills` rather
  than resetting it, so a re-diagnostic adds evidence rather than
  overwriting it.
- **`POST /diagnostic/skip`** — Write-only telemetry. Records a
  `diagnostic_skipped` audit event so D1 retention is measurable for
  "diagnostic completed" vs "skipped" cohorts. Returns `204`.

Error codes: `diagnostic_run_not_found` (404),
`diagnostic_run_not_active` (409), `diagnostic_run_already_complete`
(409), `diagnostic_answer_out_of_order` (409),
`exercise_type_mismatch` (400), `diagnostic_pool_empty` (503),
`diagnostic_unsupported_type` (500).

Tests:
- 14 new cases in `tests/diagnostic.test.ts` covering CEFR
  derivation thresholds, route auth gates, fresh-vs-resumed start,
  out-of-order rejection, learner_skills augmentation, idempotent
  complete, restart abandons + replaces, skip telemetry. 312/312
  backend tests passing.

Out of scope (Wave 12.3 / 12.4):
- Flutter `DiagnosticScreen` + route gating between sign-in and
  onboarding.
- "Skip for now" UI affordance backed by `POST /diagnostic/skip`.
- Dashboard "Welcome — your level is B2" surface backed by
  `user_profiles.level`.

### Wave 12.4 status (2026-04-28) — re-take affordance + D1 cohort SQL

**V1 MVP closeout.** Wave 12 was the last open V1 wave; this finishes
it.

- **Dashboard re-take.** A quiet `Re-run my level check` text link
  sits at the bottom of the Study Desk dashboard
  (`app/lib/screens/home_screen.dart`). Tapping pushes
  `DiagnosticScreen` via `MasteryFadeRoute`; both Begin→Complete and
  Skip-for-now pop back. The diagnostic always **augments**
  `learner_skills`, never resets — V1 spec §15. A second pass adds
  evidence on the existing skill rows; it does not wipe state. Useful
  for: a learner who Skip-for-now'd onboarding and later wants the
  level signal, or a returning learner who feels they've grown.
- **Audit-event payload locked.** The `diagnostic_completed` payload
  now carries `{ run_id, cefr_level, total_correct, total_answered,
  skills_touched: string[] }`. The shape is asserted by
  `tests/diagnostic.test.ts` so a future refactor can't silently drop
  fields the cohort query depends on. `diagnostic_skipped` carries an
  empty payload — the event_type itself is the cohort marker.

**D1 retention cohort query.** Split D1 by who took the diagnostic:

```sql
-- D1 retention by diagnostic cohort.
-- "D1 active" = the user came back at least once in the 24-72h
-- window after their first session attempt. Adjust the windows to
-- match the product's retention definition.
WITH first_attempt AS (
  SELECT user_id, MIN(submitted_at) AS first_at
  FROM exercise_attempts
  GROUP BY user_id
),
diag_cohort AS (
  SELECT
    fa.user_id,
    fa.first_at,
    EXISTS (
      SELECT 1 FROM audit_events ae
      WHERE ae.user_id = fa.user_id
        AND ae.event_type = 'diagnostic_completed'
    ) AS completed_diagnostic,
    EXISTS (
      SELECT 1 FROM audit_events ae
      WHERE ae.user_id = fa.user_id
        AND ae.event_type = 'diagnostic_skipped'
    ) AS skipped_diagnostic
  FROM first_attempt fa
),
returned_d1 AS (
  SELECT DISTINCT ea.user_id
  FROM exercise_attempts ea
  JOIN first_attempt fa ON fa.user_id = ea.user_id
  WHERE ea.submitted_at BETWEEN fa.first_at + interval '24 hours'
                            AND fa.first_at + interval '72 hours'
)
SELECT
  CASE
    WHEN completed_diagnostic THEN 'completed'
    WHEN skipped_diagnostic   THEN 'skipped'
    ELSE                          'no_signal'
  END AS cohort,
  COUNT(*)                                                  AS users,
  COUNT(*) FILTER (WHERE rd.user_id IS NOT NULL)            AS returned_d1,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE rd.user_id IS NOT NULL) / COUNT(*),
    1
  )                                                         AS d1_pct
FROM diag_cohort dc
LEFT JOIN returned_d1 rd ON rd.user_id = dc.user_id
GROUP BY cohort
ORDER BY cohort;
```

The full retention dashboard is a V1.5 follow-up per
`learning-engine-v1.md` "Out-of-MVP scope". Until then, the query
above is the authoritative shape — paste it into the Render Postgres
SQL console for a one-off cohort cut.

**Tests:** 1 widget test in
`app/test/diagnostic_dashboard_retake_test.dart` covering the
"Re-run my level check" tap → push DiagnosticScreen path. The
existing diagnostic test was extended to assert the
`diagnostic_completed` payload shape.

This closes Wave 12 and completes the V1 MVP wave plan in
`docs/plans/learning-engine-v1.md`.

## Wave 14.1 — admin retention dashboard

Founder-only surface for the V1.5 D1/D7 cohort retention table.
Backed by `users.created_at` (cohort) × `exercise_attempts.submitted_at`
(activity), aggregated in a single Postgres CTE.

**Auth:** all `/admin/*` routes require `Authorization: Bearer <jwt>`
**and** the caller's `user_id` must appear in the `ADMIN_USER_IDS` env
var (comma-separated UUIDs, lower-cased on read). Unset or empty env =
no admins, every admin route returns 403. 401 vs 403 distinction:
- 401 = bearer missing / invalid (delegated to `requireAuth`).
- 403 = bearer valid but the user is not an admin.

### GET /admin/retention

Returns the cohort table as JSON.

**Query params:**
- `window` — number of cohort days to include (count back from
  today, UTC). Clamped to `[1, 180]`. Default `30`.

**Response 200:**
```json
{
  "window_days": 30,
  "cohorts": [
    {
      "cohortDay": "2026-04-22",
      "cohortSize": 4,
      "d1Active": 3,
      "d7Active": 1,
      "d1Rate": 0.75,
      "d7Rate": 0.25,
      "d1Complete": true,
      "d7Complete": false
    }
  ]
}
```

`d1Rate` / `d7Rate` are `null` when `cohortSize == 0`.
`d1Complete` is `true` once `now >= cohort_day + 1d`; `d7Complete`
once `now >= cohort_day + 7d`. Incomplete cohorts still emit numbers
so the dashboard can show "in progress" rates with a marker.

### GET /admin/retention.html

Same data, server-rendered into a single-page HTML table that
matches the calm DESIGN.md tokens. Bookmarkable, no JS, no client
state. Same auth + `window` query param as the JSON route.

**Definition recap:**
- `cohort_day` = UTC calendar day of `users.created_at`.
- D1 active = at least one `exercise_attempts` row with
  `submitted_at` falling on `cohort_day + 1` (UTC).
- D7 active = same for `cohort_day + 7`.

**Tests:** 9 test cases in `backend/tests/admin-retention.test.ts`
covering empty DB, cohort sizing, strict D1 boundary (same-day
attempts excluded), `d1Complete` flip when window not closed,
401/403/200 auth gate, `window` clamp, and HTML rendering.

## Wave 14.3 — feedback system

User-scoped two-prompt feedback surface backed by an append-only
`feedback_responses` table. The Decision Engine does not read these
rows — they are product analytics, not engine input. Wave 14.3
shipped in three phases on 2026-04-28: phase 1 = these two
endpoints; phase 2 = `after_summary` modal on SummaryScreen Done;
phase 3 = `after_friction` modal triggered by the server-side
`friction_event` tag (see `friction-event surface` section below).

### POST /me/feedback

Records one feedback row. Authenticated.

**Request body:**
```json
{
  "prompt_kind": "after_summary | after_friction",
  "outcome": "submitted | dismissed",
  "rating": 1-5 (optional),
  "comment_text": "string ≤1000 chars (optional)",
  "context": { "session_id": "...", ... } (optional jsonb)
}
```

- `outcome = 'submitted'` requires at least one of `rating` or
  `comment_text` — server returns 400 `submitted_requires_content`
  otherwise. `outcome = 'dismissed'` is the swipe-away record and
  carries no rating.
- Both outcomes consume the cooldown so a learner who declines is
  not pestered.

**Response 201:** `{ "id": "uuid" }`

**Response 400:** `{ "error": "invalid_payload" | "submitted_requires_content" }`

**Response 401:** `{ "error": "unauthorized" }`

**Response 429:** `{ "error": "cooldown", "retry_after_seconds": N }` —
fires when a row of the same `prompt_kind` exists within the last
24 h. Cooldown is per-user × per-prompt-kind; a fresh `after_summary`
response does not block `after_friction`.

### GET /me/feedback/cooldown

Quiet, idempotent gate the client reads before deciding whether to
render either prompt. Authenticated.

**Response 200:**
```json
{
  "cooldown_hours": 24,
  "after_summary_allowed": true,
  "after_friction_allowed": true
}
```

A gate flips to `false` when a row for that prompt_kind has been
recorded in the last `cooldown_hours` (regardless of `outcome`).

**Tests:** 12 test cases in `backend/tests/feedback.test.ts` covering
auth gates, payload validation (bad enums, out-of-range rating, empty
submitted), 201 happy paths for `submitted` and `dismissed`, cooldown
enforcement, per-kind isolation, stale-row release, and the cooldown
GET responses.

### Wave 14.3 phase 3 — friction-event surface

`POST /lesson-sessions/:sessionId/answers` now carries an additional
field on the response:

```json
{
  ...,
  "friction_event": "repeated_error" | null
}
```

The service writes the same value to `exercise_attempts.friction_event`
on the row inserted for this attempt. V1 detector flags only
`repeated_error` (current attempt wrong + most recent prior attempt
in this session also wrong + both share `skill_id`). The `§17`
sibling tags (`abandon_after_error`, `retry_loop`, `time_spike`)
remain reserved.

Clients react by reading `getFeedbackCooldown()` and, when
`after_friction_allowed`, opening the `after_friction` feedback
prompt (see "Wave 14.3 — feedback system" above). Server-side
behaviour is unchanged regardless of whether the client surfaces the
prompt — the row is the source of truth for analytics.

**Tests:** 4 cases in `backend/tests/friction.test.ts` covering
single-wrong (no friction), two-consecutive-wrongs-same-skill
(`repeated_error`), prior-correct (no friction), prior-wrong-
different-skill (no friction).
