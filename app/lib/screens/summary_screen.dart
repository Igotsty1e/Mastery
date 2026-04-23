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
    final serverCorrect = summary?.correctCount;
    final serverTotal = summary?.totalExercises;
    final displayCorrect = serverCorrect ?? correctCount;
    final displayTotal = serverTotal ?? totalCount;
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
