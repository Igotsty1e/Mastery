// Wave 14.8 — widget coverage for the visual context layer.
//
// Three contracts:
//   1. The image URL is resolved via `resolveAssetUrl` and forwarded to
//      `CachedNetworkImage.imageUrl`.
//   2. The aspect ratio defaults to 3:2 and can be overridden.
//   3. The widget accepts every `ExerciseImageRole` × `ExerciseImagePolicy`
//      combination without throwing.
//
// We do NOT exercise the network path (CachedNetworkImage's
// placeholder/error widgets fire on real I/O which unit tests don't have).
// Configuration correctness is the load-bearing surface here — the
// runtime fallback to the alt-text caption is straightforward enough
// that visual QA is sufficient and a unit test would only rehearse the
// CachedNetworkImage internals.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/models/lesson.dart';
import 'package:mastery/theme/mastery_theme.dart';
import 'package:mastery/widgets/mastery_exercise_image.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: MasteryTheme.light(),
      home: Scaffold(body: child),
    );

const _image = ExerciseImage(
  url: '/images/lesson-1/ex-1.png',
  alt: 'A quiet kitchen scene with morning light.',
  role: ExerciseImageRole.sceneSetting,
  policy: ExerciseImagePolicy.optional,
);

void main() {
  testWidgets('forwards the resolved URL to CachedNetworkImage', (tester) async {
    await tester.pumpWidget(_wrap(
      const MasteryExerciseImage(image: _image),
    ));

    final cached =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    // On the test runtime (non-web), `resolveAssetUrl` prefixes the API base.
    // We assert that the path tail is preserved, regardless of how the host
    // is configured at test time.
    expect(cached.imageUrl, endsWith('/images/lesson-1/ex-1.png'));
  });

  testWidgets('defaults to a 3:2 aspect ratio', (tester) async {
    await tester.pumpWidget(_wrap(
      const MasteryExerciseImage(image: _image),
    ));

    final ratio = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(ratio.aspectRatio, closeTo(3 / 2, 1e-9));
  });

  testWidgets('honours an explicit aspect ratio override', (tester) async {
    await tester.pumpWidget(_wrap(
      const MasteryExerciseImage(image: _image, aspectRatio: 4 / 3),
    ));

    final ratio = tester.widget<AspectRatio>(find.byType(AspectRatio));
    expect(ratio.aspectRatio, closeTo(4 / 3, 1e-9));
  });

  testWidgets('builds for every role × policy combination', (tester) async {
    for (final role in ExerciseImageRole.values) {
      for (final policy in ExerciseImagePolicy.values) {
        await tester.pumpWidget(_wrap(
          MasteryExerciseImage(
            image: ExerciseImage(
              url: '/images/lesson-x/ex-x.png',
              alt: 'alt for ${role.name}/${policy.name}',
              role: role,
              policy: policy,
            ),
          ),
        ));
        expect(find.byType(CachedNetworkImage), findsOneWidget);
        expect(find.byType(AspectRatio), findsOneWidget);
      }
    }
  });

  testWidgets('absolute http(s) URLs pass through resolveAssetUrl unchanged',
      (tester) async {
    const absolute = ExerciseImage(
      url: 'https://cdn.example.com/scene.png',
      alt: 'absolute',
      role: ExerciseImageRole.contextSupport,
      policy: ExerciseImagePolicy.recommended,
    );

    await tester.pumpWidget(_wrap(
      const MasteryExerciseImage(image: absolute),
    ));

    final cached =
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(cached.imageUrl, 'https://cdn.example.com/scene.png');
  });
}
