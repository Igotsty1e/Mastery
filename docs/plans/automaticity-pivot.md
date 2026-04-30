# Automaticity pivot — roadmap

**Status:** in flight. Waves 0 / A / B / D shipped. Wave C policy
landed; Wave C content rewrite is the open item. Wave E (diagnostic
redesign) is sketched but not started.

The pivot reframes Mastery from a recognition-shaped grammar app into
a **cognitive skill engine**: pressure → forced generation → strict
feedback → reinforcement → latency reduction. Audit and rationale
in the conversation that opened the pivot (2026-04-30); this file
tracks the shipping waves and what remains.

---

## Wave status (chronological)

### Wave 0 — Dashboard cleanup (shipped, `23f0eea`)

Strip dashboard chrome that did not push the learner toward forced
generation:

- header eyebrow / greeting / sub line removed; only the level
  dropdown remains, right-aligned;
- `M` avatar removed (`_Avatar` deleted);
- Last Lesson Report no longer renders on the dashboard
  (`LastLessonStore` and the backend `lesson_sessions.debrief_snapshot`
  still record it; SummaryScreen still shows the result inline);
- Rules card collapsed behind a single trigger (`_RulesTrigger`)
  that opens a modal bottom sheet (`_RulesLibrarySheet`).

### Wave A — Latency capture (shipped, `d3b3b3a`)

`LatencyHistoryStore` (`app/lib/learner/latency_history_store.dart`) —
per-skill FIFO of the last 20 render→submit durations (ms). Captured
in `SessionController` between `SessionPhase.ready` and `submitAnswer`,
strictly client-side. Lives off the main `LearnerSkillRecord` so the
backend `/me/skills/...` contract is untouched.

### Wave B — Pace band UI (shipped, `f2f1f43`)

`LatencyBand` (`app/lib/widgets/latency_band.dart`) renders a 3px
green / amber / red rail under the `DecisionReasonLine` on the
exercise screen. Reads `LatencyHistoryStore.medianFor(skillId)`.
Hides on un-tagged exercises and skills with no recorded history.
Advisory only at this stage — no scoring effect.

### Wave C — Content shift (policy shipped, content rewrite pending)

Policy lives in `exercise_structure.md §6.7`. Audit script:
`backend/scripts/audit-composition.ts` (run via
`npm run audit:composition`).

Rules:
- `multiple_choice` ≤ 20% of items per lesson;
- `multiple_choice + listening_discrimination` ≤ 30%;
- every lesson must include ≥ 1 `short_free_sentence` and
  ≥ 1 `sentence_rewrite`;
- every `strong` / `strongest` item must carry a non-empty
  `meaning_frame`.

**Open: content rewrite.** All 5 shipped B2 fixtures violate the new
policy; the rewrite is **content authoring**, so per `CLAUDE.md` it
must be done with the `english-grammar-methodologist` skill, not by a
free-form pass. Audit baseline as of 2026-04-30:

| Lesson | items | MC count | recognition (MC+LD) | missing meaning_frame on strong/strongest |
|---|---:|---:|---:|---:|
| b2-lesson-001 (verbs + -ing) | 13 | 3 (23%) | 3 (23%) | 5 |
| b2-lesson-002 (present perfect cont. vs simple) | 13 | 5 (38%) | 6 (46%) | 1 |
| b2-lesson-003 (verbs + to + inf) | 13 | 2 (15%) | 2 (15%) | 3 |
| b2-lesson-004 (verbs with change in meaning) | 13 | 2 (15%) | 2 (15%) | 1 |
| b2-lesson-005 (verbs with both forms) | 13 | 2 (15%) | 2 (15%) | 3 |

Per-lesson rewrite TODO for the methodologist — these items must
ship before the audit script becomes a CI gate (otherwise main goes
red):

- **b2-lesson-001** — drop one MC (down to 2). Add `meaning_frame`
  to 5 items: 1 sentence_correction (`...000038`), 2 sentence_rewrite
  (`...00003b`, `...00003c`), 2 sentence_correction
  (`...000039`, `...00003a`).
- **b2-lesson-002** — drop 3 MC items (down to 2) **or** convert
  some MC to fill_blank to keep the total at 13. Add `meaning_frame`
  to 1 sentence_correction (`...000039`).
- **b2-lesson-003** — add `meaning_frame` to 3 items
  (`...000039`, `...00003b`, `...00003c`).
- **b2-lesson-004** — add `meaning_frame` to 1 item (`...000039`).
- **b2-lesson-005** — add `meaning_frame` to 3 items
  (`...000039`, `...00003b`, `...00003c`).

Until the rewrite lands, `npm run audit:composition` is intentionally
**not** wired into CI. It runs on demand. Once the methodologist
clears the TODO above, flip the script into the pre-merge job
alongside `vitest`.

### Wave D — Mastery latency gate (shipped, `2dd2d20`)

`LearnerSkillRecord` carries a new in-memory `medianResponseMsSnapshot`,
folded in by the `LearnerSkillStore` facade on every read/write from
`LatencyHistoryStore.stableMedianFor(skillId)` (≥ 5 attempts floor).
`statusAt(now)` adds one condition to the §7.2 mastered-gate trio:
the snapshot must be non-null AND `< 6000ms` (same green-band
threshold as Wave B). Without it the skill caps at `almost_mastered`.
Snapshot is never persisted — latency is per-device.

---

## Wave E — Diagnostic redesign (planned)

Replace the shipped 5× `multiple_choice` placement probe with a
mixed-evidence probe:

- 2× `fill_blank` (medium evidence — controlled retrieval),
- 2× `short_free_sentence` (strongest evidence — production with
  `meaning_frame`),
- 1× `sentence_correction` (strong evidence — repair).

Time-to-answer is recorded for each item via the existing
`LatencyHistoryStore` capture path in `SessionController`. The
post-probe screen reports three signals separately:

- recognition fluency (correct rate × speed on `fill_blank`),
- production fluency (correct rate × speed on `short_free_sentence`),
- repair accuracy (correct rate on `sentence_correction`).

Expected output: a CEFR placement *plus* a weakest-link verdict
("recognition is solid; production is the gap — that's where we'll
push first"). This is honest diagnosis, not a placement test.

Implementation gating is content-bound — the probe items must be
authored under the `english-grammar-methodologist` skill alongside
the Wave C rewrite. Engine-side, the existing
`SessionController` + `LatencyHistoryStore` plumbing is enough; no
new client architecture is needed.

---

## Wave F — Hint stripping (planned)

`fill_blank` items today always carry the base-form verb hint
(e.g. `(work)`) per `exercise_structure.md §4.1`. Wave F lets the
`DecisionEngine` strip the hint based on per-skill attempt count:

- attempt 1 on a new skill: hint visible from t = 0;
- attempt 2: hint reveals after 4 s of inactivity;
- attempt 3+: hint not shown.

Same idea as the latency band: speed up retrieval by removing
scaffolding once the rule is internalised. Requires a small change
to `Exercise.prompt` rendering and a new field on the per-attempt
runtime decision. No content-side change.

---

## Out of scope for this pivot

- Streaks, hearts, XP — explicit non-goals in `DESIGN.md` and
  `LEARNING_ENGINE.md §3`.
- Auto-advance on correct + fast — discussed in the audit but
  deliberately deferred. Reading the result and the explanation is
  part of the loop, even on a fast correct.
- Speaking / microphone — out of scope per `GRAM_STRATEGY.md §15.1`.
- Server-side `response_time_ms` — latency stays per-device per
  `LEARNING_ENGINE.md §7.5`.

---

## Doc cross-refs

- `LEARNING_ENGINE.md §7.5` — latency capture and the Wave D gate
  rationale.
- `exercise_structure.md §6.7` — composition rules enforced by the
  audit script.
- `DESIGN.md` — calm tone constraints that the latency band and the
  pace rail both honour.
- `docs/mobile-architecture.md` — Wave A / B / D runtime notes.
- `CLAUDE.md` — reminder that Wave C content rewrites must go through
  the `english-grammar-methodologist` skill.
