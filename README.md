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

## Docs

| Document | Purpose |
|---|---|
| `DESIGN.md` | Canonical design system: visual language, colors, typography, components |
| `docs/design-mockups/` | Canonical visual composition reference for the shipped screen layouts |
| `GRAM_STRATEGY.md` | Top-level pedagogy: how Mastery teaches grammar and usage |
| `exercise_structure.md` | Canonical rules for exercise design, sequencing, runtime mapping, and examples |
| `docs/content-unit-u01-blueprint.md` | Active lesson-authoring plan for the next shippable grammar unit |
| `docs/approved-spec.md` | Canonical product spec (source of truth) |
| `docs/content-contract.md` | Exercise schemas, normalization rules, AI contract |
| `docs/qa-golden-cases.md` | Acceptance test cases for all exercise types |
| `docs/system-architecture.md` | Component layout and data flow |
| `docs/backend-contract.md` | API endpoints, evaluation logic, AI integration |
| `docs/mobile-architecture.md` | Flutter app structure, screens, state |
| `docs/execution-brief.md` | Build order and acceptance gates |
| `docs/strategic-decisions.md` | Decisions made and what is locked |
| `docs/ai-session-brief.md` | One-page handoff brief for the next AI-focused session |
| `docs/ai-prompt-spec.md` | Frozen map of current AI prompt behavior and smoke cases |
| `docs/ai-eval-dataset.template.jsonl` | Seed eval dataset for future prompt/model checks |
| `docs/ai-eval-dataset.v1.jsonl` | Expanded sentence_correction eval dataset for the current lesson |
| `docs/ai-eval-dataset-guide.md` | How to interpret current-vs-human labels in the eval dataset |
| `docs/ai-eval-review-sheet.md` | Manual review sheet for future AI eval sessions |
| `docs/ai-eval-review-sheet.template.csv` | CSV companion for recording AI eval results |
| `docs/ai-readiness-checklist.md` | Pre-flight checklist for the next AI-focused session |
| `docs/ai-evaluation-rubric.md` | Shared labeling rubric for borderline AI/content decisions |
| `docs/content-qa-b2-lesson-001.md` | QA review of the current lesson content and scoring fairness risks |
| `docs/manual-ai-smoke-pack.md` | Manual local smoke pack for future live AI verification |
| `docs/implementation-scope.md` | Next-step scope for audio, exercise expansion, screens, and tooling |
| `design-english-mvp.md` | Product rationale and scope summary |

## Stack

- Client: Flutter (Dart)
- Backend: Node.js + TypeScript + Express (`backend/`)
- AI: OpenAI Responses API, server-side only (`AI_PROVIDER=openai`; stub default for local dev)
- Lesson content: JSON fixtures in `backend/data/` (manifest + per-lesson files)
