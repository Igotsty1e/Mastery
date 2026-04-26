import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/lesson.dart';
import '../session/session_controller.dart';
import '../session/session_state.dart';
import '../theme/mastery_theme.dart';
import '../widgets/fill_blank_widget.dart';
import '../widgets/listening_discrimination_widget.dart';
import '../widgets/mastery_exercise_image.dart';
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

    return Scaffold(
      backgroundColor: tokens.bgApp,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Quieter Direction A chrome (Brief B): segmented progress bar
                // with mono counter, no chevron-back. Close stays available.
                _ExerciseTopBar(
                  index: state.currentIndex,
                  total: state.totalCount,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      MasterySpacing.lg,
                      MasterySpacing.lg,
                      MasterySpacing.lg,
                      MasterySpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Mono caps instruction line — quieter than the
                        // tinted InstructionBand it replaces.
                        Text(
                          exercise.instruction.toUpperCase(),
                          style: MasteryTextStyles.mono(
                            size: 11,
                            lineHeight: 14,
                            weight: FontWeight.w600,
                            color: tokens.textTertiary,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (exercise.image != null) ...[
                          MasteryExerciseImage(image: exercise.image!),
                          const SizedBox(height: MasterySpacing.lg),
                        ],
                        _ExerciseBody(
                          key: ValueKey(exercise.exerciseId),
                          exercise: exercise,
                          enabled: !isSubmitted && !isLoading,
                          onAnswerChanged: _onAnswerChanged,
                          onTextSubmit: () => _submitIfReady(controller),
                        ),
                        if (isSubmitted && state.lastResult != null) ...[
                          const SizedBox(height: 18),
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

/// Direction A · Brief B chrome: a row of segmented progress pills (one per
/// exercise) plus a mono counter and an unobtrusive close button. The pills
/// quietly count up; the heavy LinearProgressIndicator + chevron-back combo
/// is gone — the prompt is the hero, not the chrome.
class _ExerciseTopBar extends StatelessWidget {
  final int index;
  final int total;

  const _ExerciseTopBar({
    required this.index,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          MasterySpacing.lg, 12, MasterySpacing.md, 4),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: List.generate(total, (i) {
                final active = i <= index;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == total - 1 ? 0 : 4),
                    child: AnimatedContainer(
                      duration: MasteryDurations.short,
                      curve: MasteryEasing.move,
                      height: 3,
                      decoration: BoxDecoration(
                        color: active
                            ? MasteryColors.actionPrimary
                            : tokens.borderStrong,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            '${(index + 1).toString().padLeft(2, '0')} / ${total.toString().padLeft(2, '0')}',
            style: MasteryTextStyles.mono(
              size: 12,
              lineHeight: 14,
              weight: FontWeight.w500,
              color: tokens.textTertiary,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: Icon(Icons.close_rounded, size: 20, color: tokens.textTertiary),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
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
      ExerciseType.listeningDiscrimination => ListeningDiscriminationWidget(
          audio: exercise.audio!,
          options: exercise.options!,
          enabled: enabled,
          onChanged: onAnswerChanged,
        ),
    };
  }
}
