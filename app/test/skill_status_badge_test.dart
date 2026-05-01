// Wave 14 (V1.5 Skill-progress UI) — SkillStatusBadge.
//
// Pill rendered before the CEFR chip on the dashboard Rules card.
// Status copy is delegated to `skill_state_card.dart#statusCopyFor`,
// uppercased here. Coverage focuses on:
//   - the right copy for each SkillStatus enum (the pill is the
//     dashboard's only status surface today),
//   - that the pill respects the passed `now` so reviewDue can be
//     reproduced deterministically.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/learner/learner_skill_store.dart';
import 'package:mastery/models/lesson.dart';
import 'package:mastery/theme/mastery_theme.dart';
import 'package:mastery/widgets/skill_status_badge.dart';

const _skill = 'verb-ing-after-gerund-verbs';

Widget _wrap(Widget child) => MaterialApp(
      theme: MasteryTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );

LearnerSkillRecord _rec({
  required int score,
  Map<EvidenceTier, int> evidence = const {},
  bool gateCleared = false,
  DateTime? lastAttemptAt,
  int? medianResponseMs,
}) =>
    LearnerSkillRecord(
      skillId: _skill,
      masteryScore: score,
      lastAttemptAt: lastAttemptAt,
      evidenceSummary: evidence,
      recentErrors: const [],
      productionGateCleared: gateCleared,
      medianResponseMsSnapshot: medianResponseMs,
    );

void main() {
  final now = DateTime.utc(2026, 4, 28, 12, 0, 0);

  testWidgets('renders JUST STARTED for masteryScore < 30', (tester) async {
    await tester.pumpWidget(
      _wrap(SkillStatusBadge(record: _rec(score: 10), now: now)),
    );
    expect(find.text('Just started'), findsOneWidget);
  });

  testWidgets('renders PRACTICING for masteryScore in [30,55)',
      (tester) async {
    await tester.pumpWidget(
      _wrap(SkillStatusBadge(record: _rec(score: 35), now: now)),
    );
    expect(find.text('Practicing'), findsOneWidget);
  });

  testWidgets('renders ALMOST MASTERED before the production gate',
      (tester) async {
    await tester.pumpWidget(
      _wrap(SkillStatusBadge(
        record: _rec(
          score: 75,
          gateCleared: false,
          evidence: const {EvidenceTier.strong: 2},
        ),
        now: now,
      )),
    );
    expect(find.text('Almost mastered'), findsOneWidget);
  });

  testWidgets(
      'renders MASTERED only with productionGateCleared AND fast median (Wave D)',
      (tester) async {
    await tester.pumpWidget(
      _wrap(SkillStatusBadge(
        record: _rec(
          score: 95,
          gateCleared: true,
          evidence: const {
            EvidenceTier.weak: 6,
            EvidenceTier.medium: 4,
            EvidenceTier.strong: 2,
            EvidenceTier.strongest: 1,
          },
          // Wave D — median in the green band lets the gate clear.
          medianResponseMs: 4200,
        ),
        now: now,
      )),
    );
    expect(find.text('Mastered'), findsOneWidget);
  });

  testWidgets(
      'caps at ALMOST MASTERED when median snapshot is missing (Wave D)',
      (tester) async {
    await tester.pumpWidget(
      _wrap(SkillStatusBadge(
        record: _rec(
          score: 95,
          gateCleared: true,
          evidence: const {EvidenceTier.strongest: 1, EvidenceTier.strong: 2},
          // medianResponseMs intentionally omitted — no stable timed
          // attempts yet → status holds at ALMOST MASTERED.
        ),
        now: now,
      )),
    );
    expect(find.text('Almost mastered'), findsOneWidget);
    expect(find.text('Mastered'), findsNothing);
  });

  testWidgets('renders REVIEW DUE when overdue per the schedule',
      (tester) async {
    final stale = now.subtract(const Duration(days: 30));
    await tester.pumpWidget(
      _wrap(SkillStatusBadge(
        record: _rec(
          score: 95,
          gateCleared: true,
          evidence: const {EvidenceTier.strong: 3},
          lastAttemptAt: stale,
          // Wave D — review_due requires the same green-band median
          // that gates `mastered`; without it the skill never enters
          // mastered and never expires into review_due.
          medianResponseMs: 3500,
        ),
        now: now,
      )),
    );
    expect(find.text('Review due'), findsOneWidget);
  });
}
