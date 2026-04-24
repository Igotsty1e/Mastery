import 'package:flutter/material.dart';

import '../config.dart';
import 'lesson_intro_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _startLesson(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const LessonIntroScreen(lessonId: AppConfig.defaultLessonId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mastery',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'English practice, one lesson at a time.',
                style: theme.textTheme.bodyLarge,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _startLesson(context),
                  child: const Text('Start Lesson'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
