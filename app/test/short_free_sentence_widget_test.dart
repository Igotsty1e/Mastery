// Wave 14.4 — V1.5 open-answer family, phase 4.
//
// `short_free_sentence` is a bare free-text input — no ORIGINAL
// reference card, no canonical anchor. Three contracts:
//   1. The input field starts empty and emits an empty initial value
//      so the parent's Submit gate sees a fresh state.
//   2. Each keystroke fires `onChanged` with the trimmed value.
//   3. The widget renders no anchor sentence (the calling
//      InstructionBand is the only anchor; surfacing one would bias
//      the learner toward mimicry).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/theme/mastery_theme.dart';
import 'package:mastery/widgets/short_free_sentence_widget.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: MasteryTheme.light(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('starts with an empty input field', (tester) async {
    String last = '<unset>';
    await tester.pumpWidget(_wrap(
      ShortFreeSentenceWidget(onChanged: (v) => last = v),
    ));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(last, '');
  });

  testWidgets('emits trimmed text on each keystroke', (tester) async {
    final emissions = <String>[];
    await tester.pumpWidget(_wrap(
      ShortFreeSentenceWidget(onChanged: emissions.add),
    ));
    await tester.pump();
    await tester.enterText(
      find.byType(TextField),
      '  I have been working for three hours.  ',
    );
    expect(emissions.last, 'I have been working for three hours.');
  });

  testWidgets('does NOT render any reference / anchor card', (tester) async {
    await tester.pumpWidget(_wrap(
      ShortFreeSentenceWidget(onChanged: (_) {}),
    ));
    // The sentence_rewrite + sentence_correction widgets surface an
    // ORIGINAL label; short_free_sentence must not.
    expect(find.text('ORIGINAL'), findsNothing);
  });

  testWidgets('respects the enabled flag', (tester) async {
    await tester.pumpWidget(_wrap(
      ShortFreeSentenceWidget(enabled: false, onChanged: (_) {}),
    ));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
  });
}
