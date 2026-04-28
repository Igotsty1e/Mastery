import 'package:flutter/material.dart';

import '../theme/mastery_theme.dart';

/// Wave 14.4 — V1.5 open-answer family, phase 4
/// (`short_free_sentence`).
///
/// Bare free-text input. Unlike `SentenceRewriteWidget` and
/// `SentenceCorrectionWidget`, there is NO ORIGINAL prompt card to
/// show — `short_free_sentence` is rule-conformance: the instruction
/// names the rule, the learner produces a fresh sentence. Showing
/// any anchor sentence would bias the learner toward mimicry.
///
/// Behaviour mirrors the rest of the open-answer family:
///   - input starts EMPTY,
///   - autofocus,
///   - 3-line max,
///   - emits trimmed text on every keystroke + an empty initial value
///     after first frame so Submit gates correctly.
class ShortFreeSentenceWidget extends StatefulWidget {
  final bool enabled;
  final ValueChanged<String> onChanged;

  const ShortFreeSentenceWidget({
    super.key,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<ShortFreeSentenceWidget> createState() =>
      _ShortFreeSentenceWidgetState();
}

class _ShortFreeSentenceWidgetState extends State<ShortFreeSentenceWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(() => widget.onChanged(_controller.text.trim()));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onChanged(_controller.text.trim()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      autofocus: true,
      maxLines: 3,
      style: MasteryTextStyles.bodyMd.copyWith(
        color: MasteryColors.textPrimary,
        height: 1.55,
      ),
      decoration: InputDecoration(
        labelText: 'Your sentence',
        labelStyle: MasteryTextStyles.labelSm.copyWith(
          color: MasteryColors.actionPrimary,
          letterSpacing: 0.6,
        ),
        floatingLabelStyle: MasteryTextStyles.labelSm.copyWith(
          color: MasteryColors.actionPrimary,
          letterSpacing: 0.6,
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
      ),
    );
  }
}
