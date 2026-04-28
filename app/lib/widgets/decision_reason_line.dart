import 'package:flutter/material.dart';

import '../theme/mastery_theme.dart';

/// Wave 4 transparency-layer per-routing surface per
/// `LEARNING_ENGINE.md §11.3`. Renders the one-line "why this next"
/// string the `DecisionEngine` set on `SessionState.lastDecisionReason`
/// after the previous attempt.
///
/// The widget receives an internal reason CODE from the engine
/// (e.g. `same_rule_different_angle`, `linear_default`,
/// `cap_relaxed_fallback`) and maps it through `decisionReasonCopy`
/// to user-facing copy. Codes without a curated mapping resolve to
/// `null` and the widget collapses to zero height — the calm
/// silence of §11.4. We never show raw enum strings to learners.
class DecisionReasonLine extends StatelessWidget {
  /// The raw reason code emitted by the server-side decision engine
  /// (or null when no decision was just made). The widget runs the
  /// code through `decisionReasonCopy` and renders only when the
  /// result is non-null.
  final String? text;

  const DecisionReasonLine({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final copy = decisionReasonCopy(text);
    if (copy == null) return const SizedBox.shrink();
    final tokens = context.masteryTokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        copy,
        style: MasteryTextStyles.bodySm.copyWith(
          color: tokens.textTertiary,
          fontStyle: FontStyle.italic,
          height: 1.4,
        ),
      ),
    );
  }
}

/// Maps internal `DecisionEngine` reason codes to learner-facing
/// copy per `LEARNING_ENGINE.md §11.3` + Wave 4 plan §2.4.
///
/// Codes without curated copy resolve to `null` so the calling
/// widget collapses — the §11.4 calm-silence default for codes that
/// describe operational engine state (`linear_default`,
/// `cap_relaxed_fallback`, `bank_empty`, `session_complete`,
/// `no_candidates`) the learner has no business reading.
///
/// Visible only:
///   - `same_rule_different_angle` → "Same rule, different angle."
///   - `same_rule_simpler_ask` → "Same rule, simpler ask."
String? decisionReasonCopy(String? code) {
  switch (code) {
    case 'same_rule_different_angle':
      return 'Same rule, different angle.';
    case 'same_rule_simpler_ask':
      return 'Same rule, simpler ask.';
    default:
      // Includes: null, '', linear_default, cap_relaxed_fallback,
      // no_candidates, bank_empty, session_complete, and any future
      // operational code we add server-side without a curated copy.
      return null;
  }
}
