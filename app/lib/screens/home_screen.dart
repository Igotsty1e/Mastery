import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../models/lesson.dart';
import 'lesson_intro_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ApiClient _apiClient;
  List<LessonSummary> _lessons = const [];
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _apiClient = context.read<ApiClient>();
    _loadLessons();
  }

  Future<void> _loadLessons() async {
    try {
      final lessons = await _apiClient.fetchLessons();
      if (!mounted) return;
      setState(() {
        _lessons = lessons;
        _errorMessage = null;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  void _retry() {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });
    _loadLessons();
  }

  void _openLesson(String lessonId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LessonIntroScreen(lessonId: lessonId),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Failed to load lessons:\n$_errorMessage',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _retry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_lessons.isEmpty) {
      return Center(
        child: Text(
          'No lessons available.',
          style: theme.textTheme.bodyLarge,
        ),
      );
    }

    return ListView.separated(
      itemCount: _lessons.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final lesson = _lessons[index];
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            title: Text(
              lesson.title,
              style: theme.textTheme.titleMedium,
            ),
            subtitle: lesson.description == null
                ? null
                : Text(
                    lesson.description!,
                    style: theme.textTheme.bodyMedium,
                  ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openLesson(lesson.id),
          ),
        );
      },
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
              const SizedBox(height: 24),
              Expanded(child: _buildContent(theme)),
            ],
          ),
        ),
      ),
    );
  }
}
