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

  List<Widget> _buildRuleContent(String text, ThemeData theme) {
    final paragraphs = text.split('\n\n');
    final widgets = <Widget>[];
    for (var i = 0; i < paragraphs.length; i++) {
      if (i > 0) widgets.add(const SizedBox(height: 14));
      final para = paragraphs[i];
      final lines = para.split('\n');
      final firstLine = lines[0].trim();
      final isSectionHeader = lines.length > 1 && firstLine.length <= 20;
      if (isSectionHeader) {
        widgets.add(Text(
          firstLine,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ));
        widgets.add(const SizedBox(height: 6));
        widgets.add(Text(
          lines.skip(1).join('\n'),
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        ));
      } else {
        widgets.add(
            Text(para, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)));
      }
    }
    return widgets;
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
          backgroundColor: theme.colorScheme.surfaceContainerLowest,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      lesson.level,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    lesson.title,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${lesson.exercises.length} exercises',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (lesson.introRule.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _buildRuleContent(lesson.introRule, theme),
                      ),
                    ),
                  ],
                  if (lesson.introExamples.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withOpacity(0.25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.primaryContainer,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Examples',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...lesson.introExamples.map(
                            (ex) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 7),
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      ex,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _start,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Start Practice',
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
      },
    );
  }
}
