# Onboarding V2 + First Exercise V2 — Arrival Ritual

## Status

| Wave | Status |
|---|---|
| 3-step onboarding ritual (original Brief A) | **Superseded 2026-04-26** — first version shipped in `cea886f..bd0f021` but is being replaced by a 2-step direction. The new contract is below. |
| 2-step onboarding + dashboard-as-home (current direction) | **Spec locked 2026-04-26.** Three visual directions explored as hand-written HTML mockups in `docs/design-mockups/onboarding-2step/` (open `onboarding-2step/index.html` for the side-by-side comparison). Awaiting direction pick before implementation. |
| First-exercise V2 hierarchy (original Brief B) | Pending |
| Motion polish (Brief C) | Onboarding step transitions shipped (shared-axis fade + slide, reduced-motion fallback). Lesson-intro / first-exercise motion pending. |
| QA / design review (Brief D) | Pending |

## Direction Change Summary (2026-04-26)

The first version of this spec ended onboarding with a `Handoff` step that pushed the learner directly into the lesson intro, explicitly bypassing the dashboard. The product owner reversed that decision after running the shipped flow:

- **Onboarding shrinks from 3 steps to 2.** The `Handoff` lesson-preview step is gone — its purpose (showing the upcoming lesson) is now part of the dashboard itself.
- **Dashboard becomes the single home.** Both onboarding-final and post-summary `Done` route to the same dashboard. The learner has one place they always come back to.
- **No more direct push from onboarding into the lesson intro.** Removes the "where am I?" disorientation when the learner finishes a lesson and lands somewhere they have never seen before.

The remainder of this document describes the new contract. The old 3-step copy is preserved below in *§Original 3-step contract (superseded)* for the audit trail only.

## Core Principle

On first launch, the app should feel like the product is **introducing itself with respect**, not preparing a transaction. Two short editorial steps are enough to set the tone — then the learner lands in the home they will return to every session.

## Flow Contract

### First launch

```text
Onboarding Step 1 — Promise
  → Onboarding Step 2 — Assembly
    → Dashboard (the single Home)
      → LessonIntroScreen
        → ExerciseScreen (first exercise) … → SummaryScreen
          → Dashboard
```

### Returning launch

```text
Dashboard
  → LessonIntroScreen
    → ExerciseScreen … → SummaryScreen
      → Dashboard
```

The dashboard is the **only** home state. It is the destination of `Get started` from onboarding, of `Done` from summary, and of every fresh launch after onboarding has been seen.

## Full Screen Set

### 01. Onboarding Step 1 — Promise

**Purpose**
- Establish trust fast.
- Explain that the app is focused, serious, and worth the learner's time.

**Must show**
- warm editorial hero
- one strong sentence about what the product does
- three proof points max
- progress indicator: `Step 1 of 2`

**Tone**
- calm
- premium
- zero hype

**Motion**
- soft floating hero object or study still-life
- proof points rise in sequence

### 02. Onboarding Step 2 — Assembly

**Purpose**
- Show what the app is about to do for the learner.
- Make the flow feel constructed, not random.
- End the ritual with a clear handoff into the dashboard.

**Must show**
- lesson-building metaphor
- short explanation of rule → practice → review
- visual sign that the lesson is being prepared
- progress indicator: `Step 2 of 2`
- final CTA copy: `Open my dashboard` (or equivalent — design-shotgun may propose alternatives)

**Motion**
- staged progress fill
- mini-cards appear one by one as if the session is being assembled

**Hard rule**
- the primary CTA goes to the **dashboard**, never directly to the lesson intro
- the seen-flag is persisted before navigation

### 03. Dashboard (Home)

This is the single home of the product. Behaviour for this wave matches what is already shipped: level chips, progress card for the configured lesson, `Start lesson` CTA, no other surfaces. Visual refinements may follow a separate design pass.

The dashboard is **also the destination of post-lesson `Done`**. SummaryScreen pops back to the dashboard, not to onboarding and not to a separate post-lesson celebration screen.

## Original 3-step contract (superseded)

The first version of this spec defined a `Handoff` step that previewed the upcoming lesson and routed the final CTA directly into `LessonIntroScreen`, with the explicit hard rule "no intermediate dashboard after this CTA". That direction shipped on 2026-04-26 (commits `cea886f..bd0f021`) and was then reversed by the product owner the same day in favour of the 2-step + dashboard-as-home contract above. Code matching the old contract still exists in `app/lib/screens/onboarding_arrival_ritual_screen.dart` and will be replaced by the implementation that follows the design-shotgun output.

### 04. Lesson Intro Arrival

**Purpose**
- make the transition from onboarding feel continuous

**Must preserve**
- editorial calm from onboarding
- visual continuity in surface, color, and motion

**Notes**
- the learner should feel they have arrived in a prepared lesson, not entered a new product area
- first visible block should anchor the lesson title and rule framing quickly

### 05. First Exercise — Idle

**Purpose**
- place the learner in a narrow focus tunnel

**Must show**
- subdued progress infrastructure
- concise instruction
- dominant prompt surface
- one obvious CTA

### 06. First Exercise — Engaged

**Purpose**
- show that the learner is now inside the work

**Must show**
- selected option or active input state
- CTA visually ready

**Design rule**
- chrome should stay quiet; the prompt remains the hero

### 07. First Exercise — Incorrect Result

**Purpose**
- provide decisive, non-shaming correction

**Must show**
- incorrect state
- canonical answer
- grounded explanation
- one obvious next step

**Motion**
- result panel slides/fades in
- no harsh alert behavior

### 08. First Exercise — Correct Result

**Purpose**
- reinforce progress without gamification

**Must show**
- correct state
- concise explanation
- one obvious next step

**Motion**
- same reveal system as incorrect state, just warmer semantic styling

## Visual Rules Specific To This Flow

- onboarding and lesson intro should feel like one visual family;
- the learner should never feel kicked from a marketing layer into an app shell;
- the first exercise must be quieter than the current implementation;
- prompt hierarchy outranks chrome hierarchy;
- the instruction band must stay readable but shorter and more distilled than a generic helper box.

## Motion Contract

- `Step 1 → Step 2`: crossfade plus vertical rise of assembly cards
- `Step 2 → Step 3`: lesson preview settles into place before CTA emphasis
- `Step 3 → Lesson Intro`: shared-axis or fade-through transition; no abrupt route jump
- `Lesson Intro → First Exercise`: preserve calm pacing; do not snap into quiz mode
- `Exercise submit → result`: lock input, then reveal result panel with short slide + fade

Reduced-motion fallback:

- remove float and stagger;
- keep opacity changes and instant state transitions only.

## Implementation Split For GSTACK Agents

### Agent A — Onboarding Flow

**Scope**
- first-launch onboarding only
- step container
- step progress
- step-to-step transitions
- direct handoff into lesson intro

**Files likely touched**
- `app/lib/screens/home_screen.dart`
- `app/lib/app.dart`
- `app/lib/widgets/mastery_widgets.dart`
- theme/token files only if new documented tokens are truly required

**Acceptance**
- onboarding is 3 steps
- each step is independently editable
- final CTA lands in `LessonIntroScreen`
- returning users are not forced through onboarding every launch

### Agent B — First Exercise V2

**Scope**
- visual restructuring of the first exercise state system
- instruction band refinement
- prompt-led hierarchy
- selected/ready/result states

**Files likely touched**
- `app/lib/screens/exercise_screen.dart`
- `app/lib/widgets/fill_blank_widget.dart`
- `app/lib/widgets/multiple_choice_widget.dart`
- `app/lib/widgets/sentence_correction_widget.dart`
- shared branded widgets if needed

**Acceptance**
- first exercise reads more premium and more focused than current shipped screen
- all four runtime exercise types (`fill_blank`, `multiple_choice`, `sentence_correction`, `listening_discrimination`) still fit the same design language
- incorrect/correct result reveal stays calm and teacher-like

### Agent C — Motion + Continuity

**Scope**
- onboarding step transitions
- onboarding → lesson intro handoff
- exercise result reveal motion

**Acceptance**
- motion supports hierarchy
- reduced-motion fallback exists
- no novelty animation for its own sake

### Agent D — QA + Design Review

**Scope**
- visual QA
- responsive QA
- first-launch path
- returning-user path
- regression check for lesson intro and summary

**Required GSTACK flow**
- `/qa-only` first
- then `/design-review`
- then `/review` before landing

## Ready GSTACK Briefs

Use these as the starting tasks for the next implementation wave. Give each agent at least **10 minutes** before evaluating the result.

### Brief A — Onboarding Flow Agent

**Preferred workflow**
- `/plan-eng-review` on this document first
- implementation pass
- `/review` before landing

**Task**

Implement the approved `Arrival Ritual` onboarding from `docs/plans/arrival-ritual.md` and `DESIGN.md`.

Scope:
- Replace the current first-launch onboarding with a 3-step sequence: `Promise`, `Assembly`, `Handoff`.
- Keep the dashboard for returning users.
- Make each step data-driven or at least independently editable.
- Final CTA must route directly into `LessonIntroScreen`.
- Preserve current progress/dashboard behavior for returning users.

Non-goals:
- no new product features
- no auth
- no content rewrite
- no server changes unless strictly required for routing state

Acceptance:
- first launch shows the 3-step ritual
- final onboarding CTA lands in the lesson intro
- returning launch still works
- no broken navigation loops

### Brief B — First Exercise V2 Agent

**Preferred workflow**
- implementation pass
- `/review` before landing

**Task**

Implement the first-exercise visual pass from `docs/plans/arrival-ritual.md` and `DESIGN.md`.

Scope:
- quieter chrome
- stronger prompt hierarchy
- refined instruction band
- unified state system for idle / engaged / selected / correct / incorrect
- maintain support for `fill_blank`, `multiple_choice`, and `sentence_correction`

Non-goals:
- no new exercise types
- no evaluation logic changes
- no summary redesign

Acceptance:
- the prompt reads as the hero
- result reveal feels calm and teacher-like
- all existing exercise types still work inside the same shell

### Brief C — Motion + Continuity Agent

**Preferred workflow**
- implementation pass
- `/qa-only` on transitions

**Task**

Add the motion layer required by the selected `Arrival Ritual` direction.

Scope:
- step-to-step onboarding transitions
- onboarding to lesson-intro handoff
- lesson-intro to first-exercise continuity
- exercise result reveal motion
- reduced-motion fallback

Acceptance:
- transitions reinforce hierarchy
- no ornamental motion
- reduced-motion path remains usable and visually coherent

### Brief D — QA / Design Review Agent

**Preferred workflow**
- `/qa-only`
- `/design-review`
- `/review`

**Task**

Verify the shipped onboarding and first-exercise implementation against:
- `DESIGN.md`
- `docs/plans/arrival-ritual.md`
- `docs/mobile-architecture.md`

QA checklist:
- first-launch path
- returning-user path
- direct handoff into lesson intro
- first exercise idle
- first exercise engaged
- first exercise correct
- first exercise incorrect
- reduced-motion fallback
- small-phone layout safety

Deliver:
- list of gaps
- screenshots/evidence
- final ship-readiness summary

## Implementation Order

1. lock design intent against this document and `DESIGN.md`
2. implement onboarding flow
3. implement first exercise V2 hierarchy
4. add motion pass
5. run QA-only
6. run design review
7. update docs again after shipped UI

## Not In Scope For This Wave

- new product features
- new exercise types
- adaptive onboarding
- auth / accounts
- server-side persistence
- content rewrite
- summary redesign beyond continuity adjustments
