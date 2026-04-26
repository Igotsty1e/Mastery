import 'package:flutter/material.dart';

import '../models/lesson.dart';
import '../theme/mastery_theme.dart';

class MultipleChoiceWidget extends StatefulWidget {
  final String prompt;
  final List<McOption> options;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const MultipleChoiceWidget({
    super.key,
    required this.prompt,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<MultipleChoiceWidget> createState() => _MultipleChoiceWidgetState();
}

class _MultipleChoiceWidgetState extends State<MultipleChoiceWidget> {
  String? _selected;

  void _select(String id) {
    setState(() => _selected = id);
    widget.onChanged(id);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Direction A · Brief B: serif Fraunces hero so the prompt
        // dominates the screen instead of competing with chrome.
        Text(
          widget.prompt,
          style: TextStyle(
            fontFamily: 'Fraunces',
            fontSize: 26,
            height: 34 / 26,
            fontWeight: FontWeight.w600,
            color: MasteryColors.textPrimary,
            letterSpacing: -0.4,
            fontVariations: const [
              FontVariation('opsz', 144),
              FontVariation('wght', 600),
            ],
          ),
        ),
        const SizedBox(height: 22),
        ...List.generate(widget.options.length, (i) {
          final opt = widget.options[i];
          final letter = String.fromCharCode('A'.codeUnitAt(0) + i);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _OptionRow(
              letter: letter,
              text: opt.text,
              selected: _selected == opt.id,
              enabled: widget.enabled,
              onTap: () => _select(opt.id),
            ),
          );
        }),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String letter;
  final String text;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _OptionRow({
    required this.letter,
    required this.text,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final bg = selected ? tokens.bgPrimarySoft : MasteryColors.bgSurface;
    final border = selected
        ? MasteryColors.actionPrimary
        : tokens.borderSoft;
    final radioBg = selected ? MasteryColors.actionPrimary : tokens.bgApp;
    final letterColor = selected
        ? MasteryColors.bgSurface
        : MasteryColors.textSecondary;
    final textColor = selected
        ? MasteryColors.actionPrimaryPressed
        : MasteryColors.textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(MasteryRadii.md),
        child: AnimatedContainer(
          duration: MasteryDurations.short,
          curve: MasteryEasing.move,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(
                color: border, width: selected ? 1.5 : 1.5),
            borderRadius: BorderRadius.circular(MasteryRadii.md),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: radioBg,
                  border: Border.all(color: border, width: 1.5),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  letter,
                  style: MasteryTextStyles.mono(
                    size: 12,
                    lineHeight: 14,
                    weight: FontWeight.w600,
                    color: letterColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: MasteryTextStyles.bodyMd.copyWith(
                    color: textColor,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
