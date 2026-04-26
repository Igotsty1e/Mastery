import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mastery/api/api_client.dart';
import 'package:mastery/models/evaluation.dart';
import 'package:mastery/screens/exercise_screen.dart';
import 'package:mastery/screens/home_screen.dart';
import 'package:mastery/screens/lesson_intro_screen.dart';
import 'package:mastery/screens/summary_screen.dart';
import 'package:mastery/session/session_controller.dart';
// Widget unit tests for MultipleChoiceWidget / SentenceCorrectionWidget
// were removed when the widgets switched from internal Submit buttons to
// a single screen-level CTA driven by onChanged. Integration tests below
// exercise the same paths through ExerciseScreen.

// ── fixtures ─────────────────────────────────────────────────────────────────

const _lessonId = 'a1b2c3d4-0001-4000-8000-000000000001';
const _exId = 'a1b2c3d4-0001-4000-8000-000000000011';
const _exId2 = 'a1b2c3d4-0001-4000-8000-000000000012';

Map<String, dynamic> _lessonJson() => {
      'lesson_id': _lessonId,
      'title': 'Verbs Followed by -ing',
      'language': 'en',
      'level': 'B2',
      'intro_rule':
          'Use the -ing form after certain verbs such as enjoy, avoid, suggest, mind, keep and finish.',
      'intro_examples': ['She suggested taking a taxi because it was late.'],
      'exercises': [
        {
          'exercise_id': _exId,
          'type': 'fill_blank',
          'instruction': 'Complete the gap with the correct verb form.',
          'prompt': 'I really enjoy ___ new restaurants when I travel.',
        }
      ],
    };

Map<String, dynamic> _evaluateJson({bool correct = true}) => {
      'attempt_id': '00000000-0000-4000-8000-000000000002',
      'exercise_id': _exId,
      'correct': correct,
      'evaluation_source': 'deterministic',
      'explanation': 'After enjoy, we use the -ing form.',
      'canonical_answer': 'trying',
    };

Map<String, dynamic> _resultJson() => {
      'lesson_id': _lessonId,
      'total_exercises': 1,
      'correct_count': 1,
      'answers': [
        {'exercise_id': _exId, 'correct': true},
      ],
    };

Map<String, dynamic> _lesson2Json() => {
      'lesson_id': _lessonId,
      'title': 'Verbs Followed by -ing',
      'language': 'en',
      'level': 'B2',
      'intro_rule':
          'Use the -ing form after certain verbs such as enjoy, avoid, suggest, mind, keep and finish.',
      'intro_examples': ['She suggested taking a taxi because it was late.'],
      'exercises': [
        {
          'exercise_id': _exId,
          'type': 'fill_blank',
          'instruction': 'Complete the gap with the correct verb form.',
          'prompt': 'I really enjoy ___ new restaurants when I travel.',
        },
        {
          'exercise_id': _exId2,
          'type': 'fill_blank',
          'instruction': 'Complete the gap with the correct verb form.',
          'prompt': 'We should avoid ___ important decisions when we\'re tired.',
        },
      ],
    };

http.Response _jsonOk(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

http.Response _jsonErr() => http.Response(
      '{"error":"not_found"}',
      404,
      headers: {'content-type': 'application/json'},
    );

Widget _withApi(Widget child, http.Client httpClient) => Provider<ApiClient>(
      create: (_) => ApiClient(baseUrl: 'http://test', client: httpClient),
      dispose: (_, c) => c.dispose(),
      child: MaterialApp(home: child),
    );

Widget _withController(Widget child, SessionController ctrl) =>
    ChangeNotifierProvider<SessionController>.value(
      value: ctrl,
      child: MaterialApp(home: child),
    );

Future<SessionController> _loadedCtrl(http.Client client) async {
  final api = ApiClient(baseUrl: 'http://test', client: client);
  final ctrl = SessionController(api);
  await ctrl.loadLesson(_lessonId);
  return ctrl;
}

// ── HomeScreen ────────────────────────────────────────────────────────────────

/// Pin viewport to iPhone-class dimensions per DESIGN.md so home/lesson layouts
/// don't trigger RenderFlex overflow against the default 800x600 test surface.
Future<void> _useMobileViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// Tap a widget that may be off-screen inside a scrollable. Falls back to a
/// plain tap if the widget has no Scrollable ancestor.
Future<void> _safeTap(WidgetTester tester, Finder finder) async {
  try {
    await tester.ensureVisible(finder);
    await tester.pump();
  } catch (_) {
    // No Scrollable ancestor; tap directly.
  }
  await tester.tap(finder);
}

void main() {
  setUp(() {
    // Mock shared_preferences so LocalProgressStore.getInstance() resolves
    // immediately instead of waiting on a missing platform channel.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('HomeScreen', () {
    testWidgets('shows Promise step first when onboarding not seen',
        (tester) async {
          await _useMobileViewport(tester);
      await tester.pumpWidget(_withApi(const HomeScreen(), MockClient((_) async => throw UnimplementedError())));
      await tester.pumpAndSettle();

      // Step 1 (Promise) — wordmark + Continue CTA + 1-of-2 indicator.
      expect(find.text('Mastery'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
      expect(find.text('STEP 1 OF 2'), findsOneWidget);
    });

    testWidgets('returning user (onboarding seen) lands directly on dashboard',
        (tester) async {
      await _useMobileViewport(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'onboarding_arrival_ritual_seen_v2': true,
      });
      final client = MockClient((_) async => _jsonOk(_lessonJson()));

      await tester.pumpWidget(_withApi(const HomeScreen(), client));
      await tester.pumpAndSettle();

      // Dashboard subtitle, not onboarding.
      expect(find.text('English practice, one lesson at a time.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start lesson'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Continue'), findsNothing);
    });

    testWidgets('Continue advances Promise → Assembly, final CTA reveals dashboard (no lesson push)',
        (tester) async {
      await _useMobileViewport(tester);
      final client = MockClient((_) async => _jsonOk(_lessonJson()));

      await tester.pumpWidget(_withApi(const HomeScreen(), client));
      await tester.pumpAndSettle();

      // Step 1 → 2
      await _safeTap(tester, find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text('STEP 2 OF 2'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Open my dashboard'), findsOneWidget);

      // Step 2 final CTA → dashboard (NOT lesson intro)
      await _safeTap(tester, find.widgetWithText(FilledButton, 'Open my dashboard'));
      await tester.pumpAndSettle();

      // Dashboard markers
      expect(find.text('English practice, one lesson at a time.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start lesson'), findsOneWidget);
      // Lesson intro NOT pushed automatically
      expect(find.widgetWithText(FilledButton, 'Start Practice'), findsNothing);
    });

    testWidgets('Final-step CTA persists onboarding-seen so next launch skips it',
        (tester) async {
      await _useMobileViewport(tester);
      final client = MockClient((_) async => _jsonOk(_lessonJson()));

      await tester.pumpWidget(_withApi(const HomeScreen(), client));
      await tester.pumpAndSettle();

      await _safeTap(tester, find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      await _safeTap(tester, find.widgetWithText(FilledButton, 'Open my dashboard'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('onboarding_arrival_ritual_seen_v2'), isTrue);
    });

    testWidgets('Back button on step 2 returns to step 1',
        (tester) async {
      await _useMobileViewport(tester);
      await tester.pumpWidget(_withApi(const HomeScreen(), MockClient((_) async => throw UnimplementedError())));
      await tester.pumpAndSettle();

      await _safeTap(tester, find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text('STEP 2 OF 2'), findsOneWidget);

      await _safeTap(tester, find.widgetWithText(TextButton, 'Back'));
      await tester.pumpAndSettle();
      expect(find.text('STEP 1 OF 2'), findsOneWidget);
    });
  });

  // ── LessonIntroScreen ─────────────────────────────────────────────────────

  group('LessonIntroScreen', () {
    testWidgets('shows loading spinner while fetching', (tester) async {
      await _useMobileViewport(tester);
      final completer = Completer<http.Response>();
      final client = MockClient((_) => completer.future);

      await tester.pumpWidget(
        _withApi(const LessonIntroScreen(lessonId: _lessonId), client),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(_jsonOk(_lessonJson()));
      await tester.pumpAndSettle();
    });

    testWidgets('shows error message and Retry on load failure',
        (tester) async {
          await _useMobileViewport(tester);
      final client = MockClient((_) async => _jsonErr());

      await tester.pumpWidget(
        _withApi(const LessonIntroScreen(lessonId: _lessonId), client),
      );
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load this lesson"), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    });

    testWidgets('Retry re-fetches and shows lesson on success', (tester) async {
      await _useMobileViewport(tester);
      int callCount = 0;
      final client = MockClient((_) async {
        callCount++;
        if (callCount == 1) return _jsonErr();
        return _jsonOk(_lessonJson());
      });

      await tester.pumpWidget(
        _withApi(const LessonIntroScreen(lessonId: _lessonId), client),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);

      await _safeTap(tester, find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Verbs Followed by -ing'), findsOneWidget);
      expect(callCount, equals(2));
    });
  });

  // ── ExerciseScreen ────────────────────────────────────────────────────────

  group('ExerciseScreen', () {
    testWidgets('shows error icon and Try again on evaluation failure',
        (tester) async {
          await _useMobileViewport(tester);
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) return _jsonOk(_lessonJson());
        throw Exception('network error');
      });
      final ctrl = await _loadedCtrl(client);
      await ctrl.submitAnswer('wrong');

      await tester.pumpWidget(_withController(const ExerciseScreen(), ctrl));
      await tester.pump();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    });

    testWidgets('shows Correct panel after correct answer', (tester) async {
      await _useMobileViewport(tester);
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) return _jsonOk(_lessonJson());
        return _jsonOk(_evaluateJson(correct: true));
      });
      final ctrl = await _loadedCtrl(client);
      await ctrl.submitAnswer('is');

      await tester.pumpWidget(_withController(const ExerciseScreen(), ctrl));
      await tester.pump();

      expect(find.text('Correct'), findsOneWidget);
    });

    testWidgets('shows Incorrect panel with canonical answer on wrong answer',
        (tester) async {
          await _useMobileViewport(tester);
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) return _jsonOk(_lessonJson());
        return _jsonOk(_evaluateJson(correct: false));
      });
      final ctrl = await _loadedCtrl(client);
      await ctrl.submitAnswer('are');

      await tester.pumpWidget(_withController(const ExerciseScreen(), ctrl));
      await tester.pump();

      expect(find.text('Incorrect'), findsOneWidget);
      expect(find.textContaining('trying'), findsOneWidget);
    });
  });

  // ── SummaryScreen ─────────────────────────────────────────────────────────

  group('SummaryScreen', () {
    testWidgets('renders score and heading without summary', (tester) async {
      await _useMobileViewport(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: SummaryScreen(correctCount: 4, totalCount: 5),
        ),
      );

      expect(find.text('Lesson Complete'), findsOneWidget);
      expect(find.text('CORRECT'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
    });

    testWidgets('uses server counts when summary provided', (tester) async {
      await _useMobileViewport(tester);
      const summary = LessonResultResponse(
        lessonId: _lessonId,
        totalExercises: 5,
        correctCount: 4,
        answers: [],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: SummaryScreen(
            correctCount: 0,
            totalCount: 0,
            summary: summary,
          ),
        ),
      );

      expect(find.text('4 / 5'), findsOneWidget);
    });

    testWidgets('renders debrief headline, body, watch_out and next_step',
        (tester) async {
      await _useMobileViewport(tester);
      const summary = LessonResultResponse(
        lessonId: _lessonId,
        totalExercises: 5,
        correctCount: 3,
        answers: [],
        conclusion: 'Should be hidden because debrief is present.',
        debrief: LessonDebrief(
          debriefType: LessonDebriefType.mixed,
          headline: 'Cue words tripped you up',
          body:
              'You picked the simple form when the cue pointed to duration. Reread the rule, then redo the missed items.',
          watchOut: 'Cue word first, form second.',
          nextStep: 'Redo the missed items below.',
          source: 'ai',
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: SummaryScreen(
            correctCount: 0,
            totalCount: 0,
            summary: summary,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Cue words tripped you up'), findsOneWidget);
      expect(find.textContaining('You picked the simple form'), findsOneWidget);
      expect(find.text('WATCH OUT'), findsOneWidget);
      expect(find.text('Cue word first, form second.'), findsOneWidget);
      expect(find.text('NEXT STEP'), findsOneWidget);
      expect(find.text('Redo the missed items below.'), findsOneWidget);
      // Conclusion text is suppressed when debrief is present.
      expect(find.text('Should be hidden because debrief is present.'),
          findsNothing);
    });

    testWidgets('falls back to conclusion when debrief is null', (tester) async {
      await _useMobileViewport(tester);
      const summary = LessonResultResponse(
        lessonId: _lessonId,
        totalExercises: 5,
        correctCount: 3,
        answers: [],
        conclusion: 'Good progress. The patterns below are worth drilling.',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: SummaryScreen(
            correctCount: 0,
            totalCount: 0,
            summary: summary,
          ),
        ),
      );

      expect(find.text('Good progress. The patterns below are worth drilling.'),
          findsOneWidget);
      expect(find.text('WATCH OUT'), findsNothing);
    });
  });

  // ── ExerciseScreen → SummaryScreen navigation ─────────────────────────────

  group('ExerciseScreen navigation', () {
    testWidgets('navigates to SummaryScreen when phase is summary',
        (tester) async {
          await _useMobileViewport(tester);
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) return _jsonOk(_lessonJson());
        if (call == 2) return _jsonOk(_evaluateJson(correct: true));
        return _jsonOk(_resultJson());
      });

      // Build ExerciseScreen in result phase, then advance to trigger summary.
      // Using tester.pump() to flush fake-async timers after advance().
      final ctrl = await _loadedCtrl(client); // call 1
      await ctrl.submitAnswer('is'); // call 2

      await tester.pumpWidget(_withController(const ExerciseScreen(), ctrl));
      await tester.pump(); // render result phase

      ctrl.advance(); // triggers _fetchSummary (call 3)
      await tester.pump(); // flush microtasks + timer; state → summary
      await tester.pumpAndSettle(); // settle navigation animation

      expect(find.text('Lesson Complete'), findsOneWidget);
    });

    testWidgets('passes correctCount and totalCount to SummaryScreen',
        (tester) async {
          await _useMobileViewport(tester);
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) return _jsonOk(_lessonJson());
        if (call == 2) return _jsonOk(_evaluateJson(correct: true));
        return _jsonOk(_resultJson());
      });

      final ctrl = await _loadedCtrl(client);
      await ctrl.submitAnswer('is');

      await tester.pumpWidget(_withController(const ExerciseScreen(), ctrl));
      await tester.pump();

      ctrl.advance();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('1 / 1'), findsOneWidget);
    });
  });

  // ── ExerciseScreen multi-exercise progression ────────────────────────────

  group('ExerciseScreen progression', () {
    testWidgets('shows progress 1/2 on first of two exercises', (tester) async {
      await _useMobileViewport(tester);
      final client = MockClient((_) async => _jsonOk(_lesson2Json()));
      final ctrl = await _loadedCtrl(client);

      await tester.pumpWidget(_withController(const ExerciseScreen(), ctrl));
      await tester.pump();

      expect(find.text('1 / 2'), findsOneWidget);
    });

    testWidgets('shows Next (not Finish) button after first exercise result',
        (tester) async {
          await _useMobileViewport(tester);
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) return _jsonOk(_lesson2Json());
        return _jsonOk(_evaluateJson(correct: true));
      });
      final ctrl = await _loadedCtrl(client);
      await ctrl.submitAnswer('is');

      await tester.pumpWidget(_withController(const ExerciseScreen(), ctrl));
      await tester.pump();

      expect(find.widgetWithText(FilledButton, 'Next'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Finish'), findsNothing);
    });

    testWidgets('advances to exercise 2 and updates progress to 2/2',
        (tester) async {
          await _useMobileViewport(tester);
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) return _jsonOk(_lesson2Json());
        return _jsonOk(_evaluateJson(correct: true));
      });
      final ctrl = await _loadedCtrl(client);
      await ctrl.submitAnswer('is');

      await tester.pumpWidget(_withController(const ExerciseScreen(), ctrl));
      await tester.pump();

      ctrl.advance();
      await tester.pump();

      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('We should avoid ___ important decisions when we\'re tired.'),
          findsOneWidget);
    });

    testWidgets('text field is empty after advancing to next exercise',
        (tester) async {
          await _useMobileViewport(tester);
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) return _jsonOk(_lesson2Json());
        return _jsonOk(_evaluateJson(correct: true));
      });
      final ctrl = await _loadedCtrl(client); // call 1

      await tester.pumpWidget(_withController(const ExerciseScreen(), ctrl));
      await tester.pump();

      // User types 'is' into the text field
      await tester.enterText(find.byType(TextField), 'is');
      await tester.pump();

      // Submit → call 2 → result phase
      await _safeTap(tester, find.widgetWithText(FilledButton, 'Check answer'));
      await tester.pumpAndSettle();

      // Tap Next → advance to ex2
      await _safeTap(tester, find.widgetWithText(FilledButton, 'Next'));
      await tester.pump();

      // TextField for ex2 must be empty; without a key on _ExerciseWidget the
      // FillBlankWidget State is reused and retains 'is' from ex1 (bug).
      final tf = tester.firstWidget<TextField>(find.byType(TextField));
      expect(tf.controller?.text ?? '', isEmpty);
    });

    testWidgets('shows Finish (not Next) button on last exercise after result',
        (tester) async {
          await _useMobileViewport(tester);
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) return _jsonOk(_lesson2Json());
        return _jsonOk(_evaluateJson(correct: true));
      });
      final ctrl = await _loadedCtrl(client);
      await ctrl.submitAnswer('is');
      ctrl.advance();
      await ctrl.submitAnswer('are');

      await tester.pumpWidget(_withController(const ExerciseScreen(), ctrl));
      await tester.pump();

      expect(find.widgetWithText(FilledButton, 'Finish'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Next'), findsNothing);
    });
  });

  // ── ExerciseScreen → summary fetch failure ────────────────────────────────

  group('ExerciseScreen → summary fetch failure', () {
    testWidgets(
        'navigates to SummaryScreen showing score but no badge or conclusion',
        (tester) async {
          await _useMobileViewport(tester);
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) return _jsonOk(_lessonJson());
        if (call == 2) return _jsonOk(_evaluateJson(correct: true));
        throw Exception('summary unavailable');
      });
      final ctrl = await _loadedCtrl(client);
      await ctrl.submitAnswer('is');

      await tester.pumpWidget(_withController(const ExerciseScreen(), ctrl));
      await tester.pump();

      ctrl.advance();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Lesson Complete'), findsOneWidget);
      expect(find.text('CORRECT'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });
  });


  // ── MVP loop (end-to-end navigation) ─────────────────────────────────────

  group('MVP loop (end-to-end navigation)', () {
    testWidgets(
        'Home → LessonIntro → ExerciseScreen → SummaryScreen with mocked API',
        (tester) async {
          await _useMobileViewport(tester);
      // Path-based mock: HomeScreen and LessonIntroScreen each fetch the
      // lesson, so a sequential counter would mis-route the second request.
      final client = MockClient((req) async {
        final url = req.url.toString();
        if (req.method == 'GET' && url.contains('/result')) {
          return _jsonOk(_resultJson());
        }
        if (req.method == 'GET' && url.contains('/lessons/')) {
          return _jsonOk(_lessonJson());
        }
        if (req.method == 'POST' && url.contains('/lessons/')) {
          return _jsonOk(_evaluateJson(correct: true));
        }
        return _jsonErr();
      });

      await tester.pumpWidget(
        Provider<ApiClient>(
          create: (_) => ApiClient(baseUrl: 'http://test', client: client),
          dispose: (_, c) => c.dispose(),
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      // Phase 1: 2-step Arrival Ritual onboarding → final CTA reveals the
      // dashboard per docs/plans/arrival-ritual.md. Dashboard is the single
      // Home; the learner taps Start lesson from there.
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
      await _safeTap(tester, find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();
      await _safeTap(tester, find.widgetWithText(FilledButton, 'Open my dashboard'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Start lesson'), findsOneWidget);
      await _safeTap(tester, find.widgetWithText(FilledButton, 'Start lesson'));
      await tester.pumpAndSettle();

      // Phase 2: LessonIntroScreen — lesson loaded from mocked API
      expect(find.text('Verbs Followed by -ing'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start Practice'), findsOneWidget);
      await _safeTap(tester, find.widgetWithText(FilledButton, 'Start Practice'));
      await tester.pumpAndSettle(); // navigate to ExerciseScreen

      // Phase 3: ExerciseScreen — fill-blank exercise
      expect(find.text('I really enjoy ___ new restaurants when I travel.'),
          findsOneWidget);
      await tester.enterText(find.byType(TextField), 'trying');
      await tester.pump();
      await _safeTap(tester, find.widgetWithText(FilledButton, 'Check answer'));
      await tester
          .pumpAndSettle(); // POST /lessons/:id/answers, render result panel

      // Phase 4: Correct result panel — tap Finish
      expect(find.text('Correct'), findsOneWidget);
      await _safeTap(tester, find.widgetWithText(FilledButton, 'Finish'));
      await tester.pumpAndSettle(); // advance → fetchSummary → SummaryScreen

      // Phase 5: SummaryScreen
      expect(find.text('Lesson Complete'), findsOneWidget);
      expect(find.text('1 / 1'), findsOneWidget);
    });
  });
}
