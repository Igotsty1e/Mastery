// Arrival Ritual onboarding (3-step) per docs/plans/arrival-ritual.md.
// Container holds the step state + step indicator + CTA. Step bodies live
// alongside as private widgets so each step can be tuned independently
// without touching the container.

import 'package:flutter/material.dart';

import '../theme/mastery_theme.dart';

/// Number of steps in the Arrival Ritual onboarding.
const int _stepCount = 3;

class OnboardingArrivalRitualScreen extends StatefulWidget {
  /// Called when the learner taps the final-step CTA. The HomeScreen
  /// implementation marks the onboarding as seen and routes directly into
  /// the lesson intro (no dashboard detour).
  final VoidCallback onComplete;

  const OnboardingArrivalRitualScreen({
    super.key,
    required this.onComplete,
  });

  @override
  State<OnboardingArrivalRitualScreen> createState() =>
      _OnboardingArrivalRitualScreenState();
}

class _OnboardingArrivalRitualScreenState
    extends State<OnboardingArrivalRitualScreen> {
  int _index = 0;

  void _next() {
    if (_index >= _stepCount - 1) {
      widget.onComplete();
      return;
    }
    setState(() => _index += 1);
  }

  void _back() {
    if (_index <= 0) return;
    setState(() => _index -= 1);
  }

  String get _ctaLabel => switch (_index) {
        0 => 'Continue',
        1 => 'Continue',
        _ => 'Get started',
      };

  Widget _bodyForIndex(int i) => switch (i) {
        0 => const _PromiseStep(),
        1 => const _AssemblyStep(),
        _ => const _HandoffStep(),
      };

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Scaffold(
      backgroundColor: tokens.bgApp,
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -1.0),
              radius: 0.9,
              colors: [
                tokens.bgOnboardPanel.withAlpha(180),
                tokens.bgApp,
              ],
              stops: const [0.0, 0.7],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  MasterySpacing.lg, 28, MasterySpacing.lg, 36),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 64,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _StepHeader(currentIndex: _index, total: _stepCount),
                      const SizedBox(height: MasterySpacing.xl),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: MasteryDurations.medium,
                          switchInCurve: MasteryEasing.move,
                          switchOutCurve: MasteryEasing.move,
                          child: KeyedSubtree(
                            key: ValueKey(_index),
                            child: _bodyForIndex(_index),
                          ),
                        ),
                      ),
                      _StepFooter(
                        canGoBack: _index > 0,
                        onBack: _back,
                        ctaLabel: _ctaLabel,
                        onCta: _next,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _StepHeader extends StatelessWidget {
  final int currentIndex;
  final int total;
  const _StepHeader({required this.currentIndex, required this.total});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'STEP ${currentIndex + 1} OF $total',
          style: MasteryTextStyles.mono(
            size: 11,
            lineHeight: 14,
            weight: FontWeight.w600,
            color: tokens.textTertiary,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: List.generate(total, (i) {
              final active = i <= currentIndex;
              return Padding(
                padding: const EdgeInsets.only(left: 6),
                child: AnimatedContainer(
                  duration: MasteryDurations.short,
                  curve: MasteryEasing.move,
                  width: active ? 24 : 14,
                  height: 4,
                  decoration: BoxDecoration(
                    color: active
                        ? MasteryColors.actionPrimary
                        : tokens.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ── Footer ──────────────────────────────────────────────────────────────────

class _StepFooter extends StatelessWidget {
  final bool canGoBack;
  final VoidCallback onBack;
  final String ctaLabel;
  final VoidCallback onCta;

  const _StepFooter({
    required this.canGoBack,
    required this.onBack,
    required this.ctaLabel,
    required this.onCta,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Padding(
      padding: const EdgeInsets.only(top: MasterySpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: onCta,
            child: Text(ctaLabel),
          ),
          const SizedBox(height: MasterySpacing.sm),
          AnimatedOpacity(
            opacity: canGoBack ? 1.0 : 0.0,
            duration: MasteryDurations.short,
            child: TextButton(
              onPressed: canGoBack ? onBack : null,
              child: Text(
                'Back',
                style: MasteryTextStyles.labelMd.copyWith(
                  color: tokens.textTertiary,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step 1: Promise ─────────────────────────────────────────────────────────

class _PromiseStep extends StatelessWidget {
  const _PromiseStep();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mastery',
          style: MasteryTextStyles.displayItalic(size: 56, lineHeight: 60),
        ),
        const SizedBox(height: MasterySpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            'Focused English grammar practice, one rule at a time.',
            style: MasteryTextStyles.bodyMd.copyWith(
              color: MasteryColors.textSecondary,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: MasterySpacing.xl),
        Text(
          'Promise step (placeholder body — Step 3 fills in proof points).',
          style: MasteryTextStyles.bodySm.copyWith(
            color: MasteryColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── Step 2: Assembly ────────────────────────────────────────────────────────

class _AssemblyStep extends StatelessWidget {
  const _AssemblyStep();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Assembling your lesson',
          style: MasteryTextStyles.headlineMd.copyWith(
            color: MasteryColors.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: MasterySpacing.md),
        Text(
          'Assembly step (placeholder body — Step 4 fills in the rule → practice → review metaphor).',
          style: MasteryTextStyles.bodyMd.copyWith(color: MasteryColors.textSecondary),
        ),
      ],
    );
  }
}

// ── Step 3: Handoff ─────────────────────────────────────────────────────────

class _HandoffStep extends StatelessWidget {
  const _HandoffStep();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Today\u2019s lesson',
          style: MasteryTextStyles.headlineMd.copyWith(
            color: MasteryColors.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: MasterySpacing.md),
        Text(
          'Handoff step (placeholder — Step 5 fetches the lesson preview: title, level, exercise count, and one-sentence promise).',
          style: MasteryTextStyles.bodyMd.copyWith(color: MasteryColors.textSecondary),
        ),
      ],
    );
  }
}
