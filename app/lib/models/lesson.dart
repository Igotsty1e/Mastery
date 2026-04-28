enum ExerciseType {
  fillBlank,
  multipleChoice,
  sentenceCorrection,
  sentenceRewrite,
  listeningDiscrimination,
}

ExerciseType _parseType(String s) => switch (s) {
      'fill_blank' => ExerciseType.fillBlank,
      'multiple_choice' => ExerciseType.multipleChoice,
      'sentence_correction' => ExerciseType.sentenceCorrection,
      'sentence_rewrite' => ExerciseType.sentenceRewrite,
      'listening_discrimination' => ExerciseType.listeningDiscrimination,
      _ => throw ArgumentError('Unknown exercise type: $s'),
    };

String exerciseTypeToString(ExerciseType t) => switch (t) {
      ExerciseType.fillBlank => 'fill_blank',
      ExerciseType.multipleChoice => 'multiple_choice',
      ExerciseType.sentenceCorrection => 'sentence_correction',
      ExerciseType.sentenceRewrite => 'sentence_rewrite',
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

/// Engine-side classification of the error an exercise primarily probes,
/// per the V1 spec (§5). Wave 10 (2026-04-26) dropped `transfer` and
/// `pragmatic` — neither was referenced by shipped lesson JSON, so the
/// drop is a clean break with no content rewrite.
enum TargetError {
  conceptual,
  form,
  contrast,
  careless,
}

TargetError? _parseTargetError(String? s) => switch (s) {
      'conceptual_error' => TargetError.conceptual,
      'form_error' => TargetError.form,
      'contrast_error' => TargetError.contrast,
      'careless_error' => TargetError.careless,
      // Old codes from any persisted state pre-Wave 10 silently
      // become null so the parser stays tolerant.
      _ => null,
    };

String targetErrorToString(TargetError e) => switch (e) {
      TargetError.conceptual => 'conceptual_error',
      TargetError.form => 'form_error',
      TargetError.contrast => 'contrast_error',
      TargetError.careless => 'careless_error',
    };

/// Evidence tier per `LEARNING_ENGINE.md §6.1`. Higher tiers count for more
/// in mastery accounting; only `strongest` (with a `meaning_frame`) clears
/// the production gate per §6.4.
enum EvidenceTier { weak, medium, strong, strongest }

EvidenceTier? _parseEvidenceTier(String? s) => switch (s) {
      'weak' => EvidenceTier.weak,
      'medium' => EvidenceTier.medium,
      'strong' => EvidenceTier.strong,
      'strongest' => EvidenceTier.strongest,
      _ => null,
    };

String evidenceTierToString(EvidenceTier t) => switch (t) {
      EvidenceTier.weak => 'weak',
      EvidenceTier.medium => 'medium',
      EvidenceTier.strong => 'strong',
      EvidenceTier.strongest => 'strongest',
    };

class Exercise {
  final String exerciseId;
  final ExerciseType type;
  final String instruction;

  /// Present on every type EXCEPT `listening_discrimination`, where the audio
  /// clip carries the prompt instead.
  final String? prompt;

  // multiple_choice + listening_discrimination
  final List<McOption>? options;

  // listening_discrimination only
  final ExerciseAudio? audio;

  /// Optional Visual Context Layer image, available on any exercise type per
  /// `exercise_structure.md §2.9`.
  final ExerciseImage? image;

  // Wave 1 engine metadata (LEARNING_ENGINE.md §§4–6 + content-contract.md
  // §1.2). Optional during Wave 1 backfill; the client uses them in Wave 2
  // to populate the `LearnerSkillStore`. Older fixtures and item types
  // without metadata stay null and are simply not recorded.
  final String? skillId;
  final TargetError? primaryTargetError;
  final EvidenceTier? evidenceTier;
  final String? meaningFrame;

  const Exercise({
    required this.exerciseId,
    required this.type,
    required this.instruction,
    this.prompt,
    this.options,
    this.audio,
    this.image,
    this.skillId,
    this.primaryTargetError,
    this.evidenceTier,
    this.meaningFrame,
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
      audio: type == ExerciseType.listeningDiscrimination
          ? ExerciseAudio.fromJson(j['audio'] as Map<String, dynamic>)
          : null,
      image: j['image'] != null
          ? ExerciseImage.fromJson(j['image'] as Map<String, dynamic>)
          : null,
      skillId: j['skill_id'] as String?,
      primaryTargetError: _parseTargetError(j['primary_target_error'] as String?),
      evidenceTier: _parseEvidenceTier(j['evidence_tier'] as String?),
      meaningFrame: j['meaning_frame'] as String?,
    );
  }
}

class LessonSummary {
  final String id;
  final String title;
  final String? description;

  /// Number of exercises this lesson contains. Optional for
  /// backwards-compat with older backends that don't emit the field;
  /// the Flutter dashboard treats null as "unknown" and falls back to
  /// the per-lesson `getLesson` fetch when it needs the exact count.
  final int? totalExercises;

  const LessonSummary({
    required this.id,
    required this.title,
    this.description,
    this.totalExercises,
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
      totalExercises: (j['total_exercises'] as num?)?.toInt(),
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

  Lesson copyWith({List<Exercise>? exercises}) => Lesson(
        lessonId: lessonId,
        title: title,
        language: language,
        level: level,
        introRule: introRule,
        introExamples: introExamples,
        exercises: exercises ?? this.exercises,
      );
}
