# AI Prompt Spec — Mastery MVP

**Status:** Preparation artifact for the next AI-focused session.  
**Last updated:** 2026-04-20

## Purpose

This document freezes the current AI contract and prompt behavior so the next implementation session does not need to re-derive it from code.

Current source of truth in code:
- `backend/src/ai/openai.ts`
- `backend/src/ai/interface.ts`
- `backend/src/evaluators/sentenceCorrection.ts`
- `backend/src/schemas.ts`

## Scope

AI is used only for `sentence_correction` exercises after deterministic matching fails and only when the answer is classified as borderline.

AI is never used for:
- `fill_blank`
- `multiple_choice`
- non-borderline `sentence_correction`

## Runtime Selection

Provider selection is environment-driven:

```env
AI_PROVIDER=stub|openai
OPENAI_API_KEY=...
OPENAI_MODEL=gpt-4o-mini
OPENAI_BASE_URL=https://api.openai.com/v1
```

Current behavior:
- default provider is `stub`
- if `AI_PROVIDER=openai` but `OPENAI_API_KEY` is missing, backend falls back to `stub`

## AI Invocation Gate

The OpenAI provider should be called only when all conditions hold:

1. normalized user answer is non-empty
2. normalized user answer does not exactly match any accepted correction
3. normalized user answer is not identical to the original incorrect prompt
4. minimum Levenshtein distance to accepted corrections is `<= 3`
5. normalized user answer length is within `50%..200%` of the shortest accepted correction

If any condition fails, the result must remain deterministic.

## Provider Interface

Current provider contract:

```ts
type AiEvaluationArgs = {
  exercisePrompt: string;
  acceptedCorrections: string[];
  userAnswer: string;
  signal?: AbortSignal;
};

type AiEvaluationResult = {
  correct: boolean;
  feedback: string;
};
```

## Current OpenAI Request Shape

Transport:
- endpoint: `POST /responses`
- auth: bearer token
- response format: strict JSON schema

Prompt intent:
- model acts as a strict evaluator, not a tutor
- `correct=true` only for meaning-preserving and grammar-valid corrections
- only minor typo and punctuation differences may be accepted
- output must be JSON only

Structured output schema:

```json
{
  "type": "object",
  "properties": {
    "correct": { "type": "boolean" },
    "feedback": { "type": "string" }
  },
  "required": ["correct", "feedback"],
  "additionalProperties": false
}
```

## Response Handling

Current backend expectations:
- valid JSON object with `correct:boolean` and `feedback:string`
- if `feedback` is longer than 80 chars, it is truncated
- if the model refuses, backend treats the answer as `correct=false`
- if the response is malformed, empty, timed out, or request fails, backend falls back to deterministic incorrect

## Prompt Rubric For Future Changes

Any future prompt revision should preserve these rules unless explicitly changed in spec:

- accept only grammar-correct corrections
- accept minor typos when the corrected meaning still matches an accepted correction
- reject paraphrases that change meaning
- reject structural rewrites not in the accepted corrections list, even if the rewrite is grammatically valid and meaning-preserving
- reject answers that keep the original grammar mistake
- keep feedback short and non-conversational
- never emit explanations outside JSON

## Smoke Cases To Re-Run After Any AI Change

Use these before changing model, prompt, or fallback thresholds:

1. exact accepted correction -> deterministic correct, no AI
2. capitalization-only difference -> deterministic correct, no AI
3. trailing punctuation difference -> deterministic correct, no AI
4. original incorrect prompt resubmitted -> deterministic incorrect, no AI
5. one-character typo near accepted correction -> AI path should trigger
6. clearly unrelated sentence -> deterministic incorrect, no AI
7. model timeout -> deterministic incorrect
8. malformed model JSON -> deterministic incorrect
9. refusal response -> incorrect without crashing
10. oversized feedback -> verdict preserved, feedback truncated

## Known Gaps Worth Addressing Later

These are not documentation tasks; they are queued implementation concerns:

- route-level AI rate limiting currently happens before proving AI is needed
- no live-provider smoke test against a real OpenAI key
- no reusable eval harness yet
- no token/latency logging
- prompt is hardcoded in code rather than versioned separately

## Suggested Next Session Order

1. run local smoke cases with real OpenAI provider
2. score prompt against eval dataset template
3. compare one alternative model only if baseline quality is insufficient
4. decide whether to move prompt text into a versioned asset
