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
  "evaluation_source": "deterministic|ai_fallback",
  "explanation": "string|null",
  "canonical_answer": "string"
}
```

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
  "answers": [
    {
      "exercise_id": "uuid",
      "correct": true|false
    }
  ]
}
```

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

## Error Response Shape

All errors return HTTP 4xx/5xx with body: `{ "error": "snake_case_error_code" }`.

| Code | HTTP | Meaning |
|---|---|---|
| `lesson_not_found` | 404 | Unknown lesson_id |
| `exercise_not_found` | 404 | Unknown exercise_id |
| `invalid_payload` | 400 | Malformed request |
| `rate_limit_exceeded` | 429 | Too many AI-eligible submissions from this IP (10/60s) |
| `internal_error` | 500 | Unexpected server failure |
