# Strategic Decisions — Roundups AI Assistant MVP

**Status:** Locked. Changes require spec amendment to `docs/approved-spec.md`.  
**Date:** 2026-04-17

---

## Locked Decisions

### Client framework: Flutter (Dart)
Single codebase targeting iOS and Android. No separate web app, no React Native. Flutter web target is used for local development only (`flutter run -d chrome`); it is not a production target. Not revisitable.

### Backend authority: server is sole evaluator
Client never computes correctness. Client never stores `accepted_answers`, `accepted_corrections`, or `correct_option_id`. Server responses are final.

### Exactly 3 exercise types
`fill_blank`, `multiple_choice`, `sentence_correction`. No additions in MVP.

### Evaluation order: deterministic first, AI never first
1. Deterministic match (always)
2. AI fallback (`sentence_correction` borderline only)
3. Default incorrect (AI timeout/error)

AI is never called for `fill_blank` or `multiple_choice`.

### AI scope: `sentence_correction` borderline only, server-side only
Triggered only when all three conditions hold:
1. Deterministic match failed
2. Levenshtein distance to nearest accepted correction ≤ 3
3. Submission length 50%–200% of shortest accepted correction

AI timeout = 5s. On timeout or error: `correct=false`, no feedback.

### Lesson flow: linear, no branching
No back. No skip. No adaptive reordering. No retry. No timers.

### No persistence beyond current session
No auth. No accounts. No resume. No local storage (SharedPreferences, SQLite, etc.). `LessonSession` discarded on exit.

### No gamification of any kind
No streaks, badges, points, levels, leaderboards.

---

## Open Questions (Must Resolve Before Gate 1)

| # | Question | Status |
|---|---|---|
| 1 | Lesson content source: hardcoded JSON, seeded DB, or CMS? | Resolved — JSON fixtures in `backend/data/` |
| 2 | Session model: stateless per-visit or lightweight session ID? | Resolved — client-generated `session_id` UUID; backend stores attempts in-memory keyed by `session_id:lesson_id`; no cross-session persistence |
| 3 | LLM provider for AI fallback? | Resolved — OpenAI Responses API (`AI_PROVIDER=openai`); `StubAiProvider` default for local dev |
| 4 | Empty input handling: treat as incorrect immediately (skip all evaluation)? | Confirmed — yes |

---

## Out of Scope (MVP)

Auth, persistence, resume, adaptive learning, branching, chat UI, gamification, hints, offline mode, push notifications, lesson authoring, analytics, AI-generated content, more than 3 exercise types.

Full list: `docs/approved-spec.md` §8.
