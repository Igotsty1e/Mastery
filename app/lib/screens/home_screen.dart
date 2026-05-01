// HomeScreen — first-launch routes through the Arrival Ritual onboarding;
// the dashboard is the single Home for every other launch.
//
// Order on the dashboard:
//   1. header (level dropdown trigger only — greeting + sub + avatar removed
//      in the automaticity pivot Wave 0 cleanup)
//   2. next-lesson hero
//   3. review-due section (when ReviewScheduler has due skills)
//   4. rules trigger (button → modal listing skills + per-skill rules)
//   5. premium block (visual stub — no monetisation in MVP)

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../auth/auth_client.dart';
import '../config.dart';
import '../learner/learner_skill_store.dart';
import '../learner/learner_state_migrator.dart';
import '../learner/review_scheduler.dart';
import '../learner/skill_catalog.dart';
import '../progress/local_progress_store.dart';
import '../analytics/analytics.dart';
import '../theme/mastery_theme.dart';
import '../widgets/mastery_route.dart';
import '../widgets/mastery_widgets.dart';
import '../widgets/review_due_section.dart';
import '../widgets/skill_status_badge.dart';
import 'diagnostic_screen.dart';
import 'lesson_intro_screen.dart';
import 'onboarding_arrival_ritual_screen.dart';
import 'sign_in_screen.dart';

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
  /// Wave 12.3 — diagnostic-mode gate. Sits between the sign-in gate
  /// and the onboarding ritual. Detection: after sign-in, if the
  /// learner has not skipped the diagnostic on this device AND the
  /// server has no level set for them yet, surface the probe.
  bool _showDiagnostic = false;
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

  /// Wave 14 (V1.5 Skill-progress UI) — per-skill mastery state for
  /// the Rules card on the dashboard. Indexed by `skillId` so the
  /// `_RulesCard` lookup is O(1). Populated on `_loadDashboard` from
  /// `LearnerSkillStore.allRecords()` (server-backed once auth is
  /// active). A skill the learner has not touched yet is absent from
  /// the map and its row renders without a status chip.
  Map<String, LearnerSkillRecord> _skillRecords = const {};

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
      // Wave G5 — silent stub-login for first-time visitors. The
      // public web build does not surface a sign-in screen any
      // more; we mint a stable per-device subject the first time
      // we see a fresh browser, re-use it on every later visit,
      // and proceed straight to onboarding / dashboard. Only
      // hard failures (no network) fall back to the explicit
      // SignInScreen as a safety net.
      try {
        final subject = await _stableStubSubject();
        await _authClient!.signInWithAppleStub(subject: subject);
        if (!mounted) return;
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _showSignIn = true;
          _showOnboarding = !seen;
          _resolving = false;
        });
        return;
      }
    }
    // Returning user with a live refresh token — point the engine
    // facades and the ApiClient at the remote backend before the
    // dashboard reads from them. No bulk-import here: that only fires
    // on the `signedIn` outcome of a fresh sign-in below.
    _activateAuthenticatedClients();
    final showDiagnostic = await _shouldShowDiagnostic();
    if (!mounted) return;
    setState(() {
      _showDiagnostic = showDiagnostic;
      _showOnboarding = !seen;
      _resolving = false;
    });
    if (!showDiagnostic && seen) {
      await _loadDashboard();
    }
  }

  /// Wave G5 — same stable per-install subject as `SignInScreen`
  /// uses on its (now rarely-shown) Skip path. Living here so the
  /// silent auto-skip in `_resolveInitialView` does not import
  /// `SignInScreen` to fish out a private helper.
  static const _stubSubjectKey = 'mastery_stub_subject_v1';

  Future<String> _stableStubSubject() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_stubSubjectKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final fresh = 'stub-$now';
    await prefs.setString(_stubSubjectKey, fresh);
    return fresh;
  }

  /// Wave 12.3 — diagnostic gate detection. Surface the probe when:
  /// 1. the learner has not skipped the diagnostic on this device
  ///    (`LocalProgressStore.hasSkippedDiagnostic`), AND
  /// 2. the server has no level set on `user_profiles.level` (the
  ///    diagnostic /complete stamps it; null means never run).
  ///
  /// Both checks tolerate failures by returning `false` — the
  /// onboarding ritual is still a coherent fallback if the gate
  /// cannot decide.
  Future<bool> _shouldShowDiagnostic() async {
    try {
      final skipped = await LocalProgressStore.hasSkippedDiagnostic();
      if (skipped) return false;
      final api = context.read<ApiClient>();
      final level = await api.getMyLevel();
      return level == null || level.isEmpty;
    } catch (_) {
      return false;
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
    final showDiagnostic = await _shouldShowDiagnostic();
    if (!mounted) return;
    setState(() {
      _showSignIn = false;
      _showDiagnostic = showDiagnostic;
      _showOnboarding = !seen;
    });
    if (!showDiagnostic && seen) {
      await _loadDashboard();
    }
  }

  /// Wave 12.3 — diagnostic CTA contract. Both Begin→Complete and
  /// Skip-for-now land here; the diagnostic is additive to the
  /// onboarding ritual, never a replacement, so we flip the gate off
  /// and let the onboarding flow take over. The skip path has already
  /// written `LocalProgressStore.diagnosticSkipped` and fired the
  /// `diagnostic_skipped` audit event by the time this runs; the
  /// complete path has stamped `user_profiles.level` server-side.
  Future<void> _completeDiagnostic() async {
    if (!mounted) return;
    setState(() => _showDiagnostic = false);
    final seen = await LocalProgressStore.hasSeenOnboarding();
    if (!mounted) return;
    setState(() => _showOnboarding = !seen);
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
    Analytics.trackScreen('dashboard');
    setState(() => _isLoadingDashboard = true);

    // Wave 4 review-due lookup runs in parallel with the lesson list
    // fetch so the dashboard isn't gated on the network for engine state.
    final dueFuture = ReviewScheduler.dueAt(DateTime.now().toUtc());
    // Wave 14 (V1.5 Skill-progress UI) — fetch per-skill records in
    // parallel for the Rules card status badges.
    final recordsFuture = LearnerSkillStore.allRecords();
    // Wave 12.7 — populate the SkillCatalog (display names + per-skill
    // rule snapshots) in parallel with the lesson list fetch. Failures
    // are swallowed inside refresh(); the hardcoded fallback in
    // skill_titles.dart keeps existing surfaces readable until the
    // next successful refresh.
    unawaited(SkillCatalog.instance.refresh(baseUrl: AppConfig.apiBaseUrl));
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
      final records = await recordsFuture;
      if (!mounted) return;
      setState(() {
        _curriculum = entries;
        _dueReviews = due;
        _skillRecords = {for (final r in records) r.skillId: r};
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
      final records = await recordsFuture;
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
        _skillRecords = {for (final r in records) r.skillId: r};
        _isLoadingDashboard = false;
      });
    }
  }

  /// Wave 11.3 — V1 dynamic-session entry. The server-side Decision
  /// Engine assembles the run from the bank, so the dashboard CTA no
  /// longer threads a `lessonId` through. `LessonIntroScreen` reads
  /// the null-id branch and calls `loadDynamicSession()` on the
  /// freshly-constructed controller.
  Future<void> _startDynamicSession() async {
    Analytics.trackButton('start_lesson', screen: 'dashboard');
    await Navigator.of(context).push(
      MasteryFadeRoute(
        builder: (_) => const LessonIntroScreen(),
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
    // Wave 7.4 part 2.3 — sign-in gate runs before onboarding when
    // AppConfig.authEnabled is on and the device has no valid refresh
    // token. Bypassed for the legacy unauthenticated build.
    if (_showSignIn && _authClient != null) {
      return SignInScreen(
        authClient: _authClient!,
        onResolved: _onSignInResolved,
      );
    }
    if (_showDiagnostic) {
      return DiagnosticScreen(
        apiClient: context.read<ApiClient>(),
        onComplete: _completeDiagnostic,
      );
    }
    if (_showOnboarding) {
      return OnboardingArrivalRitualScreen(
        onComplete: _completeOnboarding,
      );
    }
    return _buildDashboard();
  }

  // ────────────────────────────────────────────────────────────────────────
  // Dashboard
  //
  // The post-lesson report is still recorded in `LastLessonStore` and
  // persisted by the backend (`lesson_sessions.debrief_snapshot`), but
  // is intentionally not rendered here as part of the automaticity pivot
  // (Wave 0). The data stays available for the SummaryScreen surface and
  // for future engine-driven decisions; the dashboard itself stays lean.
  // ────────────────────────────────────────────────────────────────────────

  Widget _buildDashboard() {
    final tokens = context.masteryTokens;

    return Scaffold(
      backgroundColor: tokens.bgApp,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              MasterySpacing.lg, 16, MasterySpacing.lg, MasterySpacing.xl),
          child: Column(
            // Wave G8 — stretch so every block in the dashboard
            // (next-lesson hero, review-due, rules trigger,
            // premium block) shares the same horizontal span. The
            // pre-G8 .start mode let the Premium block shrink to
            // the width of its longest text line, which read as a
            // narrower box stuck under the wider blocks above it.
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                // CTA always boots a V1 dynamic session via
                // `_startDynamicSession`. The legacy lesson-bound
                // `_startLesson` flow was retired with the Wave 0
                // dead-code sweep; `LessonIntroScreen` keeps a
                // null-lessonId branch for the same dynamic flow.
                onStart: _startDynamicSession,
              ),
              if (_dueReviews.isNotEmpty) ...[
                const SizedBox(height: 22),
                ReviewDueSection(
                  dueReviews: _dueReviews,
                  now: DateTime.now().toUtc(),
                ),
              ],
              // Wave 11.4 — the curriculum / lessons-list block is gone.
              // The V1 dynamic flow assembles each session from the bank,
              // so a fixed unit listing no longer reflects what the
              // learner will see. Skill-progress UI is V1.5
              // (`docs/plans/learning-engine-v1.md` decision #12).
              // Rules — collapsed behind a trigger as part of the
              // automaticity pivot Wave 0. Tap → modal bottom sheet
              // listing every skill in the bank (title + CEFR chip +
              // status badge). Tapping a row inside the modal still
              // opens the per-skill rule sheet (`_RuleSheetBody`).
              const SizedBox(height: 22),
              ListenableBuilder(
                listenable: SkillCatalog.instance,
                builder: (context, _) =>
                    _RulesTrigger(records: _skillRecords),
              ),
              const SizedBox(height: 22),
              const _PremiumBlock(),
              // Wave 12.4 — diagnostic re-take affordance. Quiet text
              // link at the bottom; tapping pushes DiagnosticScreen
              // via MasteryFadeRoute. Skipping or completing pops back
              // here. The diagnostic always augments learner_skills,
              // never resets it (V1 spec §15).
              const SizedBox(height: 18),
              Center(
                child: TextButton(
                  onPressed: _openDiagnosticRetake,
                  child: Text(
                    'Re-run my level check',
                    style: MasteryTextStyles.labelMd.copyWith(
                      color: MasteryColors.textTertiary,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Wave 12.4 — pushes `DiagnosticScreen` via `MasteryFadeRoute` so a
  /// learner who Skip-for-now'd onboarding can come back to the probe
  /// later, or a returning learner can re-run it for a fresh CEFR
  /// reading. Both Begin→Complete and Skip-for-now pop back here.
  void _openDiagnosticRetake() {
    final api = context.read<ApiClient>();
    Navigator.of(context).push(
      MasteryFadeRoute<void>(
        builder: (_) => DiagnosticScreen(
          apiClient: api,
          onComplete: () => Navigator.of(context).maybePop(),
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

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerRight,
      child: _LevelTrigger(level: 'B2'),
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
// Rules trigger + library sheet (Wave 0 automaticity pivot)
//
// The Rules card used to render inline on the dashboard. To keep the
// dashboard lean, the rule list now lives behind a single trigger that
// opens a modal bottom sheet. The list of rules and the per-rule sheet
// (`_RulesRow`, `_RuleSheetBody`) are unchanged.
// ─────────────────────────────────────────────────────────────────────────

class _RulesTrigger extends StatelessWidget {
  /// Per-skill mastery records keyed by `skillId`. Forwarded into the
  /// modal so each row can render its `SkillStatusBadge`.
  final Map<String, LearnerSkillRecord> records;

  const _RulesTrigger({this.records = const {}});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final entries = SkillCatalog.instance.all;
    if (entries.isEmpty) {
      // Pre-fetch / offline: render nothing so the dashboard stays
      // calm. The trigger pops in once SkillCatalog completes refresh.
      return const SizedBox.shrink();
    }
    return InkWell(
      borderRadius: BorderRadius.circular(MasteryRadii.lg),
      onTap: () => _openLibrary(context),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        decoration: BoxDecoration(
          color: MasteryColors.bgRaised,
          border: Border.all(color: tokens.borderSoft),
          borderRadius: BorderRadius.circular(MasteryRadii.lg),
          boxShadow: tokens.shadowCard,
        ),
        child: Row(
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 22,
              color: MasteryColors.actionPrimary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rules',
                    style: MasteryTextStyles.titleSm.copyWith(
                      color: MasteryColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${entries.length} ${entries.length == 1 ? "rule" : "rules"} · tap to open the library',
                    style: MasteryTextStyles.bodySm.copyWith(
                      color: MasteryColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: tokens.textTertiary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  void _openLibrary(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MasteryColors.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MasteryRadii.lg),
        ),
      ),
      builder: (_) => _RulesLibrarySheet(records: records),
    );
  }
}

class _RulesLibrarySheet extends StatelessWidget {
  final Map<String, LearnerSkillRecord> records;

  const _RulesLibrarySheet({required this.records});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final entries = SkillCatalog.instance.all;
    final now = DateTime.now();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            MasterySpacing.lg,
            MasterySpacing.md,
            MasterySpacing.lg,
            MasterySpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: MasterySpacing.lg),
                  decoration: BoxDecoration(
                    color: tokens.borderSoft,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Rules',
                style: MasteryTextStyles.headlineLg.copyWith(
                  color: MasteryColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap a rule to read it. The badge shows where you are.',
                style: MasteryTextStyles.bodyMd.copyWith(
                  color: MasteryColors.textSecondary,
                ),
              ),
              const SizedBox(height: MasterySpacing.lg),
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: tokens.borderSoft,
                  ),
                _RulesRow(
                  entry: entries[i],
                  record: records[entries[i].skillId],
                  now: now,
                ),
              ],
              const SizedBox(height: MasterySpacing.lg),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(
                    'Close',
                    style: MasteryTextStyles.labelMd.copyWith(
                      color: MasteryColors.textSecondary,
                      letterSpacing: 0.4,
                    ),
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

class _RulesRow extends StatelessWidget {
  final SkillCatalogEntry entry;

  /// Wave 14 — null when the learner has never touched this skill.
  /// Present, even with zero attempts, when `LearnerSkillStore` has
  /// any record for it (status will be `started`).
  final LearnerSkillRecord? record;

  /// Wave 14 — anchor "now" passed in by the parent so derived status
  /// is consistent across rows in a single render. Tests can pass a
  /// fixed clock; production passes wall-clock.
  final DateTime now;

  const _RulesRow({
    required this.entry,
    required this.now,
    this.record,
  });

  bool get _hasRule =>
      entry.introRule != null && entry.introRule!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return InkWell(
      borderRadius: BorderRadius.circular(MasteryRadii.sm),
      onTap: _hasRule ? () => _openSheet(context) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 4,
          vertical: MasterySpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: MasteryTextStyles.bodyMd.copyWith(
                      color: MasteryColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (entry.description != null &&
                      entry.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.description!,
                      style: MasteryTextStyles.bodySm.copyWith(
                        color: MasteryColors.textTertiary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: MasterySpacing.md),
            // Wave 14 — status badge for skills the learner has touched.
            // Calm-tone pill; renders only when a record exists. Pinned
            // before the CEFR chip so the row reads as
            // "<title>  [<status>] [B2]" left-to-right.
            if (record != null) ...[
              SkillStatusBadge(record: record!, now: now),
              const SizedBox(width: 6),
            ],
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: tokens.bgPrimarySoft,
                borderRadius: BorderRadius.circular(MasteryRadii.pill),
              ),
              child: Text(
                entry.cefrLevel,
                style: MasteryTextStyles.labelSm.copyWith(
                  color: MasteryColors.actionPrimaryPressed,
                  letterSpacing: 0.4,
                ),
              ),
            ),
            if (_hasRule) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: tokens.textTertiary,
                size: 22,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MasteryColors.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MasteryRadii.lg),
        ),
      ),
      builder: (sheetCtx) => _RuleSheetBody(entry: entry),
    );
  }
}

class _RuleSheetBody extends StatelessWidget {
  final SkillCatalogEntry entry;

  const _RuleSheetBody({required this.entry});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            MasterySpacing.lg,
            MasterySpacing.lg,
            MasterySpacing.lg,
            MasterySpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: MasterySpacing.lg),
                  decoration: BoxDecoration(
                    color: tokens.borderSoft,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                entry.title,
                style: MasteryTextStyles.headlineLg.copyWith(
                  color: MasteryColors.textPrimary,
                ),
              ),
              const SizedBox(height: MasterySpacing.md),
              if (entry.introRule != null) ...[
                Text(
                  entry.introRule!,
                  style: MasteryTextStyles.bodyLg.copyWith(
                    color: MasteryColors.textPrimary,
                    height: 1.6,
                  ),
                ),
              ],
              if (entry.introExamples.isNotEmpty) ...[
                const SizedBox(height: MasterySpacing.xl),
                Text(
                  'Examples',
                  style: MasteryTextStyles.eyebrow(
                    color: tokens.textTertiary,
                  ),
                ),
                const SizedBox(height: MasterySpacing.sm),
                for (final ex in entry.introExamples) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 8, right: 10),
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: MasteryColors.actionPrimary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            ex,
                            style: MasteryTextStyles.bodyMd.copyWith(
                              color: MasteryColors.textPrimary,
                              height: 1.55,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: MasterySpacing.lg),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(
                    'Close',
                    style: MasteryTextStyles.labelMd.copyWith(
                      color: MasteryColors.textSecondary,
                      letterSpacing: 0.4,
                    ),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SectionEyebrow(
              label: 'Premium',
              variant: SectionEyebrowVariant.gold,
            ),
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
          const SizedBox(height: 14),
          // Wave G8 — purchase CTA. No real billing yet (V1 has no
          // payment provider wired up). The button fires an
          // analytics event so the founder can read intent before
          // building the rest of the funnel. Visible on every
          // dashboard load — `purchase_intent` clicks land in the
          // analytics_events table next to the rest of the V1
          // signal stream.
          FilledButton(
            onPressed: () => _onPurchaseTap(context),
            style: FilledButton.styleFrom(
              backgroundColor: tokens.accentGold,
              foregroundColor: MasteryColors.bgSurface,
              minimumSize: const Size.fromHeight(44),
            ),
            child: const Text('Get premium'),
          ),
        ],
      ),
    );
  }

  Future<void> _onPurchaseTap(BuildContext context) async {
    Analytics.trackButton('premium_purchase_intent', screen: 'dashboard');
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MasteryColors.bgRaised,
        title: Text(
          'Premium is on the way',
          style: MasteryTextStyles.titleSm.copyWith(
            color: MasteryColors.textPrimary,
          ),
        ),
        content: Text(
          'Thanks — your interest is logged. Billing isn\u2019t wired up yet; we\u2019ll email you the moment Premium opens.',
          style: MasteryTextStyles.bodySm.copyWith(
            color: MasteryColors.textPrimary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).maybePop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
