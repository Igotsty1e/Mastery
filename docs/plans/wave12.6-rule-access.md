# Wave 12.6 — Rule Access (post-mistake bridge) + Skill Cap

## Status

**Shipped 2026-04-28.** Plan was locked after methodologist + CEO
consults; both sides shipped:
- Wave 12.6 — `skill_rule_snapshot` field on
  `POST /lesson-sessions/:sid/answers` + Flutter `See full rule →`
  link on `ResultPanel`. Wave H1 (2026-05-01) extended the snapshot
  with the optional structured `rule_card` so the bottom sheet
  renders the textbook view when present.
- Wave 12.7 — public `GET /skills` route + `SkillCatalog` client +
  Rules card on the dashboard. Wave H1 added `rule_card` here too.
- `MAX_SKILLS_PER_SESSION = 2` cap remains in place.

This doc is the historical contract for the wave; backend route
shape is now documented in `docs/backend-contract.md`, and the
Flutter rendering contract lives in `docs/mobile-architecture.md`.

## Why this wave exists

V1 MVP shipped 2026-04-28 with bank-assembled dynamic sessions. Wave
11.x dropped the per-lesson `intro_rule` introduction because there is
no longer "one lesson = one rule" — sessions span skills.

After shipping, the founder asked: *"Почему нет теоретического
материала перед стартом lesson?"*

The right framing isn't "how do we deliver rules for procedural
acquisition" — that's the methodologist's lens, and the answer is the
existing 3-part `feedback.explanation` already covers it. The right
framing is **trust signal for adult B2 learners**: an English-grammar
app without visible theory feels like Duolingo for kids, and adult
learners churn early on that vibe even if the practice quality is
fine.

## Consults summary

**Methodologist (`english-grammar-methodologist`)** — canon survey
(Swan, Murphy, Thornbury, Larsen-Freeman, Ur). Verdict: rule access
on demand is canonically right for adult intermediate learners.
Recommended Option F: first-encounter auto-card + dashboard library
+ post-mistake bridge. Library is the load-bearing piece per Murphy
usage data (~30% of self-directed learners' time on rule pages).

**CEO/founder-mode (`plan-ceo-review`)** — attacked F on product
reality:

- Library of 5 items is laughable. Won't earn its tab.
- Auto-card before exercise = +1 tap of friction; Penny Ur explicit
  that B2 Presentation is optional. Auto-card forces it.
- `skill_id` is still code-string per `learning-engine-v1.md`
  decision #12 («красоту потом»). Library without human-readable
  names is код-салат.

CEO recommended **Mode 4 — Reduction**: ship only the post-mistake
bridge now. Library waits until bank ≥ 15 skills + display names
land. Auto-card probably never in V1.

## What ships in 12.6

### 1. `MAX_SKILLS_PER_SESSION = 2` cap (engine)

`backend/src/decision/engine.ts` adds a second cap alongside the
existing `MAX_NEW_SKILLS_PER_SESSION = 1` (Wave 13). The new cap
counts **all** distinct skills shown in a session, not just brand-new
ones. Once 2 distinct skills are in `shownExerciseIds`, the primary
loop blocks any candidate from a 3rd skill.

The Wave 12.5 `cap_relaxed_fallback` still applies if cap + §9.1
dropout starve the primary loop — sessions never end early.

Pedagogy rationale (per Ericsson on deliberate practice + per
methodologist): focused practice on 1–2 skills per session beats
fragmented exposure to 5. With this cap, worst-case rule-card
volume in any future Library/auto-card design is also bounded.

### 2. Post-mistake "See full rule" bottom sheet (client)

The narrowest wedge that solves the founder pain.

**Backend.** `POST /lesson-sessions/:sid/answers` response gains
`skill_rule_snapshot: { intro_rule: string, intro_examples: string[] } | null`.
The snapshot is sourced from the bank entry's source lesson at
attempt time. Null when the exercise has no `skill_id` (legacy /
diagnostic items can be untagged).

**Client.** `EvaluateResponse` deserialises the new field.
`ResultPanel` (or its Wave 4 successor) renders a quiet `See full
rule →` text link below the curated explanation. Visible on **any**
attempt result (correct or wrong) — adults often want to re-read the
rule after a correct answer to consolidate, not only after a
mistake.

Tap the link → `showModalBottomSheet` opens a sheet with the rule
content. Reuses the existing `_RuleSectionCard` parser from
`lesson_intro_screen.dart` so the visual treatment matches.

The bottom sheet is where the **trust signal** lives. The user sees:
"theory exists, theory is one tap away, theory is good (Murphy /
Swan grade)". That's enough to keep an adult learner engaged.

## What does NOT ship in 12.6

These were considered and explicitly deferred:

- **Library tab on dashboard** → V1.6+. Blocked on (a) bank ≥ 15
  skills (a 5-item library is empty-state theatre) and (b) skill
  display names existing as human-readable strings (decision #12 in
  `learning-engine-v1.md` punted this with «красоту потом»).
- **First-encounter auto-card before the first exercise of each
  skill** → likely never in V1. Forces reading time pre-practice;
  contradicts Penny Ur "B2 Presentation optional" principle. Re-open
  only if D7 retention telemetry shows theory-curious cohort
  benefits — which we won't have for weeks.
- **Spaced repetition of rule recall (rule mastery as a separate
  engine signal)** → V2+. No signal yet that rule recall is its own
  bottleneck.
- **AI-generated personalised hints based on per-learner mistake
  history** → V2+. Over-engineering. Wait for D7 cohort data.
- **Personal "rule notes" (learner can annotate)** → V2+. Creator-
  mode feature, niche.

## Rollout posture

Ship-and-watch, no flag. The post-mistake bridge is additive — it
appears as a quiet text link below the existing explanation. Worst-
case if there's a bug: link doesn't render or sheet doesn't open.
No data lost, no flow blocked.

The skill cap is more sensitive — it changes what items the Decision
Engine surfaces. Worst-case if there's a bug: sessions touch fewer
skills than intended (which is the desired direction anyway). Safety
net is the Wave 12.5 `cap_relaxed_fallback` — sessions never run
out of items.

## Acceptance

- [ ] Engine: regression test — session with 2 already-touched skills
      blocks candidate from a 3rd skill in primary pass.
- [ ] Engine: existing tests still green (cap_relaxed_fallback,
      session_complete short-circuit, all Wave 13 pacing cases).
- [ ] Backend: `/answers` response carries `skill_rule_snapshot` for
      the 50 shipped items; null only when `skill_id` absent.
- [ ] Client: `ResultPanel` renders `See full rule →` link iff
      snapshot is non-null; tap opens bottom sheet with the rule.
- [ ] Widget test: link present, tap opens sheet, sheet content
      matches snapshot.
- [ ] All tests green (target: 314+ backend, 144+ Flutter).
- [ ] Docs: `backend-contract.md` documents the new field;
      `content-contract.md` documents derivation; `learning-engine-v1.md`
      gets a Wave 12.6 entry.

## Out of scope (deferred to V1.6+)

Tracked here so they are not silently re-added to 12.6:

- Library tab + per-skill detail page
- First-encounter auto-card
- Spaced rule recall + rule mastery
- AI-generated hints
- Personal rule notes
- Search across rules
- Skill graph rendered visually with contrast edges

## Open questions for V1.6+ planning

These are not for 12.6 but should be revisited when bank reaches
~15 skills:

1. Does the library tab live on the dashboard (always-on) or behind
   a settings entry (low-prominence)?
2. Do we render skill names as `skill_id` strings until the
   methodologist track produces display names, or block the library
   on display names landing?
3. Is the Wave 4 transparency `SkillStateCard` the right home for
   per-skill rule access, or do rules deserve a separate surface?
