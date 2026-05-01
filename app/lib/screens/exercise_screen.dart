import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../analytics/analytics.dart';
import '../api/api_client.dart';
import '../models/lesson.dart';
import '../session/session_controller.dart';
import '../session/session_state.dart';
import '../theme/mastery_theme.dart';
import '../widgets/decision_reason_line.dart';
import '../widgets/feedback_prompt_sheet.dart';
import '../widgets/fill_blank_widget.dart';
import '../widgets/countdown_bar.dart';
import '../widgets/listening_discrimination_widget.dart';
import '../widgets/mastery_exercise_image.dart';
import '../widgets/mastery_widgets.dart';
import '../widgets/multiple_choice_widget.dart';
import '../widgets/sentence_correction_widget.dart';
import '../widgets/sentence_rewrite_widget.dart';
import '../widgets/short_free_sentence_widget.dart';
import 'summary_screen.dart';

class ExerciseScreen extends StatefulWidget {
  const ExerciseScreen({super.key});

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> {
  String _currentAnswer = '';
  String? _lastExerciseId;

  @override
  void initState() {
    super.initState();
    Analytics.trackScreen('exercise');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<SessionController>();
      void onChange() {
        final state = controller.state;
        // Reset answer when exercise advances.
        if (state.currentExercise != null &&
            state.currentExercise!.exerciseId != _lastExerciseId) {
          _lastExerciseId = state.currentExercise!.exerciseId;
          if (mounted) setState(() => _currentAnswer = '');
          Analytics.track('exercise_shown', screen: 'exercise', metadata: {
            'exercise_id': state.currentExercise!.exerciseId,
            'skill_id': state.currentExercise!.skillId,
            'type': state.currentExercise!.type.toString().split('.').last,
          });
        }
        if (state.phase == SessionPhase.summary) {
          controller.removeListener(onChange);
          if (!mounted) return;
          // Wave 4 §11.2: pass the skill IDs this lesson touched so the
          // SummaryScreen panel filters its store query to this session
          // and does not pollute with stale skills from earlier lessons.
          final touched = state.lesson?.exercises
                  .map((e) => e.skillId)
                  .whereType<String>()
                  .toSet() ??
              const <String>{};
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => SummaryScreen(
                correctCount: state.correctCount,
                totalCount: state.totalCount,
                summary: state.summary,
                touchedSkillIds: touched.isEmpty ? null : touched,
              ),
            ),
          );
        }
      }
      controller.addListener(onChange);
      _lastExerciseId = controller.state.currentExercise?.exerciseId;
    });
  }

  void _onAnswerChanged(String answer) {
    if (answer == _currentAnswer) return;
    setState(() => _currentAnswer = answer);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final controller = context.read<SessionController>();
    final state = context.watch<SessionController>().state;

    if (state.phase == SessionPhase.error) {
      return Scaffold(
        backgroundColor: tokens.bgApp,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(MasterySpacing.lg),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline,
                    size: 40, color: MasteryColors.error),
                const SizedBox(height: 16),
                Text(
                  state.errorMessage ?? 'Something went wrong.',
                  style: MasteryTextStyles.bodyMd,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: controller.retry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final exercise = state.currentExercise;
    if (exercise == null) {
      return Scaffold(backgroundColor: tokens.bgApp, body: const SizedBox());
    }

    final isSubmitted = state.phase == SessionPhase.result;
    final isLoading = state.phase == SessionPhase.evaluating;
    final progress = (state.currentIndex + 1) / state.totalCount;

    return Scaffold(
      backgroundColor: tokens.bgApp,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _ExerciseTopBar(
                  index: state.currentIndex,
                  total: state.totalCount,
                  progress: progress,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      MasterySpacing.lg,
                      18,
                      MasterySpacing.lg,
                      MasterySpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // §11.3 per-routing reason: describes WHY this
                        // next item, so it must render only on the new
                        // exercise (phase == ready), not above the
                        // just-answered question during the result
                        // panel. The DecisionEngine sets the reason in
                        // submitAnswer; advance() carries it forward
                        // into the ready phase, then the next attempt's
                        // submitAnswer either replaces it or clears it.
                        DecisionReasonLine(
                          text: state.phase == SessionPhase.ready
                              ? state.lastDecisionReason
                              : null,
                        ),
                        // Wave G7 — calm 60-second countdown bar.
                        // Replaces the earlier `LatencyBand` PACE
                        // indicator. Resets on every fresh exercise
                        // via the `ValueKey` so the animation
                        // restarts when the learner advances. Does
                        // NOT block submit — running out is
                        // visual-only.
                        CountdownBar(key: ValueKey(exercise.exerciseId)),
                        InstructionBand(
                          text: exercise.instruction,
                          icon: switch (exercise.type) {
                            ExerciseType.sentenceCorrection =>
                              Icons.edit_outlined,
                            ExerciseType.sentenceRewrite =>
                              Icons.edit_outlined,
                            ExerciseType.shortFreeSentence =>
                              Icons.edit_outlined,
                            _ => Icons.task_alt_rounded,
                          },
                        ),
                        const SizedBox(height: 16),
                        MasteryCard(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (exercise.image != null) ...[
                                MasteryExerciseImage(image: exercise.image!),
                                const SizedBox(height: MasterySpacing.lg),
                              ],
                              _ExerciseBody(
                                key: ValueKey(exercise.exerciseId),
                                exercise: exercise,
                                enabled: !isSubmitted && !isLoading,
                                onAnswerChanged: _onAnswerChanged,
                                onTextSubmit: () =>
                                    _submitIfReady(controller),
                              ),
                            ],
                          ),
                        ),
                        if (isSubmitted && state.lastResult != null) ...[
                          const SizedBox(height: 16),
                          ResultPanel(
                            correct: state.lastResult!.correct,
                            canonicalAnswer: state.lastResult!.canonicalAnswer,
                            explanation: state.lastResult!.explanation,
                            // Wave 12.6 — quiet "See full rule →" link
                            // visible on any result; opens the source
                            // lesson's intro_rule + intro_examples in a
                            // bottom sheet. Non-null only when the
                            // exercise carries a skill_id.
                            skillRuleSnapshot:
                                state.lastResult!.skillRuleSnapshot,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      MasterySpacing.lg, 0, MasterySpacing.lg, MasterySpacing.md),
                  child: FilledButton(
                    onPressed: isLoading
                        ? null
                        : isSubmitted
                            ? () => _onAdvanceTap(controller, state)
                            : (_currentAnswer.isEmpty
                                ? null
                                : () => _submitIfReady(controller)),
                    child: Text(
                      isSubmitted
                          ? (state.isLastExercise ? 'Finish' : 'Next')
                          : 'Check answer',
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isLoading)
            const ColoredBox(
              color: Color(0x402B2326),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  void _submitIfReady(SessionController controller) {
    if (_currentAnswer.isEmpty) return;
    final exercise = controller.state.currentExercise;
    Analytics.trackButton('check_answer', screen: 'exercise', extra: {
      if (exercise != null) 'exercise_id': exercise.exerciseId,
      if (exercise?.skillId != null) 'skill_id': exercise!.skillId,
    });
    controller.submitAnswer(_currentAnswer);
  }

  /// Wave 14.3 phase 3 — V1.5 after-friction prompt.
  ///
  /// When the just-resolved attempt carries a `friction_event` tag
  /// from the server (V1: `repeated_error`), check the cooldown gate
  /// and offer a single-line rating sheet between the result panel
  /// and the next exercise. Result is mirrored as one row to
  /// `POST /me/feedback` and then `controller.advance` is called.
  ///
  /// Failure modes are silent — the advance always happens. Worst
  /// case the learner doesn't see the prompt this session.
  Future<void> _onAdvanceTap(
    SessionController controller,
    SessionState state,
  ) async {
    final friction = state.lastResult?.frictionEvent;
    final exerciseId = state.lastResult?.exerciseId;
    if (friction != null) {
      final api = context.read<ApiClient>();
      try {
        final cooldown = await api.getFeedbackCooldown();
        if (mounted &&
            cooldown != null &&
            cooldown.afterFrictionAllowed) {
          final result = await showFeedbackPromptSheet(
            context,
            title: 'How did that feel?',
            subtitle:
                'Two misses on the same skill — your read of it helps us tune the rule.',
          );
          try {
            await api.submitFeedback(
              promptKind: 'after_friction',
              outcome: result.wireOutcome,
              rating: result.rating,
              commentText: result.commentText,
              context: {
                'friction_event': friction,
                if (exerciseId != null) 'exercise_id': exerciseId,
              },
            );
          } catch (_) {
            // Best-effort — do not block advance on a flaky POST.
          }
        }
      } catch (_) {
        // Quiet on cooldown read failure — skip the prompt.
      }
    }
    if (!mounted) return;
    Analytics.trackButton(
      state.isLastExercise ? 'finish' : 'next',
      screen: 'exercise',
    );
    controller.advance();
  }
}

class _ExerciseTopBar extends StatelessWidget {
  final int index;
  final int total;
  final double progress;

  const _ExerciseTopBar({
    required this.index,
    required this.total,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Column(
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded, size: 26),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const Spacer(),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${index + 1}',
                      style: MasteryTextStyles.mono(
                        size: 14,
                        lineHeight: 16,
                        weight: FontWeight.w600,
                        color: MasteryColors.textPrimary,
                      ),
                    ),
                    TextSpan(
                      text: ' / $total',
                      style: MasteryTextStyles.mono(
                        size: 14,
                        lineHeight: 16,
                        weight: FontWeight.w400,
                        color: MasteryColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.close_rounded,
                    size: 22, color: tokens.textTertiary),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 4,
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            backgroundColor: tokens.bgSurfaceAlt,
            valueColor: const AlwaysStoppedAnimation(
                MasteryColors.actionPrimary),
            minHeight: 4,
          ),
        ),
      ],
    );
  }
}

class _ExerciseBody extends StatelessWidget {
  final Exercise exercise;
  final bool enabled;
  final ValueChanged<String> onAnswerChanged;
  final VoidCallback onTextSubmit;

  const _ExerciseBody({
    super.key,
    required this.exercise,
    required this.enabled,
    required this.onAnswerChanged,
    required this.onTextSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return switch (exercise.type) {
      ExerciseType.fillBlank => FillBlankWidget(
          prompt: exercise.prompt ?? '',
          enabled: enabled,
          onChanged: onAnswerChanged,
          onSubmitField: onTextSubmit,
        ),
      ExerciseType.multipleChoice => MultipleChoiceWidget(
          prompt: exercise.prompt ?? '',
          options: exercise.options!,
          enabled: enabled,
          onChanged: onAnswerChanged,
        ),
      ExerciseType.sentenceCorrection => SentenceCorrectionWidget(
          prompt: exercise.prompt ?? '',
          enabled: enabled,
          onChanged: onAnswerChanged,
        ),
      ExerciseType.sentenceRewrite => SentenceRewriteWidget(
          prompt: exercise.prompt ?? '',
          enabled: enabled,
          onChanged: onAnswerChanged,
        ),
      ExerciseType.shortFreeSentence => ShortFreeSentenceWidget(
          enabled: enabled,
          onChanged: onAnswerChanged,
        ),
      ExerciseType.listeningDiscrimination => ListeningDiscriminationWidget(
          audio: exercise.audio!,
          options: exercise.options!,
          enabled: enabled,
          onChanged: onAnswerChanged,
        ),
    };
  }
}
