// Wave 14.3 phase 2 — V1.5 feedback prompt sheet.
//
// Three contracts the SummaryScreen relies on:
//   1. Send is disabled until at least one star is selected.
//   2. Tapping Send pops the sheet with FeedbackPromptOutcome.submitted
//      and the chosen rating + trimmed comment.
//   3. Tapping Skip pops with FeedbackPromptOutcome.dismissed and no
//      rating / comment.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/theme/mastery_theme.dart';
import 'package:mastery/widgets/feedback_prompt_sheet.dart';

Widget _wrap(VoidCallback openSheet, ValueChanged<FeedbackPromptResult?> onResult) =>
    MaterialApp(
      theme: MasteryTheme.light(),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await showFeedbackPromptSheet(ctx);
                onResult(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  setUp(() {
    // Larger surface so the sheet fits comfortably in tests.
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('Send is disabled until a star is tapped', (tester) async {
    FeedbackPromptResult? result;
    await tester.binding.setSurfaceSize(const Size(400, 800));
    await tester.pumpWidget(_wrap(() {}, (r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final sendButton =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send'));
    expect(sendButton.onPressed, isNull);

    // Tap the third star.
    final stars = find.byIcon(Icons.star_outline_rounded);
    expect(stars, findsNWidgets(5));
    await tester.tap(stars.at(2));
    await tester.pumpAndSettle();

    final after =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send'));
    expect(after.onPressed, isNotNull);
    // Cleanup: dismiss the sheet so the test can finish.
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(result?.outcome, FeedbackPromptOutcome.dismissed);
  });

  testWidgets('tapping Send returns rating + trimmed comment', (tester) async {
    FeedbackPromptResult? result;
    await tester.binding.setSurfaceSize(const Size(400, 800));
    await tester.pumpWidget(_wrap(() {}, (r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.star_outline_rounded).at(3));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  felt great   ');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.outcome, FeedbackPromptOutcome.submitted);
    expect(result!.rating, 4);
    expect(result!.commentText, 'felt great');
    expect(result!.wireOutcome, 'submitted');
  });

  testWidgets('tapping Skip returns dismissed (no rating, no comment)',
      (tester) async {
    FeedbackPromptResult? result;
    await tester.binding.setSurfaceSize(const Size(400, 800));
    await tester.pumpWidget(_wrap(() {}, (r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Comment but no star — Skip should still send dismissed.
    await tester.enterText(find.byType(TextField), 'whatever');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(result?.outcome, FeedbackPromptOutcome.dismissed);
    expect(result?.rating, isNull);
    expect(result?.commentText, isNull);
    expect(result?.wireOutcome, 'dismissed');
  });

  testWidgets('empty comment is normalised to null on submit', (tester) async {
    FeedbackPromptResult? result;
    await tester.binding.setSurfaceSize(const Size(400, 800));
    await tester.pumpWidget(_wrap(() {}, (r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.star_outline_rounded).at(0));
    await tester.pumpAndSettle();
    // No comment entered.
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(result?.outcome, FeedbackPromptOutcome.submitted);
    expect(result?.rating, 1);
    expect(result?.commentText, isNull);
  });
}
