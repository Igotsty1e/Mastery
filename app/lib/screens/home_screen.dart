// HomeScreen — first-launch routes through the Arrival Ritual onboarding;
// the dashboard is the single Home for every other launch. The dashboard
// implements the locked Study Desk contract (`docs/plans/dashboard-study-desk.md`)
// with reference visual at `docs/design-mockups/dashboard-study-desk.html`.
//
// Order on the dashboard (locked):
//   1. header (greeting + level dropdown trigger + avatar)
//   2. next-lesson hero
//   3. last-lesson report (only when LastLessonStore has a record)
//   4. current unit with badge states
//   5. coming next (quiet)
//   6. premium block (visual stub — no monetisation in MVP)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../auth/auth_client.dart';
import '../config.dart';
import '../learner/learner_skill_store.dart';
import '../learner/learner_state_migrator.dart';
import '../learner/review_scheduler.dart';
import '../progress/local_progress_store.dart';
import '../session/last_lesson_store.dart';
import '../theme/mastery_theme.dart';
import '../widgets/mastery_route.dart';
import '../widgets/mastery_widgets.dart';
import '../widgets/review_due_section.dart';
import 'lesson_intro_screen.dart';
import 'onboarding_arrival_ritual_screen.dart';
import 'sign_in_screen.dart';
import 'summary_screen.dart';

/// One row of the curriculum the dashboard tracks. Built from
/// `GET /lessons` (server order) plus the per-lesson completion count
/// from `LocalProgressStore`. Rendered into the next-lesson hero +
/// the current-unit block.
class _CurriculumEntry {
  final String id;
  final String title;
  final int totalExercises;
  final int completedExercises;

  const _CurriculumEntry({
    required this.id,
    required this.title,
    required this.totalExercises,
    required this.completedExercises,
  });

  bool get isDone =>
      totalExercises > 0 && completedExercises >= totalExercises;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _resolving = true;
  bool _showOnboarding = true;
  bool _showSignIn = false;
  bool _isLoadingDashboard = false;
  String _selectedLevel = 'B2';

  /// Created on first launch. Wave 8 (legacy drop) made auth mandatory
  /// — every shipped build constructs an AuthClient and routes through
  /// the sign-in gate or its silent stub-login Skip path.
  AuthClient? _authClient;

  /// Curriculum the dashboard renders. Built from the `/lessons` list
  /// in `_loadDashboard`. Empty until the network call resolves; the
  /// fallback path keeps a stub so the dashboard never goes blank.
  List<_CurriculumEntry> _curriculum = const [];

  /// Wave 4 §11.3 review-due teaser. Loaded on dashboard mount and
  /// after every dashboard reload so a freshly-finished session shows
  /// up here when its due time arrives.
  List<ReviewSchedule> _dueReviews = const [];

  /// Lesson the learner should land on — prefers a lesson they have
  /// already started over the manifest-order first-unfinished. Without
  /// this preference, an existing learner who had partial progress on
  /// the previous default lesson would get rewound to lesson 01 the
  /// first time the curriculum-aware dashboard ships.
  _CurriculumEntry? get _currentLesson {
    // Prefer an in-progress lesson (started but not finished).
    for (final e in _curriculum) {
      if (!e.isDone && e.completedExercises > 0) return e;
    }
    // Else the first un-started lesson in manifest order.
    for (final e in _curriculum) {
      if (!e.isDone) return e;
    }
    return null;
  }

  /// Lesson directly after the current one in the curriculum order, or
  /// `null` if the current lesson is the last one. Drives the
  /// "Coming next: …" hero copy when the current lesson is finished.
  _CurriculumEntry? get _nextAfterCurrent {
    final cur = _currentLesson;
    if (cur == null) return null;
    final i = _curriculum.indexWhere((e) => e.id == cur.id);
    if (i < 0 || i >= _curriculum.length - 1) return null;
    return _curriculum[i + 1];
  }

  @override
  void initState() {
    super.initState();
    _resolveInitialView();
  }

  // Wave 8 (legacy drop): auth is mandatory — every build constructs an
  // AuthClient, hydrates from secure storage, and either bypasses the
  // sign-in gate (returning user with a live refresh token) or shows it.
  // Skip-for-now still lands the learner on the dashboard but does so
  // through a silent stub-login under a stable per-install subject, so
  // every subsequent request — including server-owned lesson sessions —
  // carries an Authorization header.
  Future<void> _resolveInitialView() async {
    final seen = await LocalProgressStore.hasSeenOnboarding();
    _authClient ??= AuthClient(baseUrl: AppConfig.apiBaseUrl);
    final tokens = await _authClient!.hydrateFromStorage();
    if (!mounted) return;
    if (tokens == null) {
      setState(() {
        _showSignIn = true;
        _showOnboarding = !seen;
        _resolving = false;
      });
      return;
    }
    // Returning user with a live refresh token — point the engine
    // facades and the ApiClient at the remote backend before the
    // dashboard reads from them. No bulk-import here: that only fires
    // on the `signedIn` outcome of a fresh sign-in below.
    _activateAuthenticatedClients();
    if (!mounted) return;
    setState(() {
      _showOnboarding = !seen;
      _resolving = false;
    });
    if (seen) {
      await _loadDashboard();
    }
  }

  void _activateAuthenticatedClients() {
    final auth = _authClient;
    if (auth == null) return;
    LearnerSkillStore.useRemote(
      authClient: auth,
      baseUrl: AppConfig.apiBaseUrl,
    );
    ReviewScheduler.useRemote(
      authClient: auth,
      baseUrl: AppConfig.apiBaseUrl,
    );
    // ApiClient also gets the AuthClient injected so server-owned
    // lesson sessions (Wave 7.2) and authenticated answer / result
    // endpoints work end-to-end.
    context.read<ApiClient>().attachAuth(auth);
  }

  /// Wave 7.4 part 2.4 + Wave 8 — handles the SignInScreen outcome.
  ///
  /// On the explicit `signedIn` outcome (Apple stub or real Apple
  /// later) we run the bulk-migration of any device-scoped state
  /// (idempotent server-side) and switch the engine facades to the
  /// remote backend. The migrator already calls `useRemote(...)` for
  /// both stores; we additionally attach the AuthClient to the
  /// `ApiClient` so server-owned lesson sessions work.
  ///
  /// On `skipped` (now a silent stub-login per Wave 8 — see
  /// SignInScreen._skip) we still want the same authenticated
  /// connection, but we skip the migrator: the learner explicitly
  /// declined the merge, so any device-scoped progress stays local
  /// (and inert once the facades flip). Engine writes from this point
  /// on hit the server.
  Future<void> _onSignInResolved(SignInOutcome outcome) async {
    final auth = _authClient;
    if (auth != null) {
      if (outcome == SignInOutcome.signedIn) {
        final migrator = LearnerStateMigrator(
          authClient: auth,
          baseUrl: AppConfig.apiBaseUrl,
        );
        await migrator.migrate();
      } else {
        // Skipped: still flip facades to remote so subsequent writes
        // target the server. The local rows from earlier guest sessions
        // become inert.
        LearnerSkillStore.useRemote(
          authClient: auth,
          baseUrl: AppConfig.apiBaseUrl,
        );
        ReviewScheduler.useRemote(
          authClient: auth,
          baseUrl: AppConfig.apiBaseUrl,
        );
      }
      _activateAuthenticatedClients();
    }
    final seen = await LocalProgressStore.hasSeenOnboarding();
    if (!mounted) return;
    setState(() {
      _showSignIn = false;
      _showOnboarding = !seen;
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

    // Wave 4 review-due lookup runs in parallel with the lesson list
    // fetch so the dashboard isn't gated on the network for engine state.
    final dueFuture = ReviewScheduler.dueAt(DateTime.now().toUtc());
    final api = context.read<ApiClient>();

    try {
      final summaries = await api.fetchLessons();
      final entries = <_CurriculumEntry>[];
      for (final s in summaries) {
        final total = s.totalExercises ??
            // Older backend that doesn't yet emit total_exercises:
            // fall back to the per-lesson detail fetch so we still
            // know the right denominator. After the Wave-list backend
            // ships everywhere this branch is dead.
            (await api.getLesson(s.id)).exercises.length;
        final completed = await LocalProgressStore.getCompletedExercises(s.id);
        entries.add(_CurriculumEntry(
          id: s.id,
          title: s.title,
          totalExercises: total,
          completedExercises: completed.clamp(0, total),
        ));
      }
      final due = await dueFuture;
      if (!mounted) return;
      setState(() {
        _curriculum = entries;
        _dueReviews = due;
        _isLoadingDashboard = false;
      });
      // Level lookup is best-effort — a transient detail-endpoint
      // failure must not wipe the multi-lesson curriculum we just
      // loaded successfully. Default `_selectedLevel` ("B2") covers
      // every shipped lesson today; mixed-level units pick up their
      // own level when this resolves.
      if (entries.isNotEmpty) {
        try {
          final first = await api.getLesson(entries.first.id);
          if (!mounted) return;
          setState(() => _selectedLevel = first.level);
        } catch (_) {
          // keep the existing default
        }
      }
    } catch (_) {
      // Network unavailable: fall back to whatever local progress we
      // have for the legacy default lesson so the dashboard still
      // renders something sensible. The API will rebuild the list on
      // the next reload.
      final localCompleted = await LocalProgressStore.getCompletedExercises(
        AppConfig.defaultLessonId,
      );
      final due = await dueFuture;
      if (!mounted) return;
      setState(() {
        _curriculum = [
          _CurriculumEntry(
            id: AppConfig.defaultLessonId,
            title: 'Lesson',
            totalExercises: 10,
            completedExercises: localCompleted.clamp(0, 10),
          ),
        ];
        _dueReviews = due;
        _isLoadingDashboard = false;
      });
    }
  }

  Future<void> _startLesson(String lessonId) async {
    await Navigator.of(context).push(
      MasteryFadeRoute(
        builder: (_) => LessonIntroScreen(lessonId: lessonId),
      ),
    );
    if (!mounted) return;
    await _loadDashboard();
  }

  /// Wave 11.3 — V1 dynamic-session entry. The server-side Decision
  /// Engine assembles the run from the bank, so the dashboard CTA no
  /// longer threads a `lessonId` through. `LessonIntroScreen` reads
  /// the null-id branch and calls `loadDynamicSession()` on the
  /// freshly-constructed controller.
  Future<void> _startDynamicSession() async {
    await Navigator.of(context).push(
      MasteryFadeRoute(
        builder: (_) => const LessonIntroScreen(),
      ),
    );
    if (!mounted) return;
    await _loadDashboard();
  }

  void _openLastLessonSummary({bool toMistakes = false}) {
    final record = LastLessonStore.instance.record;
    if (record == null) return;
    Navigator.of(context).push(
      MasteryFadeRoute(
        builder: (_) => SummaryScreen(
          correctCount: record.correctCount,
          totalCount: record.totalExercises,
          summary: null, // record holds the headline data; SummaryScreen
          // re-renders via correct/total. The full LessonResultResponse
          // (with mistake list) is intentionally NOT carried — see tech
          // debt note in docs/plans/roadmap.md "Persistent Last Lesson
          // Report". `toMistakes` is honoured when summary is non-null.
          initialScrollToMistakes: toMistakes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_resolving) {
      return Scaffold(
        backgroundColor: context.masteryTokens.bgApp,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    // Wave 7.4 part 2.3 — sign-in gate runs before onboarding when
    // AppConfig.authEnabled is on and the device has no valid refresh
    // token. Bypassed for the legacy unauthenticated build.
    if (_showSignIn && _authClient != null) {
      return SignInScreen(
        authClient: _authClient!,
        onResolved: _onSignInResolved,
      );
    }
    if (_showOnboarding) {
      return OnboardingArrivalRitualScreen(
        onComplete: _completeOnboarding,
      );
    }
    return ListenableBuilder(
      listenable: LastLessonStore.instance,
      builder: (context, _) => _buildDashboard(),
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // Dashboard — Study Desk (docs/plans/dashboard-study-desk.md)
  // ────────────────────────────────────────────────────────────────────────

  Widget _buildDashboard() {
    final tokens = context.masteryTokens;
    final lastRecord = LastLessonStore.instance.record;

    return Scaffold(
      backgroundColor: tokens.bgApp,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              MasterySpacing.lg, 16, MasterySpacing.lg, MasterySpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _DashboardHeader(),
              const SizedBox(height: 18),
              _NextLessonHero(
                // Wave 11.3 — V1 dynamic frame. The hero no longer points
                // at a single lesson fixture; the Decision Engine
                // assembles each session from the bank.
                lessonTitle: 'Today\u2019s session',
                level: _selectedLevel,
                totalExercises: 10,
                completedExercises: 0,
                isLoading: _isLoadingDashboard,
                // Wave 11.3: lessonHasNext is meaningless under dynamic
                // sessions; the V1 hero copy ignores it. Pass `true` so
                // the legacy "no next lesson" placeholder never fires.
                lessonHasNext: true,
                // Wave 11.3 — CTA always boots a V1 dynamic session. The
                // legacy `_startLesson(lessonId)` path stays in the codebase
                // for tests and a possible roll-back, but the dashboard no
                // longer routes through it.
                onStart: _startDynamicSession,
              ),
              if (lastRecord != null) ...[
                const SizedBox(height: 22),
                _LastLessonReport(
                  record: lastRecord,
                  onReviewMistakes: () =>
                      _openLastLessonSummary(toMistakes: true),
                  onOpenFullSummary: () => _openLastLessonSummary(),
                ),
              ],
              if (_dueReviews.isNotEmpty) ...[
                const SizedBox(height: 22),
                ReviewDueSection(
                  dueReviews: _dueReviews,
                  now: DateTime.now().toUtc(),
                ),
              ],
              const SizedBox(height: 22),
              _CurrentUnitBlock(
                curriculum: _curriculum,
                currentLessonId: _currentLesson?.id,
              ),
              const SizedBox(height: 22),
              const _PremiumBlock(),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'STUDY DESK',
                style: MasteryTextStyles.mono(
                  size: 11,
                  lineHeight: 14,
                  weight: FontWeight.w600,
                  color: tokens.textTertiary,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _greeting,
                style: MasteryTextStyles.headlineMd.copyWith(
                  fontFamily: 'Fraunces',
                  fontSize: 28,
                  height: 32 / 28,
                  fontWeight: FontWeight.w600,
                  color: MasteryColors.textPrimary,
                  letterSpacing: -0.4,
                  fontVariations: const [
                    FontVariation('opsz', 144),
                    FontVariation('wght', 600),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Your next lesson is ready, your last result is close at hand.',
                style: MasteryTextStyles.bodySm.copyWith(
                  color: MasteryColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Row(
            children: const [
              _LevelTrigger(level: 'B2'),
              SizedBox(width: 10),
              _Avatar(),
            ],
          ),
        ),
      ],
    );
  }
}

class _LevelTrigger extends StatelessWidget {
  final String level;
  const _LevelTrigger({required this.level});

  Future<void> _show(BuildContext context) async {
    final tokens = context.masteryTokens;
    await showMenu<void>(
      context: context,
      position: const RelativeRect.fromLTRB(140, 110, 16, 0),
      color: MasteryColors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MasteryRadii.md),
        side: BorderSide(color: tokens.borderSoft),
      ),
      elevation: 6,
      items: const [
        _LevelMenuItem(label: 'A2', state: _LevelState.locked),
        _LevelMenuItem(label: 'B1', state: _LevelState.locked),
        _LevelMenuItem(label: 'B2', state: _LevelState.current),
        _LevelMenuItem(label: 'C1', state: _LevelState.locked),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(MasteryRadii.pill),
        onTap: () => _show(context),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: MasteryColors.bgSurface,
            border: Border.all(color: tokens.borderSoft),
            borderRadius: BorderRadius.circular(MasteryRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: MasteryColors.actionPrimary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                level,
                style: MasteryTextStyles.labelMd.copyWith(
                  color: MasteryColors.textPrimary,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 16, color: tokens.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

enum _LevelState { current, locked }

class _LevelMenuItem extends PopupMenuEntry<void> {
  final String label;
  final _LevelState state;

  const _LevelMenuItem({required this.label, required this.state});

  @override
  double get height => 40;

  @override
  bool represents(void value) => false;

  @override
  State<_LevelMenuItem> createState() => _LevelMenuItemState();
}

class _LevelMenuItemState extends State<_LevelMenuItem> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final isCurrent = widget.state == _LevelState.current;
    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Text(
            widget.label,
            style: MasteryTextStyles.labelMd.copyWith(
              color: isCurrent
                  ? MasteryColors.actionPrimaryPressed
                  : MasteryColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            isCurrent ? 'Current' : 'Locked',
            style: MasteryTextStyles.mono(
              size: 10,
              lineHeight: 12,
              weight: FontWeight.w500,
              color: tokens.textTertiary,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tokens.bgPrimarySoft,
            MasteryColors.actionPrimary,
          ],
        ),
        border: Border.all(color: tokens.borderSoft),
        shape: BoxShape.circle,
        boxShadow: tokens.shadowCard,
      ),
      child: Text(
        'M',
        style: MasteryTextStyles.labelMd.copyWith(
          color: MasteryColors.bgSurface,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Next Lesson Hero
// ─────────────────────────────────────────────────────────────────────────

class _NextLessonHero extends StatelessWidget {
  final String lessonTitle;
  final String level;
  final int totalExercises;
  final int completedExercises;
  final bool isLoading;

  /// True when there is a real next lesson to launch after the current
  /// one is finished. The dashboard now reads this from the live
  /// `/lessons` curriculum, so the CTA enables itself the moment the
  /// backend ships another lesson — no client redeploy needed.
  final bool lessonHasNext;

  /// Null when no shipped lesson is ready to start (full curriculum
  /// finished). The CTA becomes inactive in that branch.
  final VoidCallback? onStart;

  const _NextLessonHero({
    required this.lessonTitle,
    required this.level,
    required this.totalExercises,
    required this.completedExercises,
    required this.isLoading,
    required this.lessonHasNext,
    required this.onStart,
  });

  bool get _isFinished =>
      totalExercises > 0 && completedExercises >= totalExercises;

  String get _ctaLabel {
    if (_isFinished) return 'Start next lesson';
    return completedExercises > 0 ? 'Continue lesson' : 'Start lesson';
  }

  String get _promise {
    if (_isFinished) {
      return 'Next lesson in this unit is on the way. Until then, your last result is below.';
    }
    return 'Stay focused on one rule, finish the set, and the dashboard remembers your run.';
  }

  String _estimatedTime(int n) {
    if (n <= 0) return '~5 min';
    final minutes = (n * 0.5).ceil();
    return '~$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final progress = totalExercises == 0
        ? 0.0
        : (completedExercises / totalExercises).clamp(0.0, 1.0);
    // Wave 11.3 — the V1 dynamic CTA never runs out of content (the
    // Decision Engine always finds something in the bank), so the CTA
    // is enabled whenever the dashboard is not in its loading state.
    // The legacy "lesson is finished + no next lesson" gate is dead.
    final canStart = !isLoading && onStart != null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            tokens.bgPrimarySoft.withAlpha(110),
            MasteryColors.bgRaised,
          ],
          stops: const [0.0, 0.65],
        ),
        border: Border.all(color: MasteryColors.actionPrimary.withAlpha(40)),
        borderRadius: BorderRadius.circular(MasteryRadii.xl),
        boxShadow: tokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: SectionEyebrow(
                  label: 'Unit 01',
                  variant: SectionEyebrowVariant.gold,
                ),
              ),
              TagPill(label: level),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            // _isFinished only fires here when the entire shipped
            // curriculum is done — `_currentLesson` is null and the
            // hero fell back to the last lesson. The copy stays
            // agnostic about the lesson number because we have N
            // lessons now, not exactly two.
            _isFinished ? 'Coming next: more on the way' : lessonTitle,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 28,
              height: 34 / 28,
              fontWeight: FontWeight.w600,
              color: MasteryColors.textPrimary,
              letterSpacing: -0.4,
              fontVariations: const [
                FontVariation('opsz', 144),
                FontVariation('wght', 600),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _MetaRow(
            entries: [
              '$totalExercises exercises',
              _estimatedTime(totalExercises),
              _isFinished ? 'On the way' : 'Next lesson',
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _promise,
            style: MasteryTextStyles.bodyMd.copyWith(
              color: MasteryColors.textPrimary,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 18),
          _ProgressCluster(
            label: 'Lesson progress',
            current: completedExercises,
            total: totalExercises,
            progress: progress,
            isLoading: isLoading,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: canStart ? onStart : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            child: Text(_ctaLabel),
          ),
          if (_isFinished && !lessonHasNext) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                'New lesson arrives once it lands in the curriculum.',
                style: MasteryTextStyles.bodySm.copyWith(
                  color: MasteryColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final List<String> entries;
  const _MetaRow({required this.entries});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final children = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      children.add(Text(
        entries[i],
        style: MasteryTextStyles.bodySm.copyWith(
          color: MasteryColors.textSecondary,
        ),
      ));
      if (i < entries.length - 1) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: tokens.textTertiary,
              shape: BoxShape.circle,
            ),
          ),
        ));
      }
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

class _ProgressCluster extends StatelessWidget {
  final String label;
  final int current;
  final int total;
  final double progress;
  final bool isLoading;

  const _ProgressCluster({
    required this.label,
    required this.current,
    required this.total,
    required this.progress,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final fraction = isLoading ? '— / $total' : '$current / $total';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: MasteryColors.bgRaised,
        border: Border.all(color: tokens.borderSoft),
        borderRadius: BorderRadius.circular(MasteryRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: MasteryTextStyles.mono(
                    size: 11,
                    lineHeight: 14,
                    weight: FontWeight.w600,
                    color: MasteryColors.textSecondary,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: tokens.bgPrimarySoft,
                  borderRadius: BorderRadius.circular(MasteryRadii.pill),
                ),
                child: Text(
                  fraction,
                  style: MasteryTextStyles.mono(
                    size: 12,
                    lineHeight: 14,
                    weight: FontWeight.w600,
                    color: MasteryColors.actionPrimaryPressed,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(MasteryRadii.pill),
            child: SizedBox(
              height: 10,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: tokens.bgSurfaceAlt,
                valueColor: const AlwaysStoppedAnimation(
                    MasteryColors.actionPrimary),
                minHeight: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Last Lesson Report
// ─────────────────────────────────────────────────────────────────────────

class _LastLessonReport extends StatelessWidget {
  final LastLessonRecord record;
  final VoidCallback onReviewMistakes;
  final VoidCallback onOpenFullSummary;

  const _LastLessonReport({
    required this.record,
    required this.onReviewMistakes,
    required this.onOpenFullSummary,
  });

  String _whenText(DateTime t) {
    final now = DateTime.now();
    if (now.year == t.year && now.month == t.month && now.day == t.day) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (yesterday.year == t.year &&
        yesterday.month == t.month &&
        yesterday.day == t.day) {
      return 'Yesterday';
    }
    return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final debrief = record.debrief;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'LAST LESSON REPORT',
                style: MasteryTextStyles.mono(
                  size: 11,
                  lineHeight: 14,
                  weight: FontWeight.w600,
                  color: MasteryColors.textSecondary,
                  letterSpacing: 1.6,
                ),
              ),
            ),
            TextButton(
              onPressed: onOpenFullSummary,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 32),
              ),
              child: Text(
                'Open full summary',
                style: MasteryTextStyles.labelSm.copyWith(
                  color: MasteryColors.actionPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: MasteryColors.bgRaised,
            border: Border.all(color: tokens.borderSoft),
            borderRadius: BorderRadius.circular(MasteryRadii.lg),
            boxShadow: tokens.shadowCard,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionEyebrow(
                          label: 'Lesson completed',
                          variant: SectionEyebrowVariant.gold,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          record.lessonTitle,
                          style: MasteryTextStyles.titleSm.copyWith(
                            color: MasteryColors.textPrimary,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_whenText(record.completedAt)} · '
                          '${record.totalExercises} exercises · '
                          '${record.mistakesCount} ${record.mistakesCount == 1 ? "mistake" : "mistakes"}',
                          style: MasteryTextStyles.bodySm.copyWith(
                            color: MasteryColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _ScorePill(
                    correct: record.correctCount,
                    total: record.totalExercises,
                  ),
                ],
              ),
              if (debrief != null && debrief.headline.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  debrief.headline,
                  style: MasteryTextStyles.bodyMd.copyWith(
                    color: MasteryColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (debrief.body.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    debrief.body,
                    style: MasteryTextStyles.bodySm.copyWith(
                      color: MasteryColors.textPrimary,
                      height: 1.55,
                    ),
                  ),
                ],
                if (debrief.watchOut != null &&
                    debrief.watchOut!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: tokens.bgPrimarySoft.withAlpha(120),
                      borderRadius: BorderRadius.circular(MasteryRadii.sm),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WATCH OUT',
                          style: MasteryTextStyles.mono(
                            size: 10,
                            lineHeight: 12,
                            weight: FontWeight.w600,
                            color: tokens.accentGoldDeep,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            debrief.watchOut!,
                            style: MasteryTextStyles.bodySm.copyWith(
                              color: MasteryColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReviewMistakes,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        side: BorderSide(color: tokens.borderStrong),
                      ),
                      child: const Text('Review mistakes'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextButton(
                      onPressed: onOpenFullSummary,
                      style: TextButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: const Text('See full report'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScorePill extends StatelessWidget {
  final int correct;
  final int total;
  const _ScorePill({required this.correct, required this.total});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: tokens.accentGoldSoft.withAlpha(140),
        border: Border.all(color: tokens.accentGold.withAlpha(60)),
        borderRadius: BorderRadius.circular(MasteryRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$correct / $total',
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 22,
              height: 1.0,
              fontWeight: FontWeight.w600,
              color: tokens.accentGoldDeep,
              fontVariations: const [
                FontVariation('opsz', 144),
                FontVariation('wght', 600),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'SCORE',
            style: MasteryTextStyles.mono(
              size: 10,
              lineHeight: 12,
              weight: FontWeight.w600,
              color: tokens.accentGoldDeep,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Current Unit
// ─────────────────────────────────────────────────────────────────────────

class _CurrentUnitBlock extends StatelessWidget {
  /// Curriculum to render — one row per lesson, in `/lessons` order.
  final List<_CurriculumEntry> curriculum;

  /// `id` of the lesson the hero is currently pointing at (the first
  /// un-finished). The matching row gets the `current` badge; rows
  /// before it are `done`, rows after are `locked`.
  final String? currentLessonId;

  const _CurrentUnitBlock({
    required this.curriculum,
    required this.currentLessonId,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final rows = <Widget>[];
    var currentReached = false;
    for (var i = 0; i < curriculum.length; i++) {
      final entry = curriculum[i];
      final isCurrent =
          currentLessonId != null && entry.id == currentLessonId;
      final state = entry.isDone
          ? StatusBadgeVariant.done
          : isCurrent
              ? StatusBadgeVariant.current
              : currentReached
                  ? StatusBadgeVariant.locked
                  : StatusBadgeVariant.current;
      final meta = entry.isDone
          ? 'Completed · ${entry.totalExercises} exercises'
          : isCurrent
              ? 'Current lesson · ${entry.totalExercises} exercises'
              : currentReached
                  ? 'Coming up · ${entry.totalExercises} exercises'
                  : '${entry.totalExercises} exercises';
      if (isCurrent) currentReached = true;
      rows.add(_UnitRow(
        ordinal: (i + 1).toString().padLeft(2, '0'),
        title: entry.title,
        meta: meta,
        state: state,
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'CURRENT UNIT',
                style: MasteryTextStyles.mono(
                  size: 11,
                  lineHeight: 14,
                  weight: FontWeight.w600,
                  color: MasteryColors.textSecondary,
                  letterSpacing: 1.6,
                ),
              ),
            ),
            const _AllUnitsTrigger(),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          decoration: BoxDecoration(
            color: MasteryColors.bgRaised,
            border: Border.all(color: tokens.borderSoft),
            borderRadius: BorderRadius.circular(MasteryRadii.lg),
            boxShadow: tokens.shadowCard,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionEyebrow(
                label: 'Unit 01',
                variant: SectionEyebrowVariant.secondary,
              ),
              const SizedBox(height: 6),
              Text(
                'Verb patterns',
                style: MasteryTextStyles.titleSm.copyWith(
                  color: MasteryColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'A textbook sequence on verbs that change the form of what follows them.',
                style: MasteryTextStyles.bodySm.copyWith(
                  color: MasteryColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                _UnitRow(
                  ordinal: '01',
                  title: 'Lessons loading…',
                  meta: '—',
                  state: StatusBadgeVariant.locked,
                )
              else
                ...rows,
            ],
          ),
        ),
      ],
    );
  }
}

class _UnitRow extends StatelessWidget {
  final String ordinal;
  final String title;
  final String meta;
  final StatusBadgeVariant state;

  const _UnitRow({
    required this.ordinal,
    required this.title,
    required this.meta,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final (numBg, numFg, numBorder) = switch (state) {
      StatusBadgeVariant.done => (
          tokens.success.withAlpha(28),
          tokens.success,
          tokens.success.withAlpha(40),
        ),
      StatusBadgeVariant.current => (
          tokens.bgPrimarySoft,
          MasteryColors.actionPrimaryPressed,
          MasteryColors.actionPrimary.withAlpha(46),
        ),
      StatusBadgeVariant.locked => (
          tokens.bgSurfaceAlt,
          MasteryColors.textTertiary,
          tokens.borderSoft,
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: numBg,
              border: Border.all(color: numBorder),
              shape: BoxShape.circle,
            ),
            child: Text(
              ordinal,
              style: MasteryTextStyles.mono(
                size: 11,
                lineHeight: 12,
                weight: FontWeight.w600,
                color: numFg,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: MasteryTextStyles.bodyMd.copyWith(
                    color: MasteryColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  style: MasteryTextStyles.bodySm.copyWith(
                    color: MasteryColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          StatusBadge(
            label: switch (state) {
              StatusBadgeVariant.done => 'Done',
              StatusBadgeVariant.current => 'Current',
              StatusBadgeVariant.locked => 'Locked',
            },
            variant: state,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// All-units trigger — small affordance in the Current Unit header that
// opens a popup of future units. Replaces the "Coming Next" block per the
// product call to tuck future content away (mirrors the level-dropdown
// pattern). Future units are stubs until multi-unit backend lands.
// ─────────────────────────────────────────────────────────────────────────

class _AllUnitsTrigger extends StatelessWidget {
  const _AllUnitsTrigger();

  Future<void> _show(BuildContext context) async {
    final tokens = context.masteryTokens;
    await showMenu<void>(
      context: context,
      position: const RelativeRect.fromLTRB(140, 360, 16, 0),
      color: MasteryColors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MasteryRadii.md),
        side: BorderSide(color: tokens.borderSoft),
      ),
      elevation: 6,
      items: const [
        _UnitMenuItem(
          ordinal: '01',
          title: 'Verb patterns',
          state: _UnitMenuState.current,
        ),
        _UnitMenuItem(
          ordinal: '02',
          title: 'Time & completed actions',
          state: _UnitMenuState.locked,
        ),
        _UnitMenuItem(
          ordinal: '03',
          title: 'Conditionals',
          state: _UnitMenuState.locked,
        ),
        _UnitMenuItem(
          ordinal: '04',
          title: 'Reported speech',
          state: _UnitMenuState.locked,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(MasteryRadii.pill),
        onTap: () => _show(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: MasteryColors.bgSurface,
            border: Border.all(color: tokens.borderSoft),
            borderRadius: BorderRadius.circular(MasteryRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'All units',
                style: MasteryTextStyles.labelSm.copyWith(
                  color: MasteryColors.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 14, color: tokens.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

enum _UnitMenuState { current, locked }

class _UnitMenuItem extends PopupMenuEntry<void> {
  final String ordinal;
  final String title;
  final _UnitMenuState state;

  const _UnitMenuItem({
    required this.ordinal,
    required this.title,
    required this.state,
  });

  @override
  double get height => 48;

  @override
  bool represents(void value) => false;

  @override
  State<_UnitMenuItem> createState() => _UnitMenuItemState();
}

class _UnitMenuItemState extends State<_UnitMenuItem> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final isCurrent = widget.state == _UnitMenuState.current;
    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              widget.ordinal,
              style: MasteryTextStyles.mono(
                size: 11,
                lineHeight: 12,
                weight: FontWeight.w600,
                color: tokens.textTertiary,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.title,
              style: MasteryTextStyles.labelMd.copyWith(
                color: isCurrent
                    ? MasteryColors.actionPrimaryPressed
                    : MasteryColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isCurrent ? 'Current' : 'Locked',
            style: MasteryTextStyles.mono(
              size: 10,
              lineHeight: 12,
              weight: FontWeight.w500,
              color: tokens.textTertiary,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Premium block (visual stub — no monetisation in MVP)
// ─────────────────────────────────────────────────────────────────────────

class _PremiumBlock extends StatelessWidget {
  const _PremiumBlock();

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: tokens.accentGoldSoft.withAlpha(80),
        border: Border.all(color: tokens.accentGold.withAlpha(80)),
        borderRadius: BorderRadius.circular(MasteryRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionEyebrow(
            label: 'Premium',
            variant: SectionEyebrowVariant.gold,
          ),
          const SizedBox(height: 8),
          Text(
            'Unlock the full B2 course path',
            style: MasteryTextStyles.titleSm.copyWith(
              color: MasteryColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Quiet by design. Premium will extend the path, never interrupt it.',
            style: MasteryTextStyles.bodySm.copyWith(
              color: MasteryColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
