import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config.dart';
import '../models/lesson.dart';
import '../theme/mastery_theme.dart';
import 'mastery_audio_player.dart';

/// Renders a `listening_discrimination` exercise: an audio player on top
/// (with hidden transcript reveal) and a multiple-choice option list below.
///
/// Mirrors the `MultipleChoiceWidget` contract — emits the selected option
/// id via `onChanged` so the screen-level Submit flow remains unified.
class ListeningDiscriminationWidget extends StatefulWidget {
  final ExerciseAudio audio;
  final List<McOption> options;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const ListeningDiscriminationWidget({
    super.key,
    required this.audio,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<ListeningDiscriminationWidget> createState() =>
      _ListeningDiscriminationWidgetState();
}

class _ListeningDiscriminationWidgetState
    extends State<ListeningDiscriminationWidget> {
  String? _selected;

  String _resolveAudioUrl() {
    final url = widget.audio.url;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    if (kIsWeb) {
      // Same-origin path; the web build copies backend/public/audio/ into
      // the frontend bundle so the browser fetches the clip from the same
      // origin as the SPA.
      return url.startsWith('/') ? url : '/$url';
    }
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final tail = url.startsWith('/') ? url : '/$url';
    return '$base$tail';
  }

  void _select(String id) {
    setState(() => _selected = id);
    widget.onChanged(id);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MasteryAudioPlayer(
          url: _resolveAudioUrl(),
          transcript: widget.audio.transcript,
          enabled: widget.enabled,
        ),
        const SizedBox(height: MasterySpacing.lg),
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

// Visual parity with MultipleChoiceWidget._OptionRow — kept private here so
// listening items render identically without a coupling between widgets.
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
            border: Border.all(color: border, width: 1.5),
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
