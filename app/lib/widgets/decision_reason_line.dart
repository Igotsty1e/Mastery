import 'package:flutter/material.dart';

import '../theme/mastery_theme.dart';

/// Wave 4 transparency-layer per-routing surface per
/// `LEARNING_ENGINE.md §11.3`. Renders the one-line "why this next"
/// string the `DecisionEngine` set on `SessionState.lastDecisionReason`
/// after the previous attempt.
///
/// When `text` is null the widget collapses to zero height — the calm
/// silence of the linear default per §11.4. No icon, no chip, no
/// notification feel; subtle italic caption above the instruction.
class DecisionReasonLine extends StatelessWidget {
  final String? text;

  const DecisionReasonLine({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final t = text;
    if (t == null || t.isEmpty) return const SizedBox.shrink();
    final tokens = context.masteryTokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        t,
        style: MasteryTextStyles.bodySm.copyWith(
          color: tokens.textTertiary,
          fontStyle: FontStyle.italic,
          height: 1.4,
        ),
      ),
    );
  }
}
