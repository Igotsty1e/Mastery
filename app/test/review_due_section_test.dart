import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/learner/review_scheduler.dart';
import 'package:mastery/theme/mastery_theme.dart';
import 'package:mastery/widgets/review_due_section.dart';

const _skillA = 'verb-ing-after-gerund-verbs';
const _skillB = 'present-perfect-continuous-vs-simple';

Widget _wrap(Widget child) => MaterialApp(
      theme: MasteryTheme.light(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

ReviewSchedule _sched({
  required String skillId,
  required DateTime due,
  required DateTime lastOutcome,
  int step = 1,
  int mistakes = 0,
  bool graduated = false,
}) =>
    ReviewSchedule(
      skillId: skillId,
      step: step,
      dueAt: due,
      lastOutcomeAt: lastOutcome,
      lastOutcomeMistakes: mistakes,
      graduated: graduated,
    );

void main() {
  final now = DateTime.utc(2026, 4, 27, 12, 0, 0);

  group('ReviewDueSection', () {
    testWidgets('renders nothing when there are no due reviews',
        (tester) async {
      await tester.pumpWidget(
        _wrap(ReviewDueSection(dueReviews: const [], now: now)),
      );
      expect(find.text('Reviews due'), findsNothing);
    });

    testWidgets('renders a row per due review with skill title',
        (tester) async {
      final due = [
        _sched(
          skillId: _skillA,
          due: now.subtract(const Duration(days: 1)),
          lastOutcome: now.subtract(const Duration(days: 2)),
        ),
        _sched(
          skillId: _skillB,
          due: now,
          lastOutcome: now.subtract(const Duration(days: 1)),
        ),
      ];
      await tester.pumpWidget(
        _wrap(ReviewDueSection(dueReviews: due, now: now)),
      );
      expect(find.text('Reviews due'), findsOneWidget);
      expect(find.text('Verbs followed by -ing'), findsOneWidget);
      expect(
          find.text('Present perfect continuous vs simple'), findsOneWidget);
      // Count badge
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('"Review due" copy when not overdue, "X days overdue" when past',
        (tester) async {
      final due = [
        _sched(
          skillId: _skillA,
          due: now,
          lastOutcome: now.subtract(const Duration(days: 1)),
        ),
        _sched(
          skillId: _skillB,
          due: now.subtract(const Duration(days: 3)),
          lastOutcome: now.subtract(const Duration(days: 4)),
        ),
      ];
      await tester.pumpWidget(
        _wrap(ReviewDueSection(dueReviews: due, now: now)),
      );
      expect(find.text('Review due'), findsOneWidget);
      expect(find.text('3 days overdue'), findsOneWidget);
    });

    testWidgets('"1 day overdue" singular form fires at exactly one day',
        (tester) async {
      final due = [
        _sched(
          skillId: _skillA,
          due: now.subtract(const Duration(days: 1)),
          lastOutcome: now.subtract(const Duration(days: 2)),
        ),
      ];
      await tester.pumpWidget(
        _wrap(ReviewDueSection(dueReviews: due, now: now)),
      );
      expect(find.text('1 day overdue'), findsOneWidget);
    });
  });
}
