# Onboarding V2 + First Exercise V2 — Arrival Ritual

## Status

Approved direction for the next UI implementation wave.

This document translates the selected `Variant A / Arrival Ritual` concept into a screen-by-screen contract that implementation agents can ship without reopening the design decision.

## Why This Direction Won

`Arrival Ritual` is the strongest option because it does three jobs at once:

- gives the product a premium first impression;
- teaches the learner what kind of app this is without feature spam;
- ends in a direct handoff to the new lesson instead of dropping the learner back into a generic home state.

It feels more intentional than the current onboarding and creates a cleaner bridge into the first exercise.

## Core Principle

On first launch, the app should feel like it is **preparing a real lesson for the learner**.

The onboarding is not a carousel of marketing slides. It is a short ritual:

1. explain the promise;
2. show what the app is assembling;
3. hand the learner into today's lesson.

## Flow Contract

### First launch

```text
Onboarding Step 1 — Promise
  → Onboarding Step 2 — Assembly
    → Onboarding Step 3 — Handoff
      → LessonIntroScreen (new lesson)
        → ExerciseScreen (first exercise)
```

### Returning launch

```text
Home / Dashboard
  → LessonIntroScreen
    → ExerciseScreen
```

## Full Screen Set

### 01. Onboarding Step 1 — Promise

**Purpose**
- Establish trust fast.
- Explain that the app is focused, serious, and worth the learner's time.

**Must show**
- warm editorial hero
- one strong sentence about what the product does
- three proof points max
- progress indicator such as `Step 1 of 3`

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

**Must show**
- lesson-building metaphor
- short explanation of rule → practice → review
- visual sign that the lesson is being prepared

**Motion**
- staged progress fill
- mini-cards appear one by one as if the session is being assembled

### 03. Onboarding Step 3 — Handoff

**Purpose**
- End onboarding with a concrete lesson already waiting.

**Must show**
- lesson title
- level (`B2`)
- exercise count
- estimated duration
- one-sentence learning promise

**Hard rule**
- the primary CTA goes directly into the lesson intro
- no intermediate dashboard after this CTA

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
- all three runtime exercise types still fit the same design language
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
