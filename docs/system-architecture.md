# System Architecture — Roundups AI Assistant MVP

## Layers

```
┌─────────────────────────────────────────┐
│  Flutter Client (Dart)                  │
│  Render exercises, collect input,        │
│  display results. No evaluation logic.  │
└────────────────┬────────────────────────┘
                 │ REST (JSON)
┌────────────────▼────────────────────────┐
│  Backend (REST API)                     │
│  Serve lessons, evaluate answers,       │
│  enforce correctness authority.          │
│  Run deterministic matching.            │
│  Invoke AI when needed.                 │
└────────────────┬────────────────────────┘
                 │ server-side only
┌────────────────▼────────────────────────┐
│  AI Layer (OpenAI Responses API)        │
│  sentence_correction borderline eval    │
│  Returns: { correct, feedback }         │
└─────────────────────────────────────────┘
```

## Hard rules

- AI never runs on client.
- Client never makes correctness decisions.
- AI called only for `sentence_correction` borderline cases.
- AI response validated by backend before use.
- Client state: current session only (current lesson, current exercise, answers so far). No local storage.

## Data flow — answer submission

```
Client                    Backend                   AI
  │                          │                       │
  │  POST /lessons/{id}/     │                       │
  │  answers {attempt}  ───► │                       │
  │                          │ normalize user_answer  │
  │                          │ deterministic match    │
  │                          │   ┌─ hit → correct    │
  │                          │   └─ miss → borderline?│
  │                          │       ┌─ no → incorrect│
  │                          │       └─ yes ─────────►│
  │                          │                       │ evaluate
  │                          │◄──────────────────────│
  │                          │ validate AI response   │
  │                          │ timeout/error → incorrect
  │◄─────────────────────────│                       │
  │  {correct, feedback,     │                       │
  │   canonical_answer,      │                       │
  │   evaluation_source}     │                       │
```

## API surface (MVP — 3 endpoints)

```
GET  /lessons/{lesson_id}                          → lesson definition (ordered exercises)
POST /lessons/{lesson_id}/answers                  → submit one answer, receive result
GET  /lessons/{lesson_id}/result?session_id={uuid} → final lesson score
```

No other endpoints in MVP.

## Lesson content source

JSON fixtures in `backend/data/` (manifest + per-lesson files). Loaded at server startup by `src/data/lessons.ts`. No DB, no CMS. Adding lessons = drop a new JSON file and update `manifest.json`.

## Session model

No auth tokens. Client generates a `session_id` UUID at lesson start and passes it with every answer submission. Backend stores attempts in a process-lifetime in-memory map keyed by `session_id:lesson_id`. The result endpoint requires `?session_id=` to look up the correct attempt set.

No cross-session persistence. Store is in-memory only — resets on server restart. Each `session_id` scopes one lesson visit.
