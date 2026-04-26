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

### Wave 2 mastery state — `LearnerSkillStore` (device-scoped)

Per-learner per-skill state per `LEARNING_ENGINE.md §7.1` is held by
`LearnerSkillStore` (`app/lib/learner/learner_skill_store.dart`),
SharedPreferences-backed and device-scoped. Server-side learner storage
is a follow-up wave once accounts exist.

`LearnerSkillRecord` carries:

- `masteryScore` (`int` 0–100, V0 deltas weighted by evidence tier)
- `lastAttemptAt` (`DateTime?` UTC, recency for review scheduling)
- `evidenceSummary` (`Map<EvidenceTier, int>`, attempt counts per tier)
- `recentErrors` (`List<TargetError>`, FIFO-bounded at
  `LearnerSkillStore.recentErrorsCap` = 5)
- `productionGateCleared` (`bool`, set once a strongest-tier correct
  attempt with a `meaningFrame` lands per §6.4 — sticky thereafter
  per §7.1)

`status` is **derived** on read via `record.statusAt(now)` per §7.2;
only the inputs above and the production-gate flag are stored.
`SessionController.submitAnswer` calls `LearnerSkillStore.recordAttempt`
after every successful evaluation that has both a `skillId` and an
`evidenceTier`. Persistence failures are tolerated (lesson flow keeps
working). No UI surface yet.

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
