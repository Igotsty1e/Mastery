// Wave 12.6 — ResultPanel "See full rule" link + bottom sheet.
//
// Asserts:
// - the link does NOT render when skillRuleSnapshot is null
// - the link DOES render when skillRuleSnapshot is non-null
// - tapping the link opens a bottom sheet containing the rule + examples

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/models/evaluation.dart';
import 'package:mastery/theme/mastery_theme.dart';
import 'package:mastery/widgets/mastery_widgets.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: MasteryTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets(
    'No "See full rule" link when skillRuleSnapshot is null',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ResultPanel(
            correct: false,
            canonicalAnswer: 'trying',
            explanation: 'After enjoy, use the -ing form.',
            skillRuleSnapshot: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Incorrect'), findsOneWidget);
      expect(find.text('See full rule \u2192'), findsNothing);
    },
  );

  testWidgets(
    '"See full rule" link renders + opens a bottom sheet with the rule',
    (tester) async {
      const snapshot = SkillRuleSnapshot(
        introRule: 'Some verbs are followed directly by the -ing form.',
        introExamples: <String>[
          'I enjoy working with international clients.',
          'She suggested taking a taxi.',
        ],
      );
      await tester.pumpWidget(
        _wrap(
          const ResultPanel(
            correct: true,
            canonicalAnswer: 'trying',
            explanation: 'Correct — enjoy + verb-ing.',
            skillRuleSnapshot: snapshot,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Link present.
      expect(find.text('See full rule \u2192'), findsOneWidget);

      // Sheet not yet on screen.
      expect(find.textContaining('Some verbs are followed'), findsNothing);

      await tester.tap(find.text('See full rule \u2192'));
      await tester.pumpAndSettle();

      // Sheet content rendered.
      expect(
        find.textContaining('Some verbs are followed'),
        findsOneWidget,
      );
      expect(
        find.text('I enjoy working with international clients.'),
        findsOneWidget,
      );
      expect(
        find.text('She suggested taking a taxi.'),
        findsOneWidget,
      );
      expect(find.text('Close'), findsOneWidget);

      // Close dismisses.
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Some verbs are followed'), findsNothing);
    },
  );

  testWidgets(
    '"See full rule" link is visible on a CORRECT result too (per Wave 12.6 spec)',
    (tester) async {
      const snapshot = SkillRuleSnapshot(
        introRule: 'Rule text.',
        introExamples: <String>['Example.'],
      );
      await tester.pumpWidget(
        _wrap(
          const ResultPanel(
            correct: true,
            canonicalAnswer: 'trying',
            explanation: 'Yep.',
            skillRuleSnapshot: snapshot,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Correct'), findsOneWidget);
      expect(find.text('See full rule \u2192'), findsOneWidget);
    },
  );
}
