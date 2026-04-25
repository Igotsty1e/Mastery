import 'package:flutter/material.dart';
import '../models/evaluation.dart';

class SummaryScreen extends StatelessWidget {
  final int correctCount;
  final int totalCount;
  final LessonResultResponse? summary;

  const SummaryScreen({
    super.key,
    required this.correctCount,
    required this.totalCount,
    this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayCorrect = summary?.correctCount ?? correctCount;
    final displayTotal = summary?.totalExercises ?? totalCount;
    final mistakes = summary?.answers.where((a) => !a.correct).toList() ?? [];
    final conclusion = summary?.conclusion;

    final pct = displayTotal > 0 ? displayCorrect / displayTotal : 0.0;
    final scoreColor = pct == 1.0
        ? const Color(0xFF047857)
        : pct >= 0.6
            ? theme.colorScheme.primary
            : const Color(0xFFBE123C);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  'Lesson Complete',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 36, vertical: 24),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$displayCorrect / $displayTotal',
                        style: theme.textTheme.displayMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scoreColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'correct',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (conclusion != null) ...[
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    conclusion,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              if (mistakes.isNotEmpty) ...[
                const SizedBox(height: 36),
                Text(
                  'Review your mistakes',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ...mistakes.map((m) => _MistakeCard(answer: m)),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _MistakeCard extends StatelessWidget {
  final LessonResultAnswer answer;

  const _MistakeCard({required this.answer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (answer.prompt != null) ...[
            Text(
              answer.prompt!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (answer.canonicalAnswer != null)
            RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  const TextSpan(
                    text: 'Answer: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: answer.canonicalAnswer!,
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          if (answer.explanation != null) ...[
            const SizedBox(height: 10),
            Text(
              answer.explanation!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
