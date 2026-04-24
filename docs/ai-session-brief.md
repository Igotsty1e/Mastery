# AI Session Brief — Mastery MVP

**Status:** Handoff brief for the next AI-focused session.  
**Last updated:** 2026-04-20

## What This Project Is Doing

Mastery is a structured English-practice MVP.

AI is intentionally narrow:
- only for `sentence_correction`
- only after deterministic matching fails
- only for borderline cases
- never on the client

Current backend behavior is already implemented and tested. This brief is for accelerating the next session, not redefining the system.

## Start Here

If the next agent has limited context, read these in this order:

1. `docs/ai-session-brief.md`
2. `docs/ai-prompt-spec.md`
3. `docs/ai-eval-dataset-guide.md`
4. `docs/ai-eval-review-sheet.md`

Open these only if needed:
- `docs/ai-evaluation-rubric.md`
- `docs/content-qa-b2-lesson-001.md`
- `docs/manual-ai-smoke-pack.md`
- `docs/ai-eval-dataset.v1.jsonl`

## Current AI Contract

Provider:
- OpenAI Responses API

Provider selection:
- `AI_PROVIDER=stub|openai`
- default is `stub`
- if `AI_PROVIDER=openai` but key is missing, backend falls back to `stub`

Model:
- current local default/pin: `gpt-4o-mini`

Invocation gate:
- answer must be non-empty
- deterministic match must fail
- answer must not equal the original incorrect prompt
- minimum Levenshtein distance must be `<= 3`
- answer length must be within `50%..200%` of the shortest accepted correction

Fallback behavior:
- timeout, malformed JSON, or provider failure -> deterministic incorrect

## What Is Already Prepared

### 0. Runtime safeguards in place

- **Sentence-correction gating is centralized** — `evaluateSentenceCorrectionDeterministic` in `backend/src/evaluators/sentenceCorrection.ts` is the single gate used by both the route and the evaluator. No duplicate logic.
- **AI result cache** — in-memory, keyed by `(session_id, exercise_id, normalizedAnswer)`. TTL 4h, LRU cap 10K. Repeat submissions with the same answer skip AI and rate-limit entirely.
- **Rate limiter** — sliding window, 10 AI calls per IP per 60s. Checked only after gate + cache miss.
- **XFF trust boundary** — XFF accepted only from loopback/RFC 1918 socket origin; rightmost entry used.
- **AI timeout** — 5s hard cap. Timeout or parse failure → `correct=false, evaluation_source=deterministic`.

### 1. Prompt and contract map

See:
- `docs/ai-prompt-spec.md`

Use this to avoid rediscovering:
- request shape
- output schema
- response handling
- smoke cases
- known implementation gaps

### 2. Shared rubric

See:
- `docs/ai-evaluation-rubric.md`

Use this to label cases as:
- `deterministic_accept`
- `deterministic_reject`
- `borderline_ai_accept`
- `borderline_ai_reject`
- `content_gap`

### 3. Content QA

See:
- `docs/content-qa-b2-lesson-001.md`

Key conclusion:
- the biggest likely weakness is not prompt quality first
- it is scoring fairness caused by narrow `accepted_corrections`

### 4. Eval dataset

See:
- `docs/ai-eval-dataset.v1.jsonl`
- `docs/ai-eval-dataset-guide.md`

Current dataset stats:
- 36 rows total
- 12 rows for each of the 3 `sentence_correction` fixtures
- includes deterministic baselines, borderline cases, and content-gap cases

### 5. Review workflow

See:
- `docs/ai-eval-review-sheet.md`
- `docs/ai-eval-review-sheet.template.csv`

Use this to record:
- actual verdicts
- actual evaluation source
- triage bucket
- final decision

### 6. Manual smoke pack

See:
- `docs/manual-ai-smoke-pack.md`

Use this for quick live checks after:
- prompt changes
- model changes
- threshold changes
- key rotation

## Frozen Policy: Teacher-List Is Authoritative

This question is resolved. The MVP policy is:

`sentence_correction` accepts only listed teacher-approved rewrites. Structural rewrites, even if grammatically correct and meaning-preserving, are correctly rejected unless explicitly listed in `accepted_corrections`.

Consequences:
- `content_gap` rows are expected behavior, not prompt or model failures
- prompt tuning does not change this; only content expansion does
- `content_gap` is an audit label for tracking future content-authoring decisions, not a defect queue

## Known Risks To Keep In Mind

1. `sentence_correction` accepted corrections are sparse — some valid learner answers will be rejected because they fall outside the teacher-defined list. This is expected behavior under the frozen policy; flagged as a content-expansion opportunity, not a bug.
2. Near-valid structural rewrites will not be rescued by AI; they are correctly gated out before AI is even considered.
3. Rate limiting is gated correctly — the rate-limit check runs only after deterministic match and cache miss both fail. Cached results and deterministic decisions never consume rate-limit budget.
4. There is no live-provider eval harness yet; only docs, dataset, and manual smoke tooling.

## Best Canary Rows

If the next session can evaluate only a few rows, start with:

| Case ID | Why |
|---|---|
| `sc18-06` | basic typo rescue |
| `sc19-12` | catches over-permissive acceptance |
| `sc1a-08` | exposes content-gap vs AI-gap confusion |

## Recommended Next Session Order

1. Confirm provider and model are correctly wired locally.
2. Run deterministic sanity checks first.
3. Run the canary rows.
4. Run all `ai_fallback` rows from the dataset.
5. Compare actual outcomes to `desired_human_correct`.
6. Fill the review sheet before changing anything.
7. Decide whether the main blocker is:
   - prompt
   - model
   - threshold
   - content policy

## What Not To Waste Time On

- re-deriving the AI contract from code
- debating exact-match deterministic cases
- treating every valid-but-rejected row as a prompt bug
- changing prompt and model simultaneously
- broad architecture discussion before the content-policy question is answered
