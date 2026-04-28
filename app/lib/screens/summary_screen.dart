import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../learner/learner_skill_store.dart';
import '../models/evaluation.dart';
import '../theme/mastery_theme.dart';
import '../widgets/feedback_prompt_sheet.dart';
import '../widgets/mastery_widgets.dart';
import '../widgets/skill_state_card.dart';

class SummaryScreen extends StatefulWidget {
  final int correctCount;
  final int totalCount;
  final LessonResultResponse? summary;

  /// When `true`, the screen scrolls to the "Review your mistakes" section
  /// after first frame. Used by the dashboard "Last lesson report" block so
  /// its `Review mistakes` button lands directly at the relevant content.
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
  final GlobalKey _mistakesKey = GlobalKey();

  /// Wave 4 §11.2 panel data. Loaded once at screen mount; reads from
  /// SharedPreferences so the per-skill state visible here always
  /// reflects what `SessionController.submitAnswer` just wrote on the
  /// last attempt of this session. Empty until the future resolves.
  List<LearnerSkillRecord> _skillRecords = const [];

  @override
  void initState() {
    super.initState();
    _loadSkillRecords();
    if (widget.initialScrollToMistakes) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _mistakesKey.currentContext;
        if (ctx == null || !mounted) return;
        Scrollable.ensureVisible(
          ctx,
          duration: MasteryDurations.medium,
          curve: MasteryEasing.move,
          alignment: 0.05,
        );
      });
    }
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
  /// Intercepts the Done tap. If the server-side cooldown allows a
  /// new `after_summary` record, opens the rating sheet. Whatever the
  /// learner does (rate, comment, skip, swipe-away) is mirrored as a
  /// single POST to `/me/feedback` so server analytics see one row
  /// per Done. Network failures are silent — the screen always pops
  /// at the end.
  ///
  /// Why on Done (not on screen mount): the learner has just read the
  /// score and any debrief; asking now is asking when the experience
  /// is freshest, not when they're still scanning the result. It also
  /// piggybacks on an action they were going to take anyway.
  Future<void> _onDoneTap() async {
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

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final summary = widget.summary;
    final displayCorrect = summary?.correctCount ?? widget.correctCount;
    final displayTotal = summary?.totalExercises ?? widget.totalCount;
    final mistakes = summary?.answers.where((a) => !a.correct).toList() ?? [];
    final conclusion = summary?.conclusion;

    final pct = displayTotal > 0 ? displayCorrect / displayTotal : 0.0;
    final scoreColor = pct == 1.0
        ? tokens.success
        : pct >= 0.6
            ? MasteryColors.actionPrimary
            : MasteryColors.error;
    final debrief = summary?.debrief;

    return Scaffold(
      backgroundColor: tokens.bgApp,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              MasterySpacing.lg, 24, MasterySpacing.lg, MasterySpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  'Lesson Complete',
                  style: MasteryTextStyles.headlineMd.copyWith(
                    color: MasteryColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _ScoreHero(
                correct: displayCorrect,
                total: displayTotal,
                scoreColor: scoreColor,
              ),
              if (debrief != null) ...[
                const SizedBox(height: 18),
                _DebriefCard(debrief: debrief),
              ] else if (conclusion != null && conclusion.isNotEmpty) ...[
                const SizedBox(height: 18),
                MasterySoftCard(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  child: Text(
                    conclusion,
                    style: MasteryTextStyles.bodyMd.copyWith(
                      height: 1.6,
                      color: MasteryColors.textPrimary,
                    ),
                  ),
                ),
              ],
              if (_skillRecords.isNotEmpty) ...[
                const SizedBox(height: 18),
                SkillStateCard(records: _skillRecords, now: DateTime.now()),
              ],
              if (mistakes.isNotEmpty) ...[
                const SizedBox(height: 28),
                Row(
                  key: _mistakesKey,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'Review your mistakes',
                      style: MasteryTextStyles.titleMd,
                    ),
                    const Spacer(),
                    Text(
                      '${mistakes.length}',
                      style: MasteryTextStyles.mono(
                        size: 13,
                        lineHeight: 16,
                        color: tokens.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...mistakes.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MistakeCard(answer: m),
                    )),
              ],
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _onDoneTap,
                child: const Text('Done'),
              ),
            ],
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -1.0),
          radius: 0.9,
          colors: [
            tokens.accentGoldSoft.withAlpha(115),
            MasteryColors.bgRaised,
          ],
          stops: const [0.0, 0.55],
        ),
        border: Border.all(color: tokens.borderSoft),
        borderRadius: BorderRadius.circular(MasteryRadii.xl),
        boxShadow: tokens.shadowCard,
      ),
      child: Column(
        children: [
          _GoldHairline(color: tokens.accentGold),
          const SizedBox(height: 18),
          Text.rich(
            textAlign: TextAlign.center,
            TextSpan(
              style: TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 88,
                height: 1.0,
                fontWeight: FontWeight.w600,
                color: scoreColor,
                letterSpacing: -3.5,
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
                    fontSize: 44,
                    color: tokens.textTertiary,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -1.5,
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
          const SizedBox(height: 10),
          Text(
            'CORRECT',
            style: MasteryTextStyles.mono(
              size: 13,
              lineHeight: 16,
              weight: FontWeight.w400,
              color: tokens.textTertiary,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 18),
          _GoldHairline(color: tokens.accentGold),
        ],
      ),
    );
  }
}

class _GoldHairline extends StatelessWidget {
  final Color color;
  const _GoldHairline({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 1,
      color: color.withAlpha(180),
    );
  }
}

class _DebriefCard extends StatelessWidget {
  final LessonDebrief debrief;
  const _DebriefCard({required this.debrief});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final eyebrowVariant = switch (debrief.debriefType) {
      LessonDebriefType.strong => SectionEyebrowVariant.gold,
      LessonDebriefType.mixed => SectionEyebrowVariant.primary,
      LessonDebriefType.needsWork => SectionEyebrowVariant.secondary,
    };
    final eyebrowLabel = switch (debrief.debriefType) {
      LessonDebriefType.strong => 'Coach\u2019s note',
      LessonDebriefType.mixed => 'Coach\u2019s note',
      LessonDebriefType.needsWork => 'Coach\u2019s note',
    };

    return MasteryCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionEyebrow(label: eyebrowLabel, variant: eyebrowVariant),
          const SizedBox(height: 10),
          if (debrief.headline.isNotEmpty)
            Text(
              debrief.headline,
              style: MasteryTextStyles.titleMd.copyWith(
                color: MasteryColors.textPrimary,
                height: 1.3,
              ),
            ),
          if (debrief.body.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              debrief.body,
              style: MasteryTextStyles.bodyMd.copyWith(
                color: MasteryColors.textPrimary,
                height: 1.6,
              ),
            ),
          ],
          if (debrief.watchOut != null && debrief.watchOut!.isNotEmpty) ...[
            const SizedBox(height: 14),
            _DebriefTail(
              label: 'WATCH OUT',
              text: debrief.watchOut!,
              color: tokens.accentGoldDeep,
            ),
          ],
          if (debrief.nextStep != null && debrief.nextStep!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _DebriefTail(
              label: 'NEXT STEP',
              text: debrief.nextStep!,
              color: MasteryColors.actionPrimaryPressed,
            ),
          ],
        ],
      ),
    );
  }
}

class _DebriefTail extends StatelessWidget {
  final String label;
  final String text;
  final Color color;

  const _DebriefTail({
    required this.label,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: MasteryTextStyles.mono(
              size: 11,
              lineHeight: 14,
              weight: FontWeight.w600,
              color: color,
              letterSpacing: 1.4,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: MasteryTextStyles.bodySm.copyWith(
              color: MasteryColors.textPrimary,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _MistakeCard extends StatelessWidget {
  final LessonResultAnswer answer;
  const _MistakeCard({required this.answer});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return MasteryCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      shadow: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (answer.prompt != null && answer.prompt!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '"${answer.prompt!}"',
                style: MasteryTextStyles.bodyMd.copyWith(
                  color: MasteryColors.textSecondary,
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                ),
              ),
            ),
          if (answer.canonicalAnswer != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'ANSWER',
                  style: MasteryTextStyles.labelSm.copyWith(
                    color: tokens.textTertiary,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    answer.canonicalAnswer!,
                    style: MasteryTextStyles.bodyMd.copyWith(
                      color: MasteryColors.actionPrimaryPressed,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (answer.explanation != null && answer.explanation!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              answer.explanation!,
              style: MasteryTextStyles.bodySm.copyWith(
                color: MasteryColors.textSecondary,
                height: 1.55,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
