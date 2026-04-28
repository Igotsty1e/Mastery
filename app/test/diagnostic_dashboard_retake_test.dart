// Wave 12.4 — dashboard re-take affordance integration test.
//
// The full HomeScreen is too entangled with auth + network bootstrap
// to mount cleanly in a widget test (it constructs an AuthClient,
// hydrates from secure storage, fetches /lessons + /me on resolve).
// What this file actually validates is the contract the Re-run link
// owes the rest of the app: tapping it should push DiagnosticScreen
// onto the navigator, and DiagnosticScreen's onComplete should pop
// back to the dashboard.
//
// We mount a tiny harness that mimics the dashboard's trigger so
// the contract is exercised without dragging the rest of HomeScreen
// into the test. The harness uses the same MasteryFadeRoute that
// home_screen.dart's `_openDiagnosticRetake` uses.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/api/api_client.dart';
import 'package:mastery/api/diagnostic_dtos.dart';
import 'package:mastery/models/lesson.dart';
import 'package:mastery/screens/diagnostic_screen.dart';
import 'package:mastery/theme/mastery_theme.dart';
import 'package:mastery/widgets/mastery_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

Exercise _mcExercise(String id) => Exercise(
      exerciseId: id,
      type: ExerciseType.multipleChoice,
      instruction: 'Choose the correct option.',
      prompt: 'Q1',
      options: const [
        McOption(id: 'a', text: 'option a'),
        McOption(id: 'b', text: 'option b'),
      ],
      skillId: 'skill-one',
      evidenceTier: EvidenceTier.weak,
    );

class _RetakeFakeApiClient extends ApiClient {
  _RetakeFakeApiClient() : super(baseUrl: 'http://test.invalid');

  bool skipCalled = false;

  @override
  Future<DiagnosticStart> startDiagnostic() async {
    return DiagnosticStart(
      runId: 'r1',
      resumed: false,
      position: 0,
      total: 1,
      nextExercise: _mcExercise('00000000-0000-4000-8000-000000000031'),
    );
  }

  @override
  Future<void> skipDiagnostic() async {
    skipCalled = true;
  }

  @override
  Future<DiagnosticAnswerResult> submitDiagnosticAnswer({
    required String runId,
    required String exerciseId,
    required String exerciseType,
    required String userAnswer,
    DateTime? submittedAt,
  }) async =>
      throw UnimplementedError();

  @override
  Future<DiagnosticCompletion> completeDiagnostic(String runId) async =>
      throw UnimplementedError();

  @override
  Future<DiagnosticStart> restartDiagnostic() async =>
      throw UnimplementedError();
}

class _DashboardHost extends StatefulWidget {
  final ApiClient apiClient;
  const _DashboardHost({required this.apiClient});

  @override
  State<_DashboardHost> createState() => _DashboardHostState();
}

class _DashboardHostState extends State<_DashboardHost> {
  void _openRetake() {
    Navigator.of(context).push(
      MasteryFadeRoute<void>(
        builder: (_) => DiagnosticScreen(
          apiClient: widget.apiClient,
          onComplete: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MasteryColors.bgApp,
      body: Center(
        child: TextButton(
          onPressed: _openRetake,
          child: const Text('Re-run my level check'),
        ),
      ),
    );
  }
}

Widget _wrap(Widget child) => MaterialApp(
      theme: MasteryTheme.light(),
      home: child,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'tapping Re-run my level check pushes DiagnosticScreen',
    (tester) async {
      final api = _RetakeFakeApiClient();
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      await tester.pumpWidget(_wrap(_DashboardHost(apiClient: api)));
      await tester.pumpAndSettle();

      // Dashboard surface — only the link is on screen.
      expect(find.text('Re-run my level check'), findsOneWidget);
      expect(find.text('A short read on where you are.'), findsNothing);

      await tester.tap(find.text('Re-run my level check'));
      await tester.pumpAndSettle();

      // Diagnostic Welcome phase is now mounted on top.
      expect(find.text('A short read on where you are.'), findsOneWidget);
      expect(find.text('Begin'), findsOneWidget);
      expect(find.text('Skip for now'), findsOneWidget);
    },
  );

  testWidgets(
    'Skip path pops back to the dashboard host',
    (tester) async {
      final api = _RetakeFakeApiClient();
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      await tester.pumpWidget(_wrap(_DashboardHost(apiClient: api)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Re-run my level check'));
      await tester.pumpAndSettle();
      // Inside the diagnostic now.
      expect(find.text('A short read on where you are.'), findsOneWidget);

      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();

      // Diagnostic popped — dashboard link is back, welcome headline
      // is gone.
      expect(find.text('Re-run my level check'), findsOneWidget);
      expect(find.text('A short read on where you are.'), findsNothing);
      expect(api.skipCalled, isTrue);
    },
  );
}
