import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/learner/learner_skill_store.dart';
import 'package:mastery/models/lesson.dart';
import 'package:mastery/theme/mastery_theme.dart';
import 'package:mastery/widgets/skill_state_card.dart';

const _skillA = 'verb-ing-after-gerund-verbs';
const _skillB = 'present-perfect-continuous-vs-simple';

Widget _wrap(Widget child) => MaterialApp(
      theme: MasteryTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

LearnerSkillRecord _rec({
  required String skillId,
  required int score,
  Map<EvidenceTier, int> evidence = const {},
  List<TargetError> errors = const [],
  bool gateCleared = false,
  DateTime? lastAttemptAt,
  int? medianResponseMs,
}) =>
    LearnerSkillRecord(
      skillId: skillId,
      masteryScore: score,
      lastAttemptAt: lastAttemptAt,
      evidenceSummary: evidence,
      recentErrors: errors,
      productionGateCleared: gateCleared,
      medianResponseMsSnapshot: medianResponseMs,
    );

void main() {
  final now = DateTime.utc(2026, 4, 27, 12, 0, 0);

  group('SkillStateCard — copy lookup', () {
    testWidgets('renders nothing when records is empty', (tester) async {
      await tester.pumpWidget(
        _wrap(SkillStateCard(records: const [], now: now)),
      );
      expect(find.text('Where each skill stands'), findsNothing);
    });

    testWidgets('renders one row per skill, with title + status copy',
        (tester) async {
      final records = [
        _rec(skillId: _skillA, score: 10),
        _rec(skillId: _skillB, score: 35),
      ];
      await tester.pumpWidget(
        _wrap(SkillStateCard(records: records, now: now)),
      );
      expect(find.text('Where each skill stands'), findsOneWidget);
      expect(find.text('Verbs followed by -ing'), findsOneWidget);
      expect(
          find.text('Present perfect continuous vs simple'), findsOneWidget);
      expect(find.text('Just started'), findsOneWidget);
      expect(find.text('Practicing'), findsOneWidget);
    });

    testWidgets('falls back to skill_id when title is unregistered',
        (tester) async {
      final records = [_rec(skillId: 'unknown.skill', score: 5)];
      await tester.pumpWidget(
        _wrap(SkillStateCard(records: records, now: now)),
      );
      expect(find.text('unknown.skill'), findsOneWidget);
    });
  });

  group('SkillStateCard — status copy by SkillStatus', () {
    test('every SkillStatus has stable learner-facing copy', () {
      // Spot-check the §7.2 contract: each enum value maps to a label.
      expect(statusCopyFor(SkillStatus.started), 'Just started');
      expect(statusCopyFor(SkillStatus.practicing), 'Practicing');
      expect(statusCopyFor(SkillStatus.gettingThere), 'Getting there');
      expect(statusCopyFor(SkillStatus.almostMastered), 'Almost mastered');
      expect(statusCopyFor(SkillStatus.mastered), 'Mastered');
      expect(statusCopyFor(SkillStatus.reviewDue), 'Review due');
    });
  });

  group('SkillStateCard — reason line by status', () {
    test('mastered → strongest-evidence-solid copy', () {
      final r = _rec(
        skillId: _skillA,
        score: 90,
        evidence: const {EvidenceTier.strongest: 1, EvidenceTier.strong: 2},
        gateCleared: true,
        lastAttemptAt: now.subtract(const Duration(days: 1)),
        // Wave D — green-band median required for `mastered`.
        medianResponseMs: 4000,
      );
      expect(
          reasonLineFor(r, now), 'Strongest evidence on this rule is solid.');
    });

    test('almost_mastered → one-more-strong-item copy', () {
      final r = _rec(
        skillId: _skillA,
        score: 75,
        evidence: const {EvidenceTier.strong: 2},
      );
      expect(reasonLineFor(r, now), 'One more strong item to lock it in.');
    });

    test('getting_there → strong-evidence-appearing copy', () {
      final r = _rec(
        skillId: _skillA,
        score: 55,
        evidence: const {EvidenceTier.strong: 1, EvidenceTier.medium: 2},
      );
      expect(reasonLineFor(r, now), 'Strong evidence appearing — keep going.');
    });

    test('practicing → recognition-solid copy', () {
      final r = _rec(
        skillId: _skillA,
        score: 35,
        evidence: const {EvidenceTier.medium: 2},
      );
      expect(reasonLineFor(r, now),
          'Recognition is solid; production is still ahead.');
    });

    test('started with exactly one attempt → one-attempt-so-far copy', () {
      final r = _rec(
        skillId: _skillA,
        score: 10,
        evidence: const {EvidenceTier.medium: 1},
      );
      expect(reasonLineFor(r, now), 'Just one attempt so far.');
    });

    test('started with multiple attempts but low score → recognition-not-landing copy', () {
      // Codex finding: SkillStatus.started fires whenever score < 30,
      // not only on the first attempt. The copy must not lie.
      final r = _rec(
        skillId: _skillA,
        score: 0,
        evidence: const {EvidenceTier.medium: 4},
      );
      expect(reasonLineFor(r, now),
          'Recognition is not landing yet — one rule at a time.');
    });

    test('started with zero attempts → defaults to one-attempt copy (degenerate but harmless)', () {
      final r = _rec(skillId: _skillA, score: 0);
      expect(reasonLineFor(r, now), 'Just one attempt so far.');
    });

    test('review_due → days-since copy', () {
      final r = _rec(
        skillId: _skillA,
        score: 90,
        evidence: const {EvidenceTier.strongest: 1, EvidenceTier.strong: 2},
        gateCleared: true,
        lastAttemptAt: now.subtract(const Duration(days: 30)),
        // Wave D — review_due is reachable only after the skill once
        // reached mastered, which now requires a fast median.
        medianResponseMs: 4000,
      );
      expect(reasonLineFor(r, now), 'Last seen 30 days ago.');
    });
  });

  group('SkillStateCard — recurring-error row', () {
    testWidgets('hides recurring row when no error appears twice in window',
        (tester) async {
      final records = [
        _rec(
          skillId: _skillA,
          score: 5,
          errors: const [TargetError.contrast, TargetError.form],
        ),
      ];
      await tester.pumpWidget(
        _wrap(SkillStateCard(records: records, now: now)),
      );
      expect(find.textContaining('Recurring'), findsNothing);
    });

    testWidgets('shows recurring row when same error code appears twice',
        (tester) async {
      final records = [
        _rec(
          skillId: _skillA,
          score: 5,
          errors: const [
            TargetError.contrast,
            TargetError.form,
            TargetError.contrast,
          ],
        ),
      ];
      await tester.pumpWidget(
        _wrap(SkillStateCard(records: records, now: now)),
      );
      expect(find.textContaining('Recurring contrast slip'), findsOneWidget);
    });

    test('recurring copy exists for every TargetError code', () {
      for (final e in TargetError.values) {
        expect(recurringCopyFor(e).startsWith('Recurring'), isTrue,
            reason: '$e missing recurring copy');
      }
    });
  });
}
