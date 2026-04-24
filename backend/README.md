# mastery-backend

REST API for Mastery English practice. Node.js + TypeScript + Express.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Liveness check |
| GET | `/lessons` | Lightweight lesson summary list (`id`, `title`, `slug`, `order`) |
| GET | `/lessons/:lessonId` | Lesson definition (secrets stripped) |
| POST | `/lessons/:lessonId/answers` | Submit answer, get evaluation result |
| GET | `/lessons/:lessonId/result` | Lesson score summary |

## Evaluation rules

- `fill_blank`: deterministic exact match after normalization. AI never called.
- `multiple_choice`: deterministic option ID match. AI never called.
- `sentence_correction`: deterministic first; AI fallback only when Levenshtein ≤ 3 and length within 50–200% of shortest accepted answer.

AI fallback on timeout (5s) or error defaults to `correct=false, evaluation_source=deterministic`.

## Runtime constraints

- **AI result cache:** in-memory, keyed by `(session_id, exercise_id, normalizedAnswer)`. TTL 4h, LRU cap 10K entries. Repeat submissions with the same answer return cached result — no AI call, no rate-limit consumption.
- **AI rate limit:** 10 AI-eligible submissions per IP per 60s sliding window. Checked only after deterministic gate and cache miss. Returns `429 rate_limit_exceeded`.
- **XFF trust boundary:** X-Forwarded-For accepted only when socket originates from loopback or RFC 1918 address. Rightmost entry used to prevent client spoofing.
- **Session store:** attempts keyed by `session_id:lesson_id`. TTL 4h, LRU cap 10K. Resets on server restart — no persistence across deploys.

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

Preparation artifacts for the next AI-focused session:
- `../docs/ai-prompt-spec.md`
- `../docs/ai-eval-dataset.template.jsonl`
- `../docs/ai-readiness-checklist.md`
- `.env.example`
- `.env`
- `scripts/dev-local-openai.sh`

To enable the built-in OpenAI provider (Responses API structured outputs):

```sh
AI_PROVIDER=openai \
OPENAI_API_KEY=... \
OPENAI_MODEL=gpt-4o-mini \
npm run dev
```

Optional:
- `OPENAI_BASE_URL` (defaults to `https://api.openai.com/v1`)

For local-only setup without exporting shell variables manually:

1. put the real key into `backend/.env`
2. run `./scripts/dev-local-openai.sh`

## Lesson data

Lesson fixtures live in `data/` and are loaded via `src/data/lessons.ts`. Server owns all exercise definitions including accepted answers — these are never sent to clients.
