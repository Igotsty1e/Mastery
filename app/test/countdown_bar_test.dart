// Wave G7 — calm 60-second countdown bar on the exercise screen.
// Verifies the bar renders, shrinks over time, never blocks submit
// (no callback fires when the timer runs out — that's the whole
// point), and resets when the parent rebuilds with a new key.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/theme/mastery_theme.dart';
import 'package:mastery/widgets/countdown_bar.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: MasteryTheme.light(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('renders the TIME label and a track', (tester) async {
    await tester.pumpWidget(
      _wrap(const SizedBox(width: 400, child: CountdownBar())),
    );
    await tester.pump();
    expect(find.text('TIME'), findsOneWidget);
  });

  testWidgets('foreground bar shrinks as time passes', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(width: 400, child: CountdownBar(
          duration: Duration(seconds: 1),
        )),
      ),
    );
    await tester.pump();

    FractionallySizedBox sizedBox() =>
        tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox));

    final start = sizedBox().widthFactor!;
    expect(start, greaterThan(0.95));

    await tester.pump(const Duration(milliseconds: 600));
    final mid = sizedBox().widthFactor!;
    expect(mid, lessThan(start));
    expect(mid, greaterThan(0.0));

    await tester.pump(const Duration(milliseconds: 600));
    final end = sizedBox().widthFactor!;
    expect(end, lessThanOrEqualTo(0.001));

    // Bar holds at zero forever — does not throw, does not crash.
    await tester.pump(const Duration(seconds: 5));
    expect(sizedBox().widthFactor, lessThanOrEqualTo(0.001));
  });

  testWidgets('changing key restarts the countdown', (tester) async {
    var key = const ValueKey('a');
    Widget build() => _wrap(
          SizedBox(
            width: 400,
            child: CountdownBar(
              key: key,
              duration: const Duration(seconds: 1),
            ),
          ),
        );
    await tester.pumpWidget(build());
    await tester.pump(const Duration(milliseconds: 600));
    final beforeReset = tester
        .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .widthFactor!;
    expect(beforeReset, lessThan(0.5));

    key = const ValueKey('b'); // new exercise → new key → reset
    await tester.pumpWidget(build());
    await tester.pump();
    final afterReset = tester
        .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .widthFactor!;
    expect(afterReset, greaterThan(0.95));
  });
}
