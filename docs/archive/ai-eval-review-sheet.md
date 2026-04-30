# AI Eval Review Sheet — Session Template

**Dataset:** `docs/ai-eval-dataset.v1.jsonl`  
**Companion guide:** `docs/ai-eval-dataset-guide.md`  
**Rubric:** `docs/ai-evaluation-rubric.md`  
**Status:** Review template for the synthetic in-repo eval fixture.  
**Last updated:** 2026-04-20

## Purpose

Use this sheet during the next AI-focused session to record what actually happened on the eval dataset and separate:
- prompt/model failures
- threshold failures
- content gaps
- expected behavior

This sheet is intentionally operational. It is for review, not for changing the product spec.

The companion dataset is synthetic and safe to keep in the repository.
Do not append real learner data to it.

## Session Header

Fill this once per eval run:

| Field | Value |
|---|---|
| Date | |
| Operator | |
| Backend port | |
| Provider | |
| Model | |
| Prompt version | |
| Dataset version | `ai-eval-dataset.v1.jsonl` |
| Notes | |

## Run Order

1. Run deterministic rows first.
2. Run `ai_fallback` rows second.
3. Review all rows where actual behavior differs from `desired_human_correct`.
4. Split mismatches into `prompt_issue`, `model_issue`, `threshold_issue`, `content_issue`, or `ops_issue`.

## Summary Metrics

Fill this after the run:

| Metric | Value |
|---|---|
| Total rows run | 36 |
| Deterministic rows correct | |
| AI-fallback rows correct vs desired human label | |
| False positives | |
| False negatives | |
| Content-gap rows confirmed | |
| Suspected prompt issues | |
| Suspected model issues | |
| Suspected threshold issues | |
| Ops/setup issues | |

## Decision Rules

Use these default interpretations:

- actual result matches `expected_current_correct` and `desired_human_correct` -> `expected_behavior`
- actual result matches current runtime but conflicts with desired human judgment on a `content_gap` row -> `content_issue`
- actual result is too permissive on a `borderline_ai_reject` row -> `prompt_issue` or `model_issue`
- actual result is too strict on a `borderline_ai_accept` row -> `prompt_issue` or `model_issue`
- far answers reaching AI unexpectedly -> `threshold_issue`
- malformed responses, auth failures, rate limit noise, provider fallback confusion -> `ops_issue`

## Detailed Review Table

Record only rows that need discussion. Do not waste time filling every green row manually unless needed.

| Case ID | Rubric Label | Expected Current | Desired Human | Actual Correct | Actual Source | Review Bucket | Decision |
|---|---|---:|---:|---:|---|---|---|
| sc18-06 | borderline_ai_accept | true | true | | | | |
| sc18-07 | borderline_ai_accept | true | true | | | | |
| sc18-11 | borderline_ai_reject | false | false | | | | |
| sc19-07 | borderline_ai_reject | false | false | | | | |
| sc19-11 | borderline_ai_reject | false | false | | | | |
| sc19-12 | borderline_ai_reject | false | false | | | | |
| sc1a-06 | borderline_ai_accept | true | true | | | | |
| sc1a-07 | borderline_ai_reject | false | false | | | | |
| sc1a-08 | content_gap | false | false | | | | |
| sc1a-10 | borderline_ai_reject | false | false | | | | |

## Triage Notes

### Prompt issues

List rows where the model read the task incorrectly or applied the wrong acceptance standard.

| Case ID | Problem | Suggested follow-up |
|---|---|---|
| | | |

### Model issues

List rows where the prompt seems adequate but model behavior is unstable or weak.

| Case ID | Problem | Suggested follow-up |
|---|---|---|
| | | |

### Threshold issues

List rows where the wrong cases are entering or skipping the AI path because of gating.

| Case ID | Problem | Suggested follow-up |
|---|---|---|
| | | |

### Content issues

List rows where current accepted corrections are too narrow for product intent.

| Case ID | Problem | Suggested follow-up |
|---|---|---|
| | | |

### Ops issues

List rows blocked by setup, keys, rate limits, provider fallback, or malformed outputs.

| Case ID | Problem | Suggested follow-up |
|---|---|---|
| | | |

## Final Decision Block

Answer these at the end of the session:

| Question | Answer |
|---|---|
| Should prompt wording change? | |
| Should model change? | |
| Should thresholds change? | |
| Is the main blocker content quality instead of AI quality? | |
| Which 3 rows are the best regression canaries for next time? | |

## Recommended Canary Rows

If you need only three rows for fast regression checks, start with:

| Case ID | Why it matters |
|---|---|
| `sc18-06` | Basic typo rescue on a common learner error |
| `sc19-12` | Surface-near but still ungrammatical; catches over-permissiveness |
| `sc1a-08` | Structural rewrite correctly rejected under teacher-list policy — confirms expected_behavior |
