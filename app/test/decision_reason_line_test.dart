import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/theme/mastery_theme.dart';
import 'package:mastery/widgets/decision_reason_line.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: MasteryTheme.light(),
      home: Scaffold(body: child),
    );

void main() {
  group('DecisionReasonLine', () {
    testWidgets('renders the reason when text is non-null and non-empty',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const DecisionReasonLine(text: 'Same rule, different angle.')),
      );
      expect(find.text('Same rule, different angle.'), findsOneWidget);
    });

    testWidgets('collapses to zero-height SizedBox when text is null',
        (tester) async {
      await tester.pumpWidget(_wrap(const DecisionReasonLine(text: null)));
      // No Text widget should be present.
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('collapses to zero-height SizedBox when text is empty',
        (tester) async {
      await tester.pumpWidget(_wrap(const DecisionReasonLine(text: '')));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('renders all three §9.1 reason variants', (tester) async {
      const reasons = [
        'Same rule, different angle.',
        'Same rule, simpler ask.',
        'Three misses on this rule — moving on for now. We will come back later.',
      ];
      for (final r in reasons) {
        await tester.pumpWidget(_wrap(DecisionReasonLine(text: r)));
        expect(find.text(r), findsOneWidget);
      }
    });
  });
}
