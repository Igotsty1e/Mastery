// Wave F — progressive hint stripping on fill_blank.
//
// Covers three hint-reveal modes (`always` / `after4s` / `never`)
// plus the unmount-with-pending-timer path (round-3 catch from the
// plan) and the §4.1 hint-pattern anchoring on the blank.

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/theme/mastery_theme.dart';
import 'package:mastery/widgets/fill_blank_widget.dart';

const _promptWithHint = 'She hopes ___ (finish) the project before holidays.';
const _promptWithoutHint = 'I enjoy ___ books on Sundays.';

Widget _wrap(Widget child) => MaterialApp(
      theme: MasteryTheme.light(),
      home: Scaffold(body: child),
    );

Widget _widget({
  required HintRevealMode mode,
  String prompt = _promptWithHint,
}) =>
    _wrap(FillBlankWidget(
      prompt: prompt,
      onChanged: (_) {},
      hintMode: mode,
    ));

String _promptText(WidgetTester tester) {
  final widget = tester.widget(find.byKey(fillBlankPromptKey));
  if (widget is Text) {
    final data = widget.data;
    if (data != null) return data;
    final span = widget.textSpan;
    if (span != null) return span.toPlainText();
    return '';
  }
  return '';
}

bool _rendersHint(WidgetTester tester) =>
    _promptText(tester).contains('(finish)');

void main() {
  testWidgets('always mode: prompt renders verbatim with hint', (tester) async {
    await tester.pumpWidget(_widget(mode: HintRevealMode.always));
    await tester.pump();
    expect(_rendersHint(tester), isTrue);
  });

  testWidgets('never mode: hint stripped, blank preserved', (tester) async {
    await tester.pumpWidget(_widget(mode: HintRevealMode.never));
    await tester.pump();
    expect(_rendersHint(tester), isFalse);
    // Blank marker survives: render still contains `___`.
    expect(_promptText(tester), contains('___'));
  });

  testWidgets('after4s mode: hint hidden initially, revealed after 4s',
      (tester) async {
    await tester.pumpWidget(_widget(mode: HintRevealMode.after4s));
    await tester.pump();
    expect(_rendersHint(tester), isFalse);
    await tester.pump(const Duration(seconds: 4, milliseconds: 100));
    expect(_rendersHint(tester), isTrue);
  });

  testWidgets('after4s mode: typing resets the reveal timer', (tester) async {
    await tester.pumpWidget(_widget(mode: HintRevealMode.after4s));
    await tester.pump();
    expect(_rendersHint(tester), isFalse);
    // Pump 3s, then type. Hint should still be hidden because the timer
    // resets on input.
    await tester.pump(const Duration(seconds: 3));
    await tester.enterText(find.byType(TextField), 'fi');
    // 3 more seconds passed since reset → 3s, not yet 4. Hint stays hidden.
    await tester.pump(const Duration(seconds: 3));
    expect(_rendersHint(tester), isFalse);
    // Now wait the remaining 1.5s for the post-reset timer to fire.
    await tester.pump(const Duration(seconds: 1, milliseconds: 500));
    expect(_rendersHint(tester), isTrue);
  });

  testWidgets('no-hint prompt: renders verbatim across all three modes',
      (tester) async {
    for (final mode in HintRevealMode.values) {
      await tester.pumpWidget(_widget(mode: mode, prompt: _promptWithoutHint));
      await tester.pump();
      final text = _promptText(tester);
      expect(text, contains('I enjoy'),
          reason: 'mode $mode should render no-hint prompt verbatim');
      expect(text, contains('___'),
          reason: 'mode $mode should preserve blank marker');
    }
  });

  testWidgets('after4s mode: unmount with pending timer does not throw',
      (tester) async {
    await tester.pumpWidget(_widget(mode: HintRevealMode.after4s));
    await tester.pump(const Duration(seconds: 2)); // timer still pending
    // Replace with a different widget tree → triggers dispose on the
    // FillBlankWidget while its timer is still running.
    await tester.pumpWidget(_wrap(const SizedBox.shrink()));
    // Pump well past the 4s mark to ensure the original timer doesn't
    // try to call setState() after dispose.
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('never mode: hint is stripped at the blank position', (tester) async {
    await tester.pumpWidget(_widget(mode: HintRevealMode.never));
    await tester.pump();
    // `She hopes ___ the project before holidays.` — the `(finish)` and
    // its preceding space are removed; the rest stays intact.
    expect(_promptText(tester),
        equals('She hopes ___ the project before holidays.'));
  });
}
