# Design: English Practice MVP

**Status:** Approved  
**Date:** 2026-04-17  
**Canonical spec:** `docs/approved-spec.md`

---

## Problem

Adult learners need structured English correction — not open conversation, not gamified drills. This app removes noise: exercise → answer → feedback → next.

## What it is

Fixed-flow English practice. Ten or more exercises per lesson. Backend decides correctness. AI explains why, only when needed.

## What it is not

No chat. No streaks. No levels. No adaptive reordering. No accounts. No resume. One sentence: task → backend judges → client shows result.

## Constraints (non-negotiable)

- Flutter client only
- Backend authority: client never evaluates answers
- Exactly 3 exercise types: `fill_blank`, `multiple_choice`, `sentence_correction`
- Deterministic evaluation first for all types
- AI fallback only for `sentence_correction` borderline cases (Levenshtein ≤ 3 from nearest accepted answer)
- Linear lesson flow — no back, no skip, no branching
- Score shown on Lesson Complete screen (raw X / N)
- No auth, no persistence, no gamification of any kind

## Exercise types

| Type | Eval method | AI? |
|---|---|---|
| `fill_blank` | Deterministic exact match (normalized) | Never |
| `multiple_choice` | Deterministic option ID match | Never |
| `sentence_correction` | Deterministic first; AI fallback on borderline miss | Borderline only |

Normalization: Unicode NFC → trim → collapse whitespace → lowercase → strip boundary punctuation.

## Lesson flow

```
Lesson Start
  → Exercise (repeat for each)
      → User submits answer
      → Backend evaluates → returns correct/incorrect + feedback
      → Client shows result
      → User taps Next
  → Lesson Complete
      → Score: X / N
      → Done → exit
```

No timers. No retry. No skip. No back.

## AI usage

AI is called server-side only, never from client. Called only for `sentence_correction` when deterministic check fails and all borderline criteria pass:
1. Normalized answer not in `accepted_corrections[]`
2. Levenshtein distance to nearest accepted answer ≤ 3
3. Submission length between 50% and 200% of shortest accepted answer

AI returns `{ "correct": bool, "feedback": string (max 80 chars) }`. On timeout (5s) or error: default to `correct=false`, no AI feedback.

## Out of scope (MVP)

Auth, persistence, resume, adaptive learning, branching, chat UI, gamification, hints, offline mode, push notifications, lesson authoring, analytics, AI-generated content, more than 3 exercise types.
