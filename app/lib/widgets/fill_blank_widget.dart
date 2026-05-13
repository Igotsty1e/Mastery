import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/mastery_theme.dart';

/// Wave F — controls the visibility of the `(verb)` hint that follows
/// the blank in fill_blank prompts. Decided by `_ExerciseBody` from
/// the per-skill lifetime attempt count in
/// `SessionController.skillAttemptsAtStart`.
///
/// - `always`: hint visible from t=0 (today's behaviour; first encounter).
/// - `after4s`: hint hidden initially; revealed after 4s of input inactivity.
///   Each keystroke resets the timer. Once revealed, stays revealed.
/// - `never`: hint stripped permanently.
enum HintRevealMode { always, after4s, never }

class FillBlankWidget extends StatefulWidget {
  final String prompt;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitField;

  /// Wave F — see `HintRevealMode`. Default `always` preserves the
  /// pre-Wave-F render behaviour and is the safe fallback when the
  /// session's skill-attempts snapshot is unavailable.
  final HintRevealMode hintMode;

  const FillBlankWidget({
    super.key,
    required this.prompt,
    required this.onChanged,
    this.enabled = true,
    this.onSubmitField,
    this.hintMode = HintRevealMode.always,
  });

  @override
  State<FillBlankWidget> createState() => _FillBlankWidgetState();
}

class _FillBlankWidgetState extends State<FillBlankWidget> {
  late final TextEditingController _controller;

  /// Wave F — true when the parenthetical hint should be hidden from
  /// the prompt render. Initial value derives from `widget.hintMode`.
  /// Flipped to false by the 4s timer in `after4s` mode; never flipped
  /// in `never` mode.
  bool _hintHidden = false;

  /// Wave F — timer that reveals the hint after 4s of no input in
  /// `after4s` mode. Cancelled in `dispose()` to prevent
  /// `setState() after dispose`.
  Timer? _hintRevealTimer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(_onControllerChange);
    _hintHidden = widget.hintMode != HintRevealMode.always;
    if (widget.hintMode == HintRevealMode.after4s) {
      _startHintRevealTimer();
    }
  }

  void _onControllerChange() {
    widget.onChanged(_controller.text.trim());
    // Wave F — typing resets the 4s reveal timer while the hint is
    // still hidden. Once revealed, no further reset.
    if (widget.hintMode == HintRevealMode.after4s && _hintHidden) {
      _startHintRevealTimer();
    }
  }

  void _startHintRevealTimer() {
    _hintRevealTimer?.cancel();
    _hintRevealTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _hintHidden = false);
    });
  }

  @override
  void dispose() {
    _hintRevealTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PromptWithBlank(prompt: widget.prompt, hideHint: _hintHidden),
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

/// Wave F — regex anchored to the blank token. Captures the blank,
/// optional whitespace, and a parenthetical group whose opening
/// letter is lowercase (matches the §4.1 authoring convention
/// `(<base-verb>)`). Anything else (capital-letter parentheticals,
/// parentheticals not adjacent to the blank) is left alone.
final RegExp _hintPattern = RegExp(r'(_{2,})\s*\(([a-z][^)]*)\)');

/// Wave F — strip the `(verb)` hint from a prompt while preserving
/// the `___` blank marker so `_PromptWithBlank`'s blank renderer
/// still finds it. Idempotent: applying twice equals applying once.
String stripFillBlankHint(String prompt) =>
    prompt.replaceAllMapped(_hintPattern, (m) => m.group(1) ?? '___');

/// Renders the prompt with the literal "___" sequence replaced by a styled
/// inline blank, so it reads naturally with the surrounding sentence.
class _PromptWithBlank extends StatelessWidget {
  final String prompt;

  /// Wave F — when true, the parenthetical hint after the blank
  /// is stripped before the blank-pattern matching runs. False
  /// preserves the pre-Wave-F render.
  final bool hideHint;

  const _PromptWithBlank({required this.prompt, this.hideHint = false});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final base = MasteryTextStyles.bodyLg.copyWith(
      height: 1.55,
      color: MasteryColors.textPrimary,
    );

    final rendered = hideHint ? stripFillBlankHint(prompt) : prompt;

    // Render the prompt as a single Text.rich. The literal `___` stays in the
    // plain-text layer so widget-test finders that match prompt strings still
    // succeed; visually the blank gets a muted color and tighter spacing.
    // `fillBlankPromptKey` lets widget tests target the prompt Text
    // unambiguously (the TextField below also renders its own RichText).
    final pattern = RegExp(r'_{2,}');
    final matches = pattern.allMatches(rendered).toList();
    if (matches.isEmpty) {
      return Text(rendered, key: fillBlankPromptKey, style: base);
    }
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in matches) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: rendered.substring(cursor, m.start)));
      }
      spans.add(TextSpan(
        text: rendered.substring(m.start, m.end),
        style: TextStyle(
          color: tokens.textTertiary,
          letterSpacing: 2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ));
      cursor = m.end;
    }
    if (cursor < rendered.length) {
      spans.add(TextSpan(text: rendered.substring(cursor)));
    }
    return Text.rich(TextSpan(style: base, children: spans),
        key: fillBlankPromptKey);
  }
}

/// Wave F — stable key for the prompt Text inside `FillBlankWidget`.
/// Exposed for widget tests that need to read the rendered prompt
/// string unambiguously.
@visibleForTesting
const Key fillBlankPromptKey = Key('fill-blank-prompt');
