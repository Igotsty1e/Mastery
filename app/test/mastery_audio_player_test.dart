// Wave 14.8 — widget coverage for the audio player.
//
// `audioplayers` throws `MissingPluginException` in unit tests; the widget's
// play/dispose paths are already guarded with try/catch (per the comment at
// the top of the widget file). What we test here is the **visual contract**:
// transcript toggle, disabled state, default copy.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/theme/mastery_theme.dart';
import 'package:mastery/widgets/mastery_audio_player.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: MasteryTheme.light(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('renders idle play button and Show transcript affordance',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const MasteryAudioPlayer(
        url: '/audio/lesson/exercise.mp3',
        transcript: 'I have lived here for five years.',
      ),
    ));

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('Show transcript'), findsOneWidget);
    // Transcript hidden by default.
    expect(find.text('I have lived here for five years.'), findsNothing);
  });

  testWidgets('tapping Show transcript reveals the text and flips the label',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const MasteryAudioPlayer(
        url: '/audio/lesson/exercise.mp3',
        transcript: 'I have lived here for five years.',
      ),
    ));

    await tester.tap(find.text('Show transcript'));
    await tester.pumpAndSettle();

    expect(find.text('I have lived here for five years.'), findsOneWidget);
    expect(find.text('Hide transcript'), findsOneWidget);
    expect(find.text('Show transcript'), findsNothing);
  });

  testWidgets('tapping Hide transcript hides the text again', (tester) async {
    await tester.pumpWidget(_wrap(
      const MasteryAudioPlayer(
        url: '/audio/lesson/exercise.mp3',
        transcript: 'I have lived here for five years.',
      ),
    ));

    await tester.tap(find.text('Show transcript'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide transcript'));
    await tester.pumpAndSettle();

    expect(find.text('I have lived here for five years.'), findsNothing);
    expect(find.text('Show transcript'), findsOneWidget);
  });

  testWidgets('enabled=false still allows transcript reveal (read-only mode)',
      (tester) async {
    await tester.pumpWidget(_wrap(
      const MasteryAudioPlayer(
        url: '/audio/lesson/exercise.mp3',
        transcript: 'After-submit replay should still let me see the words.',
        enabled: false,
      ),
    ));

    await tester.tap(find.text('Show transcript'));
    await tester.pumpAndSettle();

    expect(
      find.text('After-submit replay should still let me see the words.'),
      findsOneWidget,
    );
  });
}
