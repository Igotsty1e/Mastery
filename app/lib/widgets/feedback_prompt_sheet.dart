import 'package:flutter/material.dart';

import '../theme/mastery_theme.dart';

/// Wave 14.3 phase 2 — V1.5 feedback prompt sheet.
///
/// Modal bottom sheet shown after a session completes (the
/// SummaryScreen "Done" tap). Five-star rating + optional one-line
/// comment, plus a quiet "Skip" link. The result the caller receives:
///
///   - `Outcome.submitted` with rating (and optional comment) when the
///     learner taps "Send".
///   - `Outcome.dismissed` when the learner taps "Skip" or
///     swipes/back-taps the sheet.
///
/// The sheet itself does NOT call the API — the caller wraps both
/// outcomes into a `POST /me/feedback`. This keeps the widget pure and
/// testable without faking the network.
///
/// Visual treatment: same calm card geometry as the Wave 12.6 rule
/// sheet (centred drag handle, rounded top corners, calm tokens). No
/// icons in the rating row — five tappable stars, accent gold on
/// selection.

/// Outcome surfaced to the caller so it can mirror the wire `outcome`
/// field on `POST /me/feedback`. Wire values: 'submitted' | 'dismissed'.
enum FeedbackPromptOutcome { submitted, dismissed }

class FeedbackPromptResult {
  final FeedbackPromptOutcome outcome;
  final int? rating;
  final String? commentText;

  const FeedbackPromptResult.submitted({
    required this.rating,
    required this.commentText,
  }) : outcome = FeedbackPromptOutcome.submitted;

  const FeedbackPromptResult.dismissed()
      : outcome = FeedbackPromptOutcome.dismissed,
        rating = null,
        commentText = null;

  /// Wire string for the `outcome` field on `POST /me/feedback`.
  String get wireOutcome => switch (outcome) {
        FeedbackPromptOutcome.submitted => 'submitted',
        FeedbackPromptOutcome.dismissed => 'dismissed',
      };
}

/// Shows the feedback sheet and resolves to a result.
/// Resolves to `FeedbackPromptResult.dismissed()` on swipe-away / back.
///
/// `title` and `subtitle` let the caller swap the framing — the
/// after-summary surface asks "How was this session?" while the
/// after-friction surface (Wave 14.3 phase 3) asks something narrower
/// like "How did that exercise feel?". The rest of the sheet
/// (5 stars, optional comment, Send / Skip) stays the same.
Future<FeedbackPromptResult> showFeedbackPromptSheet(
  BuildContext context, {
  String title = 'How was this session?',
  String subtitle = 'A quick rating helps us tune the sessions you see next.',
}) async {
  final result = await showModalBottomSheet<FeedbackPromptResult>(
    context: context,
    backgroundColor: MasteryColors.bgSurface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(MasteryRadii.lg),
      ),
    ),
    builder: (sheetCtx) =>
        _FeedbackPromptSheetBody(title: title, subtitle: subtitle),
  );
  return result ?? const FeedbackPromptResult.dismissed();
}

class _FeedbackPromptSheetBody extends StatefulWidget {
  final String title;
  final String subtitle;
  const _FeedbackPromptSheetBody({
    required this.title,
    required this.subtitle,
  });

  @override
  State<_FeedbackPromptSheetBody> createState() =>
      _FeedbackPromptSheetBodyState();
}

class _FeedbackPromptSheetBodyState extends State<_FeedbackPromptSheetBody> {
  int? _rating;
  late final TextEditingController _commentController;

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _send() {
    final rating = _rating;
    if (rating == null) return; // button is disabled in this state
    Navigator.of(context).pop(
      FeedbackPromptResult.submitted(
        rating: rating,
        commentText: _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
      ),
    );
  }

  void _skip() {
    Navigator.of(context).pop(const FeedbackPromptResult.dismissed());
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    final canSend = _rating != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: MasterySpacing.lg,
          right: MasterySpacing.lg,
          top: MasterySpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + MasterySpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: MasterySpacing.lg),
                decoration: BoxDecoration(
                  color: MasteryColors.borderSoft,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              widget.title,
              style: MasteryTextStyles.titleLg.copyWith(
                color: MasteryColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.subtitle,
              style: MasteryTextStyles.bodySm.copyWith(
                color: MasteryColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            _StarsRow(
              rating: _rating,
              onTap: (i) => setState(() => _rating = i),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commentController,
              maxLines: 2,
              maxLength: 500,
              style: MasteryTextStyles.bodyMd.copyWith(
                color: MasteryColors.textPrimary,
                height: 1.5,
              ),
              decoration: InputDecoration(
                labelText: 'Anything to add? (optional)',
                labelStyle: MasteryTextStyles.labelSm.copyWith(
                  color: tokens.textTertiary,
                  letterSpacing: 0.4,
                ),
                floatingLabelStyle: MasteryTextStyles.labelSm.copyWith(
                  color: MasteryColors.actionPrimary,
                  letterSpacing: 0.4,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: canSend ? _send : null,
              child: const Text('Send'),
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: _skip,
                child: Text(
                  'Skip',
                  style: MasteryTextStyles.bodyMd.copyWith(
                    color: tokens.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarsRow extends StatelessWidget {
  final int? rating;
  final ValueChanged<int> onTap;

  const _StarsRow({required this.rating, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(5, (i) {
        final value = i + 1;
        final filled = rating != null && value <= rating!;
        return Semantics(
          label: '$value out of 5',
          button: true,
          child: InkResponse(
            onTap: () => onTap(value),
            radius: 28,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                filled ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 36,
                color: filled
                    ? tokens.accentGold
                    : tokens.textTertiary,
              ),
            ),
          ),
        );
      }),
    );
  }
}
