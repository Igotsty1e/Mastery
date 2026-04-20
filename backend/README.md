# mastery-backend

REST API for Mastery English practice. Node.js + TypeScript + Express.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Liveness check |
| GET | `/lessons/:lessonId` | Lesson definition (secrets stripped) |
| POST | `/lessons/:lessonId/answers` | Submit answer, get evaluation result |
| GET | `/lessons/:lessonId/result` | Lesson score summary |

## Evaluation rules

- `fill_blank`: deterministic exact match after normalization. AI never called.
- `multiple_choice`: deterministic option ID match. AI never called.
- `sentence_correction`: deterministic first; AI fallback only when Levenshtein ≤ 3 and length within 50–200% of shortest accepted answer.

AI fallback on timeout (5s) or error defaults to `correct=false, evaluation_source=deterministic`.

## Setup

```sh
npm install
npm run dev       # tsx watch
npm test          # vitest
npm run build     # tsc → dist/
npm start         # node dist/server.js
```

## AI provider

Default is `StubAiProvider` (always returns incorrect).

To enable the built-in OpenAI provider (Responses API structured outputs):

```sh
AI_PROVIDER=openai \
OPENAI_API_KEY=... \
OPENAI_MODEL=gpt-4o-mini \
npm run dev
```

Optional:
- `OPENAI_BASE_URL` (defaults to `https://api.openai.com/v1`)

## Lesson data

Lesson fixtures live in `data/` and are loaded via `src/data/lessons.ts`. Server owns all exercise definitions including accepted answers — these are never sent to clients.
