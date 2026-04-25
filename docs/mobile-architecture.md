# Mobile Architecture — Roundups AI Assistant MVP

## Platform

Flutter (Dart). Single codebase. Currently runnable local target: **Flutter web** (static build + local server — see Local QA below). iOS and Android targets exist in the repo but require native toolchain setup (Xcode, Android SDK) not yet confirmed working.

## Screens (4 total)

```
HomeScreen
  → LessonIntroScreen
      → ExerciseScreen (repeated per exercise)
  → SummaryScreen
```

### HomeScreen

- Shows a minimal onboarding first: short product framing plus three bullet points about the learning model.
- CTA 1: `Get started` dismisses onboarding into the normal home state.
- Home state shows the lesson CTA: `Start Lesson`.
- Launches `LessonIntroScreen` with the hardcoded `AppConfig.defaultLessonId`.
- No lesson list, no fetch, no error state.

### LessonIntroScreen

- Fetches `GET /lessons/{lesson_id}` on mount.
- Shows loading state while fetching.
- On error: show error message + retry button.
- On success: render lesson title, curated rule explanation, and examples. CTA: `Start Practice`.
- Tapping `Start Practice` navigates to the first `ExerciseScreen`.

### ExerciseScreen

Renders one exercise at a time. Layout varies by type:

| Type | Input widget |
|---|---|
| `fill_blank` | Text field; prompt displays `___` placeholder |
| `multiple_choice` | Tappable option list (radio-style); no text input |
| `sentence_correction` | Multi-line text field; original sentence shown above |

- Submit button disabled until non-empty input provided.
- On submit: POST to `/lessons/{lesson_id}/answers`.
- Show loading indicator during POST.
- On response: display result inline (see below).

### Result display (inline, after submission)

- Correct: green indicator + explanation (if present).
- Incorrect: red indicator + canonical answer + explanation (if present).
- `explanation` always comes from the exercise's curated `feedback.explanation` block in the lesson fixture.
- AI is used only to decide correctness on borderline `sentence_correction` cases; its raw feedback is not shown to the learner.
- "Next" button appears. Tapping Next advances to next exercise or to SummaryScreen.
- No back navigation. Submit button replaced by Next button after result shown.

### SummaryScreen

- Receives score from session state; optionally fetches `GET /lessons/{lesson_id}/result` for enriched data.
- Displays: "X / N correct".
- If `conclusion` is present: shows a one-line summary verdict below the score.
- If any answers were incorrect: shows a "Review your mistakes" section with one card per mistake. Each card shows the exercise prompt, canonical answer, and explanation.
- Single "Done" button → exits lesson (pop to root).

## State model

All state is in-memory for the current lesson session. No local storage.

Key data classes (see `app/lib/models/`):

- `EvaluateResponse` — result of one answer submission: `{correct, evaluationSource, explanation?, canonicalAnswer}`
- `LessonResultAnswer` — per-exercise entry in the summary: `{exerciseId, correct, prompt?, canonicalAnswer?, explanation?}`
- `LessonResultResponse` — full lesson result from the result endpoint: `{lessonId, totalExercises, correctCount, answers, conclusion?}`

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
- No local persistence (SharedPreferences, SQLite, etc.).
- No feature flags, no A/B logic.
- No analytics calls.
