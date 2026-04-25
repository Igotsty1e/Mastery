import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:mastery/api/api_client.dart';
import 'package:mastery/models/evaluation.dart';
import 'package:mastery/models/lesson.dart';
import 'package:mastery/screens/exercise_screen.dart';
import 'package:mastery/screens/home_screen.dart';
import 'package:mastery/screens/lesson_intro_screen.dart';
import 'package:mastery/screens/summary_screen.dart';
import 'package:mastery/session/session_controller.dart';
import 'package:mastery/widgets/multiple_choice_widget.dart';
import 'package:mastery/widgets/sentence_correction_widget.dart';

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

void main() {
  group('HomeScreen', () {
    testWidgets('shows onboarding first',
        (tester) async {
      await tester.pumpWidget(_withApi(const HomeScreen(), MockClient((_) async => throw UnimplementedError())));

      expect(find.text('Mastery'), findsOneWidget);
      expect(find.text('Focused English grammar practice.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Get started'), findsOneWidget);
    });

    testWidgets('onboarding continues to home and then navigates to LessonIntroScreen',
        (tester) async {
      final client = MockClient((_) async => _jsonOk(_lessonJson()));

      await tester.pumpWidget(_withApi(const HomeScreen(), client));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Get started'));
      await tester.pumpAndSettle();

      expect(find.text('English practice, one lesson at a time.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start Lesson'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Start Lesson'));
      await tester.pumpAndSettle();

      expect(find.text('Verbs Followed by -ing'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start Practice'), findsOneWidget);
    });
  });

  // ── LessonIntroScreen ─────────────────────────────────────────────────────

  group('LessonIntroScreen', () {
    testWidgets('shows loading spinner while fetching', (tester) async {
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
      final client = MockClient((_) async => _jsonErr());

      await tester.pumpWidget(
        _withApi(const LessonIntroScreen(lessonId: _lessonId), client),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Failed to load lesson'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    });

    testWidgets('Retry re-fetches and shows lesson on success', (tester) async {
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

      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Verbs Followed by -ing'), findsOneWidget);
      expect(callCount, equals(2));
    });
  });

  // ── ExerciseScreen ────────────────────────────────────────────────────────

  group('ExerciseScreen', () {
    testWidgets('shows error icon and Try again on evaluation failure',
        (tester) async {
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
      expect(find.textContaining('Answer: trying'), findsOneWidget);
    });
  });

  // ── SummaryScreen ─────────────────────────────────────────────────────────

  group('SummaryScreen', () {
    testWidgets('renders score and heading without summary', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SummaryScreen(correctCount: 4, totalCount: 5),
        ),
      );

      expect(find.text('Lesson Complete'), findsOneWidget);
      expect(find.text('4 / 5'), findsOneWidget);
      expect(find.text('correct'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Done'), findsOneWidget);
    });

    testWidgets('uses server counts when summary provided', (tester) async {
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
  });

  // ── ExerciseScreen → SummaryScreen navigation ─────────────────────────────

  group('ExerciseScreen navigation', () {
    testWidgets('navigates to SummaryScreen when phase is summary',
        (tester) async {
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
      final client = MockClient((_) async => _jsonOk(_lesson2Json()));
      final ctrl = await _loadedCtrl(client);

      await tester.pumpWidget(_withController(const ExerciseScreen(), ctrl));
      await tester.pump();

      expect(find.text('1 / 2'), findsOneWidget);
    });

    testWidgets('shows Next (not Finish) button after first exercise result',
        (tester) async {
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
      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pumpAndSettle();

      // Tap Next → advance to ex2
      await tester.tap(find.widgetWithText(FilledButton, 'Next'));
      await tester.pump();

      // TextField for ex2 must be empty; without a key on _ExerciseWidget the
      // FillBlankWidget State is reused and retains 'is' from ex1 (bug).
      final tf = tester.firstWidget<TextField>(find.byType(TextField));
      expect(tf.controller?.text ?? '', isEmpty);
    });

    testWidgets('shows Finish (not Next) button on last exercise after result',
        (tester) async {
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
      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.text('correct'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });
  });

  // ── MultipleChoiceWidget ──────────────────────────────────────────────────

  group('MultipleChoiceWidget', () {
    final options = [
      const McOption(id: 'a', text: 'Option A'),
      const McOption(id: 'b', text: 'Option B'),
      const McOption(id: 'c', text: 'Option C'),
    ];

    Widget wrap(Widget w) =>
        MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

    testWidgets('renders prompt and all option texts', (tester) async {
      await tester.pumpWidget(wrap(
        MultipleChoiceWidget(
          prompt: 'Which is correct?',
          options: options,
          onSubmit: (_) {},
        ),
      ));

      expect(find.text('Which is correct?'), findsOneWidget);
      for (final opt in options) {
        expect(find.text(opt.text), findsOneWidget);
      }
    });

    testWidgets('Submit is disabled before any option is selected',
        (tester) async {
      await tester.pumpWidget(wrap(
        MultipleChoiceWidget(
          prompt: 'Which?',
          options: options,
          onSubmit: (_) {},
        ),
      ));

      final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit'),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('selecting an option enables Submit and calls onSubmit with id',
        (tester) async {
      String? submitted;
      await tester.pumpWidget(wrap(
        MultipleChoiceWidget(
          prompt: 'Which?',
          options: options,
          onSubmit: (v) => submitted = v,
        ),
      ));

      await tester.tap(find.text('Option B'));
      await tester.pump();

      final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit'),
      );
      expect(btn.onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pump();

      expect(submitted, equals('b'));
    });

    testWidgets('tapping option does not select when enabled is false',
        (tester) async {
      String? submitted;
      await tester.pumpWidget(wrap(
        MultipleChoiceWidget(
          prompt: 'Which?',
          options: options,
          enabled: false,
          onSubmit: (v) => submitted = v,
        ),
      ));

      await tester.tap(find.text('Option A'));
      await tester.pump();

      final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit'),
      );
      expect(btn.onPressed, isNull);
      expect(submitted, isNull);
    });
  });

  // ── SentenceCorrectionWidget ──────────────────────────────────────────────

  group('SentenceCorrectionWidget', () {
    Widget wrap(Widget w) =>
        MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

    testWidgets('pre-fills text field with prompt', (tester) async {
      await tester.pumpWidget(wrap(
        SentenceCorrectionWidget(
          prompt: 'I goes to school.',
          onSubmit: (_) {},
        ),
      ));

      expect(find.text('I goes to school.'), findsOneWidget);
    });

    testWidgets('Submit calls onSubmit with current text', (tester) async {
      String? submitted;
      await tester.pumpWidget(wrap(
        SentenceCorrectionWidget(
          prompt: 'I goes to school.',
          onSubmit: (v) => submitted = v,
        ),
      ));

      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.enterText(field, 'I go to school.');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pump();

      expect(submitted, equals('I go to school.'));
    });

    testWidgets('Submit is disabled when enabled is false', (tester) async {
      await tester.pumpWidget(wrap(
        SentenceCorrectionWidget(
          prompt: 'I goes to school.',
          enabled: false,
          onSubmit: (_) {},
        ),
      ));

      final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Submit'),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('does not submit when text is empty after trim',
        (tester) async {
      String? submitted;
      await tester.pumpWidget(wrap(
        SentenceCorrectionWidget(
          prompt: 'I goes to school.',
          onSubmit: (v) => submitted = v,
        ),
      ));

      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.enterText(field, '   ');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester.pump();

      expect(submitted, isNull);
    });
  });

  // ── MVP loop (end-to-end navigation) ─────────────────────────────────────

  group('MVP loop (end-to-end navigation)', () {
    testWidgets(
        'Home → LessonIntro → ExerciseScreen → SummaryScreen with mocked API',
        (tester) async {
      int call = 0;
      final client = MockClient((_) async {
        call++;
        if (call == 1) {
          return _jsonOk(_lessonJson()); // GET /lessons/:id
        }
        if (call == 2) {
          return _jsonOk(
              _evaluateJson(correct: true)); // POST /lessons/:id/answers
        }
        return _jsonOk(_resultJson()); // GET /lessons/:id/result
      });

      await tester.pumpWidget(
        Provider<ApiClient>(
          create: (_) => ApiClient(baseUrl: 'http://test', client: client),
          dispose: (_, c) => c.dispose(),
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      // Phase 1: HomeScreen onboarding → main CTA
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Get started'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Get started'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Start Lesson'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Start Lesson'));
      await tester.pumpAndSettle(); // navigate + fetch lesson

      // Phase 2: LessonIntroScreen — lesson loaded from mocked API
      expect(find.text('Verbs Followed by -ing'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start Practice'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Start Practice'));
      await tester.pumpAndSettle(); // navigate to ExerciseScreen

      // Phase 3: ExerciseScreen — fill-blank exercise
      expect(find.text('I really enjoy ___ new restaurants when I travel.'),
          findsOneWidget);
      await tester.enterText(find.byType(TextField), 'trying');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
      await tester
          .pumpAndSettle(); // POST /lessons/:id/answers, render result panel

      // Phase 4: Correct result panel — tap Finish
      expect(find.text('Correct'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
      await tester.pumpAndSettle(); // advance → fetchSummary → SummaryScreen

      // Phase 5: SummaryScreen
      expect(find.text('Lesson Complete'), findsOneWidget);
      expect(find.text('1 / 1'), findsOneWidget);
      expect(call, equals(3));
    });
  });
}
