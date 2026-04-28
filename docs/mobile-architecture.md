# Mobile Architecture — Roundups AI Assistant MVP

## Platform

Flutter (Dart). Single codebase. Currently runnable local target: **Flutter web** (static build + local server — see Local QA below). iOS and Android targets exist in the repo but require native toolchain setup (Xcode, Android SDK) not yet confirmed working.

## Visual system implementation

- Canonical visual spec: `DESIGN.md`
- Canonical composition reference: `docs/design-mockups/`
- Approved shipped onboarding/home wave: `docs/plans/arrival-ritual.md`
- Approved next-wave dashboard redesign contract: `docs/plans/dashboard-study-desk.md`
- Flutter theme implementation: `app/lib/theme/mastery_theme.dart`
- Reusable branded UI primitives: `app/lib/widgets/mastery_widgets.dart`

The app no longer relies on generic `ThemeData(colorSchemeSeed: ...)` styling. The current UI is being migrated onto the custom `MasteryTheme` token layer and shared `Mastery*` widgets so implementation stays aligned with the approved design system.

## Screens (4 total)

```
HomeScreen
  → LessonIntroScreen
      → ExerciseScreen (repeated per exercise)
  → SummaryScreen
```

### HomeScreen

`HomeScreen` carries two distinct states. The split below is authoritative — keep these subsections in sync with the code in `app/lib/screens/home_screen.dart` and with `docs/plans/arrival-ritual.md`.

#### First-launch onboarding — *Arrival Ritual* (shipped, Direction A · Editorial Notebook)

Status: shipped 2026-04-26. Source of truth: `docs/plans/arrival-ritual.md`. Visual reference: `docs/design-mockups/onboarding-2step/direction-a-editorial.html`. Implementation: `app/lib/screens/onboarding_arrival_ritual_screen.dart`.

- 2-step ritual: `Promise` → `Assembly`. Each step lives as a private widget so copy, layout, and motion can be tuned independently.
- Single text-only step indicator (`STEP N OF 2`) at the top — no duplicate dot row.
- Editorial typography: Fraunces wordmark in Promise, Fraunces headline in Assembly, gold hairline as a section anchor, numbered ordinals on proof points and stage cards.
- Final CTA copy: `Continue` on Step 1, `Open my dashboard` on Step 2.
- Final CTA writes `onboarding_arrival_ritual_seen_v2=true` to `LocalProgressStore`, then reveals the dashboard inside the same `HomeScreen` (no `Navigator.push`). The dashboard is the single Home — it is also the destination of `Done` from `SummaryScreen`. (The `_v2` suffix exists so an earlier `_v1` flag from the transitional 3-step onboarding is invalidated; existing users see the new ritual once.)
- Step transitions: shared-axis fade + slight rise; collapses to opacity-only when `MediaQuery.disableAnimations` is true.
- Back link appears from Step 2 onward.

#### First exercise — quieter chrome (Brief B, declined)

Status: declined 2026-04-26 by the product owner. A first attempt landed in 317a70c (bundled with the onboarding commit) and was reverted in f59599d. The current shipped exercise chrome — rose-tinted `InstructionBand`, `MasteryCard` wrapper, single `LinearProgressIndicator` + chevron-back top bar, body-text prompts — is the **long-term contract**, not a pre-V2 placeholder. Re-open the brief only if the decision is reversed.

#### Route transitions (Brief C, partial)

Status: shipped 2026-04-26. `MasteryFadeRoute` (`app/lib/widgets/mastery_route.dart`) renders a calm fade-through plus a 4% rise; collapses to opacity-only when `MediaQuery.disableAnimations` is on. Used for HomeScreen → LessonIntroScreen and LessonIntroScreen → ExerciseScreen, replacing the default sliding `MaterialPageRoute`. Onboarding step transitions already use the same motion contract. Exercise result-reveal motion is intentionally not done — the Brief B closure protects the exercise screen as the long-term contract.

#### Returning launch — Study Desk dashboard (shipped)

Status: shipped 2026-04-26 (Dashboard V2 · Study Desk wave). Source of truth: `docs/plans/dashboard-study-desk.md`. Visual reference: `docs/design-mockups/dashboard-study-desk.html`. Implementation: `app/lib/screens/home_screen.dart` plus `LastLessonStore` (`app/lib/session/last_lesson_store.dart`) and the reusable `StatusBadge` widget in `app/lib/widgets/mastery_widgets.dart`.

Layout, in locked order:

1. **Header** — eyebrow `STUDY DESK`, time-based greeting (`Good morning / afternoon / evening`), one-line sub. Compact level dropdown trigger (`B2 ▾` → menu with A2/B1/C1 marked Locked, B2 marked Current — no real switching) and a static `M` avatar circle. Dropdown overlays via `showMenu`, does not push content.
2. **Next-lesson hero** — `Unit 01` eyebrow + `B2` tag + Fraunces serif lesson title + meta row (`N exercises · ~M min · Next lesson`) + one-sentence promise + a stacked progress cluster (label + fraction pill + thick rail) + a single primary CTA (`Start lesson` / `Continue lesson` / `Start next lesson` — last one disabled until multi-lesson backend lands).
3. **Last lesson report** — only visible when `LastLessonStore.instance.record != null` (in-memory; lost on app restart). Block contains a `Lesson completed` eyebrow, lesson title, factual meta (when, exercises, mistakes), gold-soft `score pill`, debrief headline + body, optional `WATCH OUT` tail, and two actions: `Review mistakes` (pushes `SummaryScreen` with `initialScrollToMistakes: true`) and `See full report` (pushes `SummaryScreen` from the top).
4. **Current unit** — `Unit 01` card with shipped `Verbs Followed by -ing` row marked `Current` or `Done`, plus a single stub locked row for the next lesson.
5. **Premium block** — visual stub at the bottom; gold-soft surface, no `onTap`. No monetisation in MVP.

The original `Coming Next` block from the first ship was removed — future units now live behind an `All units ▾` trigger placed in the Current Unit section header. The trigger opens a popup listing units (`Current` / `Locked` states) and uses the same surface treatment as the level dropdown so the two read as one motion language. No real switching until the multi-unit backend lands.

Lesson data:
- On mount, fetches the lesson via `GET /lessons/{lesson_id}` (`AppConfig.defaultLessonId`) to populate level, lesson title, and exercise count.
- Reads locally stored completed-exercise count from `LocalProgressStore` (SharedPreferences).
- On return from a completed lesson, re-fetches to refresh the card.

Known scope deviations vs the spec text — see `docs/plans/dashboard-study-desk.md` Status section. The biggest one is **Last lesson report = in-memory only**; persistence is tracked as tech debt in `docs/plans/roadmap.md` (Workstream H).

### LessonIntroScreen

- Fetches `GET /lessons/{lesson_id}` on mount.
- Shows loading state while fetching.
- On error: show error message + retry button.
- On success: renders lesson title, curated rule explanation, and examples. CTA: `Start Practice`.
- The rule explanation (`intro_rule`) is rendered as a series of `_RuleSectionCard` blocks. Paragraphs whose first line is a short header (`Important`, `Form`, `Use`, etc.) receive distinct background tints, border colors, and icons to create visual hierarchy. Plain paragraphs render as neutral cards.
- Tapping `Start Practice` navigates to the first `ExerciseScreen`.

### ExerciseScreen

Renders one exercise at a time. Each exercise card shows an instruction band at the top (the `instruction` field from the exercise definition) that tells the learner exactly what to do before presenting the prompt. Layout varies by type:

| Type | Input widget |
|---|---|
| `fill_blank` | Text field; prompt displays `___` placeholder |
| `multiple_choice` | Tappable option list (radio-style); no text input |
| `sentence_correction` | Multi-line text field; original sentence shown above |

- Instruction is always shown, required, and sourced from the exercise `instruction` field. Rendered as a rose-tinted `InstructionBand` with an icon — the long-term contract after Brief B was declined.
- Submit button disabled until non-empty input provided.
- On submit: POST to `/lessons/{lesson_id}/answers`.
- Show loading indicator during POST.
- On response: display result inline (see below).

### Result display (inline, after submission)

- Correct: green indicator + explanation (if present).
- Incorrect: red indicator + canonical answer + explanation (if present).
- Result reveal for the first exercise should feel teacher-like and decisive, not game-like or punitive.
- `explanation` always comes from the exercise's curated `feedback.explanation` block in the lesson fixture.
- AI is used only to decide correctness on borderline `sentence_correction` cases; its raw feedback is not shown to the learner.
- "Next" button appears. Tapping Next advances to next exercise or to SummaryScreen.
- No back navigation. Submit button replaced by Next button after result shown.

### SummaryScreen

- Receives score from session state; optionally fetches `GET /lessons/{lesson_id}/result` for enriched data (mistake review + AI debrief).
- Displays: "X / N correct".
- If `debrief` is present: shows a "Coach's note" card below the score with the AI-generated `headline`, `body`, and optional `WATCH OUT` / `NEXT STEP` tail rows. The legacy one-line `conclusion` is suppressed in this case (the debrief replaces it).
- If `debrief` is null but `conclusion` is present: falls back to the one-line conclusion in a soft card.
- Debrief renders as a `MasteryCard` per `DESIGN.md` — paper background, soft border, no flashy AI framing. Eyebrow uses gold/primary/secondary tone keyed off `debrief_type` (strong / mixed / needs_work).
- If any answers were incorrect: shows a "Review your mistakes" section with one card per mistake. Each card shows the exercise prompt, canonical answer, and explanation.
- Single "Done" button → exits lesson (pop to root).

## State model

Session state (current exercise, results, score) is in-memory and discarded when the lesson exits. Exercise progress (completed count per lesson) is persisted locally via `LocalProgressStore` (`app/lib/progress/local_progress_store.dart`) using `SharedPreferences`. This allows the dashboard progress card to survive app restarts.

> **Wave 2 backend (2026-04-26).** The backend now owns persistent
> `lesson_sessions`, `exercise_attempts`, and `lesson_progress` tables
> behind the `/lessons/:id/sessions/start`, `/lessons/:id/sessions/current`,
> `/lesson-sessions/:id/answers`, `/lesson-sessions/:id/complete`,
> `/lesson-sessions/:id/result`, and `/dashboard` endpoints — see
> `docs/backend-contract.md §Lesson Sessions (Wave 2)`. The Flutter client
> is **not** rewired against this surface yet; `LocalProgressStore` and the
> in-memory `LastLessonStore` remain authoritative on-device until the
> client wave lands. The persistent backend obsoletes the
> `LocalProgressStore` indirection and the in-memory `LastLessonStore`
> singleton — both will retire when the client cuts over.

Key data classes (see `app/lib/models/`):

- `EvaluateResponse` — result of one answer submission: `{correct, explanation?, canonicalAnswer}`. The wire payload also carries `evaluation_source` (`deterministic | ai_fallback`), but the client does not parse or use it — the server alone reasons about evaluator routing.
- `LessonResultAnswer` — per-exercise entry in the summary: `{exerciseId, correct, prompt?, canonicalAnswer?, explanation?}`
- `LessonDebrief` — AI-generated post-lesson note: `{debriefType, headline, body, watchOut?, nextStep?, source}` (`source` ∈ `ai | fallback | deterministic_perfect`).
- `LessonResultResponse` — full lesson result from the result endpoint: `{lessonId, totalExercises, correctCount, answers, conclusion?, debrief?}`
- `LastLessonRecord` — in-memory snapshot held by `LastLessonStore` (`app/lib/session/last_lesson_store.dart`) so the dashboard "Last lesson report" block can render across navigation: `{lessonId, lessonTitle, completedAt, totalExercises, correctCount, debrief?}`. **Not persistent** — see `docs/plans/roadmap.md` Workstream H "Persistent Last Lesson Report".

Session state is managed by `SessionController` / `SessionState` (see `app/lib/session/`). Discarded on exit. Client never stores `accepted_answers`, `accepted_corrections`, or `correct_option_id`.

### Wave 1 engine metadata (deserialised, used by Wave 2)

`GET /lessons/{lesson_id}` may include the optional Wave 1 engine
metadata fields per `docs/content-contract.md §1.2`:

- `skillId` (`String?`)
- `primaryTargetError` (`TargetError?` — enum from `LEARNING_ENGINE.md §5`)
- `evidenceTier` (`EvidenceTier?` — `weak | medium | strong | strongest`)
- `meaningFrame` (`String?`)

`Exercise.fromJson` in `app/lib/models/lesson.dart` deserialises all
four. Older fixtures or item types without metadata leave the fields
`null` and the Wave 2 `LearnerSkillStore` simply does not record an
attempt for them. No UI surface yet — Wave 4 (Transparency Layer)
introduces the per-skill panel.

The Wave 12 `is_diagnostic` flag is server-side authoring metadata
only — `Exercise.fromJson` does not yet deserialise it because the
client never reads from a lesson endpoint to pick diagnostic items.
The diagnostic flow lives behind dedicated `/diagnostic/...` routes
(Wave 12.2) that filter the bank server-side before responding.

### Wave 12.3 — DiagnosticScreen routing gate

`DiagnosticScreen` (`app/lib/screens/diagnostic_screen.dart`) lives
between `SignInScreen` and `OnboardingArrivalRitualScreen` in the
`HomeScreen.build()` cascade. Routing detection: after sign-in, if
`LocalProgressStore.hasSkippedDiagnostic` is `false` AND
`ApiClient.getMyLevel()` returns `null`, surface the probe.

Three internal phases driven by an enum, not Navigator routes:

1. **Welcome** — editorial headline (`A short read on where you are.`)
   + proof card (`5 questions / ~2 minutes / Stays on your device`)
   + `Begin` / `Skip for now` CTAs.
2. **Probe** — five `multiple_choice` items rendered through the
   shipped `MultipleChoiceWidget`. **No instant correctness reveal**
   — picking advances to the next question silently, per V1 spec
   §10 ("the probe never penalises").
3. **Completion** — `display-md` headline `Your level: B2.` with a
   gold accent on the level letters + per-skill panel
   (`Practicing` / `Just started` `StatusBadge`s) + `Continue` /
   `Re-take the check` CTAs.

Both Begin→Complete and Skip-for-now land on the
`OnboardingArrivalRitualScreen` so the Promise → Assembly narrative
still runs. The skip path additionally writes
`LocalProgressStore.diagnosticSkipped` (so the same device does not
re-prompt) and fires `POST /diagnostic/skip` for D1 cohort
analysis.

Component reuse: `MultipleChoiceWidget`, `MasteryCard`,
`SectionEyebrow`, `MasteryProgressTrack`, `StatusBadge`, themed
`FilledButton` / `TextButton`. New widgets:
`DiagnosticProofCard` (~80 lines) +
`diagnostic_screen.dart` (~520 lines).

### Wave 2 mastery state — `LearnerSkillStore` (dual-mode since Wave 7.4 part 2B)

Per-learner per-skill state per `LEARNING_ENGINE.md §7.1` is held by
`LearnerSkillStore` (`app/lib/learner/learner_skill_store.dart`). Wave 2
shipped a SharedPreferences-only store; Wave 7.4 part 2B turned it into
a static facade over a pluggable `LearnerSkillBackend` interface with
two implementations:

- `LocalLearnerSkillBackend` — SharedPreferences-backed (the original
  Wave 2 keys), used in unauth'd builds and in guest mode after the
  Skip-for-now button on `SignInScreen`.
- `RemoteLearnerSkillBackend` — calls the auth-protected
  `/me/skills/...` endpoints via `AuthClient`, used after a learner
  signs in (or on app start when a refresh token is already in secure
  storage).

`LearnerStateMigrator` (`app/lib/learner/learner_state_migrator.dart`)
flips the facade on the `signedIn` outcome of `SignInScreen`: it
collects the local snapshot via fresh local-backend instances, POSTs
through `/me/state/bulk-import` (idempotent server-side — second
device's import is reported in the `skipped_*` arrays), and then calls
`LearnerSkillStore.useRemote(...)` and `ReviewScheduler.useRemote(...)`.
Even on hard failures (network drop, 4xx) the facades flip so the next
write hits the server.

The original SharedPreferences keys are not deleted on migration — the
local rows simply become inert once the facade is pointed at the remote
backend. Deletion is a follow-up cleanup once we are confident the
migration path is robust in production.

`LearnerSkillRecord` carries:

- `masteryScore` (`int` 0–100, V0 deltas weighted by evidence tier)
- `lastAttemptAt` (`DateTime?` UTC, recency for review scheduling)
- `evidenceSummary` (`Map<EvidenceTier, int>`, attempt counts per tier)
- `recentErrors` (`List<TargetError>`, FIFO-bounded at
  `LearnerSkillStore.recentErrorsCap` = 5)
- `productionGateCleared` (`bool`, set once a strongest-tier correct
  attempt with a `meaningFrame` lands per §6.4 — sticky thereafter
  per §7.1)
- `gateClearedAtVersion` (`int?`, the evaluator version at which the
  gate cleared per `LEARNING_ENGINE.md §12.3`). When `recordAttempt`
  sees an `evaluationVersion` higher than the recorded one, it
  invalidates the gate so the learner re-clears under the new
  evaluator semantics. `SessionController.submitAnswer` forwards the
  Wave 5 `evaluation_version` field on every attempt so this
  invalidation pivot is wired end-to-end.

`status` is **derived** on read via `record.statusAt(now)` per §7.2;
only the inputs above and the production-gate flag are stored.
`SessionController.submitAnswer` calls `LearnerSkillStore.recordAttempt`
after every successful evaluation that has both a `skillId` and an
`evidenceTier`. Persistence failures are tolerated (lesson flow keeps
working). No UI surface yet.

### Wave 3 in-session loop — `DecisionEngine` + `ReviewScheduler`

Wave 3 introduces the §9 learning loop without adding a UI surface
(Wave 4 renders).

`DecisionEngine` (`app/lib/learner/decision_engine.dart`) is a pure
function: given the lesson, the remaining-exercise queue, and the
session's per-skill mistake counts, it decides the next item to show
after an attempt per `LEARNING_ENGINE.md §9.1`:

- **1st mistake** on skill X → pull the next un-attempted item on the
  same skill to the head ("Same rule, different angle.")
- **2nd mistake** on skill X → pull the next same-skill item with a
  softer reason ("Same rule, simpler ask.")
- **3rd mistake** on skill X → drop every remaining same-skill item
  from the session and surface the §11.3 reason ("Three misses on this
  rule — moving on for now. We will come back later.")

If no replacement candidate exists (last skill-X item already played),
the engine falls through to the linear default with `reason = null`.

`SessionState` now carries `remainingIndices` (the exercise queue) and
`lastDecisionReason` (the §11.3 string for Wave 4 to render).
`SessionController` tracks `_sessionMistakesBySkill`, computes the
decision after every `submitAnswer`, and applies the reordered queue on
the next `advance()`.

`ReviewScheduler` (`app/lib/learner/review_scheduler.dart`) is the
cross-session cadence per §§9.2, 9.3, 9.4. Wave 7.4 part 2B made it
dual-mode through the same facade pattern as `LearnerSkillStore`:
`LocalReviewSchedulerBackend` writes to the original SharedPreferences
keys; `RemoteReviewSchedulerBackend` calls
`/me/skills/.../review-cadence` and `/me/reviews/due`. The migrator
flips both facades together. On session end (in `_fetchSummary`), every
skill the session touched gets a `recordSessionEnd` call:

- 0 mistakes → step advances by 1 (capped at 5; step 5 with no resets
  flags `graduated` per §9.4)
- 1+ mistakes → cadence resets to step 1

Cadence intervals (§9.3): step 1 = 1 day, step 2 = 3 days, step 3 =
7 days, step 4+ = 21 days (capped). `ReviewScheduler.dueAt(now)` returns
every non-graduated skill due at or before `now`, sorted oldest-first
— Wave 4 reads this on dashboard load to surface "review due" prompts.

### Wave 4 transparency surfaces — three new widgets

Wave 4 renders the engine state from Waves 1–5 onto the existing
screens. Per-screen visual approval cleared via the design call
recorded in `docs/plans/wave4-transparency-layer.md` (option B + small
A teaser).

- **`DecisionReasonLine`** (`app/lib/widgets/decision_reason_line.dart`)
  — exercise screen, between the top bar and `InstructionBand`. Reads
  `SessionState.lastDecisionReason` and renders only when
  `SessionPhase.ready` so the §11.3 reason describes the *next* item,
  not the just-answered question. Collapses to zero height on the linear
  default per §11.4 calm silence.
- **`SkillStateCard`** (`app/lib/widgets/skill_state_card.dart`) —
  summary screen, between the debrief card and the mistakes list. Loads
  `LearnerSkillStore.allRecords()` in `initState` and filters by the
  current lesson's `touchedSkillIds` (passed in by the exercise screen
  on push-replace) so the panel agrees with the score/debrief.
  Renders status per §7.2, the one-line reason rule per §11.2, and a
  recurring-error row when the same `TargetError` code has appeared
  twice in the last five attempts on that skill.
- **`ReviewDueSection`** (`app/lib/widgets/review_due_section.dart`) —
  dashboard, between the last-lesson report and the current-unit block.
  Reads `ReviewScheduler.dueAt(now)` in `_loadDashboard`. Collapses to
  nothing when the list is empty per §11.4.

Skill titles are resolved through
`app/lib/learner/skill_titles.dart` — a V0 embedded map for the two
shipped B2 skills, with a `skill_id` fallback when an entry is missing.
Replace this with a `GET /skills` endpoint when the bank exceeds a few
skills (deferred from Wave 4 per the plan §2.2 trade-off).

## Navigation

Linear push-based navigation. No tabs. No drawer. No back stack access after exercise submission.

```
/ (root)           → HomeScreen
                     → LessonIntroScreen (AppConfig.defaultLessonId)
                       → ExerciseScreen (repeated)
                         → SummaryScreen
```

Single hardcoded lesson ID from `AppConfig.defaultLessonId`.

## Networking

- HTTP client: `package:http` or `package:dio`.
- All requests to backend base URL (configurable via environment/build flavor).
- Timeout: 10s for lesson fetch; 10s for answer submission (AI fallback adds latency).
- On timeout or network error: show error message + retry button.
- Retry: manual only (user taps retry). No automatic retry.

## Error states

| Scenario | UI |
|---|---|
| Lesson fetch fail | Error message + retry button |
| Answer submit fail | Error message + retry button (same exercise, same input) |
| AI timeout (backend handles) | Backend returns `correct=false`; client shows result normally |

## Local QA (static build + server)

Flutter web via `flutter run -d chrome` triggers CanvasKit renderer with WebGL. In headless/CI environments where WebGL is unavailable, use the static-build path instead:

```sh
# 1. Build
flutter build web --release        # from app/

# 2. Serve
python -m http.server 8080 --directory app/build/web   # from project root

# 3. QA URL
http://localhost:8080
```

CanvasKit falls back to CPU-only rendering when WebGL is unavailable — this is non-fatal. The warning `Reason: webGLVersion is -1` is expected in headless Chromium and can be ignored.

Playwright 1.58.2 + Chromium headless confirmed working against the static-build server.

## Rules

- No client-side evaluation of any kind.
- No caching of lesson definitions across sessions.
- No local persistence of lesson content, answers, or session history. The only local write is `LocalProgressStore`, which stores the completed-exercise count per lesson via SharedPreferences for the dashboard progress card.
- No feature flags, no A/B logic.
- No analytics calls.
