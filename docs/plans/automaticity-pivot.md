# Automaticity pivot — roadmap

**Status:** Waves 0 / A / B / C / D / G1–G9 shipped. Live web build
serves first users at `https://mastery-web-igotsty1e.onrender.com`
with real OpenAI grading (`gpt-4o`), product analytics, and a
calm 60-second countdown bar. Wave G9 reordered the first-touch
flow to onboarding → diagnostic → first session, with the dashboard
becoming a post-first-session reward. **Next up: Wave H1**
(textbook-format rule cards) and **Wave H2** (dual-verdict AI judge,
tutor critically evaluates alongside deterministic match). Wave E
(diagnostic redesign), Wave F (hint stripping), and the
engine-tuning backlog item are sketched but not started.

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

## Wave H1 — Textbook-format rule cards (planned, next)

**Why.** The shipped `intro_rule` field is a flat string with
`\n\n`-separated sections. It looks like a paragraph dump, not a
rule the learner can scan and reference. The reference image
(textbook page on `-ing form` verbs) defines the target visual
contract:

- a header plate with the rule title (e.g.
  `verb/noun/adjective phrase + -ing form`);
- a one-line rule statement in the learner's grammar voice;
- a ✓ example sentence (target form bolded);
- a multi-column list of pattern members (4–6 columns, ~20–30
  verbs/phrases) so the learner sees the *scope* of the rule, not
  just the three examples we picked;
- one or more `Watch out!` callouts for nuance / object-before-ing
  / preposition-then-ing / common L1-driven slip.

**Schema.** New `rule_card` object, additive to `intro_rule` (kept
as fallback so older lessons keep rendering). Shape:

```jsonc
"rule_card": {
  "title": "verb + -ing form",
  "rule": "Some verbs are usually followed directly by the -ing form, not by `to + infinitive`.",
  "examples": [
    {"text": "I enjoy working with international clients.", "highlight": "working"}
  ],
  "pattern_lists": [
    {
      "label": "Verbs that take + -ing form",
      "items": ["admit", "appreciate", "avoid", "can't help", "delay", "deny", "detest", "discuss", "dislike", "enjoy", "escape", "face", "fancy", "feel like", "finish", "give up", "involve", "keep (on)", "mention", "mind", "miss", "postpone", "practise", "put off", "resist", "risk", "suggest", "understand"]
    }
  ],
  "watch_outs": [
    {"text": "Some of these verbs can also be followed by an object before the -ing form.", "example": "I can't stand people cheating in exams."},
    {"text": "After a preposition, we almost always use an -ing form.", "example": "I'm interested in hearing more about that course."}
  ]
}
```

Rendered in two places: the `LessonIntroScreen` (replaces the
current flat-string render) and the `_RulesLibrarySheet` on the
home dashboard. One Flutter widget, `RuleCard`, lives in
`app/lib/widgets/rule_card.dart`. When `rule_card` is missing on a
lesson the existing flat-string renderer is the fallback, so the
ship can be incremental (one lesson at a time).

**Content authoring** is gated behind the
`english-grammar-methodologist` skill per `CLAUDE.md`. Authority
chain: Murphy / Swan / EGP for verb lists, Cambridge English
Grammar Profile for the level fit (B2-only for the current 5
lessons).

**Doc updates.** Add the schema to `content-contract.md`. Note in
`exercise_structure.md §4` that lessons SHOULD ship a `rule_card`
when authored fresh. The flat `intro_rule` stays valid as a
historical / minimal form.

---

## Wave H2 — Dual-verdict AI judge (planned, follows H1)

**Why.** Today the verdict logic is split by exercise type:
`fill_blank` / `multiple_choice` / `listening_discrimination` are
deterministic-match-only; `sentence_correction` /
`sentence_rewrite` use AI as a borderline fallback;
`short_free_sentence` is AI-only. The split has two failure modes:

1. **False negatives on non-target slips.** A learner under a
   gerund-vs-infinitive lesson types `enjoying` correctly but
   misspells `restaurants`. The deterministic matcher fails the
   item; the learner thinks they got the *grammar* wrong.
2. **No critical evaluation on cheap types.** A learner can game
   `multiple_choice` with surface-pattern matching and never get
   feedback on whether they actually *understood* the form.

Wave H2 makes the AI tutor a **second judge** on every item, with
explicit knowledge of what's under test (`target_form`) and what
isn't. The combiner grants `correct` if the deterministic match
passes OR if the AI says "target was met, the only error is
off-target". This is closer to how a human teacher grades:
"yes, you used the gerund correctly — the spelling slip is a
separate issue I'll mention but won't fail you on."

**Cost.** +1 AI call per item across all six exercise types
(today: only ~50% of items go through AI). Mitigation: short
prompt, cheap model (`gpt-4o-mini` is back in play for the *judge*
role since it's a structured yes/no on a known target), strict
JSON schema response.

**Schema additions.**

- Lesson-level: `target_form` — single string describing what the
  lesson teaches (e.g. `"-ing form after gerund-only verbs (enjoy,
  avoid, suggest, mind, finish, keep, postpone)"`).
- AI response (new): `{ target_met: bool, off_target_error: bool,
  off_target_note: string|null }`. The new
  `evaluateTargetVerdict(exercise, learnerAnswer, targetForm)`
  call returns this shape. Existing `evaluateFreeSentence` /
  `evaluateBorderline` calls stay as-is for the prompt-rewrite and
  free-sentence paths; H2 adds the new judge alongside.

**Combiner.** In `backend/src/lessonSessions/service.ts`:

- `correct = deterministic.correct || (ai.target_met &&
  !ai.off_target_error_blocks_score)`;
- when `deterministic.correct === false` AND `ai.target_met ===
  true` AND `ai.off_target_error === true`, the final verdict is
  `correct` and the explanation appends a soft note: *"the form
  was right; small spelling slip — `${off_target_note}`"*.
- AI failures (timeout / 5xx / schema mismatch) fall back to the
  deterministic verdict. The system stays honest under degraded AI.

**Doc updates.** Update `LEARNING_ENGINE.md §6.3` (verdict model)
to name the dual-judge architecture; add the `target_form` field
to `content-contract.md`. Note in `backend-contract.md` that the
AI judge is now part of the standard scoring path, not just the
free-form / borderline fallback.

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
