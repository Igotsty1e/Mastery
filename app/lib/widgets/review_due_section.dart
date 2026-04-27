import 'package:flutter/material.dart';

import '../learner/review_scheduler.dart';
import '../learner/skill_titles.dart';
import '../theme/mastery_theme.dart';
import 'mastery_widgets.dart';

/// Wave 4 dashboard teaser per
/// `docs/plans/wave4-transparency-layer.md §2.3`. Surfaces every
/// non-graduated skill whose `ReviewScheduler.dueAt(now)` returns due
/// or overdue. When the list is empty the widget renders nothing —
/// silence is the right state per §11.4.
class ReviewDueSection extends StatelessWidget {
  final List<ReviewSchedule> dueReviews;
  final DateTime now;

  const ReviewDueSection({
    super.key,
    required this.dueReviews,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    if (dueReviews.isEmpty) return const SizedBox.shrink();
    final tokens = context.masteryTokens;
    return MasterySoftCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      color: MasteryColors.bgRaised,
      borderColor: tokens.borderSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'Reviews due',
                style: MasteryTextStyles.titleMd,
              ),
              const Spacer(),
              Text(
                '${dueReviews.length}',
                style: MasteryTextStyles.mono(
                  size: 13,
                  lineHeight: 16,
                  color: tokens.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < dueReviews.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _DueRow(schedule: dueReviews[i], now: now),
          ],
        ],
      ),
    );
  }
}

class _DueRow extends StatelessWidget {
  final ReviewSchedule schedule;
  final DateTime now;

  const _DueRow({required this.schedule, required this.now});

  @override
  Widget build(BuildContext context) {
    final overdueDays = now.difference(schedule.dueAt).inDays;
    final dueCopy = overdueDays <= 0
        ? 'Review due'
        : overdueDays == 1
            ? '1 day overdue'
            : '$overdueDays days overdue';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            skillTitleFor(schedule.skillId),
            style: MasteryTextStyles.bodyMd.copyWith(
              color: MasteryColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          dueCopy,
          style: MasteryTextStyles.labelSm.copyWith(
            color: overdueDays > 0
                ? MasteryColors.error
                : MasteryColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
