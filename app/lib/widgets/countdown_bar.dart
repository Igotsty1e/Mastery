import 'package:flutter/material.dart';

import '../theme/mastery_theme.dart';

/// Wave G7 — calm 60-second countdown bar on the exercise screen.
///
/// Replaces the Wave B `LatencyBand` ("PACE" indicator). The bar
/// quietly shrinks left-to-right over `duration` (default 60s).
/// Color fades from success green into warm amber in the last
/// quarter of the run; red is intentionally avoided per the
/// 2026-05-01 product call ("спокойный visual, без красного").
///
/// **Does NOT block submit.** When the bar runs out it just sits at
/// zero width — the learner can keep typing and tap "Check answer"
/// at any time. The visual is advisory: a calm pacing nudge, not a
/// graded clock.
///
/// The actual render→submit duration is still captured by
/// `SessionController` and fed into `LatencyHistoryStore` (Wave A)
/// so the future engine-tuning waves can use it without a UI
/// change.
class CountdownBar extends StatefulWidget {
  final Duration duration;
  const CountdownBar({
    super.key,
    this.duration = const Duration(seconds: 60),
  });

  @override
  State<CountdownBar> createState() => _CountdownBarState();
}

class _CountdownBarState extends State<CountdownBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'TIME',
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
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                // _controller.value: 0 → 1 over `duration`. We want
                // the bar to shrink, so progress = 1 - value.
                final progress = 1.0 - _controller.value;
                // Stay green until the last quarter, then fade
                // smoothly into warm amber. No red, ever.
                final amberShare = ((0.25 - progress) / 0.25).clamp(0.0, 1.0);
                final color = Color.lerp(
                  MasteryColors.success.withAlpha(160),
                  MasteryColors.warning.withAlpha(160),
                  amberShare,
                )!;
                return Stack(
                  children: [
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: tokens.bgSurfaceAlt,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: progress,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
