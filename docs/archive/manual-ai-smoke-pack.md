# Manual AI Smoke Pack — Local Use

**Status:** Local operator checklist. No AI calls were made to create this file.  
**Last updated:** 2026-04-20

## Purpose

This is a minimal manual smoke pack for future live verification of the OpenAI-backed path.

Use it:
- after changing prompt wording
- after changing model
- after changing fallback thresholds
- after rotating API keys
- after changing backend startup workflow

## Preconditions

- local backend is running
- if testing the live AI path, backend is running with `AI_PROVIDER=openai`
- if the default port is busy, use a separate local port such as `3001`

## Pass Criteria

A smoke pass is considered healthy when:
- deterministic cases stay deterministic
- borderline cases reach `ai_fallback`
- clearly wrong cases stay rejected
- malformed setup produces a clear operational failure instead of silent fallback confusion

## Test Matrix

### 1. Health endpoint

Goal:
- confirm server reachability

Command:

```sh
curl -sS http://127.0.0.1:3000/health
```

Expected:

```json
{"status":"ok"}
```

### 2. Deterministic sentence correction

Goal:
- prove exact normalized accepted answer does not use AI

Command:

```sh
curl -sS -X POST http://127.0.0.1:3000/lessons/a1b2c3d4-0001-4000-8000-000000000001/answers \
  -H 'Content-Type: application/json' \
  --data '{
    "session_id":"11111111-0001-4000-8000-000000000001",
    "attempt_id":"00000000-0000-4000-8000-000000000010",
    "exercise_id":"a1b2c3d4-0001-4000-8000-000000000018",
    "exercise_type":"sentence_correction",
    "user_answer":"She has been working at this company for ten years.",
    "submitted_at":"2026-04-20T03:20:00.000Z"
  }'
```

Expected:
- `correct=true`
- `evaluation_source=deterministic`

### 3. Borderline near-miss that should reach AI

Goal:
- prove live AI path is reachable

Command:

```sh
curl -sS -X POST http://127.0.0.1:3000/lessons/a1b2c3d4-0001-4000-8000-000000000001/answers \
  -H 'Content-Type: application/json' \
  --data '{
    "session_id":"11111111-0001-4000-8000-000000000001",
    "attempt_id":"00000000-0000-4000-8000-000000000011",
    "exercise_id":"a1b2c3d4-0001-4000-8000-000000000018",
    "exercise_type":"sentence_correction",
    "user_answer":"She has been working at this company fo ten years.",
    "submitted_at":"2026-04-20T03:20:00.000Z"
  }'
```

Expected:
- `evaluation_source=ai_fallback`
- `feedback` may be `null` or a short string depending on model output
- verdict should be explainable under the current rubric

### 4. Borderline near-miss that should still be rejected

Goal:
- catch overly permissive models or prompts

Command:

```sh
curl -sS -X POST http://127.0.0.1:3000/lessons/a1b2c3d4-0001-4000-8000-000000000001/answers \
  -H 'Content-Type: application/json' \
  --data '{
    "session_id":"11111111-0001-4000-8000-000000000001",
    "attempt_id":"00000000-0000-4000-8000-000000000012",
    "exercise_id":"a1b2c3d4-0001-4000-8000-000000000019",
    "exercise_type":"sentence_correction",
    "user_answer":"If I had study more, I would have passed the exam.",
    "submitted_at":"2026-04-20T03:20:00.000Z"
  }'
```

Expected:
- likely `evaluation_source=ai_fallback`
- `correct=false`

### 5. Clearly wrong answer

Goal:
- ensure non-borderline wrong answers stay deterministic

Command:

```sh
curl -sS -X POST http://127.0.0.1:3000/lessons/a1b2c3d4-0001-4000-8000-000000000001/answers \
  -H 'Content-Type: application/json' \
  --data '{
    "session_id":"11111111-0001-4000-8000-000000000001",
    "attempt_id":"00000000-0000-4000-8000-000000000013",
    "exercise_id":"a1b2c3d4-0001-4000-8000-000000000018",
    "exercise_type":"sentence_correction",
    "user_answer":"She works there and likes her job.",
    "submitted_at":"2026-04-20T03:20:00.000Z"
  }'
```

Expected:
- `correct=false`
- `evaluation_source=deterministic`

## Operational Checks

If results look suspicious, verify in this order:

1. Is the backend actually running with `AI_PROVIDER=openai`?
2. Is the request truly borderline under current rules?
3. Is the answer actually a content-gap case rather than a prompt failure?
4. Did you hit rate limiting?
5. Did the process silently fall back to `stub` because the key was missing?

## Failure Notes Template

When a smoke case fails, record:

- date
- backend port
- model
- case id
- expected result
- actual result
- preliminary bucket: `prompt_issue`, `model_issue`, `threshold_issue`, `content_issue`, `ops_issue`
