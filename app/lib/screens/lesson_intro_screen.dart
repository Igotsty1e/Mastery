import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../session/session_controller.dart';
import '../session/session_state.dart';
import 'exercise_screen.dart';

class LessonIntroScreen extends StatefulWidget {
  final String lessonId;

  const LessonIntroScreen({super.key, required this.lessonId});

  @override
  State<LessonIntroScreen> createState() => _LessonIntroScreenState();
}

class _LessonIntroScreenState extends State<LessonIntroScreen> {
  late final SessionController _controller;
  bool _controllerHandedOff = false;

  @override
  void initState() {
    super.initState();
    _controller = SessionController(
      context.read<ApiClient>(),
    );
    _controller.loadLesson(widget.lessonId);
  }

  @override
  void dispose() {
    if (!_controllerHandedOff) _controller.dispose();
    super.dispose();
  }

  void _start() {
    _controllerHandedOff = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: _controller,
          child: const ExerciseScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final state = _controller.state;

        if (state.phase == SessionPhase.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state.phase == SessionPhase.error) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Failed to load lesson:\n${state.errorMessage}'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _controller.retry,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final lesson = state.lesson!;
        final theme = Theme.of(context);
        return Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  Text(
                    lesson.level,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    lesson.title,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${lesson.exercises.length} exercises',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.grey[600]),
                  ),
                  if (lesson.introRule.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Text('Rule', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withOpacity(0.35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        lesson.introRule,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                  if (lesson.introExamples.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Examples', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ...lesson.introExamples.map(
                      (ex) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('• ',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.primary)),
                            Expanded(
                              child: Text(ex,
                                  style: theme.textTheme.bodyMedium),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _start,
                      child: const Text('Start'),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
