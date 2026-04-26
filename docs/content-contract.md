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

### 1.1 Intro Highlight Markup

`intro_rule` and `intro_examples` strings may use the `**slot**` markup to
mark the `variable_part` of a contrast (per `exercise_structure.md §2.8.1`
and `GRAM_STRATEGY.md §5.3.1`). The renderer keeps the `**…**` slot in a
distinct dusty-rose colour while the surrounding text stays neutral, so the
learner can see the changing slot before reading the explanation.

Rules:

- Markers are exactly two asterisks on each side: `**been + verb-ing**`.
- One marker pair per slot. Use sparingly — highlight only the minimum
  span that carries the contrast decision.
- The same slot must be wrapped in both the FORM block and the matching
  EXAMPLES so the learner sees the rule-to-example bridge.
- For paired contrast lines, write each pattern on its own line under the
  FORM (or IMPORTANT) header — the renderer stacks them vertically so the
  changing slots align like a diff.
- Do not nest markers, do not wrap whole sentences, do not highlight
  punctuation.

Authors who do not need a contrast highlight should leave the strings
unmarked; the parser falls back to a plain text rendering.

## 1.2 Learning Engine Metadata (Wave 1, additive)

Every `Exercise` may carry the optional engine metadata fields below. They
were introduced by `docs/plans/learning-engine-mvp-2.md` Wave 1 and are
additive — the runtime ignores them today, validates them at lesson-load
time, and passes them through unchanged on `GET /lessons/{lesson_id}` so
later waves (Mastery Model, Decision Engine, Transparency Layer) can
consume them.

```json
{
  "skill_id": "string (registry id, e.g. 'verbs.suggest_ing')",
  "primary_target_error": "conceptual_error | form_error | contrast_error | careless_error | transfer_error | pragmatic_error",
  "evidence_tier": "weak | medium | strong | strongest",
  "meaning_frame": "string (required only when evidence_tier == 'strongest')"
}
```

Rules:

- All four fields are **optional** during the Wave 1 backfill. New content
  authored after Wave 1 lands declares all four (per
  `LEARNING_ENGINE.md §§4.2, 5, 6.5`); pre-Wave-1 fixtures may be
  backfilled lazily.
- `skill_id` must reference an entry declared in the skills registry
  (`backend/data/skills.json`). The registry is the source of truth for
  the skill graph; see §10 below. This cross-reference is asserted by a
  CI test, not by `LessonSchema` itself, so registry-absent fixtures
  still load.
- `primary_target_error` must be one of the six codes in
  `LEARNING_ENGINE.md §5`.
- `evidence_tier` follows the four-tier hierarchy in
  `LEARNING_ENGINE.md §6.1`.
- `meaning_frame` is **required** when `evidence_tier == "strongest"`,
  per `LEARNING_ENGINE.md §6.3`. The schema rejects a strongest-tier item
  without a meaning_frame.
- The fields apply to all exercise families (`fill_blank`,
  `multiple_choice`, `sentence_correction`, `listening_discrimination`).

The fields are emitted on the wire by `GET /lessons/{lesson_id}` exactly
as authored — see `docs/backend-contract.md`.

## 2. Per-Type Exercise Schema

### 2.1 fill_blank

```json
{
  "exercise_id": "string (uuid)",
  "type": "fill_blank",
  "instruction": "string",
  "prompt": "string (contains exactly one `___` placeholder)",
  "accepted_answers": ["string"],
  "feedback": { "explanation": "string" }
}
```

- `instruction`: mandatory learner-facing direction that explains exactly what to do.
- `accepted_answers`: non-empty list; first entry is canonical answer.
- `prompt` must contain exactly one `___` token. No variations.

### 2.2 multiple_choice

```json
{
  "exercise_id": "string (uuid)",
  "type": "multiple_choice",
  "instruction": "string",
  "prompt": "string",
  "options": [
    { "id": "string (a|b|c|d)", "text": "string" }
  ],
  "correct_option_id": "string (a|b|c|d)",
  "feedback": { "explanation": "string" }
}
```

- `options`: 2–4 entries. No duplicate `id` values.
- `correct_option_id` must match exactly one entry in `options`.
- `instruction` should be concise and action-oriented, e.g. `Choose the correct option.`

### 2.3 sentence_correction

```json
{
  "exercise_id": "string (uuid)",
  "type": "sentence_correction",
  "instruction": "string",
  "prompt": "string (grammatically incorrect sentence)",
  "accepted_corrections": ["string"],
  "feedback": { "explanation": "string" }
}
```

- `accepted_corrections`: non-empty list of known-good corrections.
- `instruction` should clearly tell the learner to rewrite the sentence correctly.

### 2.4 listening_discrimination

```json
{
  "exercise_id": "string (uuid)",
  "type": "listening_discrimination",
  "instruction": "string",
  "audio": {
    "url": "string (path under /audio, e.g. /audio/u02-l01/q5.mp3)",
    "voice": "nova | onyx",
    "transcript": "string (exact spoken text)"
  },
  "options": [
    { "id": "string (a|b|c|d)", "text": "string (full plausible sentence)" }
  ],
  "correct_option_id": "string (a|b|c|d)",
  "image": "ExerciseImage (optional, see §2.5)",
  "feedback": { "explanation": "string" }
}
```

- `audio.url`: relative path served by the backend static-audio mount; the
  client resolves it against `API_BASE_URL`. Files must exist before the
  fixture ships (no broken URLs allowed in shipped lessons).
- `audio.voice`: enum, exactly `nova` (default warm female) or `onyx` (low
  calm male). One US accent. No other voices are supported in shipped
  lessons. See `exercise_structure.md §5.9` for voice-role guidance.
- `audio.transcript`: full and exact spoken text, character-for-character.
  Required even though it is hidden in the UI by default — used for the
  `Show transcript` reveal, accessibility, and QA review.
- `options`: 3-4 entries, each a complete sentence the learner could
  plausibly have heard. No fragments, no labelled forms.
- `correct_option_id` must match exactly one entry in `options` and must
  match the `transcript` semantically.
- there is no `prompt` field on this type; the audio is the prompt. The text
  shown on screen before listening is only the `instruction`.
- this type does **not** use AI evaluation. Scoring is exact id match against
  `correct_option_id`, identical to `multiple_choice`.

Authoring rules and distractor strategy: see `exercise_structure.md §5.9`.

### 2.5 ExerciseImage (optional, all exercise types)

Any exercise type may carry an optional `image` block per the Visual Context
Layer in `exercise_structure.md §2.9`. The shipped runtime fields are:

```json
{
  "image": {
    "url": "string (path under /images, e.g. /images/{lesson_id}/{exercise_id}.png)",
    "alt": "string (accessibility label, also used as failure-state caption)",
    "role": "scene_setting | context_support | disambiguation | listening_support",
    "policy": "optional | recommended | required"
  }
}
```

Authoring-only fields live inline alongside the runtime ones and are
stripped before the lesson endpoint responds:

```json
{
  "image": {
    "url": "...",
    "alt": "...",
    "role": "...",
    "policy": "...",
    "brief": "string (prompt for the gen-image pipeline)",
    "dont_show": "string (QA guard for the human reviewer; not sent to the model)",
    "risk": "low | medium | high"
  }
}
```

Rules:

- `image` is always optional. Omit it entirely when the exercise is
  text-only — the default `image_policy` is `none`, which is represented in
  JSON by the absence of the field.
- `url`: relative path served by the backend static-image mount. Files must
  exist before the fixture ships.
- `alt`: required and meaningful. Screen readers read this; the failure
  state surfaces it as the visible fallback.
- `role`: enum, exactly one. The role is authoring-only — the runtime does
  not change rendering based on role; the field exists so reviewers can
  judge whether the image fits the slot.
- `policy`: enum (`optional | recommended | required`). When `required`,
  shipping the lesson without the asset breaks the lesson, so the
  pre-merge QA must catch it.
- `brief` / `dont_show` / `risk` are pipeline metadata — see
  `docs/plans/roadmap.md` Workstream I and the gen-image script.
  Stripped before client response.

## 3. Attempt Payload Shape

Client → Backend:

```json
{
  "attempt_id": "string (uuid, client-generated)",
  "exercise_id": "string (uuid)",
  "exercise_type": "fill_blank|multiple_choice|sentence_correction|listening_discrimination",
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
  "explanation": "string|null",
  "canonical_answer": "string"
}
```

- `explanation`: user-facing rule explanation from the exercise's curated `feedback.explanation`.
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
- Default authoring mode is a narrow teacher-key answer set.
- Up to `3` accepted corrections may be listed only when the prompt naturally allows closely equivalent repairs of the same target structure.
- If more than `3` valid corrections are needed for fairness, the item is too open for the current runtime and must be rewritten or deferred.
- Corrections must be fully grammatically correct in the target language.
- Corrections differing only in punctuation or capitalization must be listed separately if both should be accepted (normalization handles case/boundary punctuation).
- Paraphrases that change meaning are not accepted corrections.
- Content authors are responsible for listing common correct rephrasings.

## 7. AI Fallback — sentence_correction Only

- Triggered only for `sentence_correction` when deterministic check fails.
- AI receives: original prompt, user's answer, list of `accepted_corrections`.
- AI returns: `{ "correct": bool, "feedback": string }`.
- AI decision is final for borderline cases.
- AI feedback is internal and not shown to the user; the learner still sees the exercise's curated explanation.
- If AI call fails (timeout, error): default to `correct=false`, `evaluation_source=deterministic`, `explanation` still comes from the exercise content.
- AI is never called for `fill_blank` or `multiple_choice`.

## 8. Summary Contract

| Exercise type       | Eval method           | AI used?                    |
|---------------------|-----------------------|-----------------------------|
| fill_blank          | Deterministic exact   | Never                       |
| multiple_choice     | Deterministic exact   | Never                       |
| sentence_correction | Deterministic first   | Fallback on mismatch only   |

## 9. Content Author Responsibilities

- Provide valid JSON matching schemas above.
- Include a concrete learner-facing `instruction` for every exercise.
- `fill_blank`: populate `accepted_answers` with all valid completions.
- `multiple_choice`: ensure exactly one `correct_option_id`; distractors must be plausible.
- `sentence_correction`: provide `prompt` with clear grammatical error; provide `accepted_corrections` covering most common valid corrections.
- Provide a concise, rule-specific `feedback.explanation` for every exercise. This text must explain the exact grammar point being tested.
- Do not include trick questions or ambiguous prompts.
- Flag any exercise where AI fallback is expected to be frequently needed (for review).
- Keep `prompt` strings under 300 characters.
- Do not use HTML or markdown inside `prompt`, `feedback.explanation`, or answer fields.
- For new content authored after Wave 1 lands: declare `skill_id`,
  `primary_target_error`, and `evidence_tier` per §1.2; declare
  `meaning_frame` whenever `evidence_tier == "strongest"`.

## 10. Skills Registry

The skills registry lives at `backend/data/skills.json` and is the source
of truth for the skill graph referenced by `Exercise.skill_id` (§1.2).
The backend loads the file on startup and validates it; an absent file is
treated as an empty registry during the Wave 1 rollout.

```json
{
  "version": "string (registry version tag, optional — provenance only)",
  "engine_spec_ref": "string (pointer into LEARNING_ENGINE.md, optional)",
  "notes": "string (authoring rationale, optional)",
  "skills": [
    {
      "skill_id": "string (stable identifier, e.g. 'verb-ing-after-gerund-verbs')",
      "title": "string (short human-readable name)",
      "description": "string (one-sentence rationale, optional)",
      "cefr_level": "A1 | A2 | B1 | B2 | C1 | C2",
      "prerequisites": ["string (skill_id of an earlier-mastered skill)"],
      "contrasts_with": ["string (skill_id of a sibling commonly confused with this one)"],
      "target_errors": ["conceptual_error | form_error | contrast_error | careless_error | transfer_error | pragmatic_error"],
      "mastery_signals": ["weak | medium | strong | strongest"],
      "lesson_refs": ["string (lesson_id where this skill is exercised)"]
    }
  ]
}
```

`skill_id` is a stable string. The shipped registry uses readable
kebab-case (`verb-ing-after-gerund-verbs`) but the schema does not
prescribe a separator — pick one form and stay consistent.

Validation rules (enforced at load time):

- `skill_id` must be unique within the registry.
- Every `prerequisites` and `contrasts_with` entry must reference a
  declared `skill_id`.
- A skill cannot list itself as its own prerequisite.
- `cefr_level`, `target_errors`, and `mastery_signals` use the closed
  enums declared above.
- `prerequisites`, `contrasts_with`, `target_errors`, `mastery_signals`,
  and `lesson_refs` default to `[]` when omitted.
- `description`, `version`, `engine_spec_ref`, and `notes` are optional
  authoring metadata; the runtime preserves them on parse but no current
  code path consumes them.

Cross-reference between an exercise's `skill_id` (§1.2) and the registry
is **not enforced by `LessonSchema` itself** — it is asserted by the
`skills registry cross-reference` test in
`backend/tests/skills-registry.test.ts`, which fails CI if a shipped
exercise references a `skill_id` that the registry does not declare. The
runtime tolerates registry absence (treats it as empty) so the loader
does not block boot before the file is authored.

The registry is consumed by future engine waves (Mastery Model, Decision
Engine). Wave 1 ships only the loader and validator — no runtime decision
yet depends on the registry contents.
