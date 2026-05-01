# Mastery

Mastery is an English-practice product built around structured lessons, deterministic evaluation, and a deliberately narrow use of AI.

It is aimed at learners who need guided grammar and sentence-level practice, and at builders who want a reference implementation for a constrained AI-assisted learning workflow.

## Current stage

MVP, in active development.

## Problem it solves

Most language-learning products either overuse free-form AI or hide the evaluation logic behind opaque scoring. Mastery keeps the core lesson flow deterministic, uses AI only where the rules run out, and keeps the backend as the single source of truth for correctness.

## What is implemented

- Flutter client for structured lesson flows (six exercise families:
  `fill_blank`, `multiple_choice`, `sentence_correction`,
  `sentence_rewrite`, `short_free_sentence`, `listening_discrimination`)
- Node.js + TypeScript backend for lesson delivery and evaluation
- Deterministic evaluation for `fill_blank`, `multiple_choice`, and
  `listening_discrimination`; AI-graded for the open-form types
  (`sentence_correction`, `sentence_rewrite`, `short_free_sentence`)
- Wave H2 dual-verdict AI judge on `fill_blank` — flips a deterministic
  miss to correct when the answer demonstrates the lesson's
  `target_form`, with an off-target slip note in `explanation`
- Post-lesson AI debrief generation
- Server-side auth and session foundation
- Server-side lesson session and progress model
- Content and pedagogy canon for lesson authoring (textbook-format
  `rule_card` per `docs/content-contract.md §1.2`)

## What is intentionally private

- Concrete deployment endpoints and operational dashboards
- Secret values and local environment files
- Internal planning history that is not needed to understand the product
- Internal evaluation assets that may be reviewed before any public release

## High-level architecture

- `app/` contains the Flutter client
- `backend/` contains the Node.js API, evaluation pipeline, and persistence layer
- `backend/data/` contains lesson fixtures and manifests
- `docs/` contains product contracts, plans, public architecture notes, and archive material

Public-facing architecture and workflow notes live in [`docs/public/ARCHITECTURE.md`](docs/public/ARCHITECTURE.md), [`docs/public/ROADMAP.md`](docs/public/ROADMAP.md), and [`docs/public/AI_WORKFLOW.md`](docs/public/AI_WORKFLOW.md).

## AI usage in development

AI is used in two places:

- in the product, only for borderline sentence-correction evaluation and short debrief generation
- in development, for implementation support, documentation drafting, and controlled content-authoring workflows

Human review remains required for product direction, pedagogy, and any shipped content.

## Short roadmap

- wire the Flutter client to the shipped auth and lesson-session backend
- continue the learning-engine migration in measured waves
- expand exercise and audio coverage without weakening deterministic evaluation
- tighten the public documentation and repository surface before any publication

## Status

Active development.

## Documentation

Start with [`docs/README.md`](docs/README.md) for the full document map. Public-release preparation notes live under [`docs/github-readiness/`](docs/github-readiness/).
