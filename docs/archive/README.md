# Archive — Historical Mastery Documentation

These files are kept for the git/audit trail. They are **not active source of truth** for any current behaviour. The active doc map lives in the project `README.md` and in `CLAUDE.md`.

Do not consult these to decide how the system works today. Use them only when you specifically need historical context (why a decision was made, what an earlier session shipped, what was planned at the time).

## What's here and why

### AI evaluation prep (8 files)

`ai-readiness-checklist.md`, `ai-session-brief.md`, `ai-prompt-spec.md`,
`ai-evaluation-rubric.md`, `ai-eval-review-sheet.md`,
`ai-eval-review-sheet.template.csv`, `ai-eval-dataset.v1.jsonl`,
`ai-eval-dataset.template.jsonl`, `ai-eval-dataset-guide.md`,
`manual-ai-smoke-pack.md`.

Created when the AI layer was still in stub mode. The OpenAI-backed
`sentence_correction` evaluator and the post-lesson AI debrief have since
shipped to production. The actual prompt and contract live in code
(`backend/src/ai/openai.ts`) and in `docs/backend-contract.md` §AI Prompt
Template + §Debrief Generation. If a future session needs to redo manual
AI eval, restart from these as a starting reference.

The eval datasets in this folder are synthetic author-created fixtures,
not learner production data. They are acceptable to keep in the
repository as long as they remain synthetic, contain no personal data,
and do not import operational traces.

### Historical planning artifacts

- `execution-brief.md` — phase-by-phase MVP build order. The MVP is
  shipped; this is the timeline of how it got built.
- `strategic-decisions.md` — locked decisions from 2026-04-17. The
  decisions themselves are baked into `docs/approved-spec.md`. Keep
  this for the dated record of which decisions were locked when.
- `system-architecture.md` — early ASCII layer diagram. Fully superseded
  by `docs/approved-spec.md` §2 System Boundaries.

### One-shot QA reviews

- `content-qa-b2-lesson-001.md` — single-pass QA review of the first
  shipped lesson, dated 2026-04-20. Useful as an example of the QA
  format; not a doc to consult for current lesson state.

## When to delete vs keep

Anything in this folder can be deleted permanently if it stops being
useful as historical context. Git history is the ultimate fallback. Move
out of `archive/` only if a file becomes load-bearing for active work
again — at which point it should be reviewed and updated, not silently
re-promoted.
