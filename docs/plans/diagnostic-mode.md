# Diagnostic Mode — screen spec (Wave 12.3)

## Status

Draft for the visual approval gate per `CLAUDE.md` per-screen rule.
Once approved, this doc becomes the implementation contract for the
Flutter side of Wave 12 (Diagnostic Mode).

Implementation depends on:
- Wave 12.1 (`is_diagnostic` schema + 5 tagged probe items) — shipped.
- Wave 12.2 (`/diagnostic/...` routes + CEFR derivation) — shipped.

Visual reference: this is a brand-new UX surface; no HTML mockup
exists yet. The spec below is on `DESIGN.md` tokens and re-uses the
component vocabulary already shipped in `ExerciseScreen` and
`SummaryScreen` so the diagnostic does not feel like a different
product. If post-implementation we want to evolve the look further,
spin a `/design-shotgun` against this doc — do not deviate from the
spec inline.

---

## Why this surface matters

Diagnostic is a **retention lever**, not a content feature. Per V1
spec §15 it is the strongest D1 anchor we have; per
`learning-engine-v1.md` decision #2 retention is the primary metric.
Two consequences for design:

1. **First impression weight.** This is the first product interaction
   after sign-in for every new account. It must feel **calm,
   intentional, and short**. Not "test prep."
2. **Skip must be honest.** Wave 7.4 product call kept "Skip for now"
   alive. We respect that — no dark patterns. The skip path is one
   tap away, gets logged for cohort analysis, and lands the learner
   on the dashboard with a generic level (handled server-side).

---

## Routing gate

`HomeScreen.build()` currently runs three states: `_showSignIn` →
`_showOnboarding` → dashboard. Wave 12.3 inserts a **fourth**:

```
sign-in resolved
       ↓
_showDiagnostic && _authClient != null && _userNotYetDiagnosed
       ↓
DiagnosticScreen (probe → completion)
       ↓
_showOnboarding
       ↓
dashboard
```

Detection logic:
- After sign-in, `HomeScreen` calls `GET /me/profile` (existing
  endpoint, returns `level`).
- If `level == null`, the user has never finished a diagnostic →
  show `DiagnosticScreen`.
- If `level` is set (B2 today by stub-login default, or set by a
  prior diagnostic), skip the probe — we already have a level.
- "Skip for now" sets a local `LocalProgressStore` flag so the same
  device does not re-prompt. `POST /diagnostic/skip` writes the
  audit event for cohort analysis.

Re-running the diagnostic later is reachable from the dashboard
(handled in Wave 12.4 as a settings affordance, out of scope here).

---

## DiagnosticScreen — three internal phases

The screen is a single `StatefulWidget` with three internal phases
(driven by an enum, not by separate Navigator routes). Phase
transitions use the `cubic-bezier(0.22, 1, 0.36, 1)` enter curve at
`280ms` per `DESIGN.md §Motion`.

### Phase 1 — Welcome (60-second sell)

**Goal.** Make the learner choose to take the probe instead of
skipping. Five sentences max. No bullets.

**Layout (top → bottom, `560px` max-width centred, `24px` horizontal
padding):**

- App shell, no top bar, no back button. Status bar transparent.
- `64px` top spacer.
- `headline-lg` (`Fraunces 32/38`), text `text.primary`:
  > **A short read on where you are.**
- `lg` (24px) gap.
- `body-lg` (`Manrope 18/30`), text `text.secondary`:
  > Five quick questions. Two minutes. We use them to set your
  > level and pick the first lesson you actually need — not the
  > one a curriculum thinks you do.
- `xl` (32px) gap.
- A muted **proof row** rendered as three small icon + label
  pairings on a tinted `bg.primary-soft` rounded card (radius
  `22px`, padding `24px`):
  - 🎯 `5 questions` — `Manrope 16/26`, `text.primary`
  - ⏱ `~2 minutes` — same
  - 🔒 `Stays on your device` — same
  (icons rendered as outline-style `Icons.adjust`,
  `Icons.access_time`, `Icons.lock_outline`. No emojis in actual
  UI — these are pseudo-glyphs in the spec.)
- `2xl` (40px) gap.
- **Primary CTA** (per `DESIGN.md §Component System §2`):
  height `56px`, dusty-rose fill, ivory text:
  > Begin
- `md` (16px) gap.
- **Tertiary text link** (no border, `text.secondary`,
  `label-md`), centered:
  > Skip for now

**Motion.** Mount with the same crossfade-up that
`OnboardingArrivalRitualScreen` uses (`MasteryRoute`).

**Copy guardrails.**
- Never the word "test." Never "exam." Never "assessment."
- Never timer countdown. The "two minutes" is reassurance, not a
  pressure clock.
- "Set your level" is honest — that is what CEFR derivation does.

### Phase 2 — Probe (5 multiple_choice questions)

**Goal.** Reuse the shipped `ExerciseScreen` chrome verbatim so the
learner already understands how to answer. The diagnostic is not the
moment to introduce a new interaction model.

**Layout.** The same `ExerciseCard` + `MultipleChoice` rows the
exercise screen renders. Two diffs vs a regular session:

1. **Top progress bar copy.** Regular sessions show "Question 3 of
   10." Diagnostic shows **"Question 3 of 5"** AND a calmer
   eyebrow above it (`label-sm`, `text.tertiary`, uppercase
   tracking `0.06em`):
   > QUICK CHECK
   The eyebrow makes it visually distinct from a real lesson without
   borrowing a different component.
2. **No instant correctness reveal.** This is the only behavioural
   difference from a regular MC item. After the learner picks, the
   selected row stays highlighted and the screen advances to the
   next question on a `280ms` slide (per
   `Motion §screen-to-screen`). No green check, no red X, no
   explanation panel. The learner finishes the probe without
   being told what they got wrong — that is the whole point of a
   probe (V1 spec §10 — never penalise).

The "no reveal" rule is the one place the spec deviates from the
exercise chrome. We add a one-line subtext below the choices
before the first question only:
- `body-sm`, `text.tertiary`:
  > We'll show you results at the end.

**Submit lock.** Picking an option immediately fires
`POST /diagnostic/:id/answers` and disables further taps until the
next question lands. No "Submit" button — the choice IS the submit,
matching V1 spec ("five quick questions").

**Edge cases.**
- Network error mid-probe: show an inline `Snackbar` (warm-rose),
  retry-on-tap. Do NOT clear the probe state.
- App backgrounded mid-probe: `/diagnostic/start` resumes the same
  run on next launch (server-side guarantee from Wave 12.2).

### Phase 3 — Completion

**Goal.** Land the learner on a calm "Welcome — your level is B2"
moment, then push them into the existing onboarding ritual without
a redundant celebration.

**Layout (top → bottom):**

- `4xl` (72px) top spacer (deliberately roomy — this is a hero
  moment).
- `display-md` (`Fraunces 40/46`), centred, `text.primary`:
  > **Your level: B2.**
  Where `B2` is the derived level. Use the gold accent
  (`#C89A52`) ONLY on the level digit/letters — never on the
  surrounding prose. This is a "completion" moment per
  `DESIGN.md §Color Usage Rules §4`.
- `lg` (24px) gap.
- `body-lg`, `text.secondary`, centred, max width `420px`:
  > Based on your five answers, we'll start with **{first
  > skill title}** and pick what's next from there.
  Where `{first skill title}` is whichever shipped skill the
  derivation rated weakest (lowest correct count). If all five
  were correct, the copy collapses to:
  > Strong start. We'll begin with **{first skill title}** to keep
  > the rhythm.
- `xl` (32px) gap.
- A **soft skill panel** rendered as a tinted card
  (`bg.surface-alt` background, `border.soft` border, radius
  `22px`, padding `24px`). One row per skill the probe touched
  (5 rows, one per skill). Each row:
  - `label-md` skill title (left)
  - dot + status label (right): `Practicing` (rose tint) or
    `Just started` (warm-neutral tint)
  Reuses the existing `StatusBadge` widget shape from
  `mastery_widgets.dart`. No bars, no percentages — labels only.
- `2xl` (40px) gap.
- **Primary CTA**:
  > Continue
- `md` gap.
- **Tertiary**:
  > Re-take the check
  (Wires to `POST /diagnostic/restart`, then re-mounts Phase 2
  from the top.)

**Continue lands on `OnboardingArrivalRitualScreen`** so the
learner still gets the Promise → Assembly narrative. The diagnostic
is additive, never a replacement for the onboarding ritual.

**Motion.** Phase 3 mounts with a `420ms` long crossfade (per
`Motion §Duration §long`) — slightly more deliberate than the
phase-2-to-phase-2 question slides, so the learner registers that
something resolved.

---

## Skip path (Phase 1 → dashboard)

Tapping "Skip for now":

1. Fires `POST /diagnostic/skip` (fire-and-forget; failures
   ignored — telemetry is best-effort).
2. Sets `LocalProgressStore.diagnosticSkipped = true` so the same
   device does not re-prompt.
3. Pushes `OnboardingArrivalRitualScreen` exactly the way "Begin"
   would have on Phase 3.

The skipper still gets the regular onboarding. They never see the
"Welcome — your level is X" moment because we have no level for
them; the dashboard renders without a level chip until they re-take
the diagnostic from a future settings entry point (Wave 12.4 +).

---

## Component reuse map

| Screen element | Source widget | Diff |
|---|---|---|
| Phase 1 hero | `Fraunces` headline + body — same as `OnboardingArrivalRitualScreen` Promise step | New copy. No layout diff. |
| Phase 1 proof card | New small composite using `bg.primary-soft` + icon rows | One-off. Ships in `app/lib/widgets/diagnostic_proof_card.dart`. |
| Phase 1 + 3 primary CTA | `MasteryButton.primary` | Existing. Same height/radius. |
| Phase 1 + 3 tertiary | Inline `TextButton` styled with `text.secondary` and `label-md` | Existing pattern. |
| Phase 2 question shell | `ExerciseCard` + `MultipleChoiceRows` from `exercise_screen.dart` | Reuse verbatim. |
| Phase 2 progress bar | `ProgressBar` from `mastery_widgets.dart` | Reuse. Total = 5 instead of 10. |
| Phase 2 eyebrow | New `_EyebrowLabel` (uppercase, tracked) | One-off. Tiny. |
| Phase 3 hero | `display-md` Fraunces + gold accent on the level digits | New composition. |
| Phase 3 skill panel | `StatusBadge` from `mastery_widgets.dart` | Reuse. New container. |

Estimated new Flutter LOC: ~350 lines for `diagnostic_screen.dart` +
~80 lines for `diagnostic_proof_card.dart` + small additions to
`api_client.dart` for the four routes (~60 lines) + ~40 lines of
tests. Total ~530 LOC, in line with `OnboardingArrivalRitualScreen`
(467 LOC).

---

## API client surface (Wave 12.3 client side of Wave 12.2)

`ApiClient` gains four methods, all auth-protected:

```dart
Future<DiagnosticStart> startDiagnostic();
// → { runId, resumed, position, total, nextExercise }

Future<DiagnosticAnswerResult> submitDiagnosticAnswer({
  required String runId,
  required String exerciseId,
  required String exerciseType,
  required String userAnswer,
  DateTime? submittedAt,
});
// → { result, evaluationSource, canonicalAnswer, explanation,
//     runComplete, position, total, nextExercise }

Future<DiagnosticCompletion> completeDiagnostic(String runId);
// → { runId, cefrLevel, skillMap, completedAt, alreadyCompleted }

Future<void> skipDiagnostic();
// fire-and-forget; failures are swallowed
```

All four mirror the JSON shapes documented in
`docs/backend-contract.md §Wave 12.2 status`. The DTO classes live
in `app/lib/api/diagnostic_dtos.dart`.

---

## Out of scope (Wave 12.4)

- Re-take affordance reachable from the dashboard (Phase 3's
  "Re-take the check" only fires inside the diagnostic surface
  itself; a settings/dashboard re-entry comes in 12.4).
- Skill-progress UI on the dashboard reflecting the diagnostic
  output (the skill panel on Phase 3 is local to that screen; no
  dashboard surface yet — V1.5 per `learning-engine-v1.md`
  decision #12).
- D1 retention dashboard query — V1 ships the audit events; the
  query is a V1.5 follow-up.
- Animated count-up of the level letters — V1 uses the standard
  fade-in.

---

## Approval checklist

Before implementation begins, the product owner must explicitly
approve:

- [ ] Phase 1 copy direction ("A short read on where you are."
      headline + reassurance body + 3-icon proof card).
- [ ] Phase 2 chrome reuse (regular `ExerciseScreen` cards + `QUICK
      CHECK` eyebrow + `Question 3 of 5`) and the **no instant
      reveal** rule.
- [ ] Phase 3 completion hero (gold-accented level digits, soft
      skill panel, CTA → onboarding ritual).
- [ ] Skip path lands on the regular onboarding without showing the
      "Welcome — your level is X" moment.
- [ ] Routing gate sits between sign-in and onboarding ritual.

Once approved, this doc becomes the implementation contract.
