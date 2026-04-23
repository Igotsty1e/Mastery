# Mobile Architecture — Roundups AI Assistant MVP

## Platform

Flutter (Dart). Single codebase. Currently runnable local target: **Flutter web** (`flutter run -d chrome`). iOS and Android targets exist in the repo but require native toolchain setup (Xcode, Android SDK) not yet confirmed working.

## Screens (4 total)

```
LessonScreen
  → ExerciseScreen (repeated per exercise)
      → ResultScreen (inline, same screen or modal)
  → LessonCompleteScreen
```

### LessonScreen

- Fetches `GET /lessons/{lesson_id}` on mount.
- Shows loading state while fetching.
- On error: show error message + retry button.
- On success: navigate to first ExerciseScreen.

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

- Correct: green indicator + feedback (if present).
- Incorrect: red indicator + canonical answer + feedback (if present).
- "Next" button appears. Tapping Next advances to next exercise or to LessonCompleteScreen.
- No back navigation. Submit button replaced by Next button after result shown.

### LessonCompleteScreen

- Fetches `GET /lessons/{lesson_id}/result`.
- Displays: "X / N correct".
- Single "Done" button → exits lesson (pop to root or close).

## State model

All state is in-memory for the current lesson session. No local storage.

```dart
class LessonSession {
  final String lessonId;
  final List<Exercise> exercises;
  int currentIndex;
  final List<AttemptResult> results;
}

class AttemptResult {
  final String exerciseId;
  final bool correct;
  final String? feedback;
  final String canonicalAnswer;
}
```

- `LessonSession` created when lesson loads. Discarded on exit.
- `currentIndex` increments on Next tap.
- Client never stores `accepted_answers`, `accepted_corrections`, or `correct_option_id`.

## Navigation

Linear push-based navigation. No tabs. No drawer. No back stack access after exercise submission.

```
/ (root)           → lesson selection or direct lesson launch
/lesson/{id}       → LessonScreen → ExerciseScreen → LessonCompleteScreen
```

For MVP: single hardcoded lesson_id or passed via route parameter.

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

## Rules

- No client-side evaluation of any kind.
- No caching of lesson definitions across sessions.
- No local persistence (SharedPreferences, SQLite, etc.).
- No feature flags, no A/B logic.
- No analytics calls.
