# Dashboard V2 — Study Desk

## Status

**Shipped 2026-04-26**, then heavily reduced by **Wave 0 (automaticity pivot, 2026-05-01)** — see `docs/plans/automaticity-pivot.md §Wave 0` — and **Wave 11.4 (2026-04-28)** dynamic-session cutover. Wave 0 removed:

- the Study Desk header eyebrow + time-based greeting + sub line (only the level dropdown remains, right-aligned);
- the static `M` avatar circle;
- the on-dashboard Last-lesson-report block (data is still recorded server-side and shown inline on `SummaryScreen`);
- the expanded Rules card (collapsed behind a single `_RulesTrigger` button that opens `_RulesLibrarySheet`).

Wave 11.4 additionally removed:

- the Current-unit card with the `Verbs Followed by -ing` row + locked stub + `All units ▾` trigger (the V1 dynamic flow assembles each session from the skill bank, so a fixed unit listing no longer reflects what the learner will see).

The next-lesson hero, optional `ReviewDueSection`, RulesTrigger, and premium stub remain as shipped. Sections of this spec that describe the retired surfaces are kept for historical context and marked superseded below; **do not implement them without an explicit product-owner reversal of the Wave 0 / Wave 11.4 decisions**.

Implementation: `app/lib/screens/home_screen.dart` (returning-launch state) + the reusable `StatusBadge` widget in `app/lib/widgets/mastery_widgets.dart`. Visual reference: `docs/design-mockups/dashboard-study-desk.html`. The singleton `LastLessonStore` (`app/lib/session/last_lesson_store.dart`) is still written by `SessionController` (data preserved for engine-driven future use), but no longer read for any rendering surface.

Known scope deviations vs the spec text (recorded honestly so future passes don't drift):

- ~~**Last lesson report is in-memory on the client.**~~ Superseded 2026-05-14. The Wave 2 backend `/dashboard.last_lesson_report` is still served, but the on-dashboard block consuming it was retired in Wave 0. The Flutter rebind that was planned for Wave 3 is moot; if the surface ever returns, a fresh client wave will read `/dashboard` directly.
- **Hero progress cluster shows lesson-level exercise progress, not unit-level lesson progress.** The MVP backend ships a single lesson per unit, so the spec's `Lesson 2 / 5` style would be degenerate (`Lesson 1 / 1` always). Switch back when the multi-lesson worktree (`codex/b2-content`) lands.
- ~~**Coming Next block was removed** post-ship. Future units now live behind an `All units ▾` trigger in the Current Unit section header (see §9). Mirrors the level-dropdown pattern.~~ — **Superseded 2026-05-14:** the entire Current-unit card + `All units ▾` trigger were retired in Wave 11.4 along with the fixed lesson listing. The V1 dynamic flow boots a session directly from the next-lesson hero CTA via `POST /sessions/start`.
- **Premium block is a visual stub.** No monetisation in MVP; the block exists as the last-row placeholder per spec.
- **CTA `Start next lesson`** is wired but always disabled until a real next lesson exists. Activates automatically when the multi-lesson backend lands.

Use together with:
- `DESIGN.md` — tokens, component language, interaction tone
- `docs/design-mockups/` — composition reference
- `docs/plans/arrival-ritual.md` — already-shipped onboarding/home contract

---

## 1. Product Role

The dashboard is the single Home of Mastery.

Its job is not to browse content.
Its job is to keep the learner inside a prepared study rhythm:

1. show the next lesson clearly
2. ~~keep the last lesson report within reach~~ — **retired Wave 0 (2026-05-01)**; the post-lesson summary is visible inline on `SummaryScreen` only.
3. ~~preserve textbook-like orientation inside the current unit~~ — **retired Wave 11.4 (2026-04-28)**; the V1 dynamic flow assembles each session from the skill bank, so the current-unit listing was retired along with it.

The dashboard should feel like a **study desk**, not a feed and not a data panel.

---

## 2. Core Principle

The screen must balance:

- **future** — what to study next
- ~~**memory** — what happened in the last lesson~~ — **retired Wave 0 (2026-05-01)**; the post-lesson summary is now visible inline on `SummaryScreen` only, not on the dashboard.
- **structure** — where the learner is in the unit

That balance should read in under a few seconds.

If the dashboard starts feeling like a summary archive, it failed.
If it starts feeling like a generic card list, it failed.

---

## 3. Locked Decisions

### 3.1 Level selector

Level switching is not a high-frequency action.

Use a compact `dropdown` / trigger in the header, not a full row of level chips.

Rules:
- current level visible at all times
- opens a compact menu with `locked/current` states
- must not dominate the top of the screen

### 3.2 Last lesson report — superseded 2026-05-01

> **Superseded.** The dashboard no longer renders a Last-lesson-report block as of Wave 0 (automaticity pivot, 2026-05-01) — see `docs/plans/automaticity-pivot.md §Wave 0`. The original V2 contract required it to be "visible at all times," but the pivot chose a leaner dashboard where the post-lesson result is visible inline in `SummaryScreen` only. The spec below is kept for historical reference; do not implement it without an explicit product-owner reversal.

The dashboard must keep the **last lesson summary visible at all times**.

But this means:
- always present
- not necessarily full-screen
- not a second giant summary page embedded into Home

The pattern is:

- compact but rich `Last lesson report` block always visible
- full summary still available through a clear secondary action

### 3.3 Hero hierarchy

The next-lesson hero remains the main action.

~~The last-lesson report is always present, but it is secondary.~~ Last-lesson report was retired in Wave 0 (see §3.2).

### 3.4 Unit states

`Done / Current / Locked` must use readable status badges.
No loose right-aligned raw text.

---

## 4. Exact Mobile Order

1. header
2. next lesson hero
3. last lesson report
4. current unit (with `All units ▾` trigger in its header)
5. premium / future block

The `Coming Next` block is **removed** — see §9.

---

## 5. Header Contract

Must contain:
- greeting
- short status line
- level dropdown trigger
- profile/avatar entry

Rules:
- header stays airy
- level selector is compact
- dropdown menu may overlap the canvas; it does not push content down

---

## 6. Next Lesson Hero Contract

Must contain:
- current unit label
- lesson title
- level
- exercise count
- estimated time
- one short lesson promise
- progress cluster
- one primary CTA

CTA labels allowed:
- `Start lesson`
- `Continue lesson`
- `Start next lesson`

### Progress cluster

The progress cluster is part of the hero.

Rules:
- stacked mobile-first layout
- compact inset sub-surface is allowed
- label + fraction share one row
- rail is thick, polished, and premium
- CTA should not compete spatially with the rail

Do not place the progress rail in a fragile left column beside the CTA.

---

## 7. Last Lesson Report Contract

This block is always visible on the dashboard after the learner has completed at
least one lesson.

It keeps the previous lesson psychologically close without turning the screen
into an archive.

### Must contain

- completion eyebrow
- lesson title
- factual meta:
  - when completed
  - exercise count
  - mistakes count
- score block
- coach-note headline
- coach-note body or compressed reflection
- `watch out` tail when available
- clear secondary actions:
  - `Review mistakes`
  - `See full report` / `Open full summary`

### Design intent

This block should feel like:
- a tutor's page marker left on the desk

Not like:
- a giant post-game results screen

### Important rule

The full summary remains a separate deeper view.
The dashboard block is a persistent report module, not the full screen duplicated inline.

---

## 8. Current Unit Contract

Purpose:
- preserve textbook orientation

Must contain:
- unit number
- unit title
- short unit descriptor
- compact lesson rows

Lesson rows need:
- index
- title
- short meta
- badge state

Allowed badge states:
- `Done`
- `Current`
- `Locked`

---

## 9. Coming Next — REMOVED 2026-04-26

The original `Coming Next` block was dropped after the first ship: even as a 2-row quiet preview it added scroll length without helping the learner make a decision. Future units now live behind an `All units ▾` trigger placed in the header of the `Current Unit` section — same "tuck-away" pattern as the level dropdown.

Rules for the trigger:
- compact pill in the section header, never a full-width row
- opens a popup menu listing units with `Current` / `Locked` states
- no real switching until the multi-unit backend lands
- popup uses the same surface treatment as the level dropdown so the two read as one motion language

---

## 10. Premium Block Contract

Allowed only as the last block.

Rules:
- elegant
- quiet
- extension of the learning path
- must never compete with the hero or the last-lesson report

---

## 11. Visual Tone

The dashboard should feel:
- editorial
- calm
- premium
- highly legible

It should not feel:
- gamified
- analytical
- corporate
- cluttered

---

## 12. Anti-Patterns

- no giant row of level chips at the top
- no two-column hero layout that crushes the progress cluster
- no raw `DONE / CURRENT / LOCKED` labels without badge containers
- no giant full summary pasted directly under the hero
- no analytics dashboard aesthetic
- no recommendation-feed language

---

## 13. Implementation Priority

If the next agent needs a strict build order:

1. header + level dropdown trigger
2. next lesson hero
3. last lesson report
4. current unit with badges + `All units ▾` trigger
5. premium block

---

## 14. Acceptance Criteria

The implementation passes only if:

1. the main next-lesson CTA is still the strongest action on the screen
2. the last lesson report is always visible once a lesson has been completed
3. the full summary still has its own deeper entrypoint
4. level switching no longer consumes a full-width chip row
5. the hero layout reads cleanly on a 390-wide viewport
6. the current unit states scan instantly via badges

If the result feels like a feed of stacked cards, it failed.
If it feels like a calm study desk with one obvious next step and one clear memory
of the previous lesson, it passed.
