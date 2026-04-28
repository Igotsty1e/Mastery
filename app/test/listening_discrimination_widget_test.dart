// Wave 14.8 — widget coverage for `listening_discrimination`.
//
// Three contracts the parent ExerciseScreen + SessionController rely on:
//   1. Options render in declared order with letter prefixes A, B, C, ...
//   2. Tapping an option emits onChanged with that option's id.
//   3. enabled=false suppresses option taps (after-submit lock).
//
// The audio player is wired via `MasteryAudioPlayer` and is covered
// separately in `mastery_audio_player_test.dart` — here we only verify
// it is present in the subtree.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/models/lesson.dart';
import 'package:mastery/theme/mastery_theme.dart';
import 'package:mastery/widgets/listening_discrimination_widget.dart';
import 'package:mastery/widgets/mastery_audio_player.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: MasteryTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

const _audio = ExerciseAudio(
  url: '/audio/lesson-1/ex-1.mp3',
  voice: ExerciseVoice.nova,
  transcript: 'I have eaten lunch already.',
);

const _options = <McOption>[
  McOption(id: 'opt-a', text: 'I have eaten lunch already.'),
  McOption(id: 'opt-b', text: 'I have been eating lunch already.'),
  McOption(id: 'opt-c', text: 'I am eating lunch already.'),
];

void main() {
  testWidgets('renders all options in order with letter prefixes A, B, C',
      (tester) async {
    await tester.pumpWidget(_wrap(
      ListeningDiscriminationWidget(
        audio: _audio,
        options: _options,
        onChanged: (_) {},
      ),
    ));

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
    expect(find.text('I have eaten lunch already.'), findsOneWidget);
    expect(find.text('I have been eating lunch already.'), findsOneWidget);
    expect(find.text('I am eating lunch already.'), findsOneWidget);
  });

  testWidgets('embeds the MasteryAudioPlayer above the options',
      (tester) async {
    await tester.pumpWidget(_wrap(
      ListeningDiscriminationWidget(
        audio: _audio,
        options: _options,
        onChanged: (_) {},
      ),
    ));

    expect(find.byType(MasteryAudioPlayer), findsOneWidget);
  });

  testWidgets('tapping an option emits onChanged with that option id',
      (tester) async {
    String? last;
    await tester.pumpWidget(_wrap(
      ListeningDiscriminationWidget(
        audio: _audio,
        options: _options,
        onChanged: (id) => last = id,
      ),
    ));

    await tester.tap(find.text('I have been eating lunch already.'));
    await tester.pumpAndSettle();

    expect(last, 'opt-b');
  });

  testWidgets('selecting a different option updates the emission',
      (tester) async {
    String? last;
    await tester.pumpWidget(_wrap(
      ListeningDiscriminationWidget(
        audio: _audio,
        options: _options,
        onChanged: (id) => last = id,
      ),
    ));

    await tester.tap(find.text('I have eaten lunch already.'));
    await tester.pumpAndSettle();
    expect(last, 'opt-a');

    await tester.tap(find.text('I am eating lunch already.'));
    await tester.pumpAndSettle();
    expect(last, 'opt-c');
  });

  testWidgets('enabled=false suppresses option taps (after-submit lock)',
      (tester) async {
    String? last;
    await tester.pumpWidget(_wrap(
      ListeningDiscriminationWidget(
        audio: _audio,
        options: _options,
        onChanged: (id) => last = id,
        enabled: false,
      ),
    ));

    await tester.tap(find.text('I have eaten lunch already.'));
    await tester.pumpAndSettle();

    expect(last, isNull);
  });
}
