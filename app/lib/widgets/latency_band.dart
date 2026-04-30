import 'package:flutter/material.dart';

import '../learner/latency_history_store.dart';
import '../theme/mastery_theme.dart';

/// Wave B — calm latency rail on the exercise screen.
///
/// Reads the median render→submit duration for the current skill from
/// `LatencyHistoryStore` and maps it to one of three calm zones. The
/// zones are advisory, never punitive — DESIGN.md §Brand Principles
/// ("confidence over excitement"): no streak, no countdown, no alarm.
///
/// Hides itself in three cases:
/// 1. `skillId` is `null` (un-tagged exercise) — pace is undefined.
/// 2. `LatencyHistoryStore.medianFor(skillId)` returns `null`
///    (the learner has not finished a single tagged attempt on this
///    skill yet) — calm silence per `LEARNING_ENGINE.md §11.4`.
/// 3. Resolution is in flight on the very first frame.
///
/// The rail does not refresh after an in-flight submit on the same
/// skill — the learner's pace within a single skill swing should not
/// flicker on every keypress. Wave B refresh-on-skill-change is enough
/// to stamp the band when the learner moves to a new rule.
enum LatencyPace { fast, steady, slow }

/// Boundary thresholds (ms) per the audit:
///   < 6000  → fast
///   < 12000 → steady
///   else    → slow
const int latencyFastThresholdMs = 6000;
const int latencyAlertThresholdMs = 12000;

LatencyPace paceForMedianMs(int medianMs) {
  if (medianMs < latencyFastThresholdMs) return LatencyPace.fast;
  if (medianMs < latencyAlertThresholdMs) return LatencyPace.steady;
  return LatencyPace.slow;
}

/// Test seam: a function that returns the median for a skill. Defaults
/// to `LatencyHistoryStore.medianFor`.
typedef LatencyMedianResolver = Future<int?> Function(String skillId);

class LatencyBand extends StatefulWidget {
  final String? skillId;

  /// Test-only override; production callers leave this null and the
  /// widget reads from `LatencyHistoryStore`.
  final LatencyMedianResolver? medianResolver;

  const LatencyBand({
    super.key,
    required this.skillId,
    this.medianResolver,
  });

  @override
  State<LatencyBand> createState() => _LatencyBandState();
}

class _LatencyBandState extends State<LatencyBand> {
  /// Result of the most recent resolution. `null` means either the
  /// skill has no history yet or resolution has not completed.
  int? _medianMs;

  /// `true` once a resolution has finished — used to keep the widget
  /// invisible during the very first frame instead of flashing in.
  bool _resolved = false;

  /// Bumped on every resolution so a stale future cannot overwrite a
  /// fresh one (e.g. when the skill changes mid-flight).
  int _resolutionId = 0;

  @override
  void initState() {
    super.initState();
    _resolveFor(widget.skillId);
  }

  @override
  void didUpdateWidget(covariant LatencyBand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.skillId != widget.skillId) {
      _resolveFor(widget.skillId);
    }
  }

  Future<void> _resolveFor(String? skillId) async {
    final myId = ++_resolutionId;
    if (skillId == null) {
      if (!mounted) return;
      setState(() {
        _medianMs = null;
        _resolved = true;
      });
      return;
    }
    final resolver =
        widget.medianResolver ?? LatencyHistoryStore.medianFor;
    final median = await resolver(skillId);
    if (!mounted || myId != _resolutionId) return;
    setState(() {
      _medianMs = median;
      _resolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final medianMs = _medianMs;
    if (!_resolved || medianMs == null) {
      return const SizedBox.shrink();
    }
    final pace = paceForMedianMs(medianMs);
    final tokens = context.masteryTokens;
    final color = switch (pace) {
      LatencyPace.fast => MasteryColors.success,
      LatencyPace.steady => MasteryColors.warning,
      LatencyPace.slow => MasteryColors.error,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'PACE',
            style: MasteryTextStyles.mono(
              size: 10,
              lineHeight: 12,
              weight: FontWeight.w600,
              color: tokens.textTertiary,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: color.withAlpha(180),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
