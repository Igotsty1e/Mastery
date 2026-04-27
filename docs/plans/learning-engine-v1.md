# Learning Engine V1 — implementation roadmap

> **Status (2026-04-26): draft, awaiting "go" before Wave 9 starts.**
>
> Source of truth: `LEARNING_ENGINE.md` (V1 final spec, dropped into the
> repo by the product owner on 2026-04-26). This document is the
> **execution plan** that turns that spec into shippable waves. The
> spec wins on intent; this plan wins on sequencing, scope, and
> acceptance criteria.

## Decisions log (locked, do not relitigate)

These are the answers the product owner gave during the V1 product
review. They constrain every wave below.

| # | Decision | Implication |
|---|---|---|
| 1 | **No real users yet — clean break is allowed.** Dropping data, hard-resetting tables, breaking lesson JSON shapes is fine. | No schema migrations. No lazy-recompute fallbacks. No feature flags for partial rollout. |
| 2 | **Retention is primary, learning quality is secondary** (per spec §1). Trade-offs resolved via metrics. | D1/D7 + friction events come first as observability infra (Wave 9). Numerical bounds on mastery are placeholders, tuned post-launch. |
| 3 | **Lessons-as-bank.** Lesson JSON files stop being authoritative; the Decision Engine assembles each session from a bank of exercises. | Wave 11 is a backend rewrite + API redesign. UI keeps the "Today's session" wrap so the dashboard hero does not change shape. |
| 4 | **Existing data is dropable.** Snapshot what we want to keep, throw the rest away on Wave 11 launch. | No need for backwards-compat code paths in client or server. |
| 5 | **Open answers (`sentence_rewrite`, `short_free_sentence`) and full content-gen pipeline → V1.5**, after the backend is stable. | V1 MVP runs on a manually-curated bank of ~50–100 exercises. |
| 6 | **Session = 20–30 min idle is UX guidance**, not infrastructure. | No server-side session-timeout work in V1. |
| 7 | **Skill graph stays as `backend/data/skills.json`**. Pedagogy refresh is out of scope; new skills land via the existing `english-grammar-methodologist` flow. | No skill-graph rebuild in V1. |
| 8 | **Status thresholds 0–20/21–45/46–70/71–84/85–100 are final.** | Wave 9 ships the new labels; UI updates in Wave 10. |
| 9 | **Mastery V1 gate: `≥6 attempts` OR `≥4 attempts with at least one correction/production`** (placeholder, tunable post-D7 telemetry). | Encoded in Wave 10. Tunable via a single constant. |
| 10 | **Decision Log is critical (spec §18).** | Wave 9 — first thing shipped. |
| 11 | **Bad exercises get a `qa_review_pending` flag**, not auto-exclusion. | Removes the risk that legitimately hard or anchor-low exercises get pulled out of rotation by a metric heuristic. |
| 12 | **Skill display names are kept as code identifiers in V1 MVP** ("красоту потом"). | Skill UI surfaces are V1.5. |

## Out-of-MVP scope (V1.5 backlog)

Captured here so they are not silently re-added to V1:

- Open-answer exercise widgets (`sentence_rewrite`, `short_free_sentence`) + AI evaluator with deterministic-first → AI fallback.
- Offline content generation pipeline (generator + QA agent per spec §20). V1 MVP uses a manual authoring sprint instead.
- Skill-progress UI (per-skill cards on dashboard, mastery panel on summary screen).
- Feedback system surface (after-friction prompt, after-summary prompt, cooldown).
- D1/D7 retention dashboard — V1 ships the raw event stream; the dashboard query is a V1.5 follow-up.
- Real Apple Sign-In verifier (still on `apple_stub`).

## Waves

### Wave 9 — Observability infra (low risk, ships first)

**Goal.** Make the engine inspectable before we change its behaviour. Zero user-visible impact; everything below is append-only or observability-only.

**Backend.**
- New table `decision_log` — append-only, one row per Decision Engine call:
  - `id` (uuid pk), `user_id`, `session_id` (nullable — diagnostic mode has no lesson session), `skill_id` (nullable), `previous_state` (jsonb — mastery + recent_errors snapshot), `decision` (enum: `next_exercise`, `reorder_queue`, `mark_weak`, `schedule_review`, `mastery_promoted`, `mastery_invalidated`), `reason` (varchar(120) — short reason code matching `LEARNING_ENGINE.md §11.3`), `next_exercise_id` (nullable), `created_at`.
- New columns on `exercise_attempts`:
  - `friction_event` (enum nullable: `repeated_error`, `abandon_after_error`, `retry_loop`, `time_spike`).
  - `evaluation_version` (already exists).
- New table `exercise_stats` — append-only counters, one row per exercise per day:
  - `exercise_id`, `date`, `attempts_count`, `correct_count`, `partial_count`, `wrong_count`, `avg_time_to_answer_ms`. Updated by a small `recordAttemptStats` helper invoked from `lessonSessions/service.submitAnswer`.
- New columns on `exercises` (in lesson fixtures' projection / future bank):
  - `exercise_version` (int, default 1).
  - `qa_review_pending` (bool, default false). Wave 9 only adds the column; the metric-driven flag-flip is Wave 11+.
- New columns on `skills` (in `backend/data/skills.json`):
  - `skill_version` (int, default 1).

**Client.** No changes. Status thresholds in `LearnerSkillRecord.statusAt` get the new boundaries (0–20 / 21–45 / 46–70 / 71–84 / 85–100) but stay in the same five-state enum, so UI is unchanged.

**Acceptance.**
- `decision_log` writes from every existing decision point in `lessonSessions/service` and the Wave 3 `DecisionEngine` test fixtures.
- `exercise_stats` counters increment on every `submitAnswer` call (lesson-session path only — legacy path is gone since Wave 8).
- Existing 281 backend + 133 active Flutter tests still pass.

**Risk.** Low. No behaviour change. Observability-only.

**Estimate.** 2–3 days.

---

### Wave 10 — New Mastery Model + Error model 6→4

**Goal.** Replace the score-based progression with the V1 rule-based mastery gate. Drop the two pedagogically dead error codes.

**Decisions baked in.**
- Mastery V1 = `(attempts ≥ 6) OR (attempts ≥ 4 AND at least one correction or production attempt)` with weighted accuracy ≥ 80%, no repeated conceptual error in last 5 attempts, last attempt not wrong. Numbers tunable via a single constant block (`backend/src/learner/mastery.ts`).
- Error model: drop `transfer_error`, `pragmatic_error`. Surviving codes: `conceptual_error`, `form_error`, `contrast_error`, `careless_error`.
- Status thresholds (already shipped in Wave 9): final.

**Backend.**
- `learner_skills` table grows: `attempts_count` (int), `exercise_types_seen` (jsonb — set of `single_choice|multi_select|...`), `last_outcome` (enum: `correct|partial|wrong`), `repeated_conceptual_count` (int — rolling over the same FIFO N=5 as `recent_errors`).
- `mastery.ts` — new module. `evaluateMastery(record)` returns `{ status, gateCleared }`. The Wave 7.3 `recordAttempt` service calls it after each insert. Old `mastery_score` field stays in the row but is unused (drop in Wave 11 cleanup).
- `TARGET_ERROR_CODES` enum drops the two unused codes. Existing lesson JSON references them in zero places (verified during this wave; if any do, they get rewritten via `english-grammar-methodologist`).

**Client.**
- `LearnerSkillRecord.statusAt` rewired to read the new V1 inputs (or, if the server already returns a derived status DTO, the client trusts the server's `status` and stops re-deriving).
- `targetErrorToString` enum loses two values; `_parseError` becomes more lenient (returns null on dropped codes so old persisted state does not crash).

**Acceptance.**
- New unit tests in `tests/learner-state.test.ts` for every clause of the V1 gate (each rule has a "fails on this rule alone" test).
- Existing tests stay green; the ones that asserted score-based thresholds are rewritten or deleted.
- `flutter analyze` + `flutter test` green.

**Risk.** Low — clean break is allowed, so we drop `mastery_score` reads on launch.

**Estimate.** 3–4 days.

---

### Wave 10.5 — Authoring sprint (between Wave 10 and Wave 11)

**Goal.** Hand-curate a bank of ~50–100 exercises so Wave 11's dynamic selection has something to pick from. Without this Wave 11 ships an empty engine.

**Process.**
- Invoked through the existing `english-grammar-methodologist` skill — every new exercise (and every rewrite of an existing one) goes through that skill first.
- Exercise distribution target (rough):
  - 50% completion (single_blank / multi_blank)
  - 25% selection (single_choice / multi_select)
  - 20% correction (sentence_correction / multi_error_correction)
  - 5% diagnostic-tagged (`is_diagnostic = true`) — these can also serve in regular sessions.
- Open-answer types (`sentence_rewrite`, `short_free_sentence`) skipped per V1.5 deferral.
- Coverage: every skill in `skills.json` should have at least 4 exercises (so the `attempts ≥ 4` gate is reachable).

**Output.** `backend/data/exercise_bank.json` (or per-skill files if size demands it). Strict schema enforced by Zod on backend boot.

**Risk.** Low — content work, isolated from runtime. Bottlenecked on product-owner review time, not engineering.

**Estimate.** 2–3 days of author time (parallelisable with engineering on Wave 9 wrap-up).

---

### Wave 11 — Exercise bank + dynamic Decision Engine

**Goal.** Stop using lesson JSON files as the unit of delivery. Decision Engine assembles each session from the bank.

**Backend.**
- `backend/data/lessons/*.json` files **deleted**. The lesson-as-fixture model is gone.
- Exercise bank ships as `backend/data/exercise_bank.json` (or split by skill). Schema validated at boot.
- New Decision Engine module `backend/src/decision/engine.ts`:
  - Inputs: `userId`, current session state (touched skills, mistakes-by-skill, exercises shown so far), session pacing target (default 60/30/10 — adjustable to 40/40/20 weak / 70/20/10 strong via Wave 13).
  - Output: next exercise from the bank.
  - Implements §9 priorities (mastery → variety → past errors), §12 pacing splits, §14 last-N-repeat avoidance.
- `lesson_sessions` table semantics shift: a "session" is now a server-owned 10-exercise run assembled on demand, identified by id, no longer keyed to a `lesson_id`. The column stays for the diagnostic path (Wave 12) but becomes nullable.
- New endpoint `POST /sessions/start` (replaces `POST /lessons/:id/sessions/start`) — server picks the first exercise via the engine. Returns `{ session_id, first_exercise }`.
- `POST /sessions/:id/next` — request the next exercise after an answer is recorded. The engine reads the just-recorded attempt + current pacing target.
- `POST /sessions/:id/complete` and `GET /sessions/:id/result` — same shape as Wave 7.2, retargeted to the new path.
- `GET /lessons/...` routes deleted. Dashboard fetches a curated "topic" list from a new lightweight `GET /topics` endpoint (V1 MVP returns one entry: "B2 mixed practice").

**Client.**
- `ApiClient` rewired to `/sessions/...`. `startLessonSession(lessonId)` becomes `startSession()`; `submitAnswer(sessionId, ...)` stays; new `nextExercise(sessionId)` call after each answer.
- `SessionController.loadLesson(lessonId)` becomes `loadSession()` — no lessonId. Subsequent answers + next-exercise fetches thread the session id.
- Dashboard hero copy: "Today's session" instead of lesson title. Curriculum / units block goes away in V1 (replaced by a single "Today's session" CTA + last-session report).
- LessonIntroScreen deleted (was lesson-specific). Replaced by a thin "Begin session" affordance on the dashboard.

**Acceptance.**
- A full session run end-to-end via the new endpoints (smoke).
- Decision Engine pacing target reachable in tests (60/30/10 verified on a synthetic skill graph).
- All existing Flutter tests rewired or replaced. The disabled `widget_test.dart`, `happy_path_lesson_flow_test.dart`, `cross_wave_integration_test.dart` from Wave 8 either come back to life here (if their coverage maps to the new endpoints) or get deleted in favour of new tests against `/sessions/...`.

**Risk.** Medium — biggest refactor of the V1 plan. The clean-break license keeps it bounded.

**Estimate.** 5–7 days.

---

### Wave 12 — Diagnostic Mode

**Goal.** Onboarding hook: 5–7 exercises → CEFR + skill map output. Strong retention lever (per spec §15).

**Backend.**
- New endpoint `POST /diagnostic/start` — auth required, returns the first diagnostic exercise (filtered by `is_diagnostic = true` from the bank).
- `POST /diagnostic/:id/answers` — same shape as session answers, but writes to a `diagnostic_runs` table (separate from `lesson_sessions`).
- `POST /diagnostic/:id/complete` — runs the CEFR derivation:
  - Hybrid logic: overall correctness + per-skill min (per spec). If two of the seven skills tested score under threshold X, CEFR caps at the level below.
  - Output: `{ cefr_level: "A2|B1|B2|C1", skill_map: { skill_id: status } }`. Stored on `users` row + `audit_events`.
- Re-diagnostic trigger: `POST /diagnostic/restart` on demand from the user.

**Client.**
- New `DiagnosticScreen` — between sign-in and onboarding, **skippable per Wave 7.4 product call** ("Skip for now" stays as silent stub-login).
- Result screen lives on the dashboard for one session: "Welcome — your level is B2, focus on the past simple."
- Skill-map UI is a placeholder list in V1 MVP (per V1.5 deferral on skill UI surfaces).

**Acceptance.**
- A full diagnostic run round-trip in tests (5 exercises → CEFR derivation → user row updated).
- Skip-for-now still works (does not run diagnostic).
- D1 retention is now measurable for "diagnostic completed" vs "skipped" cohorts (event labels in `audit_events`).

**Risk.** Low — isolated flow, does not touch the main session loop.

**Estimate.** 4–5 days.

---

### Wave 13 — Session pacing + skill mixing

**Goal.** Activate the §12 pacing splits and §9 mixing rules in the Decision Engine.

**Backend.**
- `pacing_target.ts` — derives `(new, reinforcement, review)` percentages from the user's mastery profile:
  - default 60/30/10
  - `weak` (≥3 skills under "practicing") → 40/40/20
  - `strong` (≥3 skills at "mastered") → 70/20/10
- Decision Engine reads the target and assembles each session accordingly. Max 1 new skill per session enforced.
- Skill mixing: 15% chance per exercise to pull a different skill (occasional, not full mix).

**Acceptance.**
- Synthetic pacing tests in `tests/decision/engine.test.ts` for each profile (default / weak / strong).
- New skill cap enforced regardless of pacing.

**Risk.** Low — local change to the Decision Engine module shipped in Wave 11.

**Estimate.** 2–3 days.

---

## Wave summary

| Wave | Days | Cumulative | Status after |
|---|---|---|---|
| 9 — Observability infra | 2–3 | 3 | Decision Log, friction events, exercise_stats live |
| 10 — Mastery V1 + Error model 6→4 | 3–4 | 7 | New gate enforced; 4-error model |
| 10.5 — Authoring sprint (overlaps Wave 11 prep) | 2–3 | 9 | ~50–100 exercises in bank |
| 11 — Exercise bank + dynamic DE | 5–7 | 16 | Lessons-as-bank live |
| 12 — Diagnostic Mode | 4–5 | 21 | Onboarding hook live |
| 13 — Session pacing + mixing | 2–3 | 24 | Adaptive pacing live |

**V1 MVP done = ~3.5 weeks of engineering** (plus authoring time in 10.5).

## Acceptance for V1 MVP overall

- Every entry in the Decisions log above is implemented.
- `LEARNING_ENGINE.md` § 1–14 + 17–18 + 21 + 24 are honoured by the runtime.
- `LEARNING_ENGINE.md` § 15 (Diagnostic) honoured for the path that does not skip it.
- §16 (Transparency) is satisfied at the level shipped today (result + explanation + skill-id surface). Skill-progress panel deferred per Decision 12.
- §19 (Debug UI) — V1 minimum (user view + decision log) is reachable via SQL queries against the new tables; no UI surface in V1 MVP.
- §22 (Feedback) deferred per V1.5 backlog above.
- §20 (Content gen pipeline) deferred per V1.5 backlog above; manual bank covers V1 MVP.

## Linked artifacts

- `LEARNING_ENGINE.md` — the V1 product spec.
- `GRAM_STRATEGY.md` — pedagogy authority.
- `exercise_structure.md` — authoring rules; updated during Wave 10.5.
- `docs/backend-contract.md` — gets a "V1 endpoints" section in Wave 11.
- `docs/mobile-architecture.md` — gets a "V1 session model" section in Wave 11.
- Existing Wave 7 + Wave 8 docs — kept as audit trail; superseded sections marked.
