import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/theme/mastery_theme.dart';
import 'package:mastery/widgets/decision_reason_line.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: MasteryTheme.light(),
      home: Scaffold(body: child),
    );

void main() {
  group('decisionReasonCopy', () {
    test('maps the two §9.1 reorder codes to learner-facing copy', () {
      expect(
        decisionReasonCopy('same_rule_different_angle'),
        'Same rule, different angle.',
      );
      expect(
        decisionReasonCopy('same_rule_simpler_ask'),
        'Same rule, simpler ask.',
      );
    });

    test(
        'returns null for operational codes (calm silence per §11.4)',
        () {
      // Every code emitted by the engine that is not a §11.3 routing
      // string should collapse to silence. We snapshot the current
      // server-side set so a new code added without a curated copy
      // forces an explicit decision in this test.
      const operationalCodes = [
        'linear_default',
        'cap_relaxed_fallback',
        'no_candidates',
        'bank_empty',
        'session_complete',
        'session_not_in_progress',
      ];
      for (final c in operationalCodes) {
        expect(decisionReasonCopy(c), isNull, reason: 'code $c');
      }
    });

    test('null and empty inputs return null', () {
      expect(decisionReasonCopy(null), isNull);
      expect(decisionReasonCopy(''), isNull);
    });
  });

  group('DecisionReasonLine widget', () {
    testWidgets('renders the curated copy for a known reorder code',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const DecisionReasonLine(text: 'same_rule_different_angle')),
      );
      expect(find.text('Same rule, different angle.'), findsOneWidget);
    });

    testWidgets('collapses for null', (tester) async {
      await tester.pumpWidget(_wrap(const DecisionReasonLine(text: null)));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('collapses for empty', (tester) async {
      await tester.pumpWidget(_wrap(const DecisionReasonLine(text: '')));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets(
        'collapses for operational codes (no raw enum leaks to UI)',
        (tester) async {
      // This is the regression bar for the QA-found bug:
      // `linear_default`, `cap_relaxed_fallback`, `same_rule_simpler_ask`
      // were being rendered raw in production. Confirm operational
      // codes never reach the screen.
      for (final c in ['linear_default', 'cap_relaxed_fallback', 'no_candidates']) {
        await tester.pumpWidget(_wrap(DecisionReasonLine(text: c)));
        expect(find.text(c), findsNothing, reason: 'raw code $c leaked');
        expect(find.byType(Text), findsNothing);
      }
    });
  });
}
