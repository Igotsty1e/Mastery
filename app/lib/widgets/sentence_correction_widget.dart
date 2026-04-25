import 'package:flutter/material.dart';

import '../theme/mastery_theme.dart';

class SentenceCorrectionWidget extends StatefulWidget {
  final String prompt;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const SentenceCorrectionWidget({
    super.key,
    required this.prompt,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<SentenceCorrectionWidget> createState() =>
      _SentenceCorrectionWidgetState();
}

class _SentenceCorrectionWidgetState extends State<SentenceCorrectionWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.prompt);
    _controller.addListener(() => widget.onChanged(_controller.text.trim()));
    // Emit initial value so the screen can enable Submit immediately.
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
            labelText: 'Your correction',
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
