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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Direction A · Brief B: the original (broken) sentence is the prompt
        // hero — Fraunces, large, slightly muted to read as "the thing to
        // change". The instruction band above already tells the learner to
        // rewrite, so we drop the ORIGINAL pill chrome.
        Text(
          widget.prompt,
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontSize: 26,
            height: 34 / 26,
            fontWeight: FontWeight.w600,
            color: MasteryColors.textPrimary,
            letterSpacing: -0.4,
            fontStyle: FontStyle.italic,
            fontVariations: const [
              FontVariation('opsz', 144),
              FontVariation('wght', 600),
            ],
          ),
        ),
        const SizedBox(height: 18),
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
