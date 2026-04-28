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

- Open-answer exercise widgets (`sentence_rewrite`, `short_free_sentence`) + AI evaluator with deterministic-first → AI fallback. **In progress 2026-04-28:** Wave 14.2 phase 1 shipped backend foundation for `sentence_rewrite` (schema, service routing through the existing deterministic-then-AI evaluator, projection stripping, route enum). Phase 2 = authoring sprint to add `sentence_rewrite` exercises to the bank. Phase 3 = Flutter widget for free-text input. Phase 4 = `short_free_sentence` (different evaluator semantics — rule-conformance, not match-to-accepted).
- Offline content generation pipeline (generator + QA agent per spec §20). V1 MVP uses a manual authoring sprint instead.
- ~~Skill-progress UI (per-skill cards on dashboard, mastery panel on summary screen).~~ Shipped 2026-04-28: summary mastery panel via Wave 4 `SkillStateCard`; dashboard per-skill status badges via Wave 14 (`SkillStatusBadge` on the Rules card).
- Feedback system surface (after-friction prompt, after-summary prompt, cooldown).
- ~~D1/D7 retention dashboard — V1 ships the raw event stream; the dashboard query is a V1.5 follow-up.~~ Shipped 2026-04-28 (code only, **not yet validated with live data**): `cohortRetention` SQL aggregation in `backend/src/admin/retention.ts`, JSON + HTML routes at `GET /admin/retention[.html]` gated by `ADMIN_USER_IDS` env var. Wave 14.1. **Live validation gated on real Apple Sign-In** (next bullet) — until real users sign up there are no meaningful cohorts to look at, so the dashboard's correctness against production data is checked the same hour the first non-stub user lands.
- Real Apple Sign-In verifier (still on `apple_stub`). **Blocks Wave 14.1 live validation** — schedule the retention dashboard QA pass for the same session that flips Apple Sign-In off the stub: set `ADMIN_USER_IDS=<founder users.id>` on Render, sign up a fresh user via real Apple, confirm a row appears in `/admin/retention` with `cohort_size = 1`.

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

**Status (2026-04-27): shipped.** Bank grew from 20 → 50 exercises across
5 skills. Three new B2 lessons authored via
`english-grammar-methodologist` to close out Unit U01 (Infinitive vs -ing):

- `backend/data/lessons/b2-lesson-003.json` — Verbs Followed by to + Infinitive (skill `verb-to-inf-after-aspirational-verbs`).
- `backend/data/lessons/b2-lesson-004.json` — Verbs with a Change in Meaning (skill `verb-both-forms-meaning-change`).
- `backend/data/lessons/b2-lesson-005.json` — Verbs with Both Forms / Little Change (skill `verb-both-forms-little-change`).

Skills registry (`backend/data/skills.json`) bumped to version 2 with
contrast / prerequisite edges between the four U01 sibling skills.
Manifest (`backend/data/manifest.json`) bumped to version 2; every entry
now carries `unit_id` / `rule_tag` / `micro_rule_tag` so the bank index
can use them.

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

**Output.** Lessons under `backend/data/lessons/` flattened into the bank
by `backend/src/data/exerciseBank.ts` at boot. Strict schema enforced by
Zod on backend boot. (The standalone `backend/data/exercise_bank.json` of
the original plan was superseded by the Wave 11 decision to keep
authoring in lesson JSON files and let the bank loader index them.)

**Diagnostic-tagged items deferred.** The 5% `is_diagnostic = true` slice
is owned by Wave 12 (Diagnostic Mode); the schema gains the field there.
The bank loader already supports the field and falls back to the first
five flat entries until then.

**Acceptance shipped.**
- 50 exercises live; coverage ≥ 4 per skill on every shipped skill (10 each on the four U01 skills, 10 on the existing PPC-vs-PP skill).
- Three new strongest-tier items (one per new lesson) — bank now has its first reachable production-gate items per `LEARNING_ENGINE.md §6.4`.
- Distribution: 25 fill_blank (50%), 14 multiple_choice (28%), 10 sentence_correction (20%), 1 listening_discrimination (2%) — within target tolerance for the V1 MVP.
- 293 backend + 136 Flutter tests green.

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

**Status (2026-04-28): in progress, broken into 12.1 / 12.2 / 12.3 / 12.4
sub-waves so each lands as a self-contained PR (mirroring the Wave 11
split). 12.1 shipped; 12.2 / 12.3 / 12.4 pending.**

- **12.1 — schema + diagnostic-tagged items (off-path).** ✅
  Optional `is_diagnostic: bool` field added to every exercise variant in
  `LessonSchema`; threaded through the `Exercise` interface and the
  exercise-bank loader (which already supported the flag via a duck-typed
  cast — Wave 12.1 cleaned that up). 5 weak-tier MC items tagged across
  the 5 shipped skills (one per skill) so the diagnostic-pool path now
  returns a real cross-skill probe instead of the `flat.slice(0, 5)`
  fallback. 6 new tests (3 schema, 3 bank-index). Content contract §1.2
  documents the field; mobile-architecture.md notes that the client
  does not deserialise it because the diagnostic flow lives behind
  dedicated `/diagnostic/...` routes server-side.
- **12.2 — backend routes + diagnostic_runs storage + CEFR derivation.** ✅
  Migration `0009_diagnostic_runs` adds the table + partial-unique
  active-run index. Four `/diagnostic/...` routes mounted: `start`,
  `:id/answers`, `:id/complete` (idempotent), `restart`, plus a
  write-only `/skip` telemetry endpoint. CEFR derivation in
  `backend/src/diagnostic/cefr.ts` (≥80% → B2, 50–79% → B1, <50%
  → A2, C1 unreachable from a B2 bank). Probe attempts augment
  `learner_skills` through the existing `recordAttempt` path so the
  probe never resets state. `user_profiles.level` is stamped on
  `/complete`; `diagnostic_completed` / `diagnostic_skipped` /
  `diagnostic_abandoned` audit events power the retention cohort
  analysis (Wave 12.4 wires the client signals). 14 new tests; 312/312
  backend green.
- **12.3 — Flutter `DiagnosticScreen`, route gating, skip-for-now.** ✅
  Three-phase screen (Welcome → Probe → Completion) at
  `app/lib/screens/diagnostic_screen.dart` (~520 LOC). Routing gate
  added to `HomeScreen.build()` between sign-in and onboarding,
  driven by `ApiClient.getMyLevel()` + `LocalProgressStore`
  diagnostic-skipped flag. Phase 2 reuses the shipped
  `MultipleChoiceWidget` chrome but never reveals correctness in-line
  per V1 spec §10. Phase 3 hero uses gold-accented level letters per
  the `DESIGN.md` completion-moment rule + a per-skill `StatusBadge`
  panel. New `DiagnosticProofCard` widget (~80 LOC). 5 widget tests
  cover Welcome surface, Probe no-reveal contract, Completion +
  Continue path, Skip-for-now writing the local flag, Re-take
  restart. 141/141 Flutter tests green (was 136). Spec lives in
  `docs/plans/diagnostic-mode.md`.
- **12.4 — re-take affordance + D1 cohort SQL + V1 MVP closeout.** ✅
  Quiet `Re-run my level check` text link at the bottom of the Study
  Desk dashboard pushes `DiagnosticScreen` via `MasteryFadeRoute`;
  Begin→Complete and Skip-for-now both pop back. The probe always
  augments `learner_skills`, never resets — V1 spec §15. Audit-event
  payload locked: `diagnostic_completed` carries
  `{ run_id, cefr_level, total_correct, total_answered,
  skills_touched: string[] }`, asserted by
  `tests/diagnostic.test.ts`. D1 retention cohort SQL example landed
  in `docs/backend-contract.md §Wave 12.4 status` — splits users by
  `diagnostic_completed` / `diagnostic_skipped` / `no_signal` and
  reports D1 active percentages. 2 widget tests in
  `app/test/diagnostic_dashboard_retake_test.dart` (push +
  pop-on-skip). 143/143 Flutter (was 141), 312/312 backend.

**V1 MVP shipped (2026-04-28).** All planned waves landed:
9 → 10 → 10.5 → 11 (.1–.4) → 12 (.1–.4) → 13. The decisions log at
the top of this file is implemented; `LEARNING_ENGINE.md §1–14, 17–18,
21, 24` honoured by the runtime; §15 (Diagnostic) honoured along the
non-skip path; §16 (Transparency) shipped at the V1 level (result +
explanation + skill_id surface — skill-progress panel deferred per
decision #12); §19 (Debug UI) reachable via SQL queries; §20 / §22
deferred to V1.5 per the Out-of-MVP scope above.

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
| 9 — Observability infra | 2–3 | 3 | ✅ Decision Log, friction events, exercise_stats live |
| 10 — Mastery V1 + Error model 6→4 | 3–4 | 7 | ✅ New gate enforced; 4-error model |
| 10.5 — Authoring sprint (overlaps Wave 11 prep) | 2–3 | 9 | ✅ Bank at 50 exercises across 5 skills |
| 11 — Exercise bank + dynamic DE | 5–7 | 16 | ✅ Lessons-as-bank live |
| 12 — Diagnostic Mode | 4–5 | 21 | ✅ Probe + CEFR + cohort telemetry |
| 13 — Session pacing + mixing | 2–3 | 24 | ✅ Adaptive pacing live |

**V1 MVP shipped 2026-04-28.**

### Post-MVP hot-fixes + product follow-ups

- **Wave 12.5 (2026-04-28)** — engine cap-relaxed fallback when §9.1 dropout + Wave 13 cap starve the primary pass. Surfaced in prod after 10.5 expanded the bank.
- **Wave 12.5b (2026-04-28)** — dynamic-mode `isLastExercise` + `submitAnswer` race fix; sessions no longer end at Q1 on the first wrong answer.
- **Wave 12.6 (2026-04-28)** — `MAX_SKILLS_PER_SESSION = 2` cap (engine) + post-mistake `See full rule →` bottom sheet (client). Founder-flagged trust signal: theory exists, theory is one tap away, theory is Murphy/Swan grade. Library tab + first-encounter auto-card explicitly **deferred** to V1.6+ pending bank ≥15 skills + skill display names. See `docs/plans/wave12.6-rule-access.md` for the full plan + methodologist + CEO consult summary.
- **Wave 12.7 (2026-04-28)** — V1.6 library entry. New public `GET /skills` route serves the registry + per-skill rule snapshot (title, description, cefr_level, intro_rule, intro_examples). Flutter `SkillCatalog` (`app/lib/learner/skill_catalog.dart`) caches it; `skillTitleFor` reads from the catalog with a hardcoded fallback for cold-start / offline. New "Rules" card on the Study Desk dashboard — every skill rendered as a row with title + CEFR chip; tap → bottom sheet with `intro_rule` + `intro_examples`. Bank ≥15 skills + skill graph search are still V2+; this is the minimal library that earns its place at 5 skills.
- **Wave 14 (2026-04-28)** — V1.5 dashboard skill-progress badges. The Rules card (Wave 12.7) now shows a compact `SkillStatusBadge` (`app/lib/widgets/skill_status_badge.dart`) before the CEFR chip on every row a learner has touched. Status copy is shared with the summary-screen panel via `statusCopyFor` so dashboard + summary stay in lockstep. Dashboard load fans out `LearnerSkillStore.allRecords()` in parallel with the lessons / review-due fetches; absent records hide the badge so untouched skills stay calm. Closes the V1.5 backlog item.
- **Wave 14.1 (2026-04-28)** — V1.5 D1/D7 retention dashboard. New `backend/src/admin/` module: `retention.ts` runs a single CTE-based SQL aggregation (`users.created_at` cohort × `exercise_attempts.submitted_at` activity) keyed by UTC calendar day, returning per-cohort `cohort_size / d1_active / d7_active / d1_rate / d7_rate / d1_complete / d7_complete`. `routes.ts` exposes `GET /admin/retention` (JSON) and `GET /admin/retention.html` (server-rendered table with calm tokens), both gated by `requireAdmin` (a wrapper around `requireAuth` that additionally checks `ADMIN_USER_IDS` env). Tests cover: empty-DB happy path, strict D1 boundary (same-day attempts excluded), `d1Complete` flip when `now` < cohort_day + 1d, all three auth states (401/403/200), and HTML rendering. **Live validation deferred** to the same session that ships real Apple Sign-In — no real users today, no meaningful cohorts; the code is in place so day-1 of real auth gives instant retention visibility.
- **Wave 14.2 phase 1 (2026-04-28)** — V1.5 open-answer family backend foundation. New `sentence_rewrite` exercise type accepted at the schema (`backend/src/data/lessonSchema.ts` + `lessons.ts`), the API enum (`schemas.ts` + `lessonSessions/routes.ts`), and the lessonSessions service routing — which reuses the existing `evaluateSentenceCorrection*` evaluator pair, since the deterministic-then-AI semantics ("is the student answer equivalent to one of these accepted variants given this prompt?") are identical for both correction and rewrite framing. `exerciseProjection.ts` strips `accepted_answers` before the wire response so the canonical rewrites never reach the client. **No client widget yet, no authored exercises in the bank yet** — phase 2 ships authoring, phase 3 ships the Flutter free-text widget, phase 4 ships `short_free_sentence` (different evaluator semantics — rule-conformance instead of match-to-accepted). Backend is feature-complete and dead-code-clean; nothing exercises this path until phase 2 lands.

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
