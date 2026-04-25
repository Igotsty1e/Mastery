// MasteryExerciseImage — visual context layer panel for any exercise type
// per DESIGN.md §15 (added when imagery support landed). Soft paper card
// with rose-cream loading skeleton and a tertiary fail state that does not
// block the exercise. Loads via Image.network with a loadingBuilder so we
// don't add a third-party dependency just for one widget.

import 'package:flutter/material.dart';

import '../config.dart';
import '../models/lesson.dart';
import '../theme/mastery_theme.dart';

class MasteryExerciseImage extends StatelessWidget {
  final ExerciseImage image;
  final double aspectRatio;

  const MasteryExerciseImage({
    super.key,
    required this.image,
    this.aspectRatio = 3 / 2,
  });

  String _resolveUrl() {
    final url = image.url;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final tail = url.startsWith('/') ? url : '/$url';
    return '$base$tail';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.masteryTokens;
    return ClipRRect(
      borderRadius: BorderRadius.circular(MasteryRadii.lg),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Container(
          decoration: BoxDecoration(
            color: tokens.bgPrimarySoft,
            border: Border.all(color: tokens.borderSoft),
          ),
          child: Image.network(
            _resolveUrl(),
            fit: BoxFit.cover,
            semanticLabel: image.alt,
            gaplessPlayback: true,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return _ImageSkeleton(tokens: tokens);
            },
            errorBuilder: (context, _, __) => _ImageUnavailable(
              alt: image.alt,
              tokens: tokens,
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageSkeleton extends StatelessWidget {
  final MasteryTokens tokens;
  const _ImageSkeleton({required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: tokens.bgPrimarySoft,
      alignment: Alignment.center,
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor:
              const AlwaysStoppedAnimation(MasteryColors.actionPrimary),
        ),
      ),
    );
  }
}

class _ImageUnavailable extends StatelessWidget {
  final String alt;
  final MasteryTokens tokens;
  const _ImageUnavailable({required this.alt, required this.tokens});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: tokens.bgSurfaceAlt,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(MasterySpacing.md),
      child: Text(
        alt,
        style: MasteryTextStyles.bodySm.copyWith(
          color: tokens.textTertiary,
          fontStyle: FontStyle.italic,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
