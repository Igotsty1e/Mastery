import 'package:flutter/material.dart';

import '../learner/learner_skill_store.dart';
import '../theme/mastery_theme.dart';
import 'skill_state_card.dart' show statusCopyFor;

/// Wave 14 (V1.5 Skill-progress UI) — mastery state indicator that
/// sits before the CEFR chip on the dashboard's Rules card.
///
/// 2026-05-01 redesign: was a soft-tinted pill that visually merged
/// with the calm beige/sage palette of the surrounding chrome. Now a
/// 5-dot progress strip ─── the filled-dot count maps 1:1 to the
/// mastery progression (started=1/5 → mastered=5/5). Review-due gets
/// a distinct circled-bang indicator instead of dots so it never
/// looks like "regressed to 0/5". The status text label still appears
/// on the right for accessibility and so the dashboard reads the same
/// copy as the post-lesson Skill panel (`statusCopyFor`).
class SkillStatusBadge extends StatelessWidget {
  final LearnerSkillRecord record;
  final DateTime now;

  /// When `false`, only the dots are rendered. Used in dense rows
  /// where the status copy would crowd the layout. Defaults to
  /// `true` (dots + label) — current callers all show both.
  final bool showLabel;

  const SkillStatusBadge({
    super.key,
    required this.record,
    required this.now,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final status = record.statusAt(now);
    final tokens = context.masteryTokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _StatusGlyph(status: status, tokens: tokens),
        if (showLabel) ...[
          const SizedBox(width: 8),
          Text(
            statusCopyFor(status),
            style: MasteryTextStyles.labelSm.copyWith(
              color: _labelColor(status, tokens),
              letterSpacing: 0.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Color _labelColor(SkillStatus s, MasteryTokens tokens) => switch (s) {
        SkillStatus.mastered => tokens.success,
        SkillStatus.reviewDue => MasteryColors.error,
        _ => MasteryColors.textSecondary,
      };
}

/// 5-dot progression strip — filled dots count up from the left.
/// `mastered` paints all 5 in success/sage so the "done" state has a
/// visual category of its own. `reviewDue` swaps the dots for a
/// circled bang indicator (warning glyph) so the regressed state is
/// not confused with "back to zero".
class _StatusGlyph extends StatelessWidget {
  final SkillStatus status;
  final MasteryTokens tokens;

  const _StatusGlyph({required this.status, required this.tokens});

  @override
  Widget build(BuildContext context) {
    if (status == SkillStatus.reviewDue) {
      return Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MasteryColors.errorSoft,
          shape: BoxShape.circle,
          border: Border.all(color: MasteryColors.error.withAlpha(120)),
        ),
        child: Icon(
          Icons.priority_high_rounded,
          size: 12,
          color: MasteryColors.error,
        ),
      );
    }
    final filled = _filledCount(status);
    final filledColor = status == SkillStatus.mastered
        ? tokens.success
        : MasteryColors.actionPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          _Dot(filled: i < filled, filledColor: filledColor, tokens: tokens),
        ],
      ],
    );
  }

  int _filledCount(SkillStatus s) => switch (s) {
        SkillStatus.started => 1,
        SkillStatus.practicing => 2,
        SkillStatus.gettingThere => 3,
        SkillStatus.almostMastered => 4,
        SkillStatus.mastered => 5,
        SkillStatus.reviewDue => 0, // unreachable — handled above
      };
}

class _Dot extends StatelessWidget {
  final bool filled;
  final Color filledColor;
  final MasteryTokens tokens;

  const _Dot({
    required this.filled,
    required this.filledColor,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? filledColor : Colors.transparent,
        border: filled
            ? null
            : Border.all(
                color: tokens.borderStrong.withAlpha(140),
                width: 1.2,
              ),
      ),
    );
  }
}
