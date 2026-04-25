import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../progress/local_progress_store.dart';
import 'lesson_intro_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _showOnboarding = true;
  bool _isLoadingDashboard = false;
  int _completedExercises = 0;
  int _totalExercises = 10;
  String _selectedLevel = 'B2';

  Future<void> _loadDashboard() async {
    if (_isLoadingDashboard) return;
    setState(() => _isLoadingDashboard = true);

    try {
      final lesson =
          await context.read<ApiClient>().getLesson(AppConfig.defaultLessonId);
      final completed =
          await LocalProgressStore.getCompletedExercises(lesson.lessonId);
      if (!mounted) return;
      setState(() {
        _selectedLevel = lesson.level;
        _totalExercises = lesson.exercises.length;
        _completedExercises = completed.clamp(0, lesson.exercises.length);
        _isLoadingDashboard = false;
      });
    } catch (_) {
      if (!mounted) return;
      final localCompleted = await LocalProgressStore.getCompletedExercises(
        AppConfig.defaultLessonId,
      );
      if (!mounted) return;
      setState(() {
        _selectedLevel = 'B2';
        _totalExercises = 10;
        _completedExercises = localCompleted.clamp(0, 10);
        _isLoadingDashboard = false;
      });
    }
  }

  Future<void> _startLesson() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const LessonIntroScreen(lessonId: AppConfig.defaultLessonId),
      ),
    );
    if (!mounted) return;
    await _loadDashboard();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_showOnboarding) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surfaceContainerLowest,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                Text(
                  'Mastery',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Focused English grammar practice.',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 40),
                _OnboardingPoint(
                  icon: Icons.menu_book_outlined,
                  title: 'One rule per lesson',
                  body:
                      'Each lesson focuses on a single grammar point — no mixing, no distraction.',
                  theme: theme,
                ),
                const SizedBox(height: 20),
                _OnboardingPoint(
                  icon: Icons.edit_outlined,
                  title: '10 targeted exercises',
                  body:
                      'Fill in the blank, choose the correct form, and correct sentences.',
                  theme: theme,
                ),
                const SizedBox(height: 20),
                _OnboardingPoint(
                  icon: Icons.check_circle_outline,
                  title: 'Instant feedback',
                  body:
                      'After each answer you see whether you were right and why, based on the grammar rule.',
                  theme: theme,
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      setState(() => _showOnboarding = false);
                      _loadDashboard();
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Get started',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
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
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Level',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _LevelChip(label: 'A2', active: _selectedLevel == 'A2'),
                  _LevelChip(label: 'B1', active: _selectedLevel == 'B1'),
                  _LevelChip(label: 'B2', active: _selectedLevel == 'B2'),
                  _LevelChip(label: 'C1', active: _selectedLevel == 'C1'),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.insights_outlined,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$_selectedLevel progress',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isLoadingDashboard
                          ? 'Loading progress...'
                          : '$_completedExercises / $_totalExercises exercises completed',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        value: _totalExercises == 0
                            ? 0
                            : _completedExercises / _totalExercises,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _startLesson,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Start Lesson',
                    style: TextStyle(fontSize: 16),
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

class _OnboardingPoint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final ThemeData theme;

  const _OnboardingPoint({
    required this.icon,
    required this.title,
    required this.body,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 22,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LevelChip extends StatelessWidget {
  final String label;
  final bool active;

  const _LevelChip({
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: active
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!active) ...[
            Icon(
              Icons.lock_outline,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: active
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
