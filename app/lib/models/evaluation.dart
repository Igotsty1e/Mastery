class EvaluateRequest {
  /// Wave 8 (legacy drop): the session id is now part of the URL
  /// (`POST /lesson-sessions/:sessionId/answers`), not the body. Kept on
  /// the model so SessionController can still thread the value end-to-end
  /// without a breaking signature shift, but no longer serialised by
  /// `toJson` and ignored by the server-side Wave2AnswerSchema.
  final String sessionId;
  final String attemptId;
  final String exerciseId;
  final String exerciseType;
  final String userAnswer;
  final String submittedAt;

  const EvaluateRequest({
    required this.sessionId,
    required this.attemptId,
    required this.exerciseId,
    required this.exerciseType,
    required this.userAnswer,
    required this.submittedAt,
  });

  Map<String, dynamic> toJson() => {
        'attempt_id': attemptId,
        'exercise_id': exerciseId,
        'exercise_type': exerciseType,
        'user_answer': userAnswer,
        'submitted_at': submittedAt,
      };
}

/// Wave 5 (`LEARNING_ENGINE.md §8.7`) three-valued evaluation outcome.
/// Single-decision families shipped today emit `correct` or `wrong`.
/// `partial` is reserved for Wave 6 multi-unit families.
enum AttemptResult { correct, partial, wrong }

AttemptResult? _parseAttemptResult(String? s) => switch (s) {
      'correct' => AttemptResult.correct,
      'partial' => AttemptResult.partial,
      'wrong' => AttemptResult.wrong,
      _ => null,
    };

class EvaluateResponse {
  final String attemptId;
  final String exerciseId;

  /// Legacy boolean field, preserved for backwards compat. Mirrors
  /// `result == AttemptResult.correct`.
  final bool correct;

  final String? explanation;
  final String canonicalAnswer;

  /// Wave 5 fields. Optional during the Wave 5 rollout window — when a
  /// learner is on a frontend build that pre-dates a backend that has
  /// rolled back, these come back null. Wave 6 multi-unit families
  /// require them.
  final AttemptResult? result;
  final List<dynamic>? responseUnits;

  /// `LEARNING_ENGINE.md §12.3` production-gate invalidation pivot. The
  /// `LearnerSkillStore` reads this on each `recordAttempt` and clears
  /// the sticky `production_gate_cleared` flag if the version moves
  /// under the previously-cleared gate.
  final int? evaluationVersion;

  const EvaluateResponse({
    required this.attemptId,
    required this.exerciseId,
    required this.correct,
    this.explanation,
    required this.canonicalAnswer,
    this.result,
    this.responseUnits,
    this.evaluationVersion,
  });

  factory EvaluateResponse.fromJson(Map<String, dynamic> j) => EvaluateResponse(
        attemptId: j['attempt_id'] as String,
        exerciseId: j['exercise_id'] as String,
        correct: j['correct'] as bool,
        explanation: j['explanation'] as String?,
        canonicalAnswer: j['canonical_answer'] as String,
        result: _parseAttemptResult(j['result'] as String?),
        responseUnits: j['response_units'] is List
            ? List<dynamic>.from(j['response_units'] as List)
            : null,
        evaluationVersion: (j['evaluation_version'] as num?)?.toInt(),
      );
}

class LessonResultAnswer {
  final String exerciseId;
  final bool correct;
  final String? prompt;
  final String? canonicalAnswer;
  final String? explanation;

  const LessonResultAnswer({
    required this.exerciseId,
    required this.correct,
    this.prompt,
    this.canonicalAnswer,
    this.explanation,
  });

  factory LessonResultAnswer.fromJson(Map<String, dynamic> j) =>
      LessonResultAnswer(
        exerciseId: j['exercise_id'] as String,
        correct: j['correct'] as bool,
        prompt: j['prompt'] as String?,
        canonicalAnswer: j['canonical_answer'] as String?,
        explanation: j['explanation'] as String?,
      );
}

enum LessonDebriefType { strong, mixed, needsWork }

LessonDebriefType _parseDebriefType(String? raw) {
  switch (raw) {
    case 'strong':
      return LessonDebriefType.strong;
    case 'needs_work':
      return LessonDebriefType.needsWork;
    case 'mixed':
    default:
      return LessonDebriefType.mixed;
  }
}

class LessonDebrief {
  final LessonDebriefType debriefType;
  final String headline;
  final String body;
  final String? watchOut;
  final String? nextStep;
  final String source;

  const LessonDebrief({
    required this.debriefType,
    required this.headline,
    required this.body,
    this.watchOut,
    this.nextStep,
    required this.source,
  });

  factory LessonDebrief.fromJson(Map<String, dynamic> j) => LessonDebrief(
        debriefType: _parseDebriefType(j['debrief_type'] as String?),
        headline: (j['headline'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
        watchOut: j['watch_out'] as String?,
        nextStep: j['next_step'] as String?,
        source: (j['source'] as String?) ?? 'fallback',
      );
}

class LessonResultResponse {
  final String lessonId;
  final int totalExercises;
  final int correctCount;
  final List<LessonResultAnswer> answers;
  final String? conclusion;
  final LessonDebrief? debrief;

  const LessonResultResponse({
    required this.lessonId,
    required this.totalExercises,
    required this.correctCount,
    required this.answers,
    this.conclusion,
    this.debrief,
  });

  factory LessonResultResponse.fromJson(Map<String, dynamic> j) =>
      LessonResultResponse(
        lessonId: j['lesson_id'] as String,
        totalExercises: j['total_exercises'] as int,
        correctCount: j['correct_count'] as int,
        answers: (j['answers'] as List?)
                ?.map((a) => LessonResultAnswer.fromJson(
                    a as Map<String, dynamic>))
                .toList() ??
            const [],
        conclusion: j['conclusion'] as String?,
        debrief: j['debrief'] is Map<String, dynamic>
            ? LessonDebrief.fromJson(j['debrief'] as Map<String, dynamic>)
            : null,
      );
}
