// MasteryFadeRoute — calm route transition for navigation between primary
// product surfaces (HomeScreen → LessonIntroScreen → ExerciseScreen).
//
// Direction A · Brief C calls for "preserve calm pacing; do not snap into
// quiz mode" between lesson intro and the exercise. The default
// MaterialPageRoute slides hard from the right, which feels like a screen
// change in a settings app, not the calm transition the spec asks for.
//
// This route renders the incoming screen with a short fade-through plus a
// 4% rise. When MediaQuery.disableAnimations is on, it collapses to
// opacity-only — same reduced-motion fallback the onboarding uses, so the
// motion language stays consistent across the product.

import 'package:flutter/material.dart';

import '../theme/mastery_theme.dart';

class MasteryFadeRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;
  final bool isFullscreenDialog;

  MasteryFadeRoute({
    required this.builder,
    this.isFullscreenDialog = false,
    super.settings,
  });

  @override
  bool get fullscreenDialog => isFullscreenDialog;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => MasteryDurations.medium;

  @override
  Duration get reverseTransitionDuration => MasteryDurations.short;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final eased = CurvedAnimation(parent: animation, curve: MasteryEasing.move);

    if (reduceMotion) {
      return FadeTransition(opacity: eased, child: child);
    }

    final offset = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(eased);

    return FadeTransition(
      opacity: eased,
      child: SlideTransition(position: offset, child: child),
    );
  }
}
