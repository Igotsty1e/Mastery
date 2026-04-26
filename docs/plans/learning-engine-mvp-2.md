# Learning Engine — MVP 2.0 Migration Plan

## Status

Approved migration plan from the **current shipped runtime** to the
**target Learning Engine** described in `LEARNING_ENGINE.md`.

This document is a **plan**, not an approved-spec replacement. The
authoritative current-runtime contracts remain:

- `docs/approved-spec.md`
- `docs/backend-contract.md`
- `docs/mobile-architecture.md`
- `docs/content-contract.md`

When this plan ships work into the runtime, those contracts must be updated
in lockstep (per the Documentation Maintenance Rule in `CLAUDE.md`).

The pedagogy and engine reference docs:

- `GRAM_STRATEGY.md` — what we teach and why
- `exercise_structure.md` — how items are written
- `LEARNING_ENGINE.md` — how decisions are made

---

## 1. Scope Summary

This plan moves Mastery from a **fixed linear deterministic workbook** to a
**deterministic adaptive workbook** in which:

- every shipped item is tagged to a skill, a primary target error, and an
  evidence tier
- per-learner per-skill state is maintained
- in-session 1/2/3 loop and cross-session 1d / 3d / 7d / 21d review cadence
  decide what comes next
- mastery is gated on a meaning-coupled production attempt
- transparency surfaces per-attempt, per-skill, and per-routing reasons
- new exercise families ship with explicit scoring safeguards

Out of scope:
- speaking / microphone capture (see `GRAM_STRATEGY.md §15.1`)
- runtime AI exercise invention (see `LEARNING_ENGINE.md §12.4`)
- chat-first UX (see `LEARNING_ENGINE.md §3 Non-Negotiables`)

---

## 2. CURRENT SHIPPED RUNTIME (truthful baseline)

This section is the contract baseline as of 2026-04-26. None of the items
listed here are removed by MVP 2.0; they are **extended** by it. New
behaviours are additive and gated until the corresponding contract docs
update.

| Area | Current state |
|---|---|
| Exercise types | `fill_blank`, `multiple_choice`, `sentence_correction`, `listening_discrimination` |
| Lesson model | Fixed linear sequence per `docs/approved-spec.md §4 Lesson Flow` |
| Evaluation | Deterministic exact / normalised match. AI fallback on `sentence_correction` borderline only (`docs/backend-contract.md §Step 5`) |
| Result shape | Boolean `correct` per attempt + `evaluation_source` + canonical answer + curated explanation |
| Mastery state | None. No per-skill state stored anywhere |
| Decision engine | None. Lesson order is the lesson order |
| Review scheduling | None. The static-adjacency authoring rule in `exercise_structure.md §6.5` is the only re-test mechanism |
| Onboarding | 2-step ritual `Promise → Assembly` ending in dashboard (`docs/plans/arrival-ritual.md`) — narrative, not diagnostic |
| Transparency | Per-attempt result + curated explanation + post-lesson AI debrief. No per-skill UI, no "why this next" UI |
| Versioning | None on exercise / skill / evaluator |
| Persistence | In-memory session, plus `LocalProgressStore` (SharedPreferences) for completed-exercise count and `LastLessonStore` (in-memory only) for the dashboard report |
| Error model in content | Implicit. Distractors and explanations target real learner errors but the four-then-six engine error codes are not yet declared on items |

These statements must remain true until the wave that changes each one
ships **and** the relevant contract doc is updated.

---

## 3. TARGET LEARNING ENGINE (where we are going)

The target state is fully described in `LEARNING_ENGINE.md`. The
high-level deltas this plan must close:

- Skill graph (engine §2.2, §4)
- Exercise bank tagged with `skill_id`, `primary_target_error`,
  `evidence_tier`, and (for strongest-tier items) `meaning_frame`
  (engine §6.5, §8)
- Six-code error model: `conceptual_error`, `form_error`, `contrast_error`,
  `careless_error`, `transfer_error`, `pragmatic_error` (engine §5)
- Mastery Model with the §6.4 production gate
- Decision Engine implementing the §9 loop and cadence
- Transparency Layer per attempt / per skill / per routing
- Diagnostic onboarding (engine §10)
- Two-agent QA + three-axis versioning (engine §12)
- Five new exercise families with their §8.4.1 safeguards

---

## 4. Migration Principles

1. **Additive first.** New schema fields land as optional. The runtime
   ignores them until the wave that activates them.
2. **One contract per wave.** Each wave updates exactly one set of contract
   docs. Cross-wave contract drift is prohibited.
3. **No mastery decisions before metadata.** The Mastery Model cannot ship
   before items are tagged with `skill_id` and `evidence_tier`.
4. **No new exercise family without its safeguard.** A planned family ships
   only with the engine-side guard in `LEARNING_ENGINE.md §8.4.1` enforced.
5. **Truth in the contract layer.** When a wave ships, the relevant
   contract doc is updated in the same PR. The plan is not the contract.
6. **Speaking remains out of scope** (`GRAM_STRATEGY.md §15.1`).

---

## 5. Implementation Waves

The waves are sequenced. Later waves depend on earlier waves' metadata or
state. Within a wave, sub-tasks may parallelise.

### Wave 1 — Metadata Layer (additive)

**Goal:** every shipped item declares the engine metadata the rest of the
plan depends on. No runtime behaviour change.

Tasks:

- extend the lesson JSON schema in `docs/content-contract.md` to add
  optional fields on every `Exercise`. **Until Wave 1 lands these fields
  in `docs/content-contract.md`, none of them are required on shipped
  fixtures, and currently shipped lessons in `backend/data/lessons/` are
  not expected to carry them.** Once Wave 1 ships:
  - `skill_id` (string, required for content **authored after Wave 1
    lands**; optional during the one-shot backfill of pre-Wave-1
    fixtures)
  - `primary_target_error` (enum from `LEARNING_ENGINE.md §5`)
  - `evidence_tier` (`weak | medium | strong | strongest`)
  - `meaning_frame` (string, required only when
    `evidence_tier == "strongest"`)
- declare an initial `skills.json` registry (skill graph entries with
  `skill_id`, `title`, `cefr_level`, `prerequisites[]`, `contrasts_with[]`,
  `target_errors[]`, `mastery_signals[]`)
- backfill metadata for shipped fixtures in `backend/data/lessons/`
  starting with `b2-lesson-001.json`
- backend ignores the new fields; serves them through to the client
  unchanged so future client work has the data
- update `docs/content-contract.md` to document the new fields as optional
  for MVP2 (no breaking change)

Exit criteria:
- every shipped exercise carries valid metadata
- `docs/content-contract.md` describes the new fields
- runtime behaviour identical to pre-wave

### Wave 2 — Mastery State Storage (no UI yet)

**Goal:** start recording per-learner per-skill state from each attempt.

Tasks:

- decide storage scope. Conservative default for MVP2 is **device-scoped
  local persistence** via SharedPreferences (mirrors the existing
  `LocalProgressStore`); server-side learner storage is a follow-up wave
  once accounts exist
- add a `LearnerSkillStore` that holds:
  - `mastery_score` (0–100)
  - `status` (per `LEARNING_ENGINE.md §7.2`)
  - `last_attempt_at`
  - `evidence_summary` (counts per evidence tier)
  - `recent_errors[]` (last N target-error codes)
  - `production_gate_cleared` (bool, per `LEARNING_ENGINE.md §6.4`)
- write to it from the existing answer-submission flow using the metadata
  shipped in Wave 1
- no UI surface yet

Exit criteria:
- after a session, the local store reflects the attempts that happened
- the production-gate flag flips correctly on the first valid
  strongest-tier correct attempt
- runtime UX identical from the learner's perspective

### Wave 3 — Decision Engine v0 + Review Cadence

**Goal:** implement the in-session 1/2/3 loop and the 1d / 3d / 7d / 21d
cadence as a thin runtime layer that can re-order or substitute items
within a lesson.

Tasks:

- introduce a `DecisionEngine` module that, given the current lesson
  fixture and the `LearnerSkillStore`, may:
  - replace the next item with another item on the same `skill_id` after
    a 1st or 2nd mistake (in-session)
  - mark a skill `weak` after a 3rd mistake (in-session) and end the loop
    on it for the session
  - schedule a review per `LEARNING_ENGINE.md §9.3` cadence (out-of-session)
- add a session-side scheduler that, on dashboard load, surfaces "review
  due" skills before "next lesson" content
- preserve the linear-lesson default when no replacement candidate exists
  (graceful fallback)
- expose a one-line decision reason that the Transparency Layer (Wave 4)
  can render

Exit criteria:
- in-session loop demonstrably replaces items after a mistake
- a review fires the next day on a skill that was missed today
- no regression on the existing fixed-flow lesson when the bank has only
  one item per skill

### Wave 4 — Transparency Layer (per skill, per routing)

**Goal:** make every routing and grading decision legible to the learner.

Tasks:

- add a per-skill panel surface (dashboard or post-lesson summary): status,
  one-line reason, recent error pattern
- render a "why this next" string at lesson intro / item intro when the
  Decision Engine substituted the item
- preserve the existing per-attempt result + curated explanation + AI
  debrief surface unchanged
- update `docs/mobile-architecture.md` to describe the new panel and the
  new strings on the existing screens

Exit criteria:
- a learner who finishes a session can see which skills moved and why
- the next-up review is labelled with its triggering reason

### Wave 5 — Evaluation Upgrades (partial credit + response units)

**Goal:** make the evaluator emit the per-unit and partial-credit shape
that the new families need.

Tasks:

- extend the attempt response shape in `docs/backend-contract.md` to
  include `result: wrong | partial | correct` (in addition to the existing
  `correct: bool`, kept for backwards compat during migration)
- add `response_units[]` with per-unit results when the item declares
  multiple units (`multi_blank`, `multi_error_correction`, `multi_select`)
- introduce `evaluation_version` field on responses
- update `docs/content-contract.md` and `docs/backend-contract.md` together

Exit criteria:
- existing single-decision items emit `result` plus the legacy `correct`
  field
- the evaluator returns coherent per-unit results on a pilot multi-unit
  item

### Wave 6 — New Exercise Families (one at a time)

**Goal:** ship the planned families with their `LEARNING_ENGINE.md §8.4.1`
safeguards enforced. Each family is its own sub-wave.

Suggested order (lowest scoring risk first):

1. `multi_blank` — closest to shipped `fill_blank`; safeguard: no
   interdependent blanks (`exercise_structure.md §5.7`).
2. `sentence_rewrite` — closest to shipped `sentence_correction`; safeguard:
   bounded answer-space, `accepted_rewrites` cap of 3
   (`exercise_structure.md §5.1`).
3. `multi_error_correction` — same primary skill / target error rollup,
   no-error decoy rule (`exercise_structure.md §5.8`).
4. `multi_select` — non-gameable scoring rule
   (`exercise_structure.md §5.6`).
5. `short_free_sentence` — deterministic-first scoring with bounded AI
   fallback envelope (`exercise_structure.md §5.5`).

Per-family tasks (template):

- declare schema in `docs/content-contract.md`
- declare evaluator behaviour in `docs/backend-contract.md`
- ship the Flutter widget per `DESIGN.md`
- author at least one pilot lesson using the family before the family is
  considered shipped
- add to `docs/qa-golden-cases.md`

Exit criteria (per family):
- safeguard is enforced by the runtime, not just declared in docs
- pilot lesson passes two-agent QA (Wave 8 or its informal precursor)
- contract docs updated in the shipping PR

### Wave 7 — Diagnostic Onboarding

**Goal:** add the placement probe described in `LEARNING_ENGINE.md §10`.

Tasks:

- design the 5–7 item probe; mix evidence tiers; never penalise
- output initial `LearnerSkillStore` state per touched skill plus a coarse
  CEFR placement
- integrate with the existing 2-step `arrival-ritual.md` onboarding rather
  than replace it; the probe slots in **after** Promise / Assembly so the
  product narrative survives
- make the probe re-callable from the dashboard

Exit criteria:
- a first-time learner finishes onboarding with a non-empty skill map
- a returning learner can re-run the probe without losing their existing
  state (the probe **augments**, does not reset)

### Wave 8 — Two-Agent QA + Versioning

**Goal:** formalise the QA pipeline that `LEARNING_ENGINE.md §12.2` and
`§12.3` require.

Tasks:

- declare `generator` and `reviewer` roles in the authoring tooling; same
  identity may not play both roles on the same item
- store per-item QA records (rule, target error, evidence tier, distractor
  logic, verdict)
- introduce three version axes:
  - `exercise_version`
  - `skill_version`
  - `evaluation_version`
- wire `evaluation_version` into Wave 5's response shape
- update `docs/content-contract.md` and `docs/approved-spec.md`

Exit criteria:
- every item shipped after this wave has a QA record on file
- attempts persist the version triple they were observed under

### Wave 9 — Error Model Coverage In Content

**Goal:** ensure the six-code error model (incl. `transfer_error`,
`pragmatic_error`) is actually exercised by shipped content, not just
declared.

Tasks:

- audit existing fixtures for distractors / explanations that map to
  `transfer_error` and `pragmatic_error` and tag them
- when authoring new lessons (especially dialogue completion when it
  lands), explicitly include items targeting these two codes
- add coverage to `docs/qa-golden-cases.md`

Exit criteria:
- every shipped CEFR band has at least one item per error code in its
  exercise bank
- explanation tone differs by error code per `LEARNING_ENGINE.md §5`
  (transfer items prefer contrast lessons; pragmatic items prefer dialogue
  framing)

---

## 6. Cross-Wave Invariants (Always True)

Throughout the migration:

- **deterministic-first scoring** — `LEARNING_ENGINE.md §3 Non-Negotiables`.
  AI never becomes the default judge.
- **backend is source of truth** — the client renders what the backend
  decides, even when the Decision Engine is local-first in Wave 2/3.
- **no hidden runtime AI expansion** — any expansion of AI scope must
  update `LEARNING_ENGINE.md §12.4` and `GRAM_STRATEGY.md §13.3` first.
- **explainability** — every routing or mastery decision must come with a
  one-line reason. Hidden decisions are forbidden.
- **production gate** — once Wave 2 ships, no skill is marked `mastered`
  without a meaning-coupled strongest-tier correct attempt
  (`LEARNING_ENGINE.md §§6.3, 6.4`).
- **runtime contracts are truthful** — every shipped wave updates
  `docs/approved-spec.md`, `docs/backend-contract.md`,
  `docs/mobile-architecture.md`, `docs/content-contract.md` as needed in
  the same PR.

---

## 7. What This Plan Does Not Decide

- The exact mastery score thresholds for each status (§7.2) — chosen at
  Wave 2 implementation time and tuned thereafter; the **labels** are part
  of the contract, the **thresholds** are not.
- Server-side persistence model for `LearnerSkillStore` — Wave 2 ships
  device-local; the upgrade to server-side is a separate workstream gated
  by the introduction of accounts.
- The exact shape of the diagnostic probe items — Wave 7 will produce the
  authoring brief.
- Whether the Decision Engine runs entirely client-side or has a
  backend-mediated review scheduler — Wave 3 will decide. The constraint
  is that backend must remain authoritative for **correctness**; routing
  may be local provided every routing decision is reproducible.

---

## 8. Cross-References

- `LEARNING_ENGINE.md` — engine spec this plan implements
- `GRAM_STRATEGY.md §11.1` — production-as-gate pedagogy this plan
  enforces
- `GRAM_STRATEGY.md §4.7` — mastery-requires-return pedagogy the cadence
  implements
- `exercise_structure.md §§5.1, 5.5, 5.6, 5.7, 5.8` — authoring contracts
  for the new exercise families
- `docs/plans/roadmap.md` — companion product roadmap (audio output,
  imagery, frontend screen expansion); this plan and the roadmap are
  parallel tracks that share content but address different layers
  (engine vs surface)
- `docs/plans/arrival-ritual.md` — current shipped onboarding; Wave 7
  augments it without replacing the narrative
- `docs/plans/dashboard-study-desk.md` — current shipped dashboard; Wave
  3 and Wave 4 surfaces hang off this dashboard
