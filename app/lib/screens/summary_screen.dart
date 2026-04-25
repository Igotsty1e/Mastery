import 'package:flutter/material.dart';

import '../models/evaluation.dart';
import '../theme/mastery_theme.dart';
import '../widgets/mastery_widgets.dart';

class SummaryScreen extends StatelessWidget {
  final int correctCount;
  final int totalCount;
  final LessonResultResponse? summary;

  const SummaryScreen({
    super.key,
    required this.correctCount,
    required this.totalCount,
    this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final displayCorrect = summary?.correctCount ?? correctCount;
    final displayTotal = summary?.totalExercises ?? totalCount;
    final mistakes = summary?.answers.where((a) => !a.correct).toList() ?? [];
    final conclusion = summary?.conclusion;

    final pct = displayTotal > 0 ? displayCorrect / displayTotal : 0.0;
    final scoreColor = pct == 1.0
        ? tokens.success
        : pct >= 0.6
            ? MasteryColors.actionPrimary
            : MasteryColors.error;

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
              if (conclusion != null && conclusion.isNotEmpty) ...[
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
              if (mistakes.isNotEmpty) ...[
                const SizedBox(height: 28),
                Row(
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
                onPressed: () => Navigator.of(context).pop(),
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
