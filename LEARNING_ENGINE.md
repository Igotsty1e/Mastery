# LEARNING_ENGINE — Mastery

## Status

Top-level canonical source of truth for the target-state Mastery learning
engine.

This document defines **where the product is going**, not the runtime that
ships today. It is one of the **three sibling top-level canonical docs**,
each authoritative in its own domain (per `GRAM_STRATEGY.md §Authority
chain`). None is subordinate to another:

- `GRAM_STRATEGY.md` — pedagogy: what we teach and why
- `exercise_structure.md` — authoring: how individual items are written
- `LEARNING_ENGINE.md` — engine design: how the system uses that pedagogy
  to make per-learner decisions (skill graph, evidence, mastery,
  decisions, transparency)

Cross-canon conflicts are resolved by domain: pedagogy decisions live in
`GRAM_STRATEGY.md`, authoring rules in `exercise_structure.md`, engine
invariants here.

If `LEARNING_ENGINE.md` describes a behaviour the runtime does not yet
implement, that behaviour is **planned**, not shipped. Anything currently in
production is documented in the contract layer:

- `docs/approved-spec.md`
- `docs/backend-contract.md`
- `docs/mobile-architecture.md`
- `docs/content-contract.md`

When this engine spec is in tension with those runtime contracts, the runtime
contracts win for what code can do **today**, and this engine spec wins for
where the product is **going**. The migration plan from one to the other lives
at `docs/plans/learning-engine-mvp-2.md`.

---

## 1. Product Direction

Mastery is a **deterministic, explainable, production-first learning engine
for adult English grammar practice.**

It is not:
- a Duolingo clone
- a chat-first AI tutor
- a gamified streak app
- a fully generative runtime exercise system

### 1.1 Core Promise

Help adult learners **understand, practise, diagnose, and produce** grammar
correctly in realistic contexts.

### 1.2 Core Learning Philosophy

Recognition is useful but not sufficient for mastery. Stronger mastery
signals include:

- correcting an error
- rewriting a sentence
- producing a short correct sentence
- using the structure in a new context

Mastery decisions must reflect this hierarchy of evidence (see §6 Evidence
Model and §7 Mastery Model).

### 1.3 Core Architecture Principle

Mastery is a **deterministic adaptive workbook**:

- exercises are generated offline or curated ahead of time
- backend remains source of truth for correctness
- AI may help generate and review content
- AI must not become the runtime judge for everything
- all learning decisions must be **explainable**

---

## 2. Engine Layers

The target-state engine has seven layers. Each layer has a clear input,
output, and owner. Most layers are **planned**; a thin slice of each already
exists in shipped code and is noted in the layer description.

| # | Layer | Owns |
|---|---|---|
| 1 | Grammar Strategy | Pedagogical thesis — meaning/use/form/contrast/repair |
| 2 | Skill Graph | The set of skills, their prerequisites, their CEFR placement |
| 3 | Exercise Bank | Curated/offline-generated items, tagged to skills + target errors |
| 4 | Evaluation Engine | Deterministic scoring + bounded AI fallback |
| 5 | Mastery Model | Per-learner per-skill state with explicit evidence basis |
| 6 | Decision Engine | What the learner sees next, and why |
| 7 | Transparency Layer | Surfaces the reason behind every grading and routing decision |

### 2.1 Layer 1 — Grammar Strategy

Defined in `GRAM_STRATEGY.md`.

Inputs: pedagogical research, open educational sources.
Outputs: rules about what to teach, in what order, with what contrast.

### 2.2 Layer 2 — Skill Graph

A skill is the smallest pedagogically meaningful, product-visible, measurable
grammar unit (see §4 Skill Model).

Inputs: Grammar Strategy + curriculum scope.
Outputs: a directed graph of skills, prerequisites, and CEFR placement.

Status: **planned**. The current product organises content as `unit → lesson
→ exercise`. The skill graph adds a parallel `skill_id` dimension on top of
that hierarchy. Skill metadata becomes the unit of mastery; the lesson
remains the unit of authoring and delivery.

### 2.3 Layer 3 — Exercise Bank

Curated and/or offline-generated exercises tagged to:

- one primary skill
- one primary target error
- difficulty band
- evidence weight (recognition vs production — see §6)
- response unit shape (single vs multi-unit)

Inputs: Skill Graph + author/QA pipeline.
Outputs: validated, versioned exercise records.

Status: **partially shipped**. Today: JSON fixtures in `backend/data/`,
no `skill_id`, no `target_error`, no evidence weight, no versioning beyond
the file itself. See migration plan.

### 2.4 Layer 4 — Evaluation Engine

Deterministic-first. AI fallback only where it is justified, bounded, and
auditable.

Inputs: learner attempt + exercise definition.
Outputs:
- `correct | partial | wrong`
- `evaluation_source` (deterministic / ai_fallback / ai_timeout / ai_error)
- per-response-unit scores when applicable
- canonical answer + curated explanation

Status: **partially shipped**. Today: deterministic exact/normalised match
for `fill_blank`, `multiple_choice`, `listening_discrimination`; AI fallback
only for `sentence_correction` borderline. No partial credit, no
response-unit scoring. See migration plan.

### 2.5 Layer 5 — Mastery Model

Per-learner per-skill state (see §7).

Inputs: attempt history, evidence weights, recency.
Outputs: per-skill score 0–100 + status label + reason string.

Status: **shipped (device-scoped, MVP2 Wave 2)**. Per-skill state lives
in the Flutter `LearnerSkillStore` (`app/lib/learner/learner_skill_store.dart`)
on each learner's device.

### 2.6 Layer 6 — Decision Engine

Chooses the next item, the next lesson, the next review window.

Inputs: Mastery Model state + Skill Graph prerequisites + content available
in the Exercise Bank.

Outputs: next-item or next-lesson recommendation + a machine-readable reason.

Status: **shipped (in-session loop + cadence, MVP2 Wave 3)**. The Flutter
`DecisionEngine` implements the §9.1 1/2/3 loop in-session;
`ReviewScheduler` persists the §9.3 cadence per skill across sessions.
Skill-graph prerequisite traversal is not yet wired (`prerequisites[]`
ships in `skills.json` but no decision yet reads them — that is a Wave
3+ extension).

### 2.7 Layer 7 — Transparency Layer

Surfaces every grading and routing decision in language the learner can act
on.

Inputs: Evaluation Engine output + Mastery Model output + Decision Engine
reason.

Outputs: result panel, skill state panel, "why this next" explanation.

Status: **partially shipped**. Today: per-item result + curated explanation +
post-lesson AI debrief. No skill state UI, no "why this next" UI.

---

## 3. Non-Negotiables

These constraints are stronger than any single feature. They define what
Mastery is and is not.

- **deterministic-first.** The default path is deterministic. AI is a
  bounded helper, never the default judge.
- **backend is source of truth.** The client renders what the backend
  decides. The client never grades, never routes, never persists state the
  backend does not know about.
- **no chat-first UX.** No free-form conversation as the primary interface.
- **no noisy gamification.** No streaks, badges, points, XP / skill
  level-up animations, mascots. CEFR proficiency labels (A1–C2) are
  **not** gamified levels — they describe the curriculum scope and the
  learner's placement, not a competitive ladder, and are part of the
  shipped product surface.
- **adult, premium tone.** Calm, direct, trustworthy coach.
- **production-first mastery.** A learner is not "mastered" on recognition
  alone (see §6).
- **explainable learning decisions.** Every grading and routing decision
  must be explainable in plain language.
- **offline-generated exercise bank.** Items are authored or generated
  ahead of time, reviewed by humans + AI, and frozen at ship time.
- **QA before content acceptance.** Two-agent QA (generator + reviewer)
  must clear an item before it enters the bank.

---

## 4. Skill Model

### 4.1 Definition

A **skill** is the smallest pedagogically meaningful, product-visible,
measurable grammar unit.

- pedagogically meaningful: it expresses one rule decision a learner can
  understand and practise
- product-visible: the learner can see its name, its state, and the
  evidence that drives that state
- measurable: it has a clear, deterministic acceptance contract

A **lesson** is a container; the **skill** is the learning unit.

### 4.2 Skill Identity

In the target state, each skill must declare:

- `skill_id` — stable identifier
- `title` — short human-readable name
- `cefr_level` — A1 / A2 / B1 / B2 / C1 / C2
- `prerequisites[]` — ordered list of `skill_id` that must reach a defined
  mastery floor before this skill is offered as a primary target
- `contrasts_with[]` — sibling skills the learner commonly confuses with
  this one
- `target_errors[]` — the error catalogue this skill is responsible for
  diagnosing (see §5)
- `mastery_signals[]` — the kinds of evidence that count toward this
  skill's mastery (see §6)

These fields are **not** required on shipped fixtures today — the rollout
is gated by `docs/plans/learning-engine-mvp-2.md Wave 1`. Until that wave
lands, the fields are absent from `backend/data/lessons/`, the schema in
`docs/content-contract.md`, and runtime payloads. Agents reviewing or
authoring shipped content should not treat missing `skill_id` as a bug.

### 4.3 Granularity Discipline

A skill should be small enough that:

- one explanation can teach it
- one item can test one decision against it
- one mastery decision can be defended in one sentence

Bad: "use English verbs correctly."
Good: "after `suggest`, use the `-ing` form, not `to + infinitive`."

### 4.4 Status

Status: **planned**. The current product has no `skill_id`. Lessons today
are organised by topic, not by a tagged skill graph. Migration in
`docs/plans/learning-engine-mvp-2.md`.

---

## 5. Error Model

Every target error in the engine must be classified into at least one of
these categories. The category drives:
- the explanation tone
- the choice of follow-up evidence
- the decision-engine response when the error recurs

| Code | Meaning |
|---|---|
| `conceptual_error` | The learner has the wrong mental model of the rule |
| `form_error` | The learner has the right rule but wrong surface form |
| `contrast_error` | The learner picked a competing valid-looking pattern |
| `careless_error` | The learner clearly knew the rule but slipped on this attempt |
| `transfer_error` | The learner imported a pattern from their first language (L1) or another known language that does not apply in English (e.g. dropping articles in contexts where Russian or many Asian languages would; misusing a cognate's syntax) |
| `pragmatic_error` | The learner produced a grammatically valid but pragmatically wrong choice (wrong register, wrong politeness, wrong tense for the discourse function — e.g. using bare imperative in a request to a stranger, using simple past where reported speech requires backshift) |

`transfer_error` and `pragmatic_error` exist because grammar mastery is not
only about whether a sentence parses. Many adult-learner errors are
grammatical at the sentence level but wrong at the language-system level
(transfer) or wrong at the discourse level (pragmatics). The engine must
be able to name and route these without forcing them into the four older
buckets.

Routing notes:

- `transfer_error` items should preferentially trigger contrast lessons that
  put the L1-import pattern next to its English counterpart, rather than
  pure repair drills
- `pragmatic_error` items should preferentially trigger dialogue-completion
  or context-reframing items, not surface-form drills
- when an item could be classified as either `form_error` or
  `transfer_error`, prefer `transfer_error` if the same error reproduces
  the L1 default — the more diagnostic label wins

Authoring requirement: every shipped exercise in the target state must
declare its `primary_target_error`. Multi-error items (see §8) must declare
one primary plus a list of secondary errors, and every error must roll up
to the **same primary skill and the same primary target error** (see §8.3).

The catalogue may be extended over time. New entries must be added here
first, before they appear in any exercise metadata.

---

## 6. Evidence Model

### 6.1 Evidence Hierarchy

Not all attempts are worth the same.

| Tier | Evidence kind | Why it counts |
|---|---|---|
| Weak | Recognition (e.g. multiple choice, listening discrimination) | Learner picked the right answer from a small set; could have guessed |
| Medium | Constrained completion (e.g. single-blank, multi-blank) | Learner had to retrieve a form |
| Strong | Correction / repair (sentence correction, multi-error correction) | Learner had to detect and repair a real-looking error |
| Strongest | Production (sentence rewrite, short free sentence) | Learner had to produce a correct form themselves |

### 6.2 Hard Rule — No Recognition-Only Mastery

A learner **must not be marked mastered on a skill based only on recognition
evidence.**

Concretely, for any skill to enter `mastered` (see §7), the attempt history
for that skill must contain at least one strong-tier or strongest-tier
correct attempt.

### 6.3 Hard Rule — Strongest-Tier Evidence Must Test Meaning + Form

Production-tier (`strongest`) evidence counts toward mastery **only when
the item tested meaning together with form, not surface form alone.**

Operational definition: a production attempt counts as strongest-tier
evidence only when **both** are true:

1. the item required the learner to commit to a meaning (a context, a
   contrast, a scenario the rule had to serve), and
2. the item required the learner to produce the target form themselves —
   not merely select it from a closed set or transform a supplied form
   without a meaning decision.

A surface-only rewrite that mechanically swaps a verb form with no meaning
choice (e.g. "rewrite this sentence in the past simple," with no contextual
cue forcing the learner to choose past simple over a competitor) drops to
**strong-tier** evidence at best, not strongest-tier.

This is the engine-side counterpart of `GRAM_STRATEGY.md §11.1
Production Is A Gate, Not A Bonus`. Production is the mastery gate
specifically because meaning-coupled production is the only attempt shape
that proves the learner can deploy the rule when reality calls for it.

### 6.4 Production Gate For Mastery

A skill cannot enter `mastered` (per §7.2) until the attempt history for
that skill contains at least one strongest-tier correct attempt that
satisfies §6.3 (meaning + form).

Strong-tier (repair) evidence is the **typical** path toward the
production gate but it is **not separately required**. A strongest-tier
correct attempt that satisfies §6.3 already clears the §6.2 floor
(at-least-one strong-or-stronger correct attempt) on its own, so a
learner who reaches the production gate without ever taking a repair item
can still be marked mastered. What strong-tier evidence cannot do is
**substitute** for the gate: a learner who only ever corrects mistakes
others have made has not yet shown they can produce the rule under their
own steam.

### 6.5 Evidence Tagging

Every exercise record in the Exercise Bank must declare:

- its evidence tier
- for strongest-tier items: an explicit `meaning_frame` field showing what
  meaning the learner must commit to (so the §6.3 rule can be audited)

The Evaluation Engine emits the tier with each attempt result. The Mastery
Model uses the tier to weight the attempt and to enforce the §6.4 gate.

Status: **shipped (metadata layer)**. `evidence_tier`, `skill_id`,
`primary_target_error`, and (where applicable) `meaning_frame` ship on
every exercise of the shipped B2 lessons (`docs/plans/learning-engine-mvp-2.md`
Wave 1). Backend validates them; the Mastery Model consumes them on the
client (Wave 2). New exercise families introduced in later waves must
declare these fields at authoring time per `docs/content-contract.md
§1.2`.

---

## 7. Mastery Model

### 7.1 Internal Representation

Per learner, per skill, the engine maintains:

- `mastery_score` — internal `0–100`
- `status` — derived label (see §7.2)
- `last_attempt_at` — recency for review scheduling
- `evidence_summary` — counts of attempts at each evidence tier
- `recent_errors[]` — last N target-error codes seen on this skill
- `production_gate_cleared` — bool. Set to `true` the first time the
  learner records a strongest-tier correct attempt that satisfies §6.3
  (meaning + form). Stored, not re-derived per request, so the gate
  cannot silently flip back if older attempts are pruned from
  `evidence_summary`. The migration plan introduces this field in
  `docs/plans/learning-engine-mvp-2.md` Wave 2.

`status` is a **derived label**: the engine computes it on read from
`mastery_score`, `evidence_summary`, `production_gate_cleared`, and
recency. `production_gate_cleared` is a **stored flag**: once set, only an
explicit invalidation (e.g. an `evaluation_version` bump per §12.3) may
clear it. The other fields above are stored per attempt.

### 7.2 Status Labels

Statuses are derived from the score, the evidence summary, and recency.
Exact thresholds are tunable; the labels themselves are part of the
contract.

| Status | Meaning |
|---|---|
| `started` | At least one attempt; not enough evidence to judge |
| `practicing` | Score climbing on weak/medium evidence; no strong evidence yet |
| `getting_there` | Strong evidence appearing; score positive but unstable |
| `almost_mastered` | Strong evidence converging; one or two stable signals away from mastery |
| `mastered` | Threshold passed AND no-recognition-only constraint (§6.2) AND at least one strongest-tier correct attempt that satisfies the meaning + form rule (§§6.3, 6.4) AND a stable median in the latency green band (Wave D — see §7.5) |
| `review_due` | Previously mastered; recency window expired, scheduled review pending |

`graduated` is not a separate status. It is an additional **flag** that
the Decision Engine sets on top of `mastered` once the cadence in §9.4
clears. A graduated skill remains in `mastered` for §7.2 purposes; the
flag controls only review scheduling (§9.4) and surfaces in the
Transparency Layer (§11.2) as "graduated from review." A graduated skill
that fails in mixed review or contrast loses the flag and drops back into
the cadence per §9.4.

### 7.3 Mastery Is Not Just Accuracy

Mastery requires:
- accuracy
- evidence-tier breadth (per §6.2)
- a strongest-tier correct attempt on the production gate (per §§6.3, 6.4)
- a stable median in the latency green band (per §7.5 Wave D)
- stability across nearby contrast skills (per `GRAM_STRATEGY.md §11`)
- absence of recurring same-error patterns

A high accuracy score on weak evidence alone is **not** mastery. Neither is
a high accuracy score on strong-tier (repair) evidence alone — the
production gate must clear.

### 7.4 Status

Status: **shipped (device-scoped, MVP2 Wave 2)**. The Flutter
`LearnerSkillStore` (`app/lib/learner/learner_skill_store.dart`) holds
the §7.1 record per skill, persisted via SharedPreferences and updated
from `SessionController.submitAnswer` after every evaluation. Status is
derived on read via `LearnerSkillRecord.statusAt(now)`; only the
`mastery_score`, `evidence_summary`, `recent_errors`, `last_attempt_at`,
and the sticky `production_gate_cleared` flag are stored. V0 score
deltas live in `LearnerSkillStore._scoreDelta` and are tunable; the
**labels** in §7.2 are part of the contract. No UI surface yet — Wave 4
introduces the per-skill panel. Server-side learner storage is a
follow-up wave once accounts exist.

### 7.5 Per-skill response-time history (Wave A — measurement-only)

The automaticity pivot adds one client-side signal that no part of the
Mastery Model reads yet: the median render→submit latency per skill.

`LatencyHistoryStore` (`app/lib/learner/latency_history_store.dart`) is
a separate, SharedPreferences-backed FIFO of the last 20 response times
(ms) per `skill_id`. The duration is captured in `SessionController`
between the moment an exercise enters `SessionPhase.ready` and the
moment `submitAnswer` fires — strictly client-side, before the network
call, so AI-fallback latency does not pollute the measurement.

The store is **deliberately separate** from `LearnerSkillStore`:

- The server has no `response_time_ms` column on `/me/skills/...`.
  Threading it through would force a backend contract change in a
  measurement-only wave.
- Latency is a per-device signal (different keyboard, different
  median); cross-device sync would dilute it.
- A separate store can be promoted to a pluggable backend later
  without touching the existing Mastery Model fields.

Sequencing:

- **Wave A — shipped.** Measurement only. Per-skill FIFO + median
  accessor. No UI, no formula change.
- **Wave B — shipped, then retired in G7.** A 3px green / amber /
  red `LatencyBand` ("PACE") rail rendered the per-skill median
  on the exercise screen as advisory feedback. Founder-test on
  the live deploy showed PACE was confusing — a verdict on past
  speed delivered before the learner had answered the current
  item. Replaced by `CountdownBar` (G7).
- **Wave D — shipped.** Median latency now gates `mastered`.
  `LearnerSkillRecord` carries an in-memory
  `medianResponseMsSnapshot` populated by the `LearnerSkillStore`
  facade on every read/write from
  `LatencyHistoryStore.stableMedianFor(skillId)` (a new accessor
  that returns `null` until the skill has at least
  `defaultMinSamplesForStableMedian` = 5 timed attempts, so a
  single fast attempt can not flip the gate on its own).
  `statusAt` adds one condition to the §7.2 mastered-gate trio:
  the snapshot must be non-null AND
  `< latencyMasteryGreenThresholdMs` (= 6000ms). Without it the
  skill caps at `almost_mastered`. The snapshot is **never
  persisted** — latency is a per-device signal (`§7.5` rationale)
  and the backend store has no `response_time_ms` column.
  Promoting the snapshot into the record on read is the contract
  that lets `statusAt` stay synchronous.
- **Wave G7 — shipped.** `CountdownBar`
  (`app/lib/widgets/countdown_bar.dart`) replaced the retired
  Wave B rail. A 60-second bar shrinks left-to-right, green →
  amber (never red), key'd on `exercise_id` so it resets on
  every fresh item. Visual only — does NOT block submit, the
  learner can answer at any time. The render→submit duration
  capture (Wave A) is unchanged, so the latency-driven
  engine-tuning backlog item still has its data stream.

---

## 8. Exercise Model (Engine View)

The exercise authoring rules live in `exercise_structure.md`. This section
records only the engine-level invariants the Decision and Mastery layers
depend on.

### 8.1 V1 Rule

**1 exercise = 1 primary skill + 1 primary target error.**

This rule exists so that:
- attempts produce clean evidence on a single skill
- explanations stay specific
- mastery accounting stays defensible

### 8.2 Response Units

An exercise may contain multiple **response units** — discrete decisions the
learner makes inside a single item (e.g. two blanks, three correctable spans).

Engine requirement: the Evaluation Engine must produce per-response-unit
results when an item has multiple units, and the Mastery Model must be able
to weight them independently.

### 8.3 Multi-Error Items

A single item may target multiple errors **only when those errors all roll
up to the same primary skill and primary target error**. This is reserved
for the `multi_error_correction` family (see exercise families §8.4).

### 8.4 Exercise Families V1 (target-state)

The engine targets nine exercise families. **Most are not shipped today.**
Shipped runtime widgets are listed in `exercise_structure.md §3.2`.

| Family | Evidence tier | Status | Authoring contract |
|---|---|---|---|
| `single_choice` | Weak | shipped as `multiple_choice` | `exercise_structure.md §4.2` |
| `multi_select` | Weak | planned | `exercise_structure.md §5.6` |
| `single_blank` | Medium | shipped as `fill_blank` | `exercise_structure.md §4.1` |
| `multi_blank` | Medium | planned | `exercise_structure.md §5.7` |
| `sentence_correction` | Strong | shipped | `exercise_structure.md §4.3` |
| `multi_error_correction` | Strong | planned (same primary skill / target error) | `exercise_structure.md §5.8` |
| `sentence_rewrite` | Strongest when meaning-coupled per §6.3 (with `meaning_frame`); otherwise Strong | shipped (Wave 14.2) | `exercise_structure.md §5.1` |
| `short_free_sentence` | Strongest when meaning-coupled per §6.3 (with `meaning_frame`); otherwise out of scope | shipped (Wave 14.4) | `exercise_structure.md §5.5` |
| `listening_discrimination` | Weak | shipped (auditory recognition variant) | `exercise_structure.md §5.9` |

The shipped families are described in detail in `exercise_structure.md
§§4.1–4.3, §5.9`. The planned families are sketched in `exercise_structure.md
§§5.1, 5.5, 5.6, 5.7, 5.8` and finalised when their widgets are scoped.

### 8.4.1 Per-Family Engine Safeguards

The authoring contracts above carry the full rules. The engine itself must
enforce these invariants when the family is wired into the runtime:

- **`multi_select`** — declared scoring rule (exact-set or bounded
  partial). The runtime must reject items whose declared rule allows
  "select everything" to score higher than "select nothing." See
  `exercise_structure.md §5.6 Scoring rule`.
- **`multi_blank`** — no interdependent blanks. The runtime evaluates each
  blank against its own accepted-answer set; cross-blank scoring is
  forbidden. See `exercise_structure.md §5.7 No interdependent blanks`.
- **`multi_error_correction`** — same primary skill, same primary target
  error across all spans (per §8.3). No-error decoy spans are allowed only
  when the item declares `allows_no_error_spans: true` and the lesson is
  not a rule-introduction lesson. See `exercise_structure.md §5.8`.
- **`sentence_rewrite`** — bounded answer-space discipline. The runtime
  must score against an enumerated `accepted_rewrites` list (cap `≤ 3`,
  matching `sentence_correction`); broader meaning-equivalent paraphrases
  are out of scope. See `exercise_structure.md §5.1 Bounded answer-space
  discipline`.
- **`short_free_sentence`** — bounded AI evaluation. **Shipped runtime
  (Wave 14.4) is AI-only**: there is no canonical answer set to match
  against, so the deterministic gate is reduced to "answer is non-empty
  and provider has the method", and rule conformance is judged by
  `AiProvider.evaluateFreeSentence`. Authors keep `accepted_examples`
  short (≤ 3) for grounding. The original target-state safeguard
  (deterministic structural + meaning-frame checks before AI) remains
  the engineering goal but is not yet enforced at the runtime; see
  `exercise_structure.md §5.5 Scoring discipline` for the target.

These safeguards are non-negotiable. A family that cannot be implemented
under its safeguard is not ready to ship; it must be re-scoped or deferred
rather than relaxed.

### 8.5 Difficulty

Difficulty bands are `easy / medium / hard`.

Hard rule: **do not make difficulty by mixing unrelated grammar skills.**
Difficulty is raised by:
- raising decision load on the same skill
- moving to a richer surface (longer prompt, more distractors, less hint)
- contrast pressure with a sibling skill the learner has already met

Difficulty is **not** raised by stacking obscure vocabulary, dense cultural
references, or unrelated grammar.

### 8.6 Distractors

Distractors must be **diagnostic**: each distractor must reflect a real
learner error from the §5 catalogue. A distractor that no real learner would
produce is a wasted slot.

### 8.7 Partial Credit

V1 supports `wrong | partial | correct` at the item level.

Multi-unit items must support response-unit scoring. The aggregate item
result is derived deterministically from the per-unit results (rule TBD per
family in `exercise_structure.md`).

Status: **shipped (response shape, MVP2 Wave 5)**. The
`POST /lessons/{lesson_id}/answers` endpoint emits `result`,
`response_units`, and `evaluation_version` per `docs/backend-contract.md`.
The legacy `correct: bool` field is preserved for backwards compat.
Single-decision families shipped today (`fill_blank`, `multiple_choice`,
`sentence_correction`, `listening_discrimination`) emit `result` of
`"correct"` or `"wrong"` and an empty `response_units` array. The
`"partial"` value and populated `response_units` are reserved for the
Wave 6 multi-unit families (`multi_blank`, `multi_error_correction`,
`multi_select`).

---

## 9. Learning Loop V1

When a learner errs on a target skill, the engine must respond — not silently
move on, and not endlessly repeat.

### 9.1 In-Session 1/2/3 Loop

| Mistake # | Engine response |
|---|---|
| 1st | Show the curated explanation. Schedule a similar item on the same skill, in a new surface (different trigger, different exercise type). |
| 2nd | Show a hint. Simplify or change the exercise type so the learner meets the rule from a different angle. |
| 3rd | Stop repeating in this session. Mark the skill weak. Move on. Schedule a review later. |

Hard rules:
- **avoid endless repetition.** Three mistakes in a session ends the loop on
  this skill until a later review window.
- **never punish.** The tone of all three responses stays calm and
  diagnostic.
- the loop is per-skill per-session. A skill that hits 3 mistakes in
  session A may be re-attempted in session B.

Anchor pedagogy: `GRAM_STRATEGY.md §4.8 Reinforce Immediately After Error`.
The static-authoring rule there (adjacent items on the same micro-rule) is a
shipped approximation of this loop. The full loop replaces it once the
engine can pick items at runtime.

### 9.2 Cross-Session Review Trigger

The 1/2/3 loop ends a skill's in-session arc but does not close it. Skills
that ended in the `weak` state, plus skills that previously reached
`mastered` and have not been touched recently, must be **re-offered** to
the learner in a later session.

The re-offer is the engine's response to "mastery requires return"
(`GRAM_STRATEGY.md §4.7`). It is not a punishment for forgetting; it is
the part of the system that makes mastery hold.

### 9.3 Default Review Cadence

The Decision Engine schedules reviews on an expanding-interval cadence by
default:

| Review # | Default interval after the previous correct review |
|---|---|
| 1 | 1 day |
| 2 | 3 days |
| 3 | 7 days |
| 4 | 21 days |
| 5+ | 21 days, capped (or graduated; see §9.4) |

How the cadence interacts with state:

- A skill enters the cadence at step 1 the first time it reaches
  `almost_mastered` or `mastered`.
- A correct review attempt advances the skill to the next interval.
- A wrong review attempt resets the skill to step 1 of the cadence and
  flips its status back to `practicing` or `getting_there` per §7.2.
- A skill that finishes a 1/2/3 loop with `weak` state (per §9.1, 3rd
  mistake) enters the cadence at step 1 with status `practicing`.

These intervals are **defaults**, not hard contract. They may be tuned per
CEFR level, per skill type, or per learner — but any tuning must:

- preserve the expanding shape (each step ≥ the previous step),
- keep the first interval ≥ 1 day (no same-session re-tests beyond the
  in-session 1/2/3 loop),
- ship a one-line reason the learner can read in the Transparency Layer
  (§11.3) when a review fires.

### 9.4 Cadence Graduation

After a skill clears the four default reviews without resetting, the
Decision Engine may flag it as `graduated` and stop scheduling individual
reviews. Graduated skills still surface in mixed-review lessons but no
longer drive standalone review prompts.

Graduation is a soft signal, not a guarantee. A graduated skill that fails
in mixed review or in a contrast item drops back into the cadence at
step 1.

Status: **shipped (engine-side, MVP2 Wave 3)**. The Flutter
`DecisionEngine` (`app/lib/learner/decision_engine.dart`) implements the
in-session 1/2/3 loop on top of the Wave 1 metadata trio: it re-orders
the remaining-exercise queue when the learner misses a skill, and ends
the loop on that skill at the third mistake. The cross-session cadence
lives in `ReviewScheduler` (`app/lib/learner/review_scheduler.dart`),
which persists the §9.3 step + due time per skill on session end and
exposes `dueAt(now)` for the dashboard. No UI surface yet — the §11.3
reason string is held on `SessionState.lastDecisionReason` and the
review-due list is read on demand; Wave 4 renders both.

---

## 10. Diagnostic Mode

A short onboarding diagnostic is **required** in the target state.

### 10.1 Shape

- 5–7 exercises
- skippable; manual level selection is the fallback
- mixes evidence tiers so the engine can probe multiple skills
- never penalises the learner — it is a placement probe, not a grade

### 10.2 Output

The diagnostic produces:

- a coarse user level (CEFR band the engine starts at)
- an initial skill map for the level — which skills are touched, which are
  open
- internal mastery estimates per touched skill (initial state for the
  Mastery Model)

### 10.3 Re-callable

The diagnostic must be re-callable later (e.g. when the learner crosses a
level boundary or returns after a long absence). It is not a one-shot
onboarding step.

Status: **planned**. The shipped onboarding is a 2-step ritual that
introduces the product but performs no diagnosis. See
`docs/plans/arrival-ritual.md` and `docs/plans/learning-engine-mvp-2.md`.

---

## 11. Transparency Layer

Every learner-visible decision must be explainable.

### 11.1 Per-Attempt Surface

After every attempt the learner sees:
- the result (correct / partial / wrong)
- the canonical answer
- the curated rule explanation (per `exercise_structure.md §10`)

These ship today.

### 11.2 Per-Skill Surface

In the target state, the learner can see, for each skill they have touched:
- the current status (per §7.2)
- a one-line reason for that status (e.g. "two strong correct in a row")
- the most recent error pattern on this skill, if any

Status: **shipped (MVP2 Wave 4)**. The Flutter `SkillStateCard`
(`app/lib/widgets/skill_state_card.dart`) renders one row per skill on
the post-lesson summary screen, filtered to the skills the just-finished
lesson touched. Status copy and reason-line rule live in the same file;
the recurring-error row appears when the same target-error code has
been observed twice in the last five attempts on that skill. V0
thresholds; tunable.

### 11.3 Per-Routing Surface

When the engine selects the next item, lesson, or review, the learner can
see a one-line **why this next** explanation:

- "You missed `since` vs `for` twice — let's revisit it on a new sentence."
- "You haven't seen `-ing` after `suggest` in two weeks — short review."
- "You're close to mastering the present perfect contrast — one more strong
  item."

Status: **shipped (MVP2 Wave 4)**. The Flutter `DecisionReasonLine`
(`app/lib/widgets/decision_reason_line.dart`) renders the §11.3 reason
on the next exercise (`SessionPhase.ready`), not above the
just-answered question. The reason source is
`SessionState.lastDecisionReason`, set by the `DecisionEngine` in Wave 3
and surviving the `advance()` transition exactly once. The dashboard
review-due teaser (`app/lib/widgets/review_due_section.dart`) renders
every non-graduated skill returned by `ReviewScheduler.dueAt(now)`; the
section collapses to nothing when the list is empty per §11.4 calm
silence.

### 11.4 Tone

Calm, direct, trustworthy coach. No emojis, no encouragements that aren't
earned, no fake stakes, no shaming.

---

## 12. Content Strategy

### 12.1 Offline Exercise Bank

The exercise bank is built **offline**, not at runtime.

Items are authored, generated, reviewed, frozen, and shipped. The runtime
selects from the frozen bank; it does not invent new items at request time.

### 12.2 Two-Agent QA

Every candidate item passes through two roles before entering the bank:

| Role | Responsibility |
|---|---|
| `generator` | Drafts the candidate item against authoring rules in `exercise_structure.md`. May be human or AI-assisted. |
| `reviewer` | Independently verifies the item against the same authoring rules + the engine invariants in §8. May be human or AI-assisted, but must be a **different** identity than the generator on the same item. |

Both roles must record:
- the rule the item targets
- the target error
- the evidence tier
- the distractor logic (where applicable)
- the QA verdict

A candidate item is accepted into the bank only when both roles sign off.

**Status (2026-04-28).** Tooling for both roles ships in V1.5:
`backend/scripts/gen-content.ts` (Wave 14.5) is the AI-assisted
generator, and `backend/scripts/qa-content.ts` (Wave 14.7) is the
AI reviewer with a different system prompt (= different identity).
The reviewer's per-type rubric (in `backend/src/content-qa/rubric.ts`)
records rule alignment, target-error match, evidence-tier
defensibility, and the per-family safeguards from §8.4.1 — the
artefacts §12.2 requires. The methodologist remains the
human-in-the-loop sign-off before items merge from `staging/` into
`lessons/`; the AI reviewer's job is to filter the obvious failures
so methodologist time goes to borderline calls.

### 12.3 Versioning

Three independent version axes are required:

- `exercise_version` — bumped when an item's prompt, options, accepted
  answers, or feedback change
- `skill_version` — bumped when a skill's identity changes (target errors,
  prerequisites, contrasts)
- `evaluation_version` — bumped when the Evaluation Engine's behaviour for
  any family changes (e.g. partial-credit rules, AI fallback bounds)

Mastery records persist the versions they were observed under, so historical
attempts can be re-interpreted or invalidated cleanly.

Status: **planned**. Today there is no version field on exercises, skills,
or the evaluator.

### 12.4 AI Boundary

AI is allowed in:
- offline content drafting
- offline content review
- runtime borderline `sentence_correction` evaluation
  (shipped, guard-railed)
- post-lesson debrief generation (shipped, guard-railed)
- runtime borderline grammaticality evaluation for `short_free_sentence`,
  bounded by the §8.4.1 safeguard (planned; ships only with the
  `short_free_sentence` family and only after the deterministic structural
  and meaning-frame checks pass)

AI is **not** allowed in:
- runtime exercise invention
- runtime correctness decisions outside the bounded fallback envelopes
  named above
- runtime mastery decisions
- runtime routing decisions

The two fallback envelopes above are the **only** runtime correctness
paths AI may participate in. Every other family must score deterministically
end-to-end. If a future workstream wants to widen this boundary, it must
update this section first, then `GRAM_STRATEGY.md §13.3 Runtime Principle`,
then the runtime contracts.

---

## 13. Engine ↔ Runtime Contract Map

Each engine concept has a runtime touchpoint. Anything the runtime does
**not** yet support is marked planned.

| Engine concept | Runtime touchpoint today | Status |
|---|---|---|
| Skill graph | none — lessons are organised by topic | planned |
| Exercise bank tagging | JSON fixtures in `backend/data/`; no `skill_id`, `target_error`, or evidence tier | planned |
| Deterministic evaluation | `backend/src/evaluation/*` (per `docs/backend-contract.md §Evaluation Logic`) | shipped |
| AI fallback | `sentence_correction` borderline only (per `docs/backend-contract.md §Step 5`) | shipped |
| Partial credit | none — boolean correct/incorrect only | planned |
| Response-unit scoring | none — one decision per item | planned |
| Mastery state | none — no per-skill state stored | planned |
| Decision engine | none — fixed lesson order | planned |
| Review cadence (1d / 3d / 7d / 21d, §9.3) | none — no scheduling layer | planned |
| Diagnostic mode | none — 2-step onboarding ritual only (per `docs/plans/arrival-ritual.md`) | planned |
| Transparency — per attempt | result panel + curated explanation + AI debrief | shipped |
| Transparency — per skill | none | planned |
| Transparency — per routing | none | planned |
| Two-agent QA | informal authoring; `english-grammar-methodologist` skill required for new content | partial |
| Versioning | none on exercise / skill / evaluator | planned |

The migration from this state to the engine MVP 2.0 is sequenced in
`docs/plans/learning-engine-mvp-2.md`.

---

## 14. Validation Standard

A change to the engine is below standard if it:

- claims a planned layer is shipped when the runtime does not implement it
- silently expands the AI boundary
- introduces a mastery decision that cannot be explained in one sentence
- introduces a routing decision the learner cannot see a reason for
- mixes exercise authoring rules into the engine spec (those belong in
  `exercise_structure.md`)
- mixes pedagogical thesis into the engine spec (that belongs in
  `GRAM_STRATEGY.md`)

Engine-level changes that pass this standard belong in this document and
should propagate downward into the runtime contracts in lockstep with the
shipped change.
