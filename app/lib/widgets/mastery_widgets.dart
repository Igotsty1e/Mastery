// Reusable widgets that compose the Quiet Premium Coach surfaces from
// DESIGN.md. See docs/design-mockups/ for visual reference.

import 'package:flutter/material.dart';

import '../models/evaluation.dart';
import '../theme/mastery_theme.dart';
import 'rule_card.dart';

/// Soft-bordered card with paper-like shadow. Used everywhere a primary
/// content surface is needed.
class MasteryCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double radius;
  final List<BoxShadow>? shadow;

  const MasteryCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MasterySpacing.lg),
    this.color,
    this.borderColor,
    this.radius = MasteryRadii.lg,
    this.shadow,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? MasteryColors.bgRaised,
        border: Border.all(color: borderColor ?? tokens.borderSoft),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow ?? tokens.shadowCard,
      ),
      child: child,
    );
  }
}

/// Tinted soft card (no shadow) for secondary surfaces — examples, hints.
class MasterySoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double radius;

  const MasterySoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MasterySpacing.lg),
    this.color,
    this.borderColor,
    this.radius = MasteryRadii.lg,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? tokens.bgPrimarySoft,
        border: Border.all(
          color: borderColor ?? MasteryColors.actionPrimary.withAlpha(56),
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

/// Pill chip with active / locked states. Used on the dashboard level row
/// and as small inline status badges.
class LevelChip extends StatelessWidget {
  final String label;
  final bool active;
  final bool locked;
  final VoidCallback? onTap;
  final double height;

  const LevelChip({
    super.key,
    required this.label,
    this.active = false,
    this.locked = false,
    this.onTap,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final bg = active
        ? MasteryColors.actionPrimary
        : MasteryColors.bgSurface;
    final fg = active ? MasteryColors.bgSurface : MasteryColors.textSecondary;
    final border = active ? MasteryColors.actionPrimary : tokens.borderStrong;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MasteryRadii.pill),
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(MasteryRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (locked && !active) ...[
                Icon(Icons.lock_outline,
                    size: 14, color: tokens.textTertiary),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: MasteryTextStyles.labelMd.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lesson-row state badge (Done / Current / Locked) for the dashboard
/// "Current unit" block per `docs/plans/dashboard-study-desk.md` §8.
enum StatusBadgeVariant { done, current, locked }

class StatusBadge extends StatelessWidget {
  final String label;
  final StatusBadgeVariant variant;

  const StatusBadge({
    super.key,
    required this.label,
    required this.variant,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final (bg, fg, border) = switch (variant) {
      StatusBadgeVariant.done => (
          tokens.success.withAlpha(28),
          tokens.success,
          tokens.success.withAlpha(40),
        ),
      StatusBadgeVariant.current => (
          MasteryColors.actionPrimary.withAlpha(30),
          MasteryColors.actionPrimaryPressed,
          MasteryColors.actionPrimary.withAlpha(46),
        ),
      StatusBadgeVariant.locked => (
          tokens.bgSurfaceAlt,
          MasteryColors.textSecondary,
          tokens.borderStrong,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(MasteryRadii.pill),
      ),
      child: Text(
        label,
        style: MasteryTextStyles.labelSm.copyWith(
          color: fg,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Compact tag pill (e.g. B2 in lesson intro header).
class TagPill extends StatelessWidget {
  final String label;
  final Color? background;
  final Color? foreground;

  const TagPill({
    super.key,
    required this.label,
    this.background,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? tokens.bgPrimarySoft,
        borderRadius: BorderRadius.circular(MasteryRadii.pill),
      ),
      child: Text(
        label,
        style: MasteryTextStyles.labelMd.copyWith(
          color: foreground ?? MasteryColors.actionPrimaryPressed,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Eyebrow label with a leading colored dot. Used to label a section
/// without competing with the title that follows.
enum SectionEyebrowVariant { primary, gold, secondary }

class SectionEyebrow extends StatelessWidget {
  final String label;
  final SectionEyebrowVariant variant;

  const SectionEyebrow({
    super.key,
    required this.label,
    this.variant = SectionEyebrowVariant.primary,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final color = switch (variant) {
      SectionEyebrowVariant.primary => MasteryColors.actionPrimary,
      SectionEyebrowVariant.gold => tokens.accentGoldDeep,
      SectionEyebrowVariant.secondary => MasteryColors.textSecondary,
    };
    final dotColor = switch (variant) {
      SectionEyebrowVariant.primary => MasteryColors.actionPrimary,
      SectionEyebrowVariant.gold => tokens.accentGold,
      SectionEyebrowVariant.secondary => MasteryColors.textSecondary,
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        // Flexible so a long eyebrow inside an Expanded parent ellipsises
        // instead of triggering a RenderFlex overflow.
        Flexible(
          child: Text(
            label.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: MasteryTextStyles.eyebrow(color: color),
          ),
        ),
      ],
    );
  }
}

/// Slim progress track with rounded ends. Optional fraction label after.
class MasteryProgressTrack extends StatelessWidget {
  final double value; // 0.0..1.0
  final double height;

  const MasteryProgressTrack({
    super.key,
    required this.value,
    this.height = 10,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return ClipRRect(
      borderRadius: BorderRadius.circular(MasteryRadii.pill),
      child: SizedBox(
        height: height,
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: height,
          backgroundColor: tokens.bgSurfaceAlt,
          valueColor:
              const AlwaysStoppedAnimation<Color>(MasteryColors.actionPrimary),
        ),
      ),
    );
  }
}

/// Result reveal panel for exercise screens. Sage on correct, wine on
/// incorrect. Replaces the inline _ResultPanel that was hard-coded in
/// exercise_screen.dart.
class ResultPanel extends StatelessWidget {
  final bool correct;
  final String? canonicalAnswer;
  final String? explanation;
  /// Wave 12.6 — when non-null, renders a quiet "See full rule →"
  /// link below the curated explanation. Tapping opens a modal
  /// bottom sheet with the source lesson's `intro_rule` and
  /// `intro_examples`. Drives the rule-access trust signal for
  /// adult B2 learners. Per `docs/plans/wave12.6-rule-access.md`
  /// the link appears on **any** result (correct or wrong) — adults
  /// re-read the rule after a correct answer to consolidate.
  final SkillRuleSnapshot? skillRuleSnapshot;

  const ResultPanel({
    super.key,
    required this.correct,
    this.canonicalAnswer,
    this.explanation,
    this.skillRuleSnapshot,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final bg = correct ? tokens.successSoft : MasteryColors.errorSoft;
    final accent = correct ? tokens.success : MasteryColors.error;
    final iconBg = correct ? tokens.success : MasteryColors.error;
    final icon = correct ? Icons.check_rounded : Icons.close_rounded;
    final label = correct ? 'Correct' : 'Incorrect';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: accent.withAlpha(70)),
        borderRadius: BorderRadius.circular(MasteryRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: bg),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: MasteryTextStyles.titleSm.copyWith(color: accent),
              ),
            ],
          ),
          if (!correct && canonicalAnswer != null) ...[
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                style: MasteryTextStyles.bodyMd,
                children: [
                  TextSpan(
                    text: 'Answer: ',
                    style: MasteryTextStyles.labelMd.copyWith(
                      color: MasteryColors.textSecondary,
                    ),
                  ),
                  TextSpan(
                    text: canonicalAnswer!,
                    style: MasteryTextStyles.bodyMd.copyWith(
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (explanation != null) ...[
            const SizedBox(height: 12),
            Text(
              explanation!,
              style: MasteryTextStyles.bodyMd.copyWith(
                color: MasteryColors.textPrimary,
                height: 1.55,
              ),
            ),
          ],
          if (skillRuleSnapshot != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => _showRuleSheet(context, skillRuleSnapshot!),
                child: Text(
                  'See full rule \u2192',
                  style: MasteryTextStyles.labelMd.copyWith(
                    color: MasteryColors.actionPrimaryPressed,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static void _showRuleSheet(
    BuildContext context,
    SkillRuleSnapshot snapshot,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MasteryColors.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MasteryRadii.lg),
        ),
      ),
      builder: (sheetCtx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              MasterySpacing.lg,
              MasterySpacing.lg,
              MasterySpacing.lg,
              MasterySpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle.
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: MasterySpacing.lg),
                    decoration: BoxDecoration(
                      color: MasteryColors.borderSoft,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Rule',
                  style: MasteryTextStyles.eyebrow(
                    color: MasteryColors.textTertiary,
                  ),
                ),
                const SizedBox(height: MasterySpacing.xs),
                if (snapshot.ruleCard != null) ...[
                  RuleCardView(data: snapshot.ruleCard!),
                ] else ...[
                  Text(
                    snapshot.introRule,
                    style: MasteryTextStyles.bodyLg.copyWith(
                      color: MasteryColors.textPrimary,
                      height: 1.6,
                    ),
                  ),
                ],
                if (snapshot.ruleCard == null &&
                    snapshot.introExamples.isNotEmpty) ...[
                  const SizedBox(height: MasterySpacing.xl),
                  Text(
                    'Examples',
                    style: MasteryTextStyles.eyebrow(
                      color: MasteryColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: MasterySpacing.sm),
                  for (final ex in snapshot.introExamples) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 8, right: 10),
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(
                                color: MasteryColors.actionPrimary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              ex,
                              style: MasteryTextStyles.bodyMd.copyWith(
                                color: MasteryColors.textPrimary,
                                height: 1.55,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: MasterySpacing.lg),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(sheetCtx).maybePop(),
                    child: Text(
                      'Close',
                      style: MasteryTextStyles.labelMd.copyWith(
                        color: MasteryColors.textSecondary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Instruction band shown above the exercise card. Pale rose surface,
/// task-alt icon, primary-pressed text.
class InstructionBand extends StatelessWidget {
  final String text;
  final IconData icon;
  /// Wave H3 — question-driven framing for `short_free_sentence`.
  /// In this mode the band drops its card chrome and renders the
  /// instruction as a prominent headline ("What do you really enjoy
  /// doing when you travel?") so the exercise header reads like a
  /// real question, not a meta-label. Methodology: TTT
  /// (Test-Teach-Test, Penny Ur §3.4 / Thornbury *Uncovering
  /// Grammar*) — production-first, rule revealed only after error.
  final bool prominent;

  const InstructionBand({
    super.key,
    required this.text,
    this.icon = Icons.task_alt_rounded,
    this.prominent = false,
  });

  @override
  Widget build(BuildContext context) {
    if (prominent) {
      // Wave H3 fix (2026-05-01): the user reported a serif fallback
      // here on Flutter web. Cause: titleMd is built via the
      // `_manrope` helper which stamps a `wght` FontVariation; on
      // Brave/Chromium the variable axis intermittently mis-renders
      // at w700 and the renderer falls back to a generic serif.
      // Build the style explicitly with `fontFamily: 'Manrope'`,
      // a named (non-variable) weight, and a small positive
      // letter-spacing so the headline matches the rest of the body
      // typography on the page.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Manrope',
            fontSize: 20,
            height: 28 / 20,
            fontWeight: FontWeight.w600,
            color: MasteryColors.textPrimary,
            letterSpacing: 0.1,
          ),
        ),
      );
    }
    final tokens = context.masteryTokens;
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.bgPrimarySoft,
        border: Border.all(
          color: MasteryColors.actionPrimary.withAlpha(56),
        ),
        borderRadius: BorderRadius.circular(MasteryRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: MasteryColors.actionPrimaryPressed),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: MasteryTextStyles.bodyMd.copyWith(
                color: MasteryColors.actionPrimaryPressed,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
