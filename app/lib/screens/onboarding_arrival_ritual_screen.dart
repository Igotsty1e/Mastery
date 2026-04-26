// Arrival Ritual onboarding (3-step) per docs/plans/arrival-ritual.md.
// Container holds the step state + step indicator + CTA. Step bodies live
// alongside as private widgets so each step can be tuned independently
// without touching the container.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/lesson.dart';
import '../theme/mastery_theme.dart';

/// Number of steps in the Arrival Ritual onboarding.
const int _stepCount = 3;

class OnboardingArrivalRitualScreen extends StatefulWidget {
  /// Called when the learner taps the final-step CTA. The HomeScreen
  /// implementation marks the onboarding as seen and routes directly into
  /// the lesson intro (no dashboard detour).
  final VoidCallback onComplete;

  /// Lesson previewed in the Handoff step so the learner sees what is being
  /// prepared before tapping the final CTA.
  final String lessonId;

  const OnboardingArrivalRitualScreen({
    super.key,
    required this.onComplete,
    required this.lessonId,
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
        1 => 'Continue',
        _ => 'Get started',
      };

  Widget _bodyForIndex(int i) => switch (i) {
        0 => const _PromiseStep(),
        1 => const _AssemblyStep(),
        _ => _HandoffStep(lessonId: widget.lessonId),
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
//
// Establish trust fast. Editorial wordmark, one strong sentence about what
// the product does, three proof points. Tone: calm, premium, zero hype.
// Per docs/plans/arrival-ritual.md §01.

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
        const _ProofPoint(
          icon: Icons.menu_book_outlined,
          title: 'One rule per lesson',
          body:
              'Each lesson teaches a single grammar point — no mixing, no distraction.',
        ),
        const SizedBox(height: MasterySpacing.lg),
        const _ProofPoint(
          icon: Icons.edit_outlined,
          title: 'Targeted exercises',
          body:
              'Fill the blank, choose the form, correct the sentence, listen and pick.',
        ),
        const SizedBox(height: MasterySpacing.lg),
        const _ProofPoint(
          icon: Icons.check_circle_outline,
          title: 'Calm, diagnostic feedback',
          body:
              'After each answer you see what was right and why, grounded in the rule.',
        ),
      ],
    );
  }
}

class _ProofPoint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _ProofPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: tokens.bgPrimarySoft,
            borderRadius: BorderRadius.circular(MasteryRadii.md),
          ),
          alignment: Alignment.center,
          child: Icon(icon,
              size: 20, color: MasteryColors.actionPrimaryPressed),
        ),
        const SizedBox(width: MasterySpacing.md),
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
    );
  }
}

// ── Step 2: Assembly ────────────────────────────────────────────────────────
//
// Show what the app is about to do for the learner. Make the flow feel
// constructed, not random — rule → practice → review, mini-cards rising
// one by one. Per docs/plans/arrival-ritual.md §02.

class _AssemblyStep extends StatelessWidget {
  const _AssemblyStep();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Building today\u2019s lesson',
          style: MasteryTextStyles.headlineMd.copyWith(
            color: MasteryColors.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: MasterySpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            'Every lesson follows the same rhythm. We move you through it without surprises.',
            style: MasteryTextStyles.bodyMd.copyWith(
              color: MasteryColors.textSecondary,
              height: 1.55,
            ),
          ),
        ),
        const SizedBox(height: MasterySpacing.xl),
        const _AssemblyCard(
          ordinal: '01',
          title: 'Rule',
          body:
              'A short, plain-English explanation of one grammar point — meaning, form, and the contrast you should notice.',
        ),
        const SizedBox(height: MasterySpacing.md),
        const _AssemblyCard(
          ordinal: '02',
          title: 'Practice',
          body:
              'Around 10 exercises that ask you to choose, complete, repair, or listen — one decision at a time.',
        ),
        const SizedBox(height: MasterySpacing.md),
        const _AssemblyCard(
          ordinal: '03',
          title: 'Review',
          body:
              'A calm coach\u2019s note on what landed and what to watch out for — so the next session has a target.',
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

// ── Step 3: Handoff ─────────────────────────────────────────────────────────
//
// End onboarding with a concrete lesson already waiting. Show title, level,
// exercise count, estimated duration, and a one-sentence learning promise.
// Fetches the lesson via the API client so the preview reflects real data.
// Per docs/plans/arrival-ritual.md §03.

class _HandoffStep extends StatefulWidget {
  final String lessonId;
  const _HandoffStep({required this.lessonId});

  @override
  State<_HandoffStep> createState() => _HandoffStepState();
}

class _HandoffStepState extends State<_HandoffStep> {
  Lesson? _lesson;
  bool _failed = false;
  bool _loadStarted = false;

  // ApiClient lookup is deferred to didChangeDependencies so context.read
  // happens at the right moment in the widget lifecycle. Reading it inside
  // an async _load() risks touching a deactivated element during teardown.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadStarted) return;
    _loadStarted = true;
    final api = context.read<ApiClient>();
    _load(api);
  }

  Future<void> _load(ApiClient api) async {
    try {
      final lesson = await api.getLesson(widget.lessonId);
      if (!mounted) return;
      setState(() => _lesson = lesson);
    } catch (_) {
      if (!mounted) return;
      // Soft failure: keep CTA enabled, fall back to a generic preview so the
      // ritual never gates the learner behind a network error.
      setState(() => _failed = true);
    }
  }

  // Estimated duration is not on the lesson schema. ~30s per exercise is a
  // safe MVP heuristic and matches what the existing onboarding promised.
  String _durationCopy(int exerciseCount) {
    if (exerciseCount <= 0) return 'About 5 minutes';
    final minutes = (exerciseCount * 0.5).ceil();
    return 'About $minutes minute${minutes == 1 ? '' : 's'}';
  }

  String _promiseFor(Lesson lesson) =>
      'By the end you\u2019ll handle "${lesson.title}" with confidence at level ${lesson.level}.';

  @override
  Widget build(BuildContext context) {
    final lesson = _lesson;
    if (lesson == null && !_failed) {
      return const _HandoffSkeleton();
    }
    if (lesson == null) {
      return const _HandoffFallback();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Today\u2019s lesson is ready',
          style: MasteryTextStyles.headlineMd.copyWith(
            color: MasteryColors.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: MasterySpacing.sm),
        Text(
          _promiseFor(lesson),
          style: MasteryTextStyles.bodyMd.copyWith(
            color: MasteryColors.textSecondary,
            height: 1.55,
          ),
        ),
        const SizedBox(height: MasterySpacing.xl),
        _LessonPreviewCard(
          title: lesson.title,
          level: lesson.level,
          exerciseCount: lesson.exercises.length,
          durationCopy: _durationCopy(lesson.exercises.length),
        ),
      ],
    );
  }
}

class _LessonPreviewCard extends StatelessWidget {
  final String title;
  final String level;
  final int exerciseCount;
  final String durationCopy;

  const _LessonPreviewCard({
    required this.title,
    required this.level,
    required this.exerciseCount,
    required this.durationCopy,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: MasteryColors.bgRaised,
        border: Border.all(color: tokens.borderSoft),
        borderRadius: BorderRadius.circular(MasteryRadii.lg),
        boxShadow: tokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'LESSON',
                style: MasteryTextStyles.mono(
                  size: 11,
                  lineHeight: 14,
                  weight: FontWeight.w600,
                  color: tokens.textTertiary,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.bgPrimarySoft,
                  borderRadius: BorderRadius.circular(MasteryRadii.pill),
                ),
                child: Text(
                  level,
                  style: MasteryTextStyles.labelMd.copyWith(
                    color: MasteryColors.actionPrimaryPressed,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: MasteryTextStyles.titleMd.copyWith(
              color: MasteryColors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _MetaChip(
                icon: Icons.menu_book_outlined,
                label: '$exerciseCount exercises',
              ),
              _MetaChip(
                icon: Icons.schedule_outlined,
                label: durationCopy,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: tokens.textTertiary),
        const SizedBox(width: 6),
        Text(
          label,
          style: MasteryTextStyles.bodySm.copyWith(
            color: MasteryColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _HandoffSkeleton extends StatelessWidget {
  const _HandoffSkeleton();

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preparing your lesson\u2026',
          style: MasteryTextStyles.headlineMd.copyWith(
            color: MasteryColors.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: MasterySpacing.xl),
        Container(
          height: 110,
          decoration: BoxDecoration(
            color: tokens.bgPrimarySoft,
            borderRadius: BorderRadius.circular(MasteryRadii.lg),
          ),
        ),
      ],
    );
  }
}

class _HandoffFallback extends StatelessWidget {
  const _HandoffFallback();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Today\u2019s lesson is ready',
          style: MasteryTextStyles.headlineMd.copyWith(
            color: MasteryColors.textPrimary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: MasterySpacing.sm),
        Text(
          'We couldn\u2019t reach the lesson preview right now, but the lesson itself will load on the next screen.',
          style: MasteryTextStyles.bodyMd.copyWith(
            color: MasteryColors.textSecondary,
            height: 1.55,
          ),
        ),
      ],
    );
  }
}
