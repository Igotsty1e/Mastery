import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../session/session_controller.dart';
import '../session/session_state.dart';
import '../theme/mastery_theme.dart';
import '../widgets/mastery_route.dart';
import '../widgets/mastery_widgets.dart';
import 'exercise_screen.dart';

class LessonIntroScreen extends StatefulWidget {
  final String lessonId;

  const LessonIntroScreen({super.key, required this.lessonId});

  @override
  State<LessonIntroScreen> createState() => _LessonIntroScreenState();
}

class _LessonIntroScreenState extends State<LessonIntroScreen> {
  late final SessionController _controller;
  bool _controllerHandedOff = false;

  @override
  void initState() {
    super.initState();
    _controller = SessionController(context.read<ApiClient>());
    _controller.loadLesson(widget.lessonId);
  }

  @override
  void dispose() {
    if (!_controllerHandedOff) _controller.dispose();
    super.dispose();
  }

  void _start() {
    _controllerHandedOff = true;
    Navigator.of(context).pushReplacement(
      MasteryFadeRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: _controller,
          child: const ExerciseScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final state = _controller.state;
        final tokens = context.masteryTokens;

        if (state.phase == SessionPhase.loading) {
          return Scaffold(
            backgroundColor: tokens.bgApp,
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (state.phase == SessionPhase.error) {
          return Scaffold(
            backgroundColor: tokens.bgApp,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(MasterySpacing.lg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline,
                        size: 40, color: MasteryColors.error),
                    const SizedBox(height: 16),
                    Text(
                      "Couldn't load this lesson",
                      style: MasteryTextStyles.titleMd,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      state.errorMessage ?? 'Try again in a moment.',
                      style: MasteryTextStyles.bodyMd.copyWith(
                        color: MasteryColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _controller.retry,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final lesson = state.lesson!;
        final sections = _parseRuleSections(lesson.introRule);

        return Scaffold(
          backgroundColor: tokens.bgApp,
          appBar: AppBar(
            backgroundColor: tokens.bgApp,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 26),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            centerTitle: true,
            title: Text(
              'LESSON 1 OF 12',
              style: MasteryTextStyles.mono(
                size: 12,
                lineHeight: 16,
                weight: FontWeight.w500,
                color: tokens.textTertiary,
                letterSpacing: 1.4,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.more_horiz_rounded,
                    color: tokens.textTertiary),
                onPressed: null,
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  MasterySpacing.lg, 8, MasterySpacing.lg, MasterySpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TagPill(label: lesson.level),
                  const SizedBox(height: MasterySpacing.md),
                  Text(
                    lesson.title,
                    style: MasteryTextStyles.headlineLg.copyWith(
                      fontSize: 36,
                      height: 40 / 36,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _MetaRow(items: [
                    '${lesson.exercises.length} exercises',
                    '~5 minutes',
                    'Grammar',
                  ]),
                  const SizedBox(height: MasterySpacing.lg),
                  ...sections.map((s) => Padding(
                        padding:
                            const EdgeInsets.only(bottom: MasterySpacing.md),
                        child: _RuleCard(section: s),
                      )),
                  if (lesson.introExamples.isNotEmpty) ...[
                    MasterySoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionEyebrow(label: 'Examples'),
                          const SizedBox(height: 14),
                          ...lesson.introExamples.map(
                            (ex) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _ExampleLine(text: ex),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: MasterySpacing.xl),
                  FilledButton(
                    onPressed: _start,
                    child: const Text('Start Practice'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------- Rule parsing ----------

class _RuleSection {
  final String title;
  final List<String> body; // raw paragraphs preserving \n inside

  const _RuleSection({required this.title, required this.body});
}

const _knownHeaders = <String>{'use', 'form', 'important', 'watch for'};

List<_RuleSection> _parseRuleSections(String text) {
  final sections = <_RuleSection>[];
  _RuleSection? current;
  void start(String title) {
    current = _RuleSection(title: title, body: []);
    sections.add(current!);
  }

  final paragraphs = text.split(RegExp(r'\n\s*\n'));
  for (final raw in paragraphs) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;
    final firstLine = trimmed.split('\n').first.trim();
    final isHeader = trimmed.length == firstLine.length &&
        _knownHeaders.contains(firstLine.toLowerCase());
    if (isHeader) {
      start(firstLine);
    } else {
      current ??= _RuleSection(title: '', body: []);
      if (sections.isEmpty) sections.add(current!);
      current!.body.add(trimmed);
    }
  }
  return sections;
}

// ---------- Rule card ----------

class _RuleCard extends StatelessWidget {
  final _RuleSection section;

  const _RuleCard({required this.section});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final normalized = section.title.trim().toLowerCase();
    final isForm = normalized == 'form';
    final isImportant = normalized == 'important';

    final bg = isImportant
        ? tokens.warningSoft
        : isForm
            ? Color.lerp(tokens.accentGoldSoft, MasteryColors.bgRaised, 0.6)!
            : MasteryColors.bgRaised;
    final border = isImportant
        ? tokens.warning.withAlpha(70)
        : isForm
            ? tokens.accentGold.withAlpha(70)
            : tokens.borderSoft;
    final accent = isImportant
        ? tokens.warning
        : isForm
            ? tokens.accentGoldDeep
            : MasteryColors.actionPrimaryPressed;
    final iconBg = isImportant
        ? tokens.warning.withAlpha(45)
        : isForm
            ? tokens.accentGoldSoft
            : tokens.bgPrimarySoft;
    final icon = isImportant
        ? Icons.priority_high_rounded
        : isForm
            ? Icons.text_fields_rounded
            : Icons.menu_book_outlined;

    return MasteryCard(
      color: bg,
      borderColor: border,
      shadow: isImportant || isForm ? const [] : null,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.title.isNotEmpty) ...[
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(MasteryRadii.sm),
                  ),
                  child: Icon(icon, size: 16, color: accent),
                ),
                const SizedBox(width: 10),
                Text(
                  section.title.toUpperCase(),
                  style: MasteryTextStyles.eyebrow(color: accent),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          ..._buildBody(context, isForm, accent),
        ],
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context, bool isForm, Color accent) {
    final widgets = <Widget>[];
    for (final paragraph in section.body) {
      final lines = paragraph.split('\n').map((l) => l.trim()).toList();
      final hasHighlight = _hasHighlightMarkup(paragraph);

      if (isForm && lines.length == 1 && _looksLikeFormula(lines.first) &&
          !hasHighlight) {
        widgets.add(_FormulaBox(text: lines.first));
        widgets.add(const SizedBox(height: 14));
      } else if (isForm && lines.length > 1 && !hasHighlight) {
        // Legacy 2-col verb grid (U01 verb pairs without markup).
        widgets.add(_VerbGrid(items: lines));
      } else if (lines.length > 1 && hasHighlight) {
        // Paired vertical stack per `exercise_structure.md §2.8.1` —
        // common parts neutral, variable_part highlighted, lines stacked
        // vertically so the changing slot is visible at a glance.
        widgets.add(_PairedFormStack(lines: lines, accent: accent));
      } else {
        widgets.add(_RuleParagraph(text: paragraph, accent: accent));
        widgets.add(const SizedBox(height: 8));
      }
    }
    if (widgets.isNotEmpty &&
        widgets.last is SizedBox &&
        (widgets.last as SizedBox).height == 8) {
      widgets.removeLast();
    }
    return widgets;
  }
}

bool _looksLikeFormula(String s) {
  return s.contains('+') || s.contains('→') || s.length <= 24;
}

/// True when `**slot**` markers appear in the text (any pair of `**…**`).
bool _hasHighlightMarkup(String text) =>
    RegExp(r'\*\*[^\*]+\*\*').hasMatch(text);

/// Parses `text` into inline spans. `**slot**` segments become highlighted
/// spans (per `exercise_structure.md §2.8.1` — variable_part visualisation).
/// All other segments inherit the base style.
List<InlineSpan> _highlightSpans({
  required String text,
  required TextStyle baseStyle,
  required Color highlightColor,
}) {
  final pattern = RegExp(r'\*\*([^\*]+)\*\*');
  final highlightStyle = baseStyle.copyWith(
    color: highlightColor,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.01,
  );
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(
        text: text.substring(cursor, match.start),
        style: baseStyle,
      ));
    }
    spans.add(TextSpan(text: match.group(1) ?? '', style: highlightStyle));
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }
  return spans;
}

/// Vertical stack of paired highlighted lines for the FORM block when the
/// author writes more than one contrast line with `**variable_part**`
/// markers. Mirrors `GRAM_STRATEGY.md §5.3.1` — present paired forms
/// vertically and align the changing slot like a diff.
class _PairedFormStack extends StatelessWidget {
  final List<String> lines;
  final Color accent;

  const _PairedFormStack({required this.lines, required this.accent});

  @override
  Widget build(BuildContext context) {
    final base = MasteryTextStyles.bodyMd.copyWith(
      color: MasteryColors.textPrimary,
      height: 1.55,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: _highlightSpans(
                text: lines[i],
                baseStyle: base,
                highlightColor: accent,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _FormulaBox extends StatelessWidget {
  final String text;
  const _FormulaBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: tokens.bgApp,
          border: Border.all(
            color: tokens.borderStrong,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(MasteryRadii.sm),
        ),
        child: Text(
          text,
          style: MasteryTextStyles.mono(
            size: 18,
            lineHeight: 22,
            weight: FontWeight.w500,
            color: MasteryColors.textPrimary,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _VerbGrid extends StatelessWidget {
  final List<String> items;
  const _VerbGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 14,
      childAspectRatio: 5.5,
      children: items.map((it) => _VerbItem(text: it)).toList(),
    );
  }
}

class _VerbItem extends StatelessWidget {
  final String text;
  const _VerbItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 5,
          height: 5,
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
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

class _RuleParagraph extends StatelessWidget {
  final String text;
  final Color accent;

  const _RuleParagraph({required this.text, required this.accent});

  @override
  Widget build(BuildContext context) {
    final base = MasteryTextStyles.bodyMd.copyWith(
      color: MasteryColors.textPrimary,
      height: 1.65,
    );
    if (!_hasHighlightMarkup(text)) {
      return Text(text, style: base);
    }
    // Multi-line paragraph with highlight markers — render line by line so
    // the contrast diff stays vertical (per §2.8.1 / §5.3.1).
    final lines = text.split('\n');
    if (lines.length == 1) {
      return Text.rich(
        TextSpan(
          children: _highlightSpans(
            text: text,
            baseStyle: base,
            highlightColor: accent,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: _highlightSpans(
                text: lines[i],
                baseStyle: base,
                highlightColor: accent,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  final List<String> items;
  const _MetaRow({required this.items});

  @override
  Widget build(BuildContext context) {
    // Single Text run with bullet separators wraps naturally on narrow phones
    // and avoids horizontal RenderFlex overflow that a Row of fixed children
    // would produce.
    final joined = items.join('  ·  ');
    return Text(
      joined,
      style: MasteryTextStyles.bodySm.copyWith(
        color: MasteryColors.textSecondary,
      ),
    );
  }
}

class _ExampleLine extends StatelessWidget {
  final String text;
  const _ExampleLine({required this.text});

  @override
  Widget build(BuildContext context) {
    final base = MasteryTextStyles.bodyMd.copyWith(height: 1.55);
    final body = _hasHighlightMarkup(text)
        ? Text.rich(
            TextSpan(
              children: _highlightSpans(
                text: text,
                baseStyle: base,
                highlightColor: MasteryColors.actionPrimaryPressed,
              ),
            ),
          )
        : Text(text, style: base);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 10),
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: MasteryColors.actionPrimary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: body),
      ],
    );
  }
}
