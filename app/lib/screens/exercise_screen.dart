import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lesson.dart';
import '../session/session_controller.dart';
import '../session/session_state.dart';
import '../theme/mastery_theme.dart';
import '../widgets/fill_blank_widget.dart';
import '../widgets/mastery_widgets.dart';
import '../widgets/multiple_choice_widget.dart';
import '../widgets/sentence_correction_widget.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<SessionController>();
      void onChange() {
        final state = controller.state;
        // Reset answer when exercise advances.
        if (state.currentExercise != null &&
            state.currentExercise!.exerciseId != _lastExerciseId) {
          _lastExerciseId = state.currentExercise!.exerciseId;
          if (mounted) setState(() => _currentAnswer = '');
        }
        if (state.phase == SessionPhase.summary) {
          controller.removeListener(onChange);
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => SummaryScreen(
                correctCount: state.correctCount,
                totalCount: state.totalCount,
                summary: state.summary,
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
                        InstructionBand(
                          text: exercise.instruction,
                          icon: switch (exercise.type) {
                            ExerciseType.sentenceCorrection =>
                              Icons.edit_outlined,
                            _ => Icons.task_alt_rounded,
                          },
                        ),
                        const SizedBox(height: 16),
                        MasteryCard(
                          padding: const EdgeInsets.all(22),
                          child: _ExerciseBody(
                            key: ValueKey(exercise.exerciseId),
                            exercise: exercise,
                            enabled: !isSubmitted && !isLoading,
                            onAnswerChanged: _onAnswerChanged,
                            onTextSubmit: () => _submitIfReady(controller),
                          ),
                        ),
                        if (isSubmitted && state.lastResult != null) ...[
                          const SizedBox(height: 16),
                          ResultPanel(
                            correct: state.lastResult!.correct,
                            canonicalAnswer: state.lastResult!.canonicalAnswer,
                            explanation: state.lastResult!.explanation,
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
                            ? controller.advance
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
    controller.submitAnswer(_currentAnswer);
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
          prompt: exercise.prompt,
          enabled: enabled,
          onChanged: onAnswerChanged,
          onSubmitField: onTextSubmit,
        ),
      ExerciseType.multipleChoice => MultipleChoiceWidget(
          prompt: exercise.prompt,
          options: exercise.options!,
          enabled: enabled,
          onChanged: onAnswerChanged,
        ),
      ExerciseType.sentenceCorrection => SentenceCorrectionWidget(
          prompt: exercise.prompt,
          enabled: enabled,
          onChanged: onAnswerChanged,
        ),
    };
  }
}
