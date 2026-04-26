# Onboarding V2 + First Exercise V2 — Arrival Ritual

## Status

| Wave | Status |
|---|---|
| 2-step onboarding + dashboard-as-home (Direction A · Editorial Notebook) | **Shipped 2026-04-26.** Visual reference: `docs/design-mockups/onboarding-2step/direction-a-editorial.html`. Implementation: `app/lib/screens/onboarding_arrival_ritual_screen.dart`, `app/lib/screens/home_screen.dart`. |
| First-exercise V2 quieter chrome (Brief B) | **Declined 2026-04-26 by product owner.** A first attempt landed in 317a70c bundled with the onboarding commit and was reverted in f59599d. Direction explicitly closed — the current shipped exercise chrome stays as the long-term contract. Re-open only if the product owner reverses this. |
| Motion polish (Brief C) | **Partial — shipped 2026-04-26.** Onboarding step transitions (shared-axis fade + slide, reduced-motion fallback) plus calm route transitions for HomeScreen → LessonIntroScreen and LessonIntroScreen → ExerciseScreen via `MasteryFadeRoute` (`app/lib/widgets/mastery_route.dart`). Exercise result-reveal motion is intentionally not done — would touch the exercise screen, which Brief B closure now protects. |
| QA / design review (Brief D) | **Code-level conformance audit shipped 2026-04-26** — see Audit log below. Live visual QA in a real browser is still pending; requires a user-driven session. |

## Audit Log — 2026-04-26 (Brief D, code-level pass)

Confirmed against shipped code (`app/lib/screens/{home_screen,onboarding_arrival_ritual_screen,lesson_intro_screen,summary_screen,exercise_screen}.dart`):

- Onboarding 2 steps with single text-only `STEP N OF 2` indicator — matches spec.
- CTA labels exactly `Continue` / `Open my dashboard` — matches spec.
- Final-step CTA never `Navigator.push`es a lesson — `_completeOnboarding()` only marks the seen-flag and reveals the dashboard via `setState`. Hard rule satisfied.
- `LocalProgressStore.markOnboardingSeen()` writes the v2 key (`onboarding_arrival_ritual_seen_v2`) so old v1 flags from the transitional 3-step onboarding are invalidated.
- `SummaryScreen.Done` calls `Navigator.pop()`. Stack at summary is `[HomeScreen, SummaryScreen]` because `LessonIntroScreen` and `ExerciseScreen` both `pushReplacement`. Pop lands on the dashboard state — matches spec.
- Onboarding step transitions use shared-axis fade + 4% rise; collapse to opacity when `MediaQuery.disableAnimations` is on. `MasteryFadeRoute` follows the same contract. Motion language consistent across product.
- 42/42 Flutter widget tests green; 195/195 backend tests green; analyzer clean of new regressions.

Soft observations (not bugs, recorded for future passes):

- Dashboard CTA copy switches from `Start lesson` to `Continue lesson` when `_completedExercises > 0`. Not in spec, kept as natural copy.
- `_ComingNext` on the dashboard renders hardcoded U02 / U03 placeholders even though the backend ships only U01. Known stub; future content waves (`codex/b2-content` branch) will replace.

What this audit did NOT do:

- Live visual QA in a real browser. Requires either a user-driven session or a screenshot-capable MCP browser run; flag here so a future Brief D pass picks it up.

## History (2026-04-26)

A first version of this spec shipped a 3-step ritual (Promise → Assembly → Handoff) that routed the final CTA directly into `LessonIntroScreen`, explicitly bypassing the dashboard. After running the shipped flow the product owner reversed that decision the same day:

- **Onboarding shrinks from 3 steps to 2.** The `Handoff` preview step is gone — its purpose (showing the upcoming lesson) is now part of the dashboard itself.
- **Dashboard becomes the single home.** Both onboarding-final and post-summary `Done` route to the same dashboard. The learner has one place they always come back to.
- **No more direct push from onboarding into the lesson intro.** Removes the "where am I?" disorientation when the learner finishes a lesson and lands somewhere they have never seen before.

The 3-step direction lived in commits `cea886f..bd0f021`. The current contract below was implemented in the commit that ships the 2-step + dashboard-as-home direction.

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
- onboarding is 2 steps (`Promise` → `Assembly`)
- each step is independently editable
- final CTA reveals the dashboard inside the same `HomeScreen` (no `Navigator.push` to `LessonIntroScreen`)
- returning users are not forced through onboarding every launch
- post-summary `Done` also lands on the dashboard

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
- Replace the current first-launch onboarding with a 2-step sequence: `Promise`, `Assembly`.
- Keep the dashboard for returning users — and route the final onboarding CTA there too.
- Make each step independently editable.
- Final CTA reveals the dashboard inside `HomeScreen` (no `Navigator.push` to `LessonIntroScreen`).
- Preserve current progress/dashboard behavior for returning users.

Non-goals:
- no new product features
- no auth
- no content rewrite
- no server changes unless strictly required for routing state

Acceptance:
- first launch shows the 2-step ritual ending on the dashboard
- final onboarding CTA does **not** push the lesson intro
- returning launch still works
- post-summary `Done` returns to the dashboard
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

1. ✅ lock design intent against this document and `DESIGN.md`
2. ✅ implement onboarding flow (Direction A · Editorial Notebook)
3. ❌ first exercise V2 hierarchy — declined 2026-04-26 by product owner
4. ✅ add motion pass — onboarding step transitions + calm route transitions
5. ✅ code-level conformance audit (see Audit Log above)
6. ⏸ live visual QA in a real browser — pending user-driven session
7. ✅ docs swept across all .md files

## Not In Scope For This Wave

- new product features
- new exercise types
- adaptive onboarding
- auth / accounts
- server-side persistence
- content rewrite
- summary redesign beyond continuity adjustments
