# AI Evaluation Rubric — Mastery MVP

**Status:** Local working rubric for future AI and content review sessions.  
**Last updated:** 2026-04-20

## Purpose

This rubric defines how to judge borderline `sentence_correction` answers without re-arguing the same standards in each session.

It is not a runtime spec and does not change the current implementation. It is a decision aid for:
- prompt review
- eval dataset labeling
- false positive / false negative triage
- content author QA

## Decision Order

Label answers in this order:

1. `deterministic_accept`
2. `deterministic_reject`
3. `borderline_ai_accept`
4. `borderline_ai_reject`
5. `content_gap`

If a case clearly belongs earlier in the list, do not escalate it to a later label.

## Labels

### `deterministic_accept`

Use when the answer should pass through exact normalized matching alone.

Typical properties:
- same wording as an accepted correction after normalization
- only differences are case, surrounding whitespace, or boundary punctuation

Examples:
- `She has been working at this company for ten years`
- `  She has been working at this company for ten years.  `

### `deterministic_reject`

Use when the answer is clearly wrong and AI should not be needed.

Typical properties:
- original error remains uncorrected
- meaning changes materially
- grammar is still clearly broken
- answer is empty or unrelated

Examples:
- `She has been working at this company since ten years.`
- `She works there and likes her job.`
- ``

### `borderline_ai_accept`

Use when deterministic matching fails, but the answer is still acceptable and the difference is minor enough that AI may rescue it.

Typical properties:
- one minor typo
- punctuation-only noise that escaped deterministic match
- tiny surface variation with preserved meaning and correct grammar

Examples:
- `She has been working at this company fo ten years.`
- `The advice she gave me was very usefull.`

### `borderline_ai_reject`

Use when the answer is close in surface form but still should be rejected.

Typical properties:
- sentence remains ungrammatical
- one part is corrected but another grammar error remains
- answer is close enough to tempt a weak model, but should still be marked wrong

Examples:
- `If I had study more, I would have passed the exam.`
- `The advice she gave me were very useful.`

### `content_gap`

Use when the learner answer is arguably valid English for the exercise, but current content and AI policy will reject it because it falls outside the teacher-defined accepted corrections.

Typical properties:
- valid rephrasing with preserved meaning
- grammar is correct
- not listed in accepted corrections
- likely too far from accepted wording to trigger AI fallback

Examples:
- `Her advice was very useful.` (structural rewrite, removes relative clause)
- `If I had studied more, I could have passed the exam.` (meaning-shift on modal, outside teacher list)

`content_gap` is not an AI failure first. It is a labeling category for audit purposes.

Under the MVP teacher-list policy, `content_gap` cases are **correctly rejected** — the accepted corrections list is the authoritative scope, not arbitrary grammar validity or meaning preservation. These cases are tracked to inform future content-authoring decisions, not as defects requiring a fix.

## What Counts As A Minor Error

Usually acceptable for `borderline_ai_accept`:
- one-character typo
- duplicated or omitted letter
- obvious misspelling that does not create a new grammar error
- tiny punctuation defect

Usually not acceptable:
- wrong verb form
- wrong tense after an auxiliary
- subject-verb disagreement
- changed preposition when it changes correctness
- changed lexical meaning

## Meaning Preservation Rule

An answer should be rejected if it changes the instructional target or sentence meaning, even if the grammar is clean.

Reject when:
- the time meaning changes
- the conditional meaning changes
- the noun countability issue disappears by replacing the noun entirely
- a different statement is produced instead of a correction

## Content-Gap Heuristics

Flag a case as `content_gap` when all are true:

1. the answer is grammatical
2. the core meaning is preserved
3. the answer is not just a typo-level variation
4. current deterministic list is too narrow to accept it
5. current borderline gate is unlikely to reach AI

## Review Questions For Borderline Cases

Ask these in order:

1. Is the final sentence grammatical?
2. Does it preserve the original meaning?
3. Is the learner clearly correcting the target error rather than rewriting the task?
4. Is the difference minor enough that AI rescue is appropriate?
5. If the answer is valid but far from accepted corrections, is this actually a content gap?

## Triage Outcomes

When reviewing a failure, assign one of:
- `prompt_issue`
- `model_issue`
- `threshold_issue`
- `content_issue`
- `expected_behavior`

Default bias:
- near-valid but rejected far from accepted wording -> `content_issue`
- clearly wrong but accepted -> `prompt_issue` or `model_issue`
- too many far answers reaching AI -> `threshold_issue`
- exact normalized answer accepted deterministically -> `expected_behavior`
