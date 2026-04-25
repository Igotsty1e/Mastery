enum ExerciseType {
  fillBlank,
  multipleChoice,
  sentenceCorrection,
  listeningDiscrimination,
}

ExerciseType _parseType(String s) => switch (s) {
      'fill_blank' => ExerciseType.fillBlank,
      'multiple_choice' => ExerciseType.multipleChoice,
      'sentence_correction' => ExerciseType.sentenceCorrection,
      'listening_discrimination' => ExerciseType.listeningDiscrimination,
      _ => throw ArgumentError('Unknown exercise type: $s'),
    };

String exerciseTypeToString(ExerciseType t) => switch (t) {
      ExerciseType.fillBlank => 'fill_blank',
      ExerciseType.multipleChoice => 'multiple_choice',
      ExerciseType.sentenceCorrection => 'sentence_correction',
      ExerciseType.listeningDiscrimination => 'listening_discrimination',
    };

class McOption {
  final String id;
  final String text;

  const McOption({required this.id, required this.text});

  factory McOption.fromJson(Map<String, dynamic> j) =>
      McOption(id: j['id'] as String, text: j['text'] as String);
}

enum ExerciseVoice { nova, onyx }

ExerciseVoice _parseVoice(String s) => switch (s) {
      'nova' => ExerciseVoice.nova,
      'onyx' => ExerciseVoice.onyx,
      _ => throw ArgumentError('Unknown voice: $s'),
    };

class ExerciseAudio {
  /// Server path under `/audio` as returned by the lesson endpoint. The client
  /// resolves this against the API base URL when it builds the playback URL.
  final String url;
  final ExerciseVoice voice;
  final String transcript;

  const ExerciseAudio({
    required this.url,
    required this.voice,
    required this.transcript,
  });

  factory ExerciseAudio.fromJson(Map<String, dynamic> j) => ExerciseAudio(
        url: j['url'] as String,
        voice: _parseVoice(j['voice'] as String),
        transcript: j['transcript'] as String,
      );
}

enum ExerciseImageRole {
  sceneSetting,
  contextSupport,
  disambiguation,
  listeningSupport,
}

ExerciseImageRole _parseImageRole(String s) => switch (s) {
      'scene_setting' => ExerciseImageRole.sceneSetting,
      'context_support' => ExerciseImageRole.contextSupport,
      'disambiguation' => ExerciseImageRole.disambiguation,
      'listening_support' => ExerciseImageRole.listeningSupport,
      _ => throw ArgumentError('Unknown image role: $s'),
    };

enum ExerciseImagePolicy { optional, recommended, required }

ExerciseImagePolicy _parseImagePolicy(String s) => switch (s) {
      'optional' => ExerciseImagePolicy.optional,
      'recommended' => ExerciseImagePolicy.recommended,
      'required' => ExerciseImagePolicy.required,
      _ => throw ArgumentError('Unknown image policy: $s'),
    };

class ExerciseImage {
  /// Server path under `/images` (e.g. `/images/{lesson_id}/{exercise_id}.png`).
  /// Resolved against the API base URL by the client when needed.
  final String url;
  final String alt;
  final ExerciseImageRole role;
  final ExerciseImagePolicy policy;

  const ExerciseImage({
    required this.url,
    required this.alt,
    required this.role,
    required this.policy,
  });

  factory ExerciseImage.fromJson(Map<String, dynamic> j) => ExerciseImage(
        url: j['url'] as String,
        alt: j['alt'] as String,
        role: _parseImageRole(j['role'] as String),
        policy: _parseImagePolicy(j['policy'] as String),
      );
}

class Exercise {
  final String exerciseId;
  final ExerciseType type;
  final String instruction;

  /// Present on every type EXCEPT `listening_discrimination`, where the audio
  /// clip carries the prompt instead.
  final String? prompt;

  // multiple_choice + listening_discrimination
  final List<McOption>? options;

  // sentence_correction only
  final bool borderlineAiFallback;

  // listening_discrimination only
  final ExerciseAudio? audio;

  /// Optional Visual Context Layer image, available on any exercise type per
  /// `exercise_structure.md §2.9`.
  final ExerciseImage? image;

  const Exercise({
    required this.exerciseId,
    required this.type,
    required this.instruction,
    this.prompt,
    this.options,
    this.borderlineAiFallback = false,
    this.audio,
    this.image,
  });

  factory Exercise.fromJson(Map<String, dynamic> j) {
    final type = _parseType(j['type'] as String);
    final hasOptions = type == ExerciseType.multipleChoice ||
        type == ExerciseType.listeningDiscrimination;
    return Exercise(
      exerciseId: j['exercise_id'] as String,
      type: type,
      instruction: j['instruction'] as String? ?? '',
      prompt: j['prompt'] as String?,
      options: hasOptions
          ? (j['options'] as List)
              .map((o) => McOption.fromJson(o as Map<String, dynamic>))
              .toList()
          : null,
      borderlineAiFallback: j['borderline_ai_fallback'] as bool? ?? false,
      audio: type == ExerciseType.listeningDiscrimination
          ? ExerciseAudio.fromJson(j['audio'] as Map<String, dynamic>)
          : null,
      image: j['image'] != null
          ? ExerciseImage.fromJson(j['image'] as Map<String, dynamic>)
          : null,
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
