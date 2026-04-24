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
  bool _navigating = false;

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

    if (state.phase == SessionPhase.summary && !_navigating) {
      _navigating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
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
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final exercise = state.currentExercise;
    if (exercise == null) return const Scaffold(body: SizedBox.shrink());

    final isSubmitted = state.phase == SessionPhase.result;
    final isLoading = state.phase == SessionPhase.evaluating;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          '${state.currentIndex + 1} / ${state.totalCount}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (state.currentIndex + 1) / state.totalCount,
          ),
        ),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ExerciseWidget(
                    key: ValueKey(exercise.exerciseId),
                    exercise: exercise,
                    enabled: !isSubmitted && !isLoading,
                    onSubmit: controller.submitAnswer,
                  ),
                  if (isSubmitted && state.lastResult != null) ...[
                    const SizedBox(height: 24),
                    _ResultPanel(
                      correct: state.lastResult!.correct,
                      explanation: state.lastResult!.explanation,
                      practicalTip: state.lastResult!.practicalTip,
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
    return switch (exercise.type) {
      ExerciseType.fillBlank => FillBlankWidget(
          prompt: exercise.prompt,
          hint: exercise.hint,
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
    };
  }
}

class _ResultPanel extends StatelessWidget {
  final bool correct;
  final String? explanation;
  final String? practicalTip;
  final String canonicalAnswer;
  final bool isLast;
  final VoidCallback onNext;

  const _ResultPanel({
    required this.correct,
    required this.explanation,
    required this.practicalTip,
    required this.canonicalAnswer,
    required this.isLast,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final color = correct ? Colors.green[700]! : Colors.red[700]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            border: Border.all(color: color.withOpacity(0.4)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                correct ? 'Correct' : 'Incorrect',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: color, fontSize: 16),
              ),
              if (!correct) ...[
                const SizedBox(height: 8),
                Text('Answer: $canonicalAnswer'),
              ],
              if (explanation != null) ...[
                const SizedBox(height: 10),
                Text(explanation!,
                    style: TextStyle(color: Colors.grey[800], fontSize: 14)),
              ],
              if (practicalTip != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 16, color: Colors.amber[700]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(practicalTip!,
                            style: TextStyle(
                                color: Colors.grey[800], fontSize: 13)),
                      ),
                    ],
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
            child: Text(isLast ? 'Finish' : 'Next'),
          ),
        ),
      ],
    );
  }
}
