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

  List<_RuleSection> _parseRuleSections(String text) {
    final paragraphs = text.split('\n\n');
    final sections = <_RuleSection>[];
    for (final para in paragraphs) {
      final lines = para.split('\n');
      final firstLine = lines[0].trim();
      final isSectionHeader = lines.length > 1 && firstLine.length <= 20;
      if (isSectionHeader) {
        sections.add(
          _RuleSection(
            title: firstLine,
            bodyLines: lines.skip(1).toList(),
          ),
        );
      } else {
        sections.add(
          _RuleSection(
            title: '',
            bodyLines: [para],
          ),
        );
      }
    }
    return sections;
  }

  List<Widget> _buildRuleContent(String text, ThemeData theme) {
    final sections = _parseRuleSections(text);
    return sections
        .map((section) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _RuleSectionCard(section: section),
            ))
        .toList();
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
                    SizedBox(
                      width: double.infinity,
                      child: Column(
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
                            .withValues(alpha: 0.25),
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

class _RuleSection {
  final String title;
  final List<String> bodyLines;

  const _RuleSection({
    required this.title,
    required this.bodyLines,
  });
}

class _RuleSectionCard extends StatelessWidget {
  final _RuleSection section;

  const _RuleSectionCard({required this.section});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = section.title.trim().toLowerCase();
    final isImportant = normalized == 'important';
    final isForm = normalized == 'form';
    final isUse = normalized == 'use';

    final bgColor = isImportant
        ? const Color(0xFFFFF7ED)
        : isForm
            ? const Color(0xFFEEF2FF)
            : theme.colorScheme.surface;
    final borderColor = isImportant
        ? const Color(0xFFF59E0B)
        : isForm
            ? const Color(0xFF818CF8)
            : theme.colorScheme.outlineVariant;
    final accentColor = isImportant
        ? const Color(0xFFB45309)
        : isForm
            ? const Color(0xFF4338CA)
            : theme.colorScheme.primary;
    final icon = isImportant
        ? Icons.priority_high_rounded
        : isForm
            ? Icons.rule_folder_outlined
            : isUse
                ? Icons.lightbulb_outline_rounded
                : Icons.menu_book_outlined;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.title.isNotEmpty) ...[
            Row(
              children: [
                Icon(icon, size: 18, color: accentColor),
                const SizedBox(width: 8),
                Text(
                  section.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          ...section.bodyLines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RuleLineText(
                line: line,
                accentColor: accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleLineText extends StatelessWidget {
  final String line;
  final Color accentColor;

  const _RuleLineText({
    required this.line,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = line.trim();
    final colonIndex = trimmed.indexOf(':');

    if (colonIndex > 0 && colonIndex < trimmed.length - 1) {
      final label = trimmed.substring(0, colonIndex + 1);
      final body = trimmed.substring(colonIndex + 1).trimLeft();
      return RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            height: 1.55,
          ),
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: accentColor,
              ),
            ),
            TextSpan(text: body),
          ],
        ),
      );
    }

    final isFormula = trimmed.contains('+') || trimmed.contains('...');
    return Text(
      trimmed,
      style: theme.textTheme.bodyMedium?.copyWith(
        height: 1.55,
        fontWeight: isFormula ? FontWeight.w600 : FontWeight.normal,
        color: isFormula ? accentColor : theme.colorScheme.onSurface,
      ),
    );
  }
}
