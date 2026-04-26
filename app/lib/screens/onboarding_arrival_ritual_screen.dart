// Arrival Ritual onboarding (2-step, Direction A · Editorial Notebook).
// Source of truth: docs/plans/arrival-ritual.md.
// Visual reference: docs/design-mockups/onboarding-2step/direction-a-editorial.html.
//
// Container holds the step state + a single text-only step indicator + CTA.
// Step bodies live as private widgets so each step can be tuned independently.

import 'package:flutter/material.dart';

import '../theme/mastery_theme.dart';

const int _stepCount = 2;

class OnboardingArrivalRitualScreen extends StatefulWidget {
  /// Called when the learner taps the final-step CTA. The HomeScreen
  /// implementation marks the onboarding as seen and reveals the dashboard.
  /// No direct push into the lesson intro — the dashboard is the single Home.
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

  // Step-to-step transition: shared-axis style — incoming step rises and
  // fades in, outgoing step settles and fades out. Honours reduced-motion
  // (MediaQuery.disableAnimations) by collapsing to opacity-only.
  Widget _stepTransition(Widget child, Animation<double> animation) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      return FadeTransition(opacity: animation, child: child);
    }
    final offset = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(animation);
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(position: offset, child: child),
    );
  }

  String get _ctaLabel => switch (_index) {
        0 => 'Continue',
        _ => 'Open my dashboard',
      };

  Widget _bodyForIndex(int i) => switch (i) {
        0 => const _PromiseStep(),
        _ => const _AssemblyStep(),
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
                          transitionBuilder: _stepTransition,
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
//
// Single text-only indicator per Direction A spec. No duplicate dot bar.

class _StepHeader extends StatelessWidget {
  final int currentIndex;
  final int total;
  const _StepHeader({required this.currentIndex, required this.total});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Text(
      'STEP ${currentIndex + 1} OF $total',
      style: MasteryTextStyles.mono(
        size: 11,
        lineHeight: 14,
        weight: FontWeight.w600,
        color: tokens.textTertiary,
        letterSpacing: 1.6,
      ),
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
//
// Editorial wordmark, one strong sentence about what the product does, three
// numbered proof points separated by hairline rules. Tone: calm, premium,
// zero hype. Direction A · Editorial Notebook.

class _PromiseStep extends StatelessWidget {
  const _PromiseStep();

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
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
            'Focused English grammar practice. One rule per lesson, taught with the precision an adult learner deserves.',
            style: MasteryTextStyles.bodyMd.copyWith(
              color: MasteryColors.textSecondary,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: MasterySpacing.lg),
        Container(
          width: 36,
          height: 1,
          color: tokens.accentGold.withAlpha(140),
        ),
        const SizedBox(height: MasterySpacing.lg),
        const _ProofPoint(
          ordinal: '01',
          title: 'One rule per lesson',
          body: 'A single grammar point — no mixing, no distraction.',
        ),
        const _ProofPointDivider(),
        const _ProofPoint(
          ordinal: '02',
          title: 'Targeted exercises',
          body:
              'Fill the blank, choose the form, repair the sentence, listen and pick.',
        ),
        const _ProofPointDivider(),
        const _ProofPoint(
          ordinal: '03',
          title: 'Calm diagnostic feedback',
          body:
              'After each answer — what was right, and why — grounded in the rule.',
        ),
      ],
    );
  }
}

class _ProofPoint extends StatelessWidget {
  final String ordinal;
  final String title;
  final String body;

  const _ProofPoint({
    required this.ordinal,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              ordinal,
              style: MasteryTextStyles.mono(
                size: 12,
                lineHeight: 14,
                weight: FontWeight.w600,
                color: tokens.accentGoldDeep,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: MasteryTextStyles.titleSm.copyWith(
                    color: MasteryColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: MasteryTextStyles.bodySm.copyWith(
                    color: MasteryColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProofPointDivider extends StatelessWidget {
  const _ProofPointDivider();

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Container(height: 1, color: tokens.borderSoft);
  }
}

// ── Step 2: Assembly ────────────────────────────────────────────────────────
//
// Editorial title + framing sentence + three numbered stage cards
// (Rule / Practice / Review). Final CTA opens the dashboard.

class _AssemblyStep extends StatelessWidget {
  const _AssemblyStep();

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Every lesson follows the same rhythm.',
          style: MasteryTextStyles.headlineMd.copyWith(
            color: MasteryColors.textPrimary,
            height: 1.18,
          ),
        ),
        const SizedBox(height: MasterySpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            'Three short phases. We move you through them without surprises.',
            style: MasteryTextStyles.bodyMd.copyWith(
              color: MasteryColors.textSecondary,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: MasterySpacing.lg),
        Container(
          width: 36,
          height: 1,
          color: tokens.accentGold.withAlpha(140),
        ),
        const SizedBox(height: MasterySpacing.lg),
        const _AssemblyCard(
          ordinal: '01',
          title: 'Rule',
          body:
              'A short, plain-English explanation of one grammar point — meaning, form, the contrast you should notice.',
        ),
        const SizedBox(height: MasterySpacing.md),
        const _AssemblyCard(
          ordinal: '02',
          title: 'Practice',
          body:
              'Around 10 exercises — choose, complete, repair, or listen. One decision at a time.',
        ),
        const SizedBox(height: MasterySpacing.md),
        const _AssemblyCard(
          ordinal: '03',
          title: 'Review',
          body:
              "A short coach\u2019s note after the lesson — what landed, what slipped, and the one micro-rule to watch next time.",
        ),
      ],
    );
  }
}

class _AssemblyCard extends StatelessWidget {
  final String ordinal;
  final String title;
  final String body;

  const _AssemblyCard({
    required this.ordinal,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: MasteryColors.bgRaised,
        border: Border.all(color: tokens.borderSoft),
        borderRadius: BorderRadius.circular(MasteryRadii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ordinal,
            style: MasteryTextStyles.mono(
              size: 13,
              lineHeight: 16,
              weight: FontWeight.w600,
              color: tokens.accentGoldDeep,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: MasteryTextStyles.titleSm.copyWith(
                    color: MasteryColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: MasteryTextStyles.bodySm.copyWith(
                    color: MasteryColors.textSecondary,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
