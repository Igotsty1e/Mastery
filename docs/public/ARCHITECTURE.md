# Mastery Architecture

## Overview

Mastery is a lesson-driven English practice product with a Flutter client and a Node.js backend. The backend owns lesson delivery, evaluation, and any AI-assisted decision points.

## Main components

- `app/`: Flutter client for lesson navigation, exercise rendering, and local UI state
- `backend/`: Node.js + TypeScript API for lesson data, answer submission, evaluation, auth, and session flows
- `backend/data/`: lesson fixtures and supporting content assets
- `docs/`: product contracts, planning artifacts, and public-facing documentation

## Core flow

1. The client requests lesson definitions from the backend.
2. The learner submits answers to the backend.
3. The backend evaluates the answer deterministically whenever possible.
4. AI is consulted in two narrow shapes: as a borderline fallback or
   open-form grader on the open-answer exercise families
   (sentence-correction / sentence-rewrite / short-free-sentence),
   and as a dual-verdict judge on fill-blank items — flipping a
   deterministic miss to correct when the answer demonstrates the
   lesson's target form despite an off-target slip. Short lesson
   debriefs are also AI-generated.
5. The backend returns correctness, explanation, and any debrief output to the client.

## Evaluation design

- deterministic-first evaluation is the default
- AI is a fallback or a second judge, never the primary grader
- the backend remains the source of truth for correctness

## Persistence model

- current client UX still includes device-local state
- backend auth, sessions, and lesson-session persistence already exist for the next client wave
- production persistence targets Postgres-compatible storage

## Boundaries

- the repository does not expose private operational dashboards or secret values
- internal deployment specifics are intentionally excluded from the public architecture layer
