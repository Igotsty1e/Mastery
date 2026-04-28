// Wave 12.3 — diagnostic-mode screen.
//
// Three internal phases driven by an enum (no Navigator routes):
//
//   1. Welcome  — 60-second sell, Begin / Skip for now.
//   2. Probe    — 5 multiple_choice items, no instant correctness reveal.
//   3. Completion — CEFR + per-skill panel, Continue / Re-take.
//
// Spec: `docs/plans/diagnostic-mode.md`. Reuses the existing
// `MultipleChoiceWidget`, `MasteryColors` / `MasteryTextStyles` /
// `MasterySpacing` tokens, and the themed `FilledButton` /
// `TextButton` shapes. Diagnostic surface lives between SignInScreen
// and OnboardingArrivalRitualScreen — see HomeScreen routing gate.

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/diagnostic_dtos.dart';
import '../learner/skill_titles.dart';
import '../models/lesson.dart';
import '../progress/local_progress_store.dart';
import '../theme/mastery_theme.dart';
import '../widgets/diagnostic_proof_card.dart';
import '../widgets/mastery_widgets.dart';
import '../widgets/multiple_choice_widget.dart';

enum _Phase { welcome, probe, completion, error }

/// Screen surfaces the diagnostic probe. Mounts after sign-in, before
/// the Arrival Ritual onboarding. Calls [onComplete] when the
/// learner has either finished the probe or chosen to skip — both
/// paths route to the onboarding ritual.
class DiagnosticScreen extends StatefulWidget {
  final ApiClient apiClient;
  final VoidCallback onComplete;

  const DiagnosticScreen({
    super.key,
    required this.apiClient,
    required this.onComplete,
  });

  @override
  State<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends State<DiagnosticScreen> {
  _Phase _phase = _Phase.welcome;
  bool _busy = false;
  String? _errorMessage;

  // Run state (populated when the probe starts).
  String? _runId;
  int _position = 0;
  int _total = 5;
  Exercise? _currentExercise;

  // Completion state.
  DiagnosticCompletion? _completion;

  Future<void> _onBegin() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final start = await widget.apiClient.startDiagnostic();
      if (!mounted) return;
      setState(() {
        _runId = start.runId;
        _position = start.position;
        _total = start.total;
        _currentExercise = start.nextExercise;
        _phase = start.nextExercise == null ? _Phase.error : _Phase.probe;
        _busy = false;
        if (start.nextExercise == null) {
          _errorMessage =
              "We couldn't load the questions right now. Please try again.";
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _phase = _Phase.error;
        _errorMessage =
            "We couldn't load the questions right now. Please try again.";
      });
    }
  }

  Future<void> _onSkip() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Fire-and-forget; the ApiClient swallows errors so the skip path
    // is never blocked by a server outage. Mark the local flag too so
    // the same device does not re-prompt.
    await widget.apiClient.skipDiagnostic();
    await LocalProgressStore.markDiagnosticSkipped();
    if (!mounted) return;
    widget.onComplete();
  }

  Future<void> _onPick(String optionId) async {
    final runId = _runId;
    final exercise = _currentExercise;
    if (runId == null || exercise == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.apiClient.submitDiagnosticAnswer(
        runId: runId,
        exerciseId: exercise.exerciseId,
        exerciseType: 'multiple_choice',
        userAnswer: optionId,
      );
      if (!mounted) return;
      if (result.runComplete) {
        // Run finished — fire /complete to derive CEFR + skill_map.
        try {
          final completion = await widget.apiClient.completeDiagnostic(runId);
          if (!mounted) return;
          setState(() {
            _completion = completion;
            _phase = _Phase.completion;
            _position = result.position;
            _total = result.total;
            _currentExercise = null;
            _busy = false;
          });
        } catch (_) {
          if (!mounted) return;
          setState(() {
            _phase = _Phase.error;
            _errorMessage =
                "We couldn't summarise your answers right now. Please try again.";
            _busy = false;
          });
        }
        return;
      }
      setState(() {
        _position = result.position;
        _total = result.total;
        _currentExercise = result.nextExercise;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = 'Something went wrong. Tap an option to retry.';
      });
    }
  }

  Future<void> _onRetake() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorMessage = null;
    });
    try {
      final start = await widget.apiClient.restartDiagnostic();
      if (!mounted) return;
      setState(() {
        _runId = start.runId;
        _position = start.position;
        _total = start.total;
        _currentExercise = start.nextExercise;
        _completion = null;
        _phase = start.nextExercise == null ? _Phase.error : _Phase.probe;
        _busy = false;
        if (start.nextExercise == null) {
          _errorMessage =
              "We couldn't load the questions right now. Please try again.";
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _phase = _Phase.error;
        _errorMessage = "Couldn't restart. Please try again.";
      });
    }
  }

  void _onContinue() {
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MasteryColors.bgApp,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: MasteryDurations.medium,
          switchInCurve: MasteryEasing.enter,
          child: _buildPhase(),
        ),
      ),
    );
  }

  Widget _buildPhase() {
    return switch (_phase) {
      _Phase.welcome => _WelcomePhase(
          key: const ValueKey('welcome'),
          busy: _busy,
          onBegin: _onBegin,
          onSkip: _onSkip,
        ),
      _Phase.probe => _ProbePhase(
          key: ValueKey('probe-$_position'),
          position: _position,
          total: _total,
          exercise: _currentExercise,
          busy: _busy,
          showHint: _position == 0,
          errorMessage: _errorMessage,
          onPick: _onPick,
        ),
      _Phase.completion => _CompletionPhase(
          key: const ValueKey('completion'),
          completion: _completion!,
          busy: _busy,
          onContinue: _onContinue,
          onRetake: _onRetake,
        ),
      _Phase.error => _ErrorPhase(
          key: const ValueKey('error'),
          message: _errorMessage ?? 'Something went wrong.',
          busy: _busy,
          onRetry: _onBegin,
          onSkip: _onSkip,
        ),
    };
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Phase 1 — Welcome
// ─────────────────────────────────────────────────────────────────────────

class _WelcomePhase extends StatelessWidget {
  final bool busy;
  final VoidCallback onBegin;
  final VoidCallback onSkip;

  const _WelcomePhase({
    super.key,
    required this.busy,
    required this.onBegin,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: MasterySpacing.lg,
            vertical: MasterySpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: MasterySpacing.xxxl),
              Text(
                'A short read on where you are.',
                style: MasteryTextStyles.headlineLg.copyWith(
                  color: MasteryColors.textPrimary,
                ),
              ),
              const SizedBox(height: MasterySpacing.lg),
              Text(
                'Five quick questions. Two minutes. We use them to set '
                'your level and pick the first lesson you actually need '
                "— not the one a curriculum thinks you do.",
                style: MasteryTextStyles.bodyLg.copyWith(
                  color: MasteryColors.textSecondary,
                ),
              ),
              const SizedBox(height: MasterySpacing.xl),
              const DiagnosticProofCard(),
              const SizedBox(height: MasterySpacing.xxl),
              FilledButton(
                onPressed: busy ? null : onBegin,
                child: busy
                    ? const _ButtonSpinner()
                    : const Text('Begin'),
              ),
              const SizedBox(height: MasterySpacing.md),
              Center(
                child: TextButton(
                  onPressed: busy ? null : onSkip,
                  child: Text(
                    'Skip for now',
                    style: MasteryTextStyles.labelMd.copyWith(
                      color: MasteryColors.textSecondary,
                      letterSpacing: 0.4,
                    ),
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

// ─────────────────────────────────────────────────────────────────────────
// Phase 2 — Probe
// ─────────────────────────────────────────────────────────────────────────

class _ProbePhase extends StatelessWidget {
  final int position;
  final int total;
  final Exercise? exercise;
  final bool busy;
  final bool showHint;
  final String? errorMessage;
  final ValueChanged<String> onPick;

  const _ProbePhase({
    super.key,
    required this.position,
    required this.total,
    required this.exercise,
    required this.busy,
    required this.showHint,
    required this.errorMessage,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final ex = exercise;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: MasterySpacing.lg,
            vertical: MasterySpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionEyebrow(
                label: 'Quick check',
                variant: SectionEyebrowVariant.secondary,
              ),
              const SizedBox(height: MasterySpacing.xs),
              Text(
                'Question ${position + 1} of $total',
                style: MasteryTextStyles.labelLg.copyWith(
                  color: MasteryColors.textPrimary,
                ),
              ),
              const SizedBox(height: MasterySpacing.sm),
              MasteryProgressTrack(
                value: total == 0 ? 0 : position / total,
              ),
              const SizedBox(height: MasterySpacing.xl),
              if (ex == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: MasterySpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                MasteryCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ex.instruction,
                        style: MasteryTextStyles.bodyMd.copyWith(
                          color: MasteryColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: MasterySpacing.md),
                      MultipleChoiceWidget(
                        prompt: ex.prompt ?? '',
                        options: ex.options ?? const [],
                        enabled: !busy,
                        onChanged: onPick,
                      ),
                    ],
                  ),
                ),
                if (showHint) ...[
                  const SizedBox(height: MasterySpacing.md),
                  Text(
                    "We'll show you results at the end.",
                    style: MasteryTextStyles.bodySm.copyWith(
                      color: MasteryColors.textTertiary,
                    ),
                  ),
                ],
              ],
              if (errorMessage != null) ...[
                const SizedBox(height: MasterySpacing.md),
                Text(
                  errorMessage!,
                  style: MasteryTextStyles.bodySm.copyWith(
                    color: MasteryColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Phase 3 — Completion
// ─────────────────────────────────────────────────────────────────────────

class _CompletionPhase extends StatelessWidget {
  final DiagnosticCompletion completion;
  final bool busy;
  final VoidCallback onContinue;
  final VoidCallback onRetake;

  const _CompletionPhase({
    super.key,
    required this.completion,
    required this.busy,
    required this.onContinue,
    required this.onRetake,
  });

  @override
  Widget build(BuildContext context) {
    final firstWeakSkill = _firstWeakSkill(completion.skillMap);
    final firstWeakTitle =
        firstWeakSkill == null ? null : skillTitleFor(firstWeakSkill);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: MasterySpacing.lg,
            vertical: MasterySpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: MasterySpacing.xxxxl),
              _LevelHeadline(level: completion.cefrLevel),
              const SizedBox(height: MasterySpacing.lg),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    firstWeakTitle == null
                        ? "Strong start. We'll begin with the next lesson on your path."
                        : (_strongRun(completion.skillMap)
                            ? "Strong start. We'll begin with $firstWeakTitle to keep the rhythm."
                            : "Based on your five answers, we'll start with $firstWeakTitle and pick what's next from there."),
                    textAlign: TextAlign.center,
                    style: MasteryTextStyles.bodyLg.copyWith(
                      color: MasteryColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: MasterySpacing.xl),
              _SkillPanel(skillMap: completion.skillMap),
              const SizedBox(height: MasterySpacing.xxl),
              FilledButton(
                onPressed: busy ? null : onContinue,
                child: busy
                    ? const _ButtonSpinner()
                    : const Text('Continue'),
              ),
              const SizedBox(height: MasterySpacing.md),
              Center(
                child: TextButton(
                  onPressed: busy ? null : onRetake,
                  child: Text(
                    'Re-take the check',
                    style: MasteryTextStyles.labelMd.copyWith(
                      color: MasteryColors.textSecondary,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _firstWeakSkill(Map<String, String> skillMap) {
    if (skillMap.isEmpty) return null;
    // Prefer a skill flagged 'started' (the probe's "haven't proven
    // yourself yet" status). Fall back to the first 'practicing'
    // entry when every skill is already practicing.
    for (final entry in skillMap.entries) {
      if (entry.value == 'started') return entry.key;
    }
    return skillMap.keys.first;
  }

  static bool _strongRun(Map<String, String> skillMap) {
    if (skillMap.isEmpty) return false;
    return skillMap.values.every((s) => s != 'started');
  }
}

class _LevelHeadline extends StatelessWidget {
  final String level;

  const _LevelHeadline({required this.level});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: MasteryTextStyles.displayMd.copyWith(
            color: MasteryColors.textPrimary,
          ),
          children: [
            const TextSpan(text: 'Your level: '),
            TextSpan(
              text: level,
              style: MasteryTextStyles.displayMd.copyWith(
                color: MasteryColors.accentGold,
              ),
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }
}

class _SkillPanel extends StatelessWidget {
  final Map<String, String> skillMap;

  const _SkillPanel({required this.skillMap});

  @override
  Widget build(BuildContext context) {
    if (skillMap.isEmpty) return const SizedBox.shrink();
    final entries = skillMap.entries.toList();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MasterySpacing.lg,
        vertical: MasterySpacing.lg,
      ),
      decoration: BoxDecoration(
        color: MasteryColors.bgSurfaceAlt,
        borderRadius: BorderRadius.circular(MasteryRadii.lg),
        border: Border.all(color: MasteryColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: MasterySpacing.sm),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: MasteryColors.borderSoft,
                ),
              ),
            _SkillRow(
              skillId: entries[i].key,
              status: entries[i].value,
            ),
          ],
        ],
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  final String skillId;
  final String status;

  const _SkillRow({required this.skillId, required this.status});

  @override
  Widget build(BuildContext context) {
    final isPracticing = status == 'practicing';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            skillTitleFor(skillId),
            style: MasteryTextStyles.bodyMd.copyWith(
              color: MasteryColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: MasterySpacing.sm),
        StatusBadge(
          label: isPracticing ? 'Practicing' : 'Just started',
          variant: isPracticing
              ? StatusBadgeVariant.current
              : StatusBadgeVariant.locked,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Error phase + tiny utilities
// ─────────────────────────────────────────────────────────────────────────

class _ErrorPhase extends StatelessWidget {
  final String message;
  final bool busy;
  final VoidCallback onRetry;
  final VoidCallback onSkip;

  const _ErrorPhase({
    super.key,
    required this.message,
    required this.busy,
    required this.onRetry,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MasterySpacing.lg,
            vertical: MasterySpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                style: MasteryTextStyles.bodyLg.copyWith(
                  color: MasteryColors.textPrimary,
                ),
              ),
              const SizedBox(height: MasterySpacing.xl),
              FilledButton(
                onPressed: busy ? null : onRetry,
                child: busy
                    ? const _ButtonSpinner()
                    : const Text('Try again'),
              ),
              const SizedBox(height: MasterySpacing.md),
              Center(
                child: TextButton(
                  onPressed: busy ? null : onSkip,
                  child: Text(
                    'Skip for now',
                    style: MasteryTextStyles.labelMd.copyWith(
                      color: MasteryColors.textSecondary,
                      letterSpacing: 0.4,
                    ),
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

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(MasteryColors.bgSurface),
      ),
    );
  }
}
