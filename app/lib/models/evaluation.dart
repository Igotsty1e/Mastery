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
  final String? practicalTip;
  final String canonicalAnswer;

  const EvaluateResponse({
    required this.attemptId,
    required this.exerciseId,
    required this.correct,
    required this.evaluationSource,
    this.explanation,
    this.practicalTip,
    required this.canonicalAnswer,
  });

  factory EvaluateResponse.fromJson(Map<String, dynamic> j) => EvaluateResponse(
        attemptId: j['attempt_id'] as String,
        exerciseId: j['exercise_id'] as String,
        correct: j['correct'] as bool,
        evaluationSource: j['evaluation_source'] as String,
        explanation: j['explanation'] as String?,
        practicalTip: j['practical_tip'] as String?,
        canonicalAnswer: j['canonical_answer'] as String,
      );
}

class LessonResultAnswer {
  final String exerciseId;
  final bool correct;

  const LessonResultAnswer({required this.exerciseId, required this.correct});

  factory LessonResultAnswer.fromJson(Map<String, dynamic> j) =>
      LessonResultAnswer(
        exerciseId: j['exercise_id'] as String,
        correct: j['correct'] as bool,
      );
}

class LessonResultResponse {
  final String lessonId;
  final int totalExercises;
  final int correctCount;
  final List<LessonResultAnswer> answers;

  const LessonResultResponse({
    required this.lessonId,
    required this.totalExercises,
    required this.correctCount,
    required this.answers,
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
      );
}
