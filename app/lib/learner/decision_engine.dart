import '../models/lesson.dart';

/// In-session learning loop per `LEARNING_ENGINE.md §9.1` (the 1/2/3 loop).
///
/// Pure-function engine: given the lesson, the remaining-exercise queue,
/// and the per-skill mistake counts for *this session*, it decides what to
/// show next after an attempt.
///
/// Wave 3 V0 covers the in-session loop only. The cross-session review
/// cadence per §9.2/§9.3 lives in `ReviewScheduler`.
class DecisionEngine {
  /// Decision after an attempt has been evaluated. The session controller
  /// applies the new queue on the next `advance()`.
  ///
  /// `reason` is a learner-facing one-liner per §11.3, surfaced by the
  /// future Transparency Layer (Wave 4). Wave 3 returns the string but
  /// stores it on session state without rendering it.
  static DecisionResult decideAfterAttempt({
    required Lesson lesson,
    required List<int> remainingQueue,
    required Map<String, int> mistakesBySkill,
    required Exercise justAttempted,
    required bool justCorrect,
  }) {
    // remainingQueue[0] is the just-attempted exercise. The decision
    // determines what the *next* head should be — drop the just-attempted
    // index, then choose how to order the rest.
    final remaining =
        remainingQueue.isEmpty ? <int>[] : remainingQueue.sublist(1);
    if (remaining.isEmpty) {
      return const DecisionResult.endSession();
    }

    final skillId = justAttempted.skillId;
    if (skillId == null) {
      // Untagged exercise — fall back to the linear default. No decision
      // surface, no reason string.
      return DecisionResult.advance(remaining);
    }

    final mistakesOnSkill = mistakesBySkill[skillId] ?? 0;

    // §9.1, 3rd mistake: stop repeating. The rule's intent is "move on
    // to other skills you can still progress on". When the lesson is
    // single-skill (or every remaining item happens to share the just-
    // missed skill), there is nothing to move on to — the right
    // behaviour is to fall through to the linear default and let the
    // learner finish the planned sequence. Truncating the queue here
    // would silently cut the lesson short, which is what the bug report
    // showed: a 10-item single-skill lesson ending after the 3rd wrong
    // attempt as if every exercise had been completed.
    if (mistakesOnSkill >= 3) {
      // "Other" includes both differently-tagged items AND untagged
      // items: the §9.1 intent is "show something other than the skill
      // you just hammered". An untagged item has unknown identity but
      // is by definition not the just-missed skill, so a mixed
      // tagged/untagged lesson can still legitimately move on to the
      // untagged slot.
      final hasOther =
          remaining.any((i) => lesson.exercises[i].skillId != skillId);
      if (!hasOther) {
        // Single-skill (or otherwise no escape) — fall through to
        // linear rather than truncate. Truncating here was the prod
        // bug where 10-exercise single-skill lessons closed at the
        // 3rd mistake.
        return DecisionResult.advance(remaining);
      }
      final filtered = remaining
          .where((i) => lesson.exercises[i].skillId != skillId)
          .toList();
      return DecisionResult.advance(
        filtered,
        reason:
            'Three misses on this rule — moving on for now. We will come back later.',
      );
    }

    // §9.1, 1st/2nd mistake on a wrong answer: pull the next un-attempted
    // item on the same skill to the head (different surface, different
    // angle). If no other same-skill item remains, the loop falls through
    // to linear default.
    if (!justCorrect && mistakesOnSkill >= 1) {
      final sameSkillIndex = remaining.indexWhere(
          (i) => lesson.exercises[i].skillId == skillId);
      if (sameSkillIndex > 0) {
        final reordered = List<int>.from(remaining);
        final pulled = reordered.removeAt(sameSkillIndex);
        reordered.insert(0, pulled);
        final reason = mistakesOnSkill == 1
            ? 'Same rule, different angle.'
            : 'Same rule, simpler ask.';
        return DecisionResult.advance(reordered, reason: reason);
      }
      // Same-skill item is already next in line, or none remain — let the
      // linear default carry the loop.
    }

    return DecisionResult.advance(remaining);
  }

  /// Returns the set of skills that the learner attempted in this session,
  /// each tagged with the in-session outcome the `ReviewScheduler` needs:
  /// the mistake count. The scheduler decides the cadence step from this.
  static Map<String, int> sessionMistakeSummary(
      Map<String, int> mistakesBySkill) {
    return Map<String, int>.from(mistakesBySkill);
  }
}

class DecisionResult {
  /// New ordered queue of remaining exercise indices (head = next).
  /// Empty when `endSession` is true.
  final List<int> remainingQueue;

  /// One-line learner-facing reason (`LEARNING_ENGINE.md §11.3`). Null
  /// when the decision was the linear default. Wave 4 renders it; Wave 3
  /// stores it on session state.
  final String? reason;

  /// True when the engine decided the session is over (e.g. a 3rd-mistake
  /// skip emptied the queue).
  final bool endSession;

  const DecisionResult.advance(this.remainingQueue, {this.reason})
      : endSession = false;

  const DecisionResult.endSession({this.reason})
      : remainingQueue = const [],
        endSession = true;
}
