// Wave B — LatencyBand renders the calm pace rail on the exercise
// screen. Three zones (fast / steady / slow), hides on un-tagged
// exercises and skills with no recorded history, and refreshes when
// the skill changes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/theme/mastery_theme.dart';
import 'package:mastery/widgets/latency_band.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: MasteryTheme.light(),
      home: Scaffold(body: child),
    );

/// Returns the painted color of the rail (the only `Container` with a
/// `BoxDecoration` and a `borderRadius` of 2 inside the band). Returns
/// `null` when the band has collapsed itself.
Color? _railColor(WidgetTester tester) {
  final container = tester
      .widgetList<Container>(find.byType(Container))
      .where((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.borderRadius != null;
      })
      .firstOrNull;
  if (container == null) return null;
  return (container.decoration as BoxDecoration).color;
}

void main() {
  group('paceForMedianMs', () {
    test('< 6000ms → fast', () {
      expect(paceForMedianMs(0), LatencyPace.fast);
      expect(paceForMedianMs(3000), LatencyPace.fast);
      expect(paceForMedianMs(5999), LatencyPace.fast);
    });

    test('6000ms..11999ms → steady', () {
      expect(paceForMedianMs(6000), LatencyPace.steady);
      expect(paceForMedianMs(8500), LatencyPace.steady);
      expect(paceForMedianMs(11999), LatencyPace.steady);
    });

    test('>= 12000ms → slow', () {
      expect(paceForMedianMs(12000), LatencyPace.slow);
      expect(paceForMedianMs(20000), LatencyPace.slow);
    });
  });

  group('LatencyBand widget', () {
    testWidgets('hides when skillId is null', (tester) async {
      await tester.pumpWidget(_wrap(
        const LatencyBand(skillId: null),
      ));
      await tester.pumpAndSettle();
      // No `PACE` label, no rail.
      expect(find.text('PACE'), findsNothing);
      expect(_railColor(tester), isNull);
    });

    testWidgets('hides when median resolver returns null (no history)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        LatencyBand(
          skillId: 'skill-x',
          medianResolver: (_) async => null,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('PACE'), findsNothing);
      expect(_railColor(tester), isNull);
    });

    testWidgets('renders fast (success) rail when median below 6000ms',
        (tester) async {
      await tester.pumpWidget(_wrap(
        LatencyBand(
          skillId: 'skill-x',
          medianResolver: (_) async => 3000,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('PACE'), findsOneWidget);
      expect(_railColor(tester), MasteryColors.success.withAlpha(180));
    });

    testWidgets('renders steady (warning) rail when median in 6000..12000',
        (tester) async {
      await tester.pumpWidget(_wrap(
        LatencyBand(
          skillId: 'skill-x',
          medianResolver: (_) async => 8000,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('PACE'), findsOneWidget);
      expect(_railColor(tester), MasteryColors.warning.withAlpha(180));
    });

    testWidgets('renders slow (error) rail when median at or above 12000',
        (tester) async {
      await tester.pumpWidget(_wrap(
        LatencyBand(
          skillId: 'skill-x',
          medianResolver: (_) async => 14000,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('PACE'), findsOneWidget);
      expect(_railColor(tester), MasteryColors.error.withAlpha(180));
    });

    testWidgets('refetches and re-paints when skillId changes',
        (tester) async {
      String? activeSkillId = 'skill-fast';
      Future<int?> resolver(String s) async {
        return switch (s) {
          'skill-fast' => 2000,
          'skill-slow' => 14000,
          _ => null,
        };
      }

      Widget build() => _wrap(LatencyBand(
            skillId: activeSkillId,
            medianResolver: resolver,
          ));

      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(_railColor(tester), MasteryColors.success.withAlpha(180));

      activeSkillId = 'skill-slow';
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(_railColor(tester), MasteryColors.error.withAlpha(180));
    });

    testWidgets('switching to a skill with no history collapses the band',
        (tester) async {
      String? activeSkillId = 'skill-known';
      Future<int?> resolver(String s) async {
        return s == 'skill-known' ? 4000 : null;
      }

      Widget build() => _wrap(LatencyBand(
            skillId: activeSkillId,
            medianResolver: resolver,
          ));

      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(find.text('PACE'), findsOneWidget);

      activeSkillId = 'skill-unknown';
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(find.text('PACE'), findsNothing);
      expect(_railColor(tester), isNull);
    });
  });
}
