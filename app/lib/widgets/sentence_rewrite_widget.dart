import 'package:flutter/material.dart';

import '../theme/mastery_theme.dart';

/// Wave 14.2 phase 3 — V1.5 open-answer family widget for the
/// `sentence_rewrite` exercise type.
///
/// Visual contract mirrors `SentenceCorrectionWidget` (same ORIGINAL
/// reference card + free-text input below). Two intentional differences:
///   - The text field starts EMPTY. `sentence_rewrite` asks the learner
///     to produce a transformed sentence from scratch, not edit the
///     prompt in place. Pre-filling would muddle the framing — the
///     learner could submit the prompt unchanged and pass the
///     deterministic check by accident.
///   - Label reads "Your rewrite" instead of "Your correction" so the
///     framing matches the instruction directive ("Rewrite using…").
///
/// All other behaviour (autofocus, 3-line max, post-frame initial emit
/// so Submit can light up if the learner types nothing yet) is the
/// same as `SentenceCorrectionWidget`.
class SentenceRewriteWidget extends StatefulWidget {
  final String prompt;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const SentenceRewriteWidget({
    super.key,
    required this.prompt,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<SentenceRewriteWidget> createState() => _SentenceRewriteWidgetState();
}

class _SentenceRewriteWidgetState extends State<SentenceRewriteWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(() => widget.onChanged(_controller.text.trim()));
    // Emit initial empty value so the parent's Submit-button gate sees
    // a fresh state immediately. The button stays disabled until the
    // learner types anything (parent enforces the empty-string guard).
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
    final tokens = context.masteryTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: tokens.bgSurfaceAlt,
            borderRadius: BorderRadius.circular(MasteryRadii.sm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  'ORIGINAL',
                  style: MasteryTextStyles.labelSm.copyWith(
                    color: tokens.textTertiary,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.prompt,
                  style: MasteryTextStyles.bodySm.copyWith(
                    color: MasteryColors.textSecondary,
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _controller,
          enabled: widget.enabled,
          autofocus: true,
          maxLines: 3,
          style: MasteryTextStyles.bodyMd.copyWith(
            color: MasteryColors.textPrimary,
            height: 1.55,
          ),
          decoration: InputDecoration(
            labelText: 'Your rewrite',
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
        ),
      ],
    );
  }
}
