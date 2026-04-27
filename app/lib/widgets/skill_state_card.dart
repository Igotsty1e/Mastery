import 'package:flutter/material.dart';

import '../learner/learner_skill_store.dart';
import '../learner/skill_titles.dart';
import '../models/lesson.dart';
import '../theme/mastery_theme.dart';
import 'mastery_widgets.dart';

/// Wave 4 transparency-layer per-skill panel per
/// `LEARNING_ENGINE.md §11.2`. Renders one row per skill the learner
/// touched, showing status, a one-line reason, and a recurring-error
/// row when the same target error has appeared twice in the last five
/// attempts.
///
/// The card is purely informational. No tap actions, no edit affordance.
/// Tone follows §11.4 — calm, no fake stakes, no encouragement that
/// isn't earned.
class SkillStateCard extends StatelessWidget {
  /// Records to render. Caller is responsible for ordering and for
  /// filtering (e.g. only this-session skills on the summary screen).
  final List<LearnerSkillRecord> records;

  /// Anchor "now" for status derivation. Tests pass a fixed clock; the
  /// summary screen passes the wall-clock.
  final DateTime now;

  const SkillStateCard({
    super.key,
    required this.records,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const SizedBox.shrink();
    final tokens = context.masteryTokens;
    return MasterySoftCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      color: MasteryColors.bgRaised,
      borderColor: tokens.borderSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where each skill stands',
            style: MasteryTextStyles.titleMd,
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < records.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _SkillRow(record: records[i], now: now),
          ],
        ],
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  final LearnerSkillRecord record;
  final DateTime now;

  const _SkillRow({required this.record, required this.now});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final status = record.statusAt(now);
    final recurring = _recurringError(record.recentErrors);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                skillTitleFor(record.skillId),
                style: MasteryTextStyles.bodyMd.copyWith(
                  color: MasteryColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              statusCopyFor(status),
              style: MasteryTextStyles.labelSm.copyWith(
                color: _statusColor(status, tokens),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          reasonLineFor(record, now),
          style: MasteryTextStyles.bodySm.copyWith(
            color: MasteryColors.textSecondary,
            height: 1.45,
          ),
        ),
        if (recurring != null) ...[
          const SizedBox(height: 6),
          Text(
            recurringCopyFor(recurring),
            style: MasteryTextStyles.bodySm.copyWith(
              color: tokens.textTertiary,
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Color _statusColor(SkillStatus s, MasteryTokens tokens) => switch (s) {
        SkillStatus.mastered => tokens.success,
        SkillStatus.almostMastered => MasteryColors.actionPrimary,
        SkillStatus.gettingThere => MasteryColors.actionPrimary,
        SkillStatus.practicing => MasteryColors.textSecondary,
        SkillStatus.started => tokens.textTertiary,
        SkillStatus.reviewDue => MasteryColors.error,
      };
}

/// Status label per `LEARNING_ENGINE.md §7.2`. Labels are part of the
/// contract; thresholds for transitions are tunable in
/// `LearnerSkillRecord.statusAt`.
String statusCopyFor(SkillStatus status) => switch (status) {
      SkillStatus.started => 'Just started',
      SkillStatus.practicing => 'Practicing',
      SkillStatus.gettingThere => 'Getting there',
      SkillStatus.almostMastered => 'Almost mastered',
      SkillStatus.mastered => 'Mastered',
      SkillStatus.reviewDue => 'Review due',
    };

/// One-line reason rule per `docs/plans/wave4-transparency-layer.md
/// §2.2`. V0 thresholds; tunable. Tone is calm coach, not cheerleader.
String reasonLineFor(LearnerSkillRecord record, DateTime now) {
  final status = record.statusAt(now);
  switch (status) {
    case SkillStatus.mastered:
      return 'Strongest evidence on this rule is solid.';
    case SkillStatus.almostMastered:
      return 'One more strong item to lock it in.';
    case SkillStatus.gettingThere:
      return 'Strong evidence appearing — keep going.';
    case SkillStatus.practicing:
      return 'Recognition is solid; production is still ahead.';
    case SkillStatus.started:
      // Status `started` is masteryScore < 30, which can persist after
      // many wrong attempts — not just on the first one. Read the
      // evidence summary so the copy stays factually true:
      // - 1 attempt total → "Just one attempt so far."
      // - more attempts but still low score → "Recognition is not
      //   landing yet — one rule at a time."
      final attempts =
          record.evidenceSummary.values.fold<int>(0, (a, b) => a + b);
      if (attempts <= 1) return 'Just one attempt so far.';
      return 'Recognition is not landing yet — one rule at a time.';
    case SkillStatus.reviewDue:
      final last = record.lastAttemptAt;
      if (last == null) return 'Time for a review.';
      final days = now.difference(last).inDays;
      if (days <= 0) return 'Time for a review.';
      if (days == 1) return 'Last seen 1 day ago.';
      return 'Last seen $days days ago.';
  }
}

/// Returns the target-error code that appears at least twice in the
/// recent-errors window per `docs/plans/wave4-transparency-layer.md
/// §2.2`. If multiple codes meet the threshold, returns the most recent
/// one (so the row reflects the current pattern, not a stale streak).
TargetError? _recurringError(List<TargetError> recent) {
  if (recent.length < 2) return null;
  final counts = <TargetError, int>{};
  for (final e in recent) {
    counts[e] = (counts[e] ?? 0) + 1;
  }
  TargetError? best;
  for (final e in recent.reversed) {
    if ((counts[e] ?? 0) >= 2) {
      best = e;
      break;
    }
  }
  return best;
}

/// Copy for the recurring-error row. Calm framing — the engine reports
/// the pattern; it does not scold the learner.
String recurringCopyFor(TargetError error) => switch (error) {
      TargetError.contrast =>
        'Recurring contrast slip — keep watching for the rule that fits the meaning.',
      TargetError.form =>
        'Recurring form slip — the verb shape is the thing to lock in.',
      TargetError.conceptual =>
        'Recurring concept slip — the underlying rule needs a re-read.',
      TargetError.careless =>
        'Recurring careless slip — slow down for one beat before submitting.',
    };
