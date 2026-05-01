# Automaticity pivot — roadmap

**Status:** Waves 0 / A / B / C / D / G1–G7 shipped. Live web build
serves first users at `https://mastery-web-igotsty1e.onrender.com`
with real OpenAI grading (`gpt-4o-mini`), product analytics, and a
calm 60-second countdown bar. Wave E (diagnostic redesign), Wave F
(hint stripping), and the engine-tuning backlog item below are
sketched but not started.

The composition audit (`npm run audit:composition`) is a pre-merge
CI gate alongside `vitest` in `.github/workflows/backend-test.yml`.

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

### Wave B — Pace band UI (shipped → retired in G7)

`LatencyBand` (originally `app/lib/widgets/latency_band.dart`,
deleted in commit `b3bdd59`) rendered a 3px green / amber / red
rail under the `DecisionReasonLine` on the exercise screen,
labelled `PACE`. The colour came from
`LatencyHistoryStore.medianFor(skillId)` — green for fast, amber
for steady, red for slow. The widget hid itself on un-tagged
exercises and skills with no recorded history; advisory only,
no scoring effect.

**Retired** in Wave G7 because the founder-test on the live
deploy (2026-05-01) showed `PACE` was confusing — it's a
verdict on past speed *before* the learner has answered the
current item, with no contextual hint about what to do with
that verdict. Replaced by `CountdownBar` (Wave G7 below).

### Wave C — Content shift (shipped)

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

Shipped via four content commits, all authored under the
`english-grammar-methodologist` skill per `CLAUDE.md` gating:

- `b092912` — **b2-lesson-001** rewrite. MC `…037` (`enjoy`,
  whole-sentence judgment) converted to `fill_blank` (`enjoy` was
  already double-covered by `…031` and `…03d`); 5 `meaning_frame`
  strings added on items `…038 …039 …03a …03b …03c`.
- `3b0a66a` — **b2-lesson-002** rewrite. Three MC items (`…033`
  `wash` simple, `…035` `write` simple, `…03a` `run` continuous)
  converted to `fill_blank` with the §4.1 `(verb)` hint convention;
  kept `…036` (diagnostic probe) and `…037` (image-supported scene)
  as MC; 1 `meaning_frame` added on `…039`.
- `53ac40e` — **b2-lessons 003 / 004 / 005** metadata sweep. No
  structural changes (those three were already MC-clean); 7
  `meaning_frame` strings added across the three files.

Final audit: 0 violations across all 5 shipped B2 fixtures.

The audit script is wired into the pre-merge CI gate as of the same
commit as this update — it runs after `vitest` in
`.github/workflows/backend-test.yml`. Any future fixture that
violates §6.7 will block the merge.

### Wave D — Mastery latency gate (shipped, `2dd2d20`)

`LearnerSkillRecord` carries a new in-memory `medianResponseMsSnapshot`,
folded in by the `LearnerSkillStore` facade on every read/write from
`LatencyHistoryStore.stableMedianFor(skillId)` (≥ 5 attempts floor).
`statusAt(now)` adds one condition to the §7.2 mastered-gate trio:
the snapshot must be non-null AND `< 6000ms` (the same threshold the
retired `LatencyBand` used to call "fast"). Without it the skill
caps at `almost_mastered`. Snapshot is never persisted — latency is
per-device.

### Waves G1–G7 — Live-web hardening (shipped, 2026-05-01)

Lit-up the public web build for first users:

- **G1** (`93a5910`) — Decision Engine last-resort fallback. When
  every skill in the bank is in §9.1 dropout AND the
  `MAX_SKILLS_PER_SESSION` cap blocks every untouched one, a third
  pass keeps the session alive instead of ending mid-stride. Reason
  code `last_resort_fallback`.
- **G2** (`30e0bea`) + **G2.1** (`6d62604`) — Summary-screen rewrite:
  removed mistake-review section, collapsed the skill panel into a
  compact pill list with a "See progress →" sheet, replaced `Done`
  with prominent `Practice another 10` + quiet `Back to home`,
  shrunk the score hero from 280px → 80px and tightened the
  Coach's note padding.
- **G3** (`e1894b0`) — `StubAiProvider.evaluateFreeSentence` so
  prod can grade `short_free_sentence` even without an OpenAI key
  (lenient by design — operators must wire the real key).
- **G4** (`5b91698`) — product analytics. New `analytics_events`
  table, `POST /me/events` ingest, client-side `Analytics`
  singleton wired into screen views + key buttons. Operator
  queries via psql.
- **G5** (`44e9222`) — silent first-touch auth + share-friendly
  Open Graph / Twitter Card meta + quiet `Send feedback` link
  (mailto `igotstyle227@gmail.com`).
- **G5.1** (`cf51337`) — CORS allowlist hardcodes the public web
  origin so a fresh deploy with no env config still works.
- **G6** (`fa7e3cb` + supporting commits) — `OpenAiProvider`
  evaluator prompt rewritten to a short three-gate shape after
  prod probes showed gpt-4o-mini ignored the longer multi-step
  prompt. 7/7 strict cases pass through the production session
  path. Default model bumped to `gpt-4o`; operator can override
  via `OPENAI_MODEL` env var. `/debug/ai-probe` route stays
  behind `DEBUG_PROBE_TOKEN` for future regressions.
- **G7** (`b3bdd59`) — `LatencyBand` retired, replaced by
  `CountdownBar` (60-second calm shrinking bar, green → amber,
  no red, does NOT block submit, label `TIME` instead of `PACE`).
  Per-skill latency capture (Wave A) is unchanged so the engine
  tuning backlog item below still has its data stream.

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

## Backlog (parked, not started)

These are decisions the founder explicitly tabled for a later
session. Listed here so they don't get lost; each will graduate
into a Wave when picked up.

- **Latency-driven engine tuning.** The `CountdownBar` (Wave G7) is
  visual only; the per-skill render→submit median captured in
  `LatencyHistoryStore` (Wave A) is currently consumed only by the
  Wave D mastered-gate. The future use case named in the
  2026-05-01 product call is **adaptive pacing**: feed the median
  back into the Decision Engine so an over-the-threshold skill
  surfaces more often / sooner, and a fast-stable skill gets
  graduated quickly. Likely shape: a new `pacingTarget` factor in
  `backend/src/decision/engine.ts` that reads
  `LearnerSkillRecord.medianResponseMsSnapshot` (already plumbed
  to the client; would need to land server-side via a new field
  in the `/me/skills` DTO or a separate `/me/pacing` endpoint).
- **Real Apple Sign-In** — currently `signInWithAppleStub`. Real
  Apple IdToken verification lands when the iOS build does.
- **Custom domain** — operator's call. Bind via Render dashboard
  → CNAME on the registrar.
- **Cleanup `/debug/ai-probe`** — diagnostic route shipped in G6.
  Stays gated behind `DEBUG_PROBE_TOKEN` env var (route 404s
  without it). Remove once we trust the production grader for a
  full week without regression.

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
