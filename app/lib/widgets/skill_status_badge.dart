import 'package:flutter/material.dart';

import '../learner/learner_skill_store.dart';
import '../theme/mastery_theme.dart';
import 'skill_state_card.dart' show statusCopyFor;

/// Wave 14 (V1.5 Skill-progress UI) — compact mastery state pill that
/// sits before the CEFR chip on the dashboard's Rules card.
///
/// Reuses `statusCopyFor` from `skill_state_card.dart` so the dashboard
/// and the post-lesson summary read the same status copy. Color
/// treatment mirrors `_SkillRow._statusColor` in that file.
class SkillStatusBadge extends StatelessWidget {
  final LearnerSkillRecord record;
  final DateTime now;

  const SkillStatusBadge({
    super.key,
    required this.record,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final status = record.statusAt(now);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: _background(status, tokens),
        borderRadius: BorderRadius.circular(MasteryRadii.pill),
      ),
      child: Text(
        statusCopyFor(status).toUpperCase(),
        style: MasteryTextStyles.labelSm.copyWith(
          color: _foreground(status, tokens),
          letterSpacing: 0.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _foreground(SkillStatus s, MasteryTokens tokens) => switch (s) {
        SkillStatus.mastered => tokens.success,
        SkillStatus.almostMastered => MasteryColors.actionPrimaryPressed,
        SkillStatus.gettingThere => MasteryColors.actionPrimaryPressed,
        SkillStatus.practicing => MasteryColors.textSecondary,
        SkillStatus.started => tokens.textTertiary,
        SkillStatus.reviewDue => MasteryColors.error,
      };

  Color _background(SkillStatus s, MasteryTokens tokens) => switch (s) {
        SkillStatus.mastered => tokens.successSoft,
        SkillStatus.almostMastered => tokens.bgPrimarySoft,
        SkillStatus.gettingThere => tokens.bgPrimarySoft,
        SkillStatus.practicing => tokens.bgSurfaceAlt,
        SkillStatus.started => tokens.bgSurfaceAlt,
        SkillStatus.reviewDue => MasteryColors.errorSoft,
      };
}
