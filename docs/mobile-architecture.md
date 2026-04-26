# Mobile Architecture — Roundups AI Assistant MVP

## Platform

Flutter (Dart). Single codebase. Currently runnable local target: **Flutter web** (static build + local server — see Local QA below). iOS and Android targets exist in the repo but require native toolchain setup (Xcode, Android SDK) not yet confirmed working.

## Visual system implementation

- Canonical visual spec: `DESIGN.md`
- Canonical composition reference: `docs/design-mockups/`
- Approved next-wave screen contract (onboarding + first exercise V2): `docs/onboarding-first-exercise-arrival-ritual.md`
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

`HomeScreen` carries two distinct states. The split below is authoritative — keep these subsections in sync with the code in `app/lib/screens/home_screen.dart` and with `docs/onboarding-first-exercise-arrival-ritual.md`.

#### First-launch onboarding — *Arrival Ritual* (proposed, not yet shipped)

Status: spec approved, implementation pending. Source of truth: `docs/onboarding-first-exercise-arrival-ritual.md`.

- 3 step ritual: `Promise` → `Assembly` → `Handoff`.
- Each step is independently editable (copy, art, motion).
- The final `Handoff` step previews the upcoming lesson title, level, exercise count, and one-sentence learning promise.
- Final CTA routes **directly** into `LessonIntroScreen` — no detour through the dashboard.
- Currently shipped code: a single-screen minimal onboarding (`_buildOnboarding()` in `home_screen.dart`). The Arrival Ritual will replace it.

#### Returning launch — Dashboard (shipped)

Status: shipped. The screen the learner sees on every launch after the first.

- Read-only level selector chips (A2 / B1 / B2 / C1; only B2 is active in the current MVP).
- Progress card showing completed-exercise count vs total for the configured lesson.
- `Start Lesson` CTA → `LessonIntroScreen`.
- On mount, fetches the lesson via `GET /lessons/{lesson_id}` (`AppConfig.defaultLessonId`) to populate level and total exercise count; reads locally stored completed count from `LocalProgressStore` (SharedPreferences).
- On return from a completed lesson, re-fetches to refresh the card.
- Single hardcoded lesson ID from `AppConfig.defaultLessonId`. No lesson list, no dynamic level switching.

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

- Instruction is always shown, required, and sourced from the exercise `instruction` field.
- The first exercise should follow the approved V2 direction in `docs/onboarding-first-exercise-arrival-ritual.md`: quieter chrome, stronger prompt hierarchy, and a more premium focus tunnel.
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

Session state is managed by `SessionController` / `SessionState` (see `app/lib/session/`). Discarded on exit. Client never stores `accepted_answers`, `accepted_corrections`, or `correct_option_id`.

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
