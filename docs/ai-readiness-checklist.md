# AI Readiness Checklist — Mastery MVP

**Status:** Local preparation checklist for the next AI-focused session.  
**Last updated:** 2026-04-20

## Goal

Reduce token waste and decision churn before touching AI behavior, prompt wording, model choice, or fallback thresholds.

## Ready Now

- AI scope is already constrained to `sentence_correction` only
- provider abstraction exists
- deterministic gate exists before AI
- timeout path exists
- malformed response path exists
- tests already cover the main AI control-flow cases

## Prepare Before Editing AI Logic

- confirm whether the next session is allowed to change prompt text only, or also thresholds
- have a real OpenAI API key available locally if live testing is expected
- decide one baseline model to test first
- agree on pass/fail criteria for borderline answers
- use the eval dataset template instead of ad hoc manual prompts

## Local Setup Checklist

- backend dependencies installed
- `.env` or shell env ready with `AI_PROVIDER=openai`
- `OPENAI_API_KEY` present
- optional `OPENAI_MODEL` explicitly pinned
- optional `OPENAI_BASE_URL` set only if testing against a proxy or compatible endpoint

## Validation Order

1. Run deterministic/backend tests first.
2. Run existing AI unit tests.
3. Run a small live smoke pass with 3-5 eval rows only.
4. Review false positives before reviewing false negatives.
5. Change one variable at a time: prompt or model or threshold, never all at once.

## Minimum Smoke Pass

- one exact deterministic match
- one original-prompt resubmission
- one near typo that should be accepted
- one near typo that should still be rejected
- one clearly unrelated answer

## Evidence To Save From The Next Session

- exact prompt version used
- exact model used
- raw model JSON for failures
- whether failure was false positive or false negative
- final decision: prompt change, model change, or no change

## Stop Conditions

Stop and document instead of continuing if any of these happen:

- prompt changes improve one case but noticeably worsen another accepted baseline
- model output stops following strict JSON reliably
- a threshold change starts moving clearly non-borderline cases into the AI path
- the team has not agreed what counts as an acceptable typo versus a real grammar error

## Out Of Scope For This Checklist

- architecture redesign
- runtime telemetry implementation
- provider migration
- production rollout plan
- UI changes around AI feedback
