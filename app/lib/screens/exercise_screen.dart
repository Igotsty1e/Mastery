import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/lesson.dart';
import '../session/session_controller.dart';
import '../session/session_state.dart';
import '../widgets/fill_blank_widget.dart';
import '../widgets/multiple_choice_widget.dart';
import '../widgets/sentence_correction_widget.dart';
import 'summary_screen.dart';

class ExerciseScreen extends StatefulWidget {
  const ExerciseScreen({super.key});

  @override
  State<ExerciseScreen> createState() => _ExerciseScreenState();
}

class _ExerciseScreenState extends State<ExerciseScreen> {
  @override
  void initState() {
    super.initState();
    // Navigate when session reaches summary phase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<SessionController>();
      void _onStateChange() {
        if (controller.state.phase == SessionPhase.summary) {
          controller.removeListener(_onStateChange);
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => SummaryScreen(
                correctCount: controller.state.correctCount,
                totalCount: controller.state.totalCount,
                summary: controller.state.summary,
              ),
            ),
          );
        }
      }
      controller.addListener(_onStateChange);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<SessionController>();
    final state = context.watch<SessionController>().state;

    if (state.phase == SessionPhase.error) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  state.errorMessage ?? 'Something went wrong.',
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
    if (exercise == null) return const Scaffold(body: SizedBox.shrink());

    final isSubmitted = state.phase == SessionPhase.result;
    final isLoading = state.phase == SessionPhase.evaluating;

    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        title: Text(
          '${state.currentIndex + 1} / ${state.totalCount}',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (state.currentIndex + 1) / state.totalCount,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                          color: theme.colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: _ExerciseWidget(
                        key: ValueKey(exercise.exerciseId),
                        exercise: exercise,
                        enabled: !isSubmitted && !isLoading,
                        onSubmit: controller.submitAnswer,
                      ),
                    ),
                  ),
                  if (isSubmitted && state.lastResult != null) ...[
                    const SizedBox(height: 16),
                    _ResultPanel(
                      correct: state.lastResult!.correct,
                      explanation: state.lastResult!.explanation,
                      canonicalAnswer: state.lastResult!.canonicalAnswer,
                      isLast: state.isLastExercise,
                      onNext: controller.advance,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isLoading)
            const ColoredBox(
              color: Color(0x55000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _ExerciseWidget extends StatelessWidget {
  final Exercise exercise;
  final bool enabled;
  final void Function(String) onSubmit;

  const _ExerciseWidget({
    super.key,
    required this.exercise,
    required this.enabled,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.colorScheme.primaryContainer),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.task_alt_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  exercise.instruction,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        switch (exercise.type) {
          ExerciseType.fillBlank => FillBlankWidget(
              prompt: exercise.prompt,
              enabled: enabled,
              onSubmit: onSubmit,
            ),
          ExerciseType.multipleChoice => MultipleChoiceWidget(
              prompt: exercise.prompt,
              options: exercise.options!,
              enabled: enabled,
              onSubmit: onSubmit,
            ),
          ExerciseType.sentenceCorrection => SentenceCorrectionWidget(
              prompt: exercise.prompt,
              enabled: enabled,
              onSubmit: onSubmit,
            ),
        },
      ],
    );
  }
}

class _ResultPanel extends StatelessWidget {
  final bool correct;
  final String? explanation;
  final String canonicalAnswer;
  final bool isLast;
  final VoidCallback onNext;

  const _ResultPanel({
    required this.correct,
    required this.explanation,
    required this.canonicalAnswer,
    required this.isLast,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor =
        correct ? const Color(0xFFECFDF5) : const Color(0xFFFFF1F2);
    final borderColor =
        correct ? const Color(0xFF6EE7B7) : const Color(0xFFFDA4AF);
    final labelColor =
        correct ? const Color(0xFF047857) : const Color(0xFFBE123C);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    correct ? Icons.check_circle : Icons.cancel,
                    size: 20,
                    color: labelColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    correct ? 'Correct' : 'Incorrect',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: labelColor,
                    ),
                  ),
                ],
              ),
              if (!correct) ...[
                const SizedBox(height: 10),
                Text(
                  'Answer: $canonicalAnswer',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (explanation != null) ...[
                const SizedBox(height: 10),
                Text(
                  explanation!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onNext,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              isLast ? 'Finish' : 'Next',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}
