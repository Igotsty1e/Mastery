enum ExerciseType { fillBlank, multipleChoice, sentenceCorrection }

ExerciseType _parseType(String s) => switch (s) {
      'fill_blank' => ExerciseType.fillBlank,
      'multiple_choice' => ExerciseType.multipleChoice,
      'sentence_correction' => ExerciseType.sentenceCorrection,
      _ => throw ArgumentError('Unknown exercise type: $s'),
    };

String exerciseTypeToString(ExerciseType t) => switch (t) {
      ExerciseType.fillBlank => 'fill_blank',
      ExerciseType.multipleChoice => 'multiple_choice',
      ExerciseType.sentenceCorrection => 'sentence_correction',
    };

class McOption {
  final String id;
  final String text;

  const McOption({required this.id, required this.text});

  factory McOption.fromJson(Map<String, dynamic> j) =>
      McOption(id: j['id'] as String, text: j['text'] as String);
}

class Exercise {
  final String exerciseId;
  final ExerciseType type;
  final String prompt;

  // fill_blank only
  final String? hint;

  // multiple_choice only
  final List<McOption>? options;

  // sentence_correction only
  final bool borderlineAiFallback;

  const Exercise({
    required this.exerciseId,
    required this.type,
    required this.prompt,
    this.hint,
    this.options,
    this.borderlineAiFallback = false,
  });

  factory Exercise.fromJson(Map<String, dynamic> j) {
    final type = _parseType(j['type'] as String);
    return Exercise(
      exerciseId: j['exercise_id'] as String,
      type: type,
      prompt: j['prompt'] as String,
      hint: j['hint'] as String?,
      options: type == ExerciseType.multipleChoice
          ? (j['options'] as List)
              .map((o) => McOption.fromJson(o as Map<String, dynamic>))
              .toList()
          : null,
      borderlineAiFallback: j['borderline_ai_fallback'] as bool? ?? false,
    );
  }
}

class LessonSummary {
  final String id;
  final String title;
  final String? description;

  const LessonSummary({
    required this.id,
    required this.title,
    this.description,
  });

  factory LessonSummary.fromJson(Map<String, dynamic> j) {
    final id = j['id'] ?? j['lesson_id'];
    if (id is! String) {
      throw const FormatException('Lesson summary is missing a valid id');
    }

    final title = j['title'];
    if (title is! String) {
      throw const FormatException('Lesson summary is missing a valid title');
    }

    return LessonSummary(
      id: id,
      title: title,
      description: j['description'] as String?,
    );
  }
}

class Lesson {
  final String lessonId;
  final String title;
  final String language;
  final String level;
  final String introRule;
  final List<String> introExamples;
  final List<Exercise> exercises;

  const Lesson({
    required this.lessonId,
    required this.title,
    required this.language,
    required this.level,
    required this.introRule,
    required this.introExamples,
    required this.exercises,
  });

  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
        lessonId: j['lesson_id'] as String,
        title: j['title'] as String,
        language: j['language'] as String,
        level: j['level'] as String,
        introRule: j['intro_rule'] as String? ?? '',
        introExamples:
            (j['intro_examples'] as List?)?.map((e) => e as String).toList() ??
                const [],
        exercises: (j['exercises'] as List)
            .map((e) => Exercise.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
