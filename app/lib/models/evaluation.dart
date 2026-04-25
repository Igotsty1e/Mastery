class EvaluateRequest {
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
        'session_id': sessionId,
        'attempt_id': attemptId,
        'exercise_id': exerciseId,
        'exercise_type': exerciseType,
        'user_answer': userAnswer,
        'submitted_at': submittedAt,
      };
}

class EvaluateResponse {
  final String attemptId;
  final String exerciseId;
  final bool correct;
  final String evaluationSource;
  final String? explanation;
  final String canonicalAnswer;

  const EvaluateResponse({
    required this.attemptId,
    required this.exerciseId,
    required this.correct,
    required this.evaluationSource,
    this.explanation,
    required this.canonicalAnswer,
  });

  factory EvaluateResponse.fromJson(Map<String, dynamic> j) => EvaluateResponse(
        attemptId: j['attempt_id'] as String,
        exerciseId: j['exercise_id'] as String,
        correct: j['correct'] as bool,
        evaluationSource: j['evaluation_source'] as String,
        explanation: j['explanation'] as String?,
        canonicalAnswer: j['canonical_answer'] as String,
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
