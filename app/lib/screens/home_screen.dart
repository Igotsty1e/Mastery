import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../progress/local_progress_store.dart';
import '../theme/mastery_theme.dart';
import '../widgets/mastery_widgets.dart';
import 'lesson_intro_screen.dart';
import 'onboarding_arrival_ritual_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _resolving = true;
  bool _showOnboarding = true;
  bool _isLoadingDashboard = false;
  int _completedExercises = 0;
  int _totalExercises = 10;
  String _lessonTitle = 'Verbs Followed by -ing';
  String _selectedLevel = 'B2';

  @override
  void initState() {
    super.initState();
    _resolveInitialView();
  }

  // First-launch detection per docs/plans/arrival-ritual.md: if the learner
  // has already completed the Arrival Ritual onboarding, drop them into the
  // dashboard. Otherwise show the onboarding flow.
  Future<void> _resolveInitialView() async {
    final seen = await LocalProgressStore.hasSeenOnboarding();
    if (!mounted) return;
    setState(() {
      _showOnboarding = !seen;
      _resolving = false;
    });
    if (seen) {
      await _loadDashboard();
    }
  }

  // Onboarding-final CTA contract (locked 2026-04-26 per
  // docs/plans/arrival-ritual.md): mark onboarding seen and reveal the
  // dashboard. The dashboard is the single Home — both this CTA and the
  // SummaryScreen `Done` button land here. Onboarding never pushes the
  // lesson intro directly.
  Future<void> _completeOnboarding() async {
    await LocalProgressStore.markOnboardingSeen();
    if (!mounted) return;
    setState(() => _showOnboarding = false);
    await _loadDashboard();
  }

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
        _lessonTitle = lesson.title;
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
    if (_resolving) {
      return Scaffold(
        backgroundColor: context.masteryTokens.bgApp,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_showOnboarding) {
      return OnboardingArrivalRitualScreen(
        onComplete: _completeOnboarding,
      );
    }
    return _buildDashboard();
  }

  // ---------- Dashboard ----------
  Widget _buildDashboard() {
    final tokens = context.masteryTokens;
    final progress = _totalExercises == 0
        ? 0.0
        : _completedExercises / _totalExercises;

    return Scaffold(
      backgroundColor: tokens.bgApp,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              MasterySpacing.lg, 28, MasterySpacing.lg, MasterySpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mastery',
                style: MasteryTextStyles.displayItalic(
                  size: 32,
                  lineHeight: 34,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'English practice, one lesson at a time.',
                style: MasteryTextStyles.bodyMd.copyWith(
                  color: MasteryColors.textSecondary,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'LEVEL',
                style: MasteryTextStyles.labelMd.copyWith(
                  color: MasteryColors.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: MasterySpacing.sm),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  LevelChip(
                      label: 'A2',
                      active: _selectedLevel == 'A2',
                      locked: _selectedLevel != 'A2'),
                  LevelChip(
                      label: 'B1',
                      active: _selectedLevel == 'B1',
                      locked: _selectedLevel != 'B1'),
                  LevelChip(
                      label: 'B2',
                      active: _selectedLevel == 'B2',
                      locked: _selectedLevel != 'B2'),
                  LevelChip(
                      label: 'C1',
                      active: _selectedLevel == 'C1',
                      locked: _selectedLevel != 'C1'),
                ],
              ),
              const SizedBox(height: 28),
              MasteryCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: SectionEyebrow(label: "Today's lesson"),
                        ),
                        TagPill(label: _selectedLevel),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _lessonTitle,
                      style: MasteryTextStyles.headlineMd.copyWith(
                        fontFamily: 'Fraunces',
                        fontSize: 26,
                        height: 30 / 26,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                        fontVariations: const [
                          FontVariation('opsz', 144),
                          FontVariation('wght', 600),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$_totalExercises exercises  ·  ~5 minutes',
                      style: MasteryTextStyles.bodySm.copyWith(
                        color: MasteryColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                            child:
                                MasteryProgressTrack(value: progress)),
                        const SizedBox(width: 14),
                        Text(
                          _isLoadingDashboard
                              ? '— / $_totalExercises'
                              : '$_completedExercises / $_totalExercises',
                          style: MasteryTextStyles.mono(
                            size: 14,
                            lineHeight: 18,
                            weight: FontWeight.w600,
                            color: MasteryColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _isLoadingDashboard ? null : _startLesson,
                      child: Text(
                        _completedExercises > 0
                            ? 'Continue lesson'
                            : 'Start lesson',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: MasterySpacing.lg),
              const _ComingNext(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComingNext extends StatelessWidget {
  const _ComingNext();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'COMING NEXT',
              style: MasteryTextStyles.labelMd.copyWith(
                color: MasteryColors.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            Text(
              'See all',
              style: MasteryTextStyles.labelSm.copyWith(
                color: MasteryColors.actionPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _NextRow(
          number: '02',
          title: 'Verbs Followed by to-Infinitive',
          subtitle: 'B2  ·  10 exercises',
        ),
        const SizedBox(height: 8),
        _NextRow(
          number: '03',
          title: 'Reported Speech: Statements',
          subtitle: 'B2  ·  10 exercises',
        ),
      ],
    );
  }
}

class _NextRow extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;

  const _NextRow({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: tokens.bgSurfaceAlt,
        border: Border.all(color: tokens.borderSoft),
        borderRadius: BorderRadius.circular(MasteryRadii.md),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MasteryColors.bgRaised,
              border: Border.all(color: tokens.borderSoft),
              borderRadius: BorderRadius.circular(MasteryRadii.pill),
            ),
            child: Text(
              number,
              style: MasteryTextStyles.mono(
                size: 12,
                lineHeight: 12,
                weight: FontWeight.w500,
                color: MasteryColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: MasteryTextStyles.bodyMd.copyWith(
                    fontWeight: FontWeight.w700,
                    color: MasteryColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: MasteryTextStyles.bodySm.copyWith(
                    color: tokens.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.lock_outline,
              size: 16, color: tokens.textTertiary),
        ],
      ),
    );
  }
}
