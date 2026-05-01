// Wave H1 — textbook-format rule card.
//
// Renders a structured pedagogical rule (header plate, one-line
// statement, ✓ examples, multi-column pattern lists, "Watch out!"
// callouts). The data model is `RuleCardData`, parsed from the
// `rule_card` field on a Lesson / SkillCatalogEntry /
// SkillRuleSnapshot. When `rule_card` is null on those carriers,
// callers fall back to the legacy `intro_rule` flat-string parser
// in `lesson_intro_screen.dart`.
//
// Schema: `docs/content-contract.md §1.2`.

import 'package:flutter/material.dart';

import '../models/rule_card.dart';
import '../theme/mastery_theme.dart';

export '../models/rule_card.dart';

/// Textbook-format rule card view. Used by `LessonIntroScreen`,
/// the dashboard `_RuleSheetBody`, and the result-panel
/// `See full rule →` sheet.
class RuleCardView extends StatelessWidget {
  final RuleCardData data;

  const RuleCardView({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitlePlate(text: data.title),
        const SizedBox(height: MasterySpacing.md),
        Text(
          data.rule,
          style: MasteryTextStyles.bodyLg.copyWith(
            color: MasteryColors.textPrimary,
            height: 1.55,
          ),
        ),
        if (data.examples.isNotEmpty) ...[
          const SizedBox(height: MasterySpacing.md),
          for (final ex in data.examples) ...[
            _ExampleLine(example: ex),
            const SizedBox(height: 6),
          ],
        ],
        for (final list in data.patternLists) ...[
          const SizedBox(height: MasterySpacing.lg),
          _PatternListBlock(list: list),
        ],
        for (final watchOut in data.watchOuts) ...[
          const SizedBox(height: MasterySpacing.md),
          _WatchOutCallout(watchOut: watchOut, accent: tokens.warning),
        ],
      ],
    );
  }
}

class _TitlePlate extends StatelessWidget {
  final String text;

  const _TitlePlate({required this.text});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.bgPrimarySoft,
        borderRadius: BorderRadius.circular(MasteryRadii.pill),
        border: Border.all(
          color: MasteryColors.actionPrimary.withAlpha(60),
        ),
      ),
      child: Text(
        text,
        style: MasteryTextStyles.labelMd.copyWith(
          color: MasteryColors.actionPrimaryPressed,
          letterSpacing: 0.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ExampleLine extends StatelessWidget {
  final RuleCardExample example;

  const _ExampleLine({required this.example});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final base = MasteryTextStyles.bodyMd.copyWith(
      color: MasteryColors.textPrimary,
      height: 1.55,
    );
    final spans = _highlightSpans(
      text: example.text,
      highlight: example.highlight,
      baseStyle: base,
      highlightColor: MasteryColors.actionPrimaryPressed,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3, right: 8),
          child: Icon(
            Icons.check_rounded,
            size: 18,
            color: tokens.success,
          ),
        ),
        Expanded(
          child: Text.rich(TextSpan(children: spans)),
        ),
      ],
    );
  }
}

class _PatternListBlock extends StatelessWidget {
  final RuleCardPatternList list;

  const _PatternListBlock({required this.list});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final crossAxisCount = list.items.length <= 6
        ? 2
        : list.items.length <= 18
            ? 3
            : 4;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MasterySpacing.md),
      decoration: BoxDecoration(
        color: tokens.bgSurfaceAlt,
        border: Border.all(color: tokens.borderSoft),
        borderRadius: BorderRadius.circular(MasteryRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            list.label,
            style: MasteryTextStyles.eyebrow(
              color: MasteryColors.textTertiary,
            ),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: crossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 12,
            childAspectRatio: 4.2,
            children: list.items
                .map((it) => _PatternItem(text: it))
                .toList(growable: false),
          ),
        ],
      ),
    );
  }
}

class _PatternItem extends StatelessWidget {
  final String text;

  const _PatternItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 4,
          decoration: const BoxDecoration(
            color: MasteryColors.actionPrimary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: MasteryTextStyles.bodyMd.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.05,
              color: MasteryColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

class _WatchOutCallout extends StatelessWidget {
  final RuleCardWatchOut watchOut;
  final Color accent;

  const _WatchOutCallout({required this.watchOut, required this.accent});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final base = MasteryTextStyles.bodyMd.copyWith(
      color: MasteryColors.textPrimary,
      height: 1.55,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MasterySpacing.md),
      decoration: BoxDecoration(
        color: tokens.warningSoft,
        border: Border.all(color: accent.withAlpha(70)),
        borderRadius: BorderRadius.circular(MasteryRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.priority_high_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                'WATCH OUT',
                style: MasteryTextStyles.eyebrow(color: accent),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(watchOut.text, style: base),
          if (watchOut.example != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3, right: 8),
                  child: Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: tokens.success,
                  ),
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: _highlightSpans(
                        text: watchOut.example!,
                        highlight: watchOut.highlight,
                        baseStyle: base,
                        highlightColor: accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Splits `text` so the first occurrence of `highlight` (if any and
/// if literally present) is rendered with a bold, accent-coloured
/// span. When `highlight` is null or not present, the whole text
/// becomes a single neutral span.
List<InlineSpan> _highlightSpans({
  required String text,
  required String? highlight,
  required TextStyle baseStyle,
  required Color highlightColor,
}) {
  if (highlight == null || highlight.isEmpty) {
    return [TextSpan(text: text, style: baseStyle)];
  }
  final idx = text.indexOf(highlight);
  if (idx < 0) {
    return [TextSpan(text: text, style: baseStyle)];
  }
  final highlightStyle = baseStyle.copyWith(
    color: highlightColor,
    fontWeight: FontWeight.w700,
  );
  return [
    if (idx > 0) TextSpan(text: text.substring(0, idx), style: baseStyle),
    TextSpan(text: highlight, style: highlightStyle),
    if (idx + highlight.length < text.length)
      TextSpan(
        text: text.substring(idx + highlight.length),
        style: baseStyle,
      ),
  ];
}
