import 'package:flutter/material.dart';

import '../theme/mastery_theme.dart';

class FillBlankWidget extends StatefulWidget {
  final String prompt;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitField;

  const FillBlankWidget({
    super.key,
    required this.prompt,
    required this.onChanged,
    this.enabled = true,
    this.onSubmitField,
  });

  @override
  State<FillBlankWidget> createState() => _FillBlankWidgetState();
}

class _FillBlankWidgetState extends State<FillBlankWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(() => widget.onChanged(_controller.text.trim()));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PromptWithBlank(prompt: widget.prompt),
        const SizedBox(height: 18),
        TextField(
          controller: _controller,
          enabled: widget.enabled,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => widget.onSubmitField?.call(),
          style: MasteryTextStyles.titleSm.copyWith(
            color: MasteryColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: 'Type your answer',
            hintStyle: MasteryTextStyles.bodyMd.copyWith(
              color: MasteryColors.textTertiary,
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 18, vertical: 16),
          ),
        ),
      ],
    );
  }
}

/// Renders the prompt with the literal "___" sequence replaced by a styled
/// inline blank, so it reads naturally with the surrounding sentence.
class _PromptWithBlank extends StatelessWidget {
  final String prompt;
  const _PromptWithBlank({required this.prompt});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final base = MasteryTextStyles.bodyLg.copyWith(
      height: 1.55,
      color: MasteryColors.textPrimary,
    );

    // Render the prompt as a single Text.rich. The literal `___` stays in the
    // plain-text layer so widget-test finders that match prompt strings still
    // succeed; visually the blank gets a muted color and tighter spacing.
    final pattern = RegExp(r'_{2,}');
    final matches = pattern.allMatches(prompt).toList();
    if (matches.isEmpty) {
      return Text(prompt, style: base);
    }
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in matches) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: prompt.substring(cursor, m.start)));
      }
      spans.add(TextSpan(
        text: prompt.substring(m.start, m.end),
        style: TextStyle(
          color: tokens.textTertiary,
          letterSpacing: 2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ));
      cursor = m.end;
    }
    if (cursor < prompt.length) {
      spans.add(TextSpan(text: prompt.substring(cursor)));
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }
}
