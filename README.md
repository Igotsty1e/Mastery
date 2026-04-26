# Mastery — Roundups AI Assistant

Flutter app for structured English practice (web runnable locally; iOS/Android pending native toolchain). Fixed lessons, deterministic evaluation, minimal AI.

## What it is

Users complete lessons composed of exercises. The backend decides correctness. AI is used only for borderline `sentence_correction` cases. No accounts, no server-side persistence, no gamification. Exercise progress (completed count) is stored locally on-device via SharedPreferences.

## Key constraints

- Flutter (Dart) client only
- Backend is single source of truth for all correctness decisions
- Exactly 3 exercise types: `fill_blank`, `multiple_choice`, `sentence_correction`
- Deterministic evaluation for all types; AI fallback only for `sentence_correction` borderline cases
- Fixed linear lesson flow — no skipping, no backtracking, no branching
- No auth, no resume, no adaptive learning, no chat UI

## Docs — active source of truth

The list below is the active doc map. Anything not listed here lives in `docs/archive/` and is historical only — see `docs/archive/README.md`.

### Product + system contracts

| Document | Purpose |
|---|---|
| `docs/approved-spec.md` | Canonical product spec — system boundaries, exercise types, lesson flow, evaluation policy, non-goals |
| `docs/backend-contract.md` | API endpoints, evaluation logic, AI integration, debrief generation, CORS, error codes |
| `docs/mobile-architecture.md` | Flutter app structure, screens, state, data classes |
| `docs/content-contract.md` | Lesson + exercise JSON schemas, normalization rules, accepted-answers policy |
| `docs/qa-golden-cases.md` | Acceptance test cases across all exercise types |

### Pedagogy + content authoring

| Document | Purpose |
|---|---|
| `GRAM_STRATEGY.md` | Top-level pedagogy: how Mastery teaches grammar and usage |
| `exercise_structure.md` | Canonical rules for exercise design, sequencing, runtime mapping |
| `docs/content-unit-u01-blueprint.md` | Active unit-level authoring plan for the next shippable grammar unit |
| `docs/implementation-scope.md` | Next-step roadmap for audio, exercise expansion, screens, and tooling |

### Visual + UX

| Document | Purpose |
|---|---|
| `DESIGN.md` | Canonical design system: visual language, colors, typography, components, motion |
| `docs/design-mockups/` | Canonical visual composition reference for shipped screen layouts |
| `docs/onboarding-first-exercise-arrival-ritual.md` | Approved next-wave UI contract: 3-step onboarding + first-exercise V2 |

### Project root

| Document | Purpose |
|---|---|
| `CLAUDE.md` | Agent operating rules, deploy config, doc-maintenance rule |
| `README.md` | This file — orientation + doc map |

### Archived

`docs/archive/` — historical AI-eval prep artifacts, MVP planning briefs, superseded architecture diagrams. See `docs/archive/README.md` for the inventory.

## Stack

- Client: Flutter (Dart)
- Backend: Node.js + TypeScript + Express (`backend/`)
- AI: OpenAI Responses API, server-side only (`AI_PROVIDER=openai`; stub default for local dev)
- Lesson content: JSON fixtures in `backend/data/` (manifest + per-lesson files)
