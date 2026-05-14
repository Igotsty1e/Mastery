# Onboarding V2 — Arrival Ritual

## Status

| Wave | Status |
|---|---|
| 2-step onboarding + dashboard-as-home (Direction A · Editorial Notebook) | **Shipped 2026-04-26.** Visual reference: `docs/design-mockups/onboarding-2step/direction-a-editorial.html`. Implementation: `app/lib/screens/onboarding_arrival_ritual_screen.dart`, `app/lib/screens/home_screen.dart`. |
| Motion polish | **Partial — shipped 2026-04-26.** Onboarding step transitions (shared-axis fade + slide, reduced-motion fallback) plus calm route transitions for HomeScreen → LessonIntroScreen and LessonIntroScreen → ExerciseScreen via `MasteryFadeRoute` (`app/lib/widgets/mastery_route.dart`). Exercise result-reveal motion intentionally not done — the exercise screen is the long-term contract (see History). |
| QA / design review | **Code-level conformance audit shipped 2026-04-26** — see Audit log below. Live visual QA in a real browser is still pending; requires a user-driven session. |

## Audit Log — 2026-04-26 (code-level pass)

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

- Live visual QA in a real browser. Requires either a user-driven session or a screenshot-capable MCP browser run; flag here for a future QA pass.

## History (2026-04-26)

A first version of this spec shipped a 3-step ritual (Promise → Assembly → Handoff) that routed the final CTA directly into `LessonIntroScreen`, explicitly bypassing the dashboard. After running the shipped flow the product owner reversed that decision the same day:

- **Onboarding shrinks from 3 steps to 2.** The `Handoff` preview step is gone — its purpose (showing the upcoming lesson) is now part of the dashboard itself.
- **Dashboard becomes the single home.** Both onboarding-final and post-summary `Done` route to the same dashboard. The learner has one place they always come back to.
- **No more direct push from onboarding into the lesson intro.** Removes the "where am I?" disorientation when the learner finishes a lesson and lands somewhere they have never seen before.

The 3-step direction lived in commits `cea886f..bd0f021`. The current contract below was implemented in the commit that ships the 2-step + dashboard-as-home direction.

The original wave also scoped a first-exercise V2 chrome redesign (quieter chrome, prompt-led hierarchy, refined instruction band). A first attempt landed in 317a70c bundled with the onboarding commit and was reverted in f59599d. **The exercise V2 chrome was declined 2026-04-26 by the product owner — the current shipped exercise chrome is the long-term contract and must not be redesigned without an explicit reversal.** The exercise-specific spec is omitted from this doc by design.

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

## Onboarding Screen Set

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

That separate pass is now tracked in:
- `docs/plans/dashboard-study-desk.md`
- `docs/design-mockups/dashboard-study-desk.html`

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

## Visual Rules Specific To This Flow

- onboarding and lesson intro should feel like one visual family;
- the learner should never feel kicked from a marketing layer into an app shell.

## Motion Contract

- `Step 1 → Step 2`: crossfade plus vertical rise of assembly cards
- `Step 2 → Dashboard`: lesson preview settles into place before CTA emphasis
- `Dashboard → Lesson Intro`: shared-axis or fade-through transition; no abrupt route jump
- `Lesson Intro → First Exercise`: preserve calm pacing; do not snap into quiz mode

Reduced-motion fallback:

- remove float and stagger;
- keep opacity changes and instant state transitions only.

## Implementation Order

1. ✅ lock design intent against this document and `DESIGN.md`
2. ✅ implement onboarding flow (Direction A · Editorial Notebook)
3. ✅ add motion pass — onboarding step transitions + calm route transitions
4. ✅ code-level conformance audit (see Audit Log above)
5. ⏸ live visual QA in a real browser — pending user-driven session
6. ✅ docs swept across all .md files

## Not In Scope For This Wave

- new product features
- new exercise types
- adaptive onboarding
- auth / accounts
- server-side persistence
- content rewrite
- summary redesign beyond continuity adjustments
