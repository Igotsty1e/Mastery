# mastery — Flutter client

Flutter app for Roundups AI Assistant English practice. Connects to the backend REST API at `backend/`.

## Local dev target

```sh
flutter run -d chrome
```

iOS and Android targets are present in the project but require native toolchain (Xcode / Android SDK) not yet confirmed working.

## Screens

| Screen | Route | Description |
|--------|-------|-------------|
| HomeScreen | `/` | Minimal onboarding, then dashboard with level selector and progress card |
| LessonIntroScreen | `/lesson/{id}` | Fetches lesson, shows loading/error states, then rule + examples |
| ExerciseScreen | (within lesson) | Renders one exercise; submits answer; shows inline result |
| SummaryScreen | (within lesson) | Shows final score, conclusion, and mistake review |

## State model

Session state (exercises, results, score) is in-memory and discarded on exit. Exercise progress (completed count per lesson) is persisted locally via `LocalProgressStore` (`lib/progress/local_progress_store.dart`) using `SharedPreferences`, so the dashboard progress card survives app restarts.

- `session_id`: UUID generated at lesson start, passed with every answer submission.
- `LessonSession`: holds lesson data, current exercise index, and results. Discarded on exit.

## UX rules

- One lesson = one grammar rule.
- Rule teaching happens on the intro screen, before practice starts.
- No hints or practical tips after incorrect answers.
- Post-answer explanation is curated content tied to the exact exercise rule.

## Backend URL

Set via build flavor or environment. Default: `http://localhost:3000` for local dev.
