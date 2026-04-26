# Mastery — Roundups AI Assistant

Flutter app for structured English practice (web runnable locally; iOS/Android pending native toolchain). Fixed lessons, deterministic evaluation, minimal AI.

## What it is

Users complete lessons composed of exercises. The backend decides correctness. AI is used only for borderline `sentence_correction` cases and a short post-lesson debrief. The shipped UX is anonymous; exercise progress (completed count) is stored locally on-device via SharedPreferences.

The backend ships an auth & identity foundation (Drizzle ORM, opaque refresh-token sessions, hard-delete) staged for a future client wave — see [`docs/plans/auth-foundation.md`](docs/plans/auth-foundation.md). The Flutter client is **not** wired to it yet.

## Key constraints

- Flutter (Dart) client only
- Backend is single source of truth for all correctness decisions
- 4 exercise types: `fill_blank`, `multiple_choice`, `sentence_correction`, `listening_discrimination` (multi-unit families gated on Wave 6)
- Deterministic evaluation for all types; AI fallback only for `sentence_correction` borderline cases
- Default linear lesson flow with the `LEARNING_ENGINE.md §9.1` 1/2/3 in-session loop layered on top — the Decision Engine may pull a same-skill item to the head after a wrong answer; on the third miss it ends the loop on that skill for the session
- Per-skill mastery state + cross-session review cadence are device-scoped today (`LearnerSkillStore` + `ReviewScheduler` shipped in Waves 2–3); server-side migration lives in `docs/plans/auth-server-state-wave7.md` Wave 7
- Backend auth foundation (Apple stub + refresh tokens + server-owned lesson sessions) is shipped; Flutter client wiring is Wave 7.4. No chat UI, no resume mid-session.

## Stack

- Client: Flutter (Dart)
- Backend: Node.js + TypeScript + Express (`backend/`)
- AI: OpenAI Responses API, server-side only (`AI_PROVIDER=openai`; stub default for local dev)
- Lesson content: JSON fixtures in `backend/data/` (manifest + per-lesson files)

## Documentation

The full doc map lives in [`docs/README.md`](docs/README.md). It groups every active document by purpose (canon / contracts / plans / authoring / references / history) and is the single place to update when files are added, renamed, or archived.

Repo-root canon, in load order:

- [`CLAUDE.md`](CLAUDE.md) — agent operating rules + doc-maintenance rule
- [`DESIGN.md`](DESIGN.md) — visual canon
- [`GRAM_STRATEGY.md`](GRAM_STRATEGY.md) — pedagogy canon
- [`exercise_structure.md`](exercise_structure.md) — exercise authoring canon
- [`LEARNING_ENGINE.md`](LEARNING_ENGINE.md) — target-state engine canon (skill graph, evidence model, mastery model, decision engine, transparency layer); migration in [`docs/plans/learning-engine-mvp-2.md`](docs/plans/learning-engine-mvp-2.md)

Everything else lives under `docs/` — start at [`docs/README.md`](docs/README.md).

Current active design wave after the shipped onboarding/home pass:
- [`docs/plans/dashboard-study-desk.md`](docs/plans/dashboard-study-desk.md) — next `HomeScreen` redesign handoff
- [`docs/design-mockups/dashboard-study-desk.html`](docs/design-mockups/dashboard-study-desk.html) — visual prototype for that wave
