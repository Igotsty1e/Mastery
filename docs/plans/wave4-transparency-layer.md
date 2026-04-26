# Wave 4 — Transparency Layer

> Status: **draft, awaiting design + scope approval.** Engine plumbing
> for this wave (DecisionEngine reasons + LearnerSkillStore status +
> ReviewScheduler.dueAt) all shipped in Wave 3. This doc scopes the UI
> surfaces that render that data per `LEARNING_ENGINE.md §11`.

## 0. Anchor

- **Engine spec (target):** `LEARNING_ENGINE.md §11 Transparency Layer`
  - §11.1 per-attempt — already shipped (curated explanation + canonical
    answer); Wave 4 does **not** touch this surface
  - §11.2 per-skill — current status, one-line reason, recent error pattern
  - §11.3 per-routing — "why this next" string when the engine reordered
    or scheduled the item
  - §11.4 tone — calm, direct, no emojis, no fake stakes
- **Engine plumbing (shipped, Wave 3):**
  - `LearnerSkillStore.getRecord(skillId).statusAt(now)` returns
    `SkillStatus` per §7.2
  - `LearnerSkillRecord.recentErrors` carries the last N target errors
    per §7.1
  - `SessionState.lastDecisionReason` carries the §11.3 string from the
    most recent `DecisionEngine` decision
  - `ReviewScheduler.dueAt(now)` returns sorted `ReviewSchedule[]` for
    skills due at or before `now`
- **Visual contract (locked):**
  - `DESIGN.md` — tokens (color / typography / spacing / motion)
  - `docs/plans/dashboard-study-desk.md` — shipped Dashboard V2 contract.
    Adding a new card to the dashboard is a **per-screen visual change**
    per `CLAUDE.md §Behavior Rules` and needs explicit approval.
  - `docs/plans/arrival-ritual.md` — Brief B (first-exercise V2 chrome)
    was declined; the current exercise chrome is the long-term contract.
    **Wave 4 does not touch the exercise screen chrome.**

## 1. Goal

Make every routing and grading decision the engine makes legible to the
learner, in language they can act on. Three concrete user-visible
surfaces:

1. **Per-skill panel** (per §11.2). Where: dashboard or post-lesson
   summary (design call). For each skill the learner has touched: status
   label, one-line reason, recent error pattern.
2. **"Why this next" string** (per §11.3). Where: lesson intro and/or
   item intro. Rendered only when the `DecisionEngine` substituted the
   item — silent on the linear default.
3. **Review-due surface** (per §9.3 / §11.3). Where: dashboard. Lists
   skills `ReviewScheduler.dueAt(now)` returns, surfaced before "next
   lesson" content per the Wave 3 plan task.

Out of scope:
- Diagnostic mode (§10) — separate wave.
- Mixed-review lesson generator — pulls from §9.4 graduated cadence,
  separate wave.
- Skill-graph prerequisite chain rendering — `prerequisites[]` ships in
  `skills.json` but no UI yet.
- Per-attempt rewrite — §11.1 surface stays as-is.

## 2. The four open design decisions

These need user approval before implementation begins. Listed in
priority order; each is independent.

### 2.1 Where lives the per-skill panel?

Three viable directions, each with tradeoffs:

| Direction | Where | Pro | Con |
|---|---|---|---|
| **A — Dashboard expansion** | New section on `home_screen.dart` between `_LastLessonReport` and `_CurrentUnitBlock` | Always visible; one screen for all engine state | Pollutes the calm Study Desk dashboard; per-screen approval needed for shipped layout |
| **B — Summary-screen extension** | New `_SkillStateCard` on `summary_screen.dart` between `_DebriefCard` and `_MistakeCard` | Contextual to the just-finished session; doesn't touch dashboard | Only seen at session end; learner who returns later doesn't see updated state |
| **C — Tap-through detail** | New `SkillDetailScreen` route, opened from a small "skills" affordance on dashboard | Dashboard stays calm; rich detail for engaged learners | Discoverability — learners may never tap |

**Recommendation:** **B + small A teaser.** Detailed per-skill panel
lives on the summary screen (high context, calm). Dashboard gets one
condensed surface — the review-due list (§2.3 below) — which carries
the most actionable engine output without crowding the Study Desk.

### 2.2 What does the per-skill panel show?

Per §11.2 the contract is: status, one-line reason, recent error
pattern. Concrete copy proposals (calm-coach tone per §11.4):

- **Status label:** translated from `SkillStatus` enum to learner-facing
  copy:
  - `started` → "Just started"
  - `practicing` → "Practicing"
  - `gettingThere` → "Getting there"
  - `almostMastered` → "Almost mastered"
  - `mastered` → "Mastered"
  - `reviewDue` → "Review due"
- **One-line reason** (derived rule, V0):
  - mastered + production_gate_cleared → "Strongest evidence on this rule
    is solid."
  - almostMastered → "One more strong item to lock it in."
  - gettingThere → "Strong evidence appearing — keep going."
  - practicing → "Recognition is solid; production still ahead."
  - started → "Just one attempt so far."
  - reviewDue → "Last seen N days ago."
- **Recent error pattern** (derived from `recentErrors[]`): when the
  same target-error code appears ≥2 times in the last 5, surface it as
  "Recurring: \<error code\> — \<short copy\>" (e.g. "Recurring:
  contrast — keep watching for `-ing` vs `to`-infinitive."). Otherwise
  hide the row.

**Skill title:** the `Skill.title` lives in `backend/data/skills.json`
but the client has no copy of the registry today. Two options:

1. **Embed a small client-side skill map** in
   `app/lib/learner/skill_titles.dart` for the two shipped skills. Cheap
   and consistent with V0 scope. Update by hand as new skills ship.
2. **Add `GET /skills` endpoint** that returns the registry. Cleaner
   long-term; one new route + one Flutter fetch + caching.

**Recommendation:** option 1 for Wave 4 (V0 scope), option 2 deferred
to Wave 5/6 when more skills land.

### 2.3 What does the dashboard review-due surface look like?

Single condensed row(s) above `_CurrentUnitBlock`. For each skill in
`ReviewScheduler.dueAt(now)`:

- skill title + "Review due" (or "X days overdue")
- tap target → opens lesson on that skill (currently always the same
  lesson per skill since both shipped lessons are 1-skill; later waves
  may surface a review-only mini-session)

When the list is empty: render nothing (no "All caught up!" placeholder
— per §11.4 calm tone, silence is the right state).

### 2.4 What does the "why this next" string look like?

`SessionState.lastDecisionReason` already carries one of three strings
(per Wave 3 implementation):

- "Same rule, different angle." (1st mistake reorder)
- "Same rule, simpler ask." (2nd mistake reorder)
- "Three misses on this rule — moving on for now. We will come back
  later." (3rd mistake skip)

**Where to render:**

- **Item intro** is the right place — between the result panel from the
  previous attempt and the next exercise prompt. Small italic line above
  the instruction, dismissible by scrolling/answering.
- **Lesson intro** can also display the most overdue review reason from
  ReviewScheduler when the lesson opens, e.g. "Picking this up after 3
  days." Optional.

**Visual treatment:** small caption text in `tokens.subtleSubtitle`
weight, no icon, no chip. Single line that's easy to ignore — the kind
of voice a calm tutor uses, not a notification.

## 3. Implementation outline (after design approval)

Once §2.1–§2.4 are answered, implementation breaks into:

1. **Skill-title resolver** — `app/lib/learner/skill_titles.dart` with
   the two-skill V0 map. ~20 lines.
2. **Per-skill panel widget** — new file
   `app/lib/widgets/skill_state_card.dart` rendering status + reason +
   error-pattern row. Pure widget, no state.
3. **Reason-line widget** — new
   `app/lib/widgets/decision_reason_line.dart`, single-line caption
   above the exercise prompt.
4. **Review-due dashboard surface** — depending on §2.1/§2.3, either
   inline in `home_screen.dart` or a small new widget above
   `_CurrentUnitBlock`. Reads `ReviewScheduler.dueAt(now)` on
   `initState` of `_HomeScreenState`.
5. **Wire `lastDecisionReason` into `exercise_screen.dart`** — read
   from `SessionController.state` and render between attempts.
6. **Tests** —
   - widget test: `skill_state_card_test.dart` for each of the six
     SkillStatus labels
   - widget test: `decision_reason_line_test.dart` for visibility
     toggle (null vs. set)
   - integration test: dashboard renders review-due rows when
     `ReviewScheduler` has scheduled entries
7. **Docs sync** —
   - `LEARNING_ENGINE.md §11.2` and `§11.3` flip "planned" → shipped
   - `docs/mobile-architecture.md` adds the three new widgets and
     describes where they read from
   - `DESIGN.md` either gets a `§Wave 4 Transparency` section or remains
     unchanged if the new widgets reuse existing tokens
   - `docs/plans/learning-engine-mvp-2.md` Wave 4 status flips to shipped
8. **Visual approval gate** — before implementation, the per-screen
   visual change to the dashboard (whether it's a teaser per §2.1 or a
   review-due surface per §2.3) needs explicit yes from the user. The
   summary-screen panel in §2.1 also needs explicit yes since the
   shipped summary layout is contract-locked.

## 4. Estimated scope

- Pure-Flutter widgets: ~250-350 lines
- Tests: ~150-200 lines
- Docs sync: ~50-80 lines
- One day of implementation after design discovery is closed.

## 5. Recommended next step

Run `/design-shotgun` for the per-skill panel placement (§2.1) — produces
3-4 visual variants in `docs/design-mockups/` to choose between before
writing Flutter. The other three open decisions (§2.2-§2.4) can be
resolved from this doc directly.

## 6. Linked artifacts

- `LEARNING_ENGINE.md §§11.1-11.4` — engine spec
- `docs/plans/learning-engine-mvp-2.md §Wave 4` — task list
- `docs/plans/dashboard-study-desk.md` — locked dashboard contract
- `app/lib/learner/decision_engine.dart` — reason source
- `app/lib/learner/learner_skill_store.dart` — status source
- `app/lib/learner/review_scheduler.dart` — review-due source
- `DESIGN.md §14 + tokens` — visual rules
