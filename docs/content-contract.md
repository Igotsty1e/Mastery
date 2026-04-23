# Content Contract — Roundups AI Assistant MVP

## 1. Canonical Lesson Schema

```json
{
  "lesson_id": "string (uuid)",
  "title": "string",
  "language": "string (BCP-47, e.g. 'en')",
  "level": "string (A1|A2|B1|B2|C1|C2)",
  "intro_rule": "string (short grammar/vocabulary rule, shown before exercises)",
  "intro_examples": ["string (2–3 illustrative examples of the rule)"],
  "exercises": ["Exercise"]
}
```

## 2. Per-Type Exercise Schema

### 2.1 fill_blank

```json
{
  "exercise_id": "string (uuid)",
  "type": "fill_blank",
  "prompt": "string (contains exactly one `___` placeholder)",
  "accepted_answers": ["string"],
  "hint": "string|null"
}
```

- `accepted_answers`: non-empty list; first entry is canonical answer.
- `prompt` must contain exactly one `___` token. No variations.

### 2.2 multiple_choice

```json
{
  "exercise_id": "string (uuid)",
  "type": "multiple_choice",
  "prompt": "string",
  "options": [
    { "id": "string (a|b|c|d)", "text": "string" }
  ],
  "correct_option_id": "string (a|b|c|d)"
}
```

- `options`: 2–4 entries. No duplicate `id` values.
- `correct_option_id` must match exactly one entry in `options`.

### 2.3 sentence_correction

```json
{
  "exercise_id": "string (uuid)",
  "type": "sentence_correction",
  "prompt": "string (grammatically incorrect sentence)",
  "accepted_corrections": ["string"],
  "borderline_ai_fallback": true
}
```

- `accepted_corrections`: non-empty list of known-good corrections.
- `borderline_ai_fallback`: always `true` for this type.

## 3. Attempt Payload Shape

Client → Backend:

```json
{
  "attempt_id": "string (uuid, client-generated)",
  "exercise_id": "string (uuid)",
  "exercise_type": "fill_blank|multiple_choice|sentence_correction",
  "user_answer": "string",
  "submitted_at": "string (ISO 8601 UTC)"
}
```

Backend → Client:

```json
{
  "attempt_id": "string",
  "exercise_id": "string",
  "correct": true,
  "evaluation_source": "deterministic|ai_fallback",
  "feedback": "string|null",
  "canonical_answer": "string"
}
```

- `feedback`: null when `correct=true` and no AI was used.
- `canonical_answer`: always the first entry from `accepted_answers` or `accepted_corrections`.

## 4. Normalization Rules

Applied by backend before comparison. Order is fixed.

1. Unicode NFC normalization.
2. Trim leading and trailing whitespace.
3. Collapse internal whitespace runs to single space.
4. Lowercase all characters.
5. Strip punctuation: `. , ! ? ; : ' "` at string boundaries only (not mid-word apostrophes).

Normalization applies to both `user_answer` and each entry in `accepted_answers` / `accepted_corrections`.

Example:
- Raw user input: `"  It's A Cat. "` → normalized: `"it's a cat"`
- Stored answer: `"It's a cat."` → normalized: `"it's a cat"`
- Result: match.

## 5. Acceptable Answers Policy

### fill_blank

- Match succeeds if normalized `user_answer` equals any normalized entry in `accepted_answers`.
- Comparison is exact after normalization. No fuzzy match.
- Content authors must enumerate all acceptable answers explicitly.

### multiple_choice

- Match succeeds if `user_answer` equals `correct_option_id` (case-insensitive, trimmed).
- No normalization beyond trim + lowercase on the option id.

### sentence_correction

- Step 1 (deterministic): match succeeds if normalized `user_answer` equals any normalized entry in `accepted_corrections`.
- Step 2 (AI fallback): invoked only when step 1 fails. See Section 7.

## 6. Accepted Corrections Policy

- Content authors must provide at least one accepted correction per `sentence_correction` exercise.
- Corrections must be fully grammatically correct in the target language.
- Corrections differing only in punctuation or capitalization must be listed separately if both should be accepted (normalization handles case/boundary punctuation).
- Paraphrases that change meaning are not accepted corrections.
- Content authors are responsible for listing common correct rephrasings.

## 7. AI Fallback — sentence_correction Only

- Triggered only for `sentence_correction` when deterministic check fails.
- AI receives: original prompt, user's answer, list of `accepted_corrections`.
- AI returns: `{ "correct": bool, "feedback": string }`.
- AI decision is final for borderline cases.
- If AI call fails (timeout, error): default to `correct=false`, `evaluation_source=deterministic`, `feedback=null`.
- AI is never called for `fill_blank` or `multiple_choice`.

## 8. Summary Contract

| Exercise type       | Eval method           | AI used?                    |
|---------------------|-----------------------|-----------------------------|
| fill_blank          | Deterministic exact   | Never                       |
| multiple_choice     | Deterministic exact   | Never                       |
| sentence_correction | Deterministic first   | Fallback on mismatch only   |

## 9. Content Author Responsibilities

- Provide valid JSON matching schemas above.
- `fill_blank`: populate `accepted_answers` with all valid completions.
- `multiple_choice`: ensure exactly one `correct_option_id`; distractors must be plausible.
- `sentence_correction`: provide `prompt` with clear grammatical error; provide `accepted_corrections` covering most common valid corrections.
- Do not include trick questions or ambiguous prompts.
- Flag any exercise where AI fallback is expected to be frequently needed (for review).
- Keep `prompt` strings under 300 characters.
- Do not use HTML or markdown inside `prompt`, `hint`, or answer fields.
