// Wave 12.3 — DiagnosticScreen widget coverage.
//
// Exercises the three internal phases (Welcome → Probe → Completion)
// against a fake ApiClient that returns canned diagnostic responses.
// The fake stays small on purpose; the wire format is covered
// end-to-end in tests/diagnostic.test.ts on the backend side, so
// this file focuses on UI behaviour:
//
//   - Welcome surfaces the proof card + Begin/Skip CTAs.
//   - "Begin" advances to Probe and renders the first question without
//     a correctness reveal.
//   - Each pick advances to the next question silently.
//   - The final pick triggers /complete and lands on the Completion
//     hero with the level + skill panel.
//   - "Skip for now" flips LocalProgressStore.diagnosticSkipped and
//     fires onComplete.
//   - "Re-take the check" returns to Probe via /diagnostic/restart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/api/api_client.dart';
import 'package:mastery/api/diagnostic_dtos.dart';
import 'package:mastery/models/lesson.dart';
import 'package:mastery/progress/local_progress_store.dart';
import 'package:mastery/screens/diagnostic_screen.dart';
import 'package:mastery/theme/mastery_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Exercise _mcExercise({
  required String id,
  required String skillId,
  required String prompt,
}) =>
    Exercise(
      exerciseId: id,
      type: ExerciseType.multipleChoice,
      instruction: 'Choose the correct option.',
      prompt: prompt,
      options: const [
        McOption(id: 'a', text: 'option a'),
        McOption(id: 'b', text: 'option b'),
        McOption(id: 'c', text: 'option c'),
        McOption(id: 'd', text: 'option d'),
      ],
      skillId: skillId,
      evidenceTier: EvidenceTier.weak,
    );

class _FakeDiagnosticApiClient extends ApiClient {
  _FakeDiagnosticApiClient() : super(baseUrl: 'http://test.invalid');

  bool skipCalled = false;
  int answerCallCount = 0;
  int completeCallCount = 0;
  int restartCallCount = 0;

  static final _exercises = [
    _mcExercise(
      id: '00000000-0000-4000-8000-000000000031',
      skillId: 'skill-one',
      prompt: 'Q1',
    ),
    _mcExercise(
      id: '00000000-0000-4000-8000-000000000032',
      skillId: 'skill-two',
      prompt: 'Q2',
    ),
    _mcExercise(
      id: '00000000-0000-4000-8000-000000000033',
      skillId: 'skill-three',
      prompt: 'Q3',
    ),
  ];
  int _position = 0;

  @override
  Future<DiagnosticStart> startDiagnostic() async {
    _position = 0;
    return DiagnosticStart(
      runId: 'run-1',
      resumed: false,
      position: 0,
      total: _exercises.length,
      nextExercise: _exercises[0],
    );
  }

  @override
  Future<DiagnosticAnswerResult> submitDiagnosticAnswer({
    required String runId,
    required String exerciseId,
    required String exerciseType,
    required String userAnswer,
    DateTime? submittedAt,
  }) async {
    answerCallCount += 1;
    _position += 1;
    final runComplete = _position >= _exercises.length;
    return DiagnosticAnswerResult(
      result: 'wrong',
      evaluationSource: 'deterministic',
      canonicalAnswer: 'option a',
      explanation: null,
      runComplete: runComplete,
      position: _position,
      total: _exercises.length,
      nextExercise: runComplete ? null : _exercises[_position],
    );
  }

  @override
  Future<DiagnosticCompletion> completeDiagnostic(String runId) async {
    completeCallCount += 1;
    return DiagnosticCompletion(
      runId: runId,
      cefrLevel: 'B2',
      skillMap: const {
        'skill-one': 'practicing',
        'skill-two': 'started',
        'skill-three': 'practicing',
      },
      completedAt: DateTime.utc(2026, 4, 28, 9, 0),
      alreadyCompleted: false,
    );
  }

  @override
  Future<DiagnosticStart> restartDiagnostic() async {
    restartCallCount += 1;
    _position = 0;
    return DiagnosticStart(
      runId: 'run-2',
      resumed: false,
      position: 0,
      total: _exercises.length,
      nextExercise: _exercises[0],
    );
  }

  @override
  Future<void> skipDiagnostic() async {
    skipCalled = true;
  }
}

Widget _wrap(Widget child) => MaterialApp(
      theme: MasteryTheme.light(),
      home: child,
    );

/// Hosts a DiagnosticScreen and unmounts it on onComplete. Mirrors the
/// production HomeScreen behaviour: once the diagnostic completes (or
/// is skipped), the parent flips its routing flag and the screen
/// unmounts. Without this, the busy-state spinner inside the
/// FilledButton animates forever and `pumpAndSettle` times out.
class _DiagnosticHost extends StatefulWidget {
  final ApiClient apiClient;
  final VoidCallback onComplete;

  const _DiagnosticHost({
    required this.apiClient,
    required this.onComplete,
  });

  @override
  State<_DiagnosticHost> createState() => _DiagnosticHostState();
}

class _DiagnosticHostState extends State<_DiagnosticHost> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();
    return DiagnosticScreen(
      apiClient: widget.apiClient,
      onComplete: () {
        setState(() => _done = true);
        widget.onComplete();
      },
    );
  }
}

/// The DiagnosticScreen lays out for ≥800px tall viewports (Phase 3
/// hero alone uses a 72px top spacer + display-md headline). The
/// default flutter_test view is 800×600, which clips the primary CTA
/// off the bottom edge. We resize the view for every test so taps
/// land on visible widgets.
Future<void> _setTallView(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 1400));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Welcome surfaces headline + proof card + Begin / Skip',
    (tester) async {
      final api = _FakeDiagnosticApiClient();
      var completed = false;
      await _setTallView(tester);
      await tester.pumpWidget(
        _wrap(
          DiagnosticScreen(
            apiClient: api,
            onComplete: () => completed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('A short read on where you are.'), findsOneWidget);
      expect(find.text('5 questions'), findsOneWidget);
      expect(find.text('~2 minutes'), findsOneWidget);
      expect(find.text('Stays on your device'), findsOneWidget);
      expect(find.text('Begin'), findsOneWidget);
      expect(find.text('Skip for now'), findsOneWidget);
      expect(completed, isFalse);
    },
  );

  testWidgets(
    'Begin advances to Probe and renders the first question without a reveal',
    (tester) async {
      final api = _FakeDiagnosticApiClient();
      await _setTallView(tester);
      await tester.pumpWidget(
        _wrap(
          DiagnosticScreen(apiClient: api, onComplete: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Begin'));
      await tester.pumpAndSettle();

      // SectionEyebrow uppercases its label by design.
      expect(find.text('QUICK CHECK'), findsOneWidget);
      expect(find.text('Question 1 of 3'), findsOneWidget);
      expect(find.text('Q1'), findsOneWidget);
      // The "We'll show you results at the end." hint must appear on
      // the FIRST question only — protecting the no-instant-reveal
      // contract from drifting toward exercise-screen chrome.
      expect(find.text("We'll show you results at the end."), findsOneWidget);
      // Crucially, a regular ResultPanel ("Correct" / "Try again")
      // must NOT be on screen — the diagnostic never reveals.
      expect(find.text('Correct'), findsNothing);
      expect(find.text('Try again'), findsNothing);
    },
  );

  testWidgets(
    'Picking the final answer triggers /complete and lands on Completion',
    (tester) async {
      final api = _FakeDiagnosticApiClient();
      var completedCalls = 0;
      await _setTallView(tester);
      await tester.pumpWidget(
        _wrap(
          _DiagnosticHost(
            apiClient: api,
            onComplete: () => completedCalls += 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Begin'));
      await tester.pumpAndSettle();

      // Three questions → three picks. Tap the first MC option each time.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('option a').first);
        await tester.pumpAndSettle();
      }

      expect(api.answerCallCount, 3);
      expect(api.completeCallCount, 1);
      // Completion phase is now mounted.
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Re-take the check'), findsOneWidget);
      // The "Your level: B2." hero is a RichText built from TextSpans;
      // `find.text` does not see TextSpan content, so dive into the
      // RichText widgets and assert against their plainText.
      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      expect(
        richTexts.any((r) {
          final s = r.text.toPlainText();
          return s.contains('Your level') && s.contains('B2');
        }),
        isTrue,
      );
      // Skill rows render the human-readable fallback when titles are
      // not in the shipped map.
      expect(find.text('Practicing'), findsAtLeastNWidgets(1));
      expect(find.text('Just started'), findsAtLeastNWidgets(1));
      // onComplete is only called when the learner taps Continue.
      expect(completedCalls, 0);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(completedCalls, 1);
    },
  );

  testWidgets(
    'Skip writes the local skip flag, fires the API, and calls onComplete',
    (tester) async {
      final api = _FakeDiagnosticApiClient();
      var completedCalls = 0;
      await _setTallView(tester);
      await tester.pumpWidget(
        _wrap(
          _DiagnosticHost(
            apiClient: api,
            onComplete: () => completedCalls += 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();

      expect(api.skipCalled, isTrue);
      expect(completedCalls, 1);
      expect(await LocalProgressStore.hasSkippedDiagnostic(), isTrue);
    },
  );

  testWidgets('Re-take the check restarts the run', (tester) async {
    final api = _FakeDiagnosticApiClient();
    await _setTallView(tester);
    await tester.pumpWidget(
      _wrap(
        DiagnosticScreen(apiClient: api, onComplete: () {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Begin'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('option a').first);
      await tester.pumpAndSettle();
    }
    expect(find.text('Re-take the check'), findsOneWidget);
    await tester.tap(find.text('Re-take the check'));
    await tester.pumpAndSettle();

    expect(api.restartCallCount, 1);
    // Back at probe phase, first question.
    expect(find.text('Question 1 of 3'), findsOneWidget);
    expect(find.text('Q1'), findsOneWidget);
  });
}
