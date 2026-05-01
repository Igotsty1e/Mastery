import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../analytics/analytics.dart';
import '../api/api_client.dart';
import '../learner/learner_skill_store.dart';
import '../learner/skill_titles.dart';
import '../models/evaluation.dart';
import '../theme/mastery_theme.dart';
import '../widgets/feedback_prompt_sheet.dart';
import '../widgets/mastery_route.dart';
import '../widgets/mastery_widgets.dart';
import '../widgets/skill_state_card.dart';
import '../widgets/skill_status_badge.dart';
import 'lesson_intro_screen.dart';

class SummaryScreen extends StatefulWidget {
  final int correctCount;
  final int totalCount;
  final LessonResultResponse? summary;

  /// Wave 14.9 left-over: the dashboard Last-lesson CTA used to deep-link
  /// into the mistake list. The Wave G2 SummaryScreen rewrite removes the
  /// mistake list entirely (per the 2026-05-01 product call), so this
  /// flag is now a no-op kept for backwards compat with existing callers.
  /// Remove once every caller has been updated.
  final bool initialScrollToMistakes;

  /// Wave 4 §11.2: skill IDs that this just-finished lesson touched. The
  /// per-skill panel filters its records by this set so the panel agrees
  /// with the lesson's score/debrief instead of polluting with skills
  /// from earlier lessons. Null = no filter (legacy dashboard re-open
  /// path that does not know which skills this lesson touched).
  final Set<String>? touchedSkillIds;

  const SummaryScreen({
    super.key,
    required this.correctCount,
    required this.totalCount,
    this.summary,
    this.initialScrollToMistakes = false,
    this.touchedSkillIds,
  });

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  /// Wave 4 §11.2 panel data. Loaded once at screen mount; reads from
  /// SharedPreferences so the per-skill state visible here always
  /// reflects what `SessionController.submitAnswer` just wrote on the
  /// last attempt of this session. Empty until the future resolves.
  List<LearnerSkillRecord> _skillRecords = const [];

  @override
  void initState() {
    super.initState();
    _loadSkillRecords();
    Analytics.trackScreen('summary', metadata: {
      'correct': widget.correctCount,
      'total': widget.totalCount,
    });
  }

  Future<void> _loadSkillRecords() async {
    final all = await LearnerSkillStore.allRecords();
    if (!mounted) return;
    final filter = widget.touchedSkillIds;
    final filtered = filter == null
        ? all
        : all.where((r) => filter.contains(r.skillId)).toList();
    setState(() => _skillRecords = filtered);
  }

  /// Wave 14.3 phase 2 — V1.5 feedback after-summary surface.
  ///
  /// Intercepts the discreet "Back to home" tap. If the server-side
  /// cooldown allows a new `after_summary` record, opens the rating
  /// sheet. Whatever the learner does (rate, comment, skip,
  /// swipe-away) is mirrored as a single POST to `/me/feedback` so
  /// server analytics see one row per Done. Network failures are
  /// silent — the screen always pops at the end.
  Future<void> _onBackToHomeTap() async {
    Analytics.trackButton('back_to_home', screen: 'summary');
    final api = context.read<ApiClient>();
    final summaryId = widget.summary?.lessonId;
    final navigator = Navigator.of(context);

    FeedbackPromptResult? result;
    try {
      final cooldown = await api.getFeedbackCooldown();
      if (!mounted) return;
      if (cooldown != null && cooldown.afterSummaryAllowed) {
        result = await showFeedbackPromptSheet(context);
      }
    } catch (_) {
      // Cooldown read failures are quiet — pop without prompting.
    }
    if (result != null) {
      try {
        await api.submitFeedback(
          promptKind: 'after_summary',
          outcome: result.wireOutcome,
          rating: result.rating,
          commentText: result.commentText,
          context: summaryId == null
              ? null
              : {'summary_lesson_id': summaryId},
        );
      } catch (_) {
        // Best-effort — never block the dashboard return on a flaky
        // feedback POST.
      }
    }
    if (!mounted) return;
    navigator.pop();
  }

  /// Wave G2 — primary CTA. The product call on 2026-05-01 made
  /// "practice another 10" the dominant action on the summary, so
  /// the learner can stay in the loop without bouncing through the
  /// dashboard. Pushes a fresh `LessonIntroScreen` (which boots a
  /// dynamic session via `loadDynamicSession()`) and replaces the
  /// current SummaryScreen so the back gesture lands on the
  /// dashboard, not on the just-finished summary.
  void _onPracticeMoreTap() {
    Analytics.trackButton('practice_another_10', screen: 'summary');
    Navigator.of(context).pushReplacement(
      MasteryFadeRoute(
        builder: (_) => const LessonIntroScreen(),
      ),
    );
  }

  /// Wave G5 — quiet feedback button. Opens the user's mail client
  /// with a pre-filled subject and a body stub that includes the
  /// session score so the recipient can correlate the note with what
  /// the learner just experienced. Best-effort: a browser without a
  /// configured handler simply does nothing — we don't surface a
  /// "your mailto: failed" warning, the learner can copy the email
  /// from the screen if they care.
  Future<void> _onSendFeedbackTap() async {
    Analytics.trackButton('send_feedback', screen: 'summary');
    final correct = widget.summary?.correctCount ?? widget.correctCount;
    final total = widget.summary?.totalExercises ?? widget.totalCount;
    final body = Uri.encodeComponent(
      'Hi! I just finished a Mastery session ($correct/$total).\n\n'
      'What worked / didn\u2019t:\n',
    );
    final subject = Uri.encodeComponent('Mastery feedback');
    final uri = Uri.parse(
      'mailto:igotstyle227@gmail.com?subject=$subject&body=$body',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Quiet failure — see method docstring.
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final summary = widget.summary;
    final displayCorrect = summary?.correctCount ?? widget.correctCount;
    final displayTotal = summary?.totalExercises ?? widget.totalCount;

    final pct = displayTotal > 0 ? displayCorrect / displayTotal : 0.0;
    final scoreColor = pct == 1.0
        ? tokens.success
        : pct >= 0.6
            ? MasteryColors.actionPrimary
            : MasteryColors.error;
    final debrief = summary?.debrief;
    final conclusion = summary?.conclusion;

    return Scaffold(
      backgroundColor: tokens.bgApp,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    MasterySpacing.lg, 14, MasterySpacing.lg, MasterySpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'Session done',
                        style: MasteryTextStyles.titleLg.copyWith(
                          color: MasteryColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ScoreHero(
                      correct: displayCorrect,
                      total: displayTotal,
                      scoreColor: scoreColor,
                    ),
                    if (debrief != null) ...[
                      const SizedBox(height: 12),
                      _DebriefCard(debrief: debrief),
                    ] else if (conclusion != null && conclusion.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      MasterySoftCard(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                        child: Text(
                          conclusion,
                          style: MasteryTextStyles.bodySm.copyWith(
                            height: 1.55,
                            color: MasteryColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                    if (_skillRecords.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _CompactSkillPanel(records: _skillRecords),
                    ],
                  ],
                ),
              ),
            ),
            // Sticky CTA dock at the bottom: prominent "practice more"
            // primary action + a quiet text-button to bail to the
            // dashboard. Wrapped in SafeArea inset so the bottom edge
            // doesn't collide with the home indicator on iPhone.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  MasterySpacing.lg, 0, MasterySpacing.lg, MasterySpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _onPracticeMoreTap,
                    child: const Text('Practice another 10'),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: _onBackToHomeTap,
                    style: TextButton.styleFrom(
                      foregroundColor: MasteryColors.textTertiary,
                      minimumSize: const Size.fromHeight(40),
                    ),
                    child: Text(
                      'Back to home',
                      style: MasteryTextStyles.labelMd.copyWith(
                        color: MasteryColors.textTertiary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _onSendFeedbackTap,
                    style: TextButton.styleFrom(
                      foregroundColor: MasteryColors.textTertiary,
                      minimumSize: const Size.fromHeight(36),
                    ),
                    child: Text(
                      'Send feedback',
                      style: MasteryTextStyles.labelSm.copyWith(
                        color: MasteryColors.textTertiary,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreHero extends StatelessWidget {
  final int correct;
  final int total;
  final Color scoreColor;

  const _ScoreHero({
    required this.correct,
    required this.total,
    required this.scoreColor,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -1.0),
          radius: 0.9,
          colors: [
            tokens.accentGoldSoft.withAlpha(110),
            MasteryColors.bgRaised,
          ],
          stops: const [0.0, 0.6],
        ),
        border: Border.all(color: tokens.borderSoft),
        borderRadius: BorderRadius.circular(MasteryRadii.lg),
        boxShadow: tokens.shadowCard,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Wave G2.1 — compact horizontal layout. The previous
          // hero stacked huge (88px) digits + hairlines + label
          // vertically, eating ~280px of viewport. The score is
          // the smallest piece of information on the screen, so
          // it should not be the loudest. Now: number on the
          // left, label on the right, ~80px tall.
          Text.rich(
            textAlign: TextAlign.left,
            TextSpan(
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 48,
                height: 1.0,
                fontWeight: FontWeight.w600,
                color: scoreColor,
                letterSpacing: -2.0,
                fontVariations: const [
                  FontVariation('opsz', 144),
                  FontVariation('wght', 600),
                ],
              ),
              children: [
                TextSpan(text: '$correct'),
                TextSpan(
                  text: ' / ',
                  style: TextStyle(
                    fontSize: 28,
                    color: tokens.textTertiary,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -1.0,
                    fontVariations: const [
                      FontVariation('opsz', 144),
                      FontVariation('wght', 500),
                    ],
                  ),
                ),
                TextSpan(text: '$total'),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 1,
            height: 32,
            color: tokens.accentGold.withAlpha(160),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'CORRECT',
              style: MasteryTextStyles.mono(
                size: 12,
                lineHeight: 16,
                weight: FontWeight.w500,
                color: MasteryColors.textSecondary,
                letterSpacing: 2.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wave G2 — calmer debrief card. Drops the per-row WATCH OUT /
/// NEXT STEP rails the AI used to emit; the headline + body alone is
/// what the learner actually reads. The eyebrow stays so the source
/// of the note (an AI coach voice, not a robot) is named explicitly.
class _DebriefCard extends StatelessWidget {
  final LessonDebrief debrief;
  const _DebriefCard({required this.debrief});

  @override
  Widget build(BuildContext context) {
    final eyebrowVariant = switch (debrief.debriefType) {
      LessonDebriefType.strong => SectionEyebrowVariant.gold,
      LessonDebriefType.mixed => SectionEyebrowVariant.primary,
      LessonDebriefType.needsWork => SectionEyebrowVariant.secondary,
    };

    return MasteryCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionEyebrow(
            label: 'Coach\u2019s note',
            variant: eyebrowVariant,
          ),
          const SizedBox(height: 8),
          if (debrief.headline.isNotEmpty)
            Text(
              debrief.headline,
              style: MasteryTextStyles.titleSm.copyWith(
                color: MasteryColors.textPrimary,
                height: 1.3,
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
        ],
      ),
    );
  }
}

/// Wave G2 — compact skill-progress strip. One row per touched skill:
/// title + status pill, no inline reason text. Tapping the
/// "See progress →" footer opens a modal with the full
/// `SkillStateCard` (the previous SummaryScreen surface, kept intact
/// so reason copy and recurring-error rows stay accessible to anyone
/// who wants the depth). Rationale: the post-session screen is for
/// orientation, not study; the heavy text panel made the page feel
/// like a graded report. The full breakdown is one tap away.
class _CompactSkillPanel extends StatelessWidget {
  final List<LearnerSkillRecord> records;
  const _CompactSkillPanel({required this.records});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final now = DateTime.now();
    return MasteryCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionEyebrow(
            label: 'Skills',
            variant: SectionEyebrowVariant.secondary,
          ),
          const SizedBox(height: MasterySpacing.sm),
          for (var i = 0; i < records.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: tokens.borderSoft,
              ),
            _CompactSkillRow(record: records[i], now: now),
          ],
          const SizedBox(height: MasterySpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _openProgressSheet(context),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'See progress \u2192',
                style: MasteryTextStyles.labelMd.copyWith(
                  color: MasteryColors.actionPrimary,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openProgressSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MasteryColors.bgSurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MasteryRadii.lg),
        ),
      ),
      builder: (sheetCtx) => _ProgressSheetBody(records: records),
    );
  }
}

class _CompactSkillRow extends StatelessWidget {
  final LearnerSkillRecord record;
  final DateTime now;

  const _CompactSkillRow({required this.record, required this.now});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MasterySpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              skillTitleFor(record.skillId),
              style: MasteryTextStyles.bodyMd.copyWith(
                color: MasteryColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: MasterySpacing.sm),
          SkillStatusBadge(record: record, now: now),
        ],
      ),
    );
  }
}

class _ProgressSheetBody extends StatelessWidget {
  final List<LearnerSkillRecord> records;
  const _ProgressSheetBody({required this.records});

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
              SkillStateCard(records: records, now: DateTime.now()),
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
