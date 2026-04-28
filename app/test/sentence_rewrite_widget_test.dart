// Wave 14.2 phase 3 — V1.5 open-answer family widget.
//
// Three contracts the parent ExerciseScreen + SessionController rely
// on:
//   1. The text field starts empty (sentence_rewrite framing — not
//      sentence_correction's edit-in-place).
//   2. Each keystroke fires `onChanged` with the trimmed value.
//   3. The "ORIGINAL" reference card renders the prompt verbatim.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/theme/mastery_theme.dart';
import 'package:mastery/widgets/sentence_rewrite_widget.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: MasteryTheme.light(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets(
      'starts with an empty input field (sentence_rewrite is fresh-write, not edit-in-place)',
      (tester) async {
    String last = '<unset>';
    await tester.pumpWidget(_wrap(
      SentenceRewriteWidget(
        prompt: 'I work here for five years.',
        onChanged: (v) => last = v,
      ),
    ));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    // The post-frame initial emit fires with the empty value.
    expect(last, '');
  });

  testWidgets('renders the prompt verbatim on the ORIGINAL card',
      (tester) async {
    await tester.pumpWidget(_wrap(
      SentenceRewriteWidget(
        prompt: 'She continues to volunteer at the shelter every weekend.',
        onChanged: (_) {},
      ),
    ));
    expect(find.text('ORIGINAL'), findsOneWidget);
    expect(
      find.text('She continues to volunteer at the shelter every weekend.'),
      findsOneWidget,
    );
  });

  testWidgets('emits trimmed text on each keystroke', (tester) async {
    final emissions = <String>[];
    await tester.pumpWidget(_wrap(
      SentenceRewriteWidget(
        prompt: 'I work here for five years.',
        onChanged: emissions.add,
      ),
    ));
    await tester.pump();
    await tester.enterText(
      find.byType(TextField),
      "  I have worked here for five years.  ",
    );
    expect(emissions.last, "I have worked here for five years.");
  });

  testWidgets('respects the enabled flag (locks input when disabled)',
      (tester) async {
    await tester.pumpWidget(_wrap(
      SentenceRewriteWidget(
        prompt: 'Anything.',
        enabled: false,
        onChanged: (_) {},
      ),
    ));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
  });
}
