# Mastery — Roundups AI Assistant

Flutter app for structured English practice (web runnable locally; iOS/Android pending native toolchain). Fixed lessons, deterministic evaluation, minimal AI.

## What it is

Users complete lessons composed of exercises. The backend decides correctness. AI is used only for borderline `sentence_correction` cases and a short post-lesson debrief. No accounts, no server-side persistence, no gamification. Exercise progress (completed count) is stored locally on-device via SharedPreferences.

## Key constraints

- Flutter (Dart) client only
- Backend is single source of truth for all correctness decisions
- 4 exercise types: `fill_blank`, `multiple_choice`, `sentence_correction`, `listening_discrimination`
- Deterministic evaluation for all types; AI fallback only for `sentence_correction` borderline cases
- Fixed linear lesson flow — no skipping, no backtracking, no branching
- No auth, no resume, no adaptive learning, no chat UI

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

Everything else lives under `docs/` — start at [`docs/README.md`](docs/README.md).
