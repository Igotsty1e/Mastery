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

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'Lesson Complete',
                  style: theme.textTheme.headlineMedium,
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  '$displayCorrect / $displayTotal',
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'correct',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: Colors.grey[600]),
                ),
              ),
              if (conclusion != null) ...[
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    conclusion,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              if (mistakes.isNotEmpty) ...[
                const SizedBox(height: 32),
                Text(
                  'Mistakes to review',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...mistakes.map((m) => _MistakeCard(answer: m)),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (answer.prompt != null) ...[
              Text(
                answer.prompt!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (answer.canonicalAnswer != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Answer: ',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: Text(
                      answer.canonicalAnswer!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            if (answer.explanation != null) ...[
              const SizedBox(height: 8),
              Text(
                answer.explanation!,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (answer.practicalTip != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 14,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        answer.practicalTip!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
