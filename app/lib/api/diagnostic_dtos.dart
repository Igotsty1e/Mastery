// Wave 12.3 — Flutter DTOs for the four /diagnostic/... endpoints
// shipped in Wave 12.2.
//
// Each shape mirrors the JSON the backend returns; field names follow
// the Dart camelCase convention while the wire stays snake_case (as
// throughout the rest of the client).

import '../models/lesson.dart';

/// Response of `POST /diagnostic/start` (and `restart`). `nextExercise`
/// is the projected multiple_choice item at the run's current
/// position; null when the run was created without any items in the
/// pool (defensive — the server returns 503 in that case before this
/// DTO is built).
class DiagnosticStart {
  final String runId;
  final bool resumed;
  final int position;
  final int total;
  final Exercise? nextExercise;

  const DiagnosticStart({
    required this.runId,
    required this.resumed,
    required this.position,
    required this.total,
    required this.nextExercise,
  });

  factory DiagnosticStart.fromJson(Map<String, dynamic> j) {
    final next = j['next_exercise'];
    return DiagnosticStart(
      runId: j['run_id'] as String,
      resumed: (j['resumed'] as bool?) ?? false,
      position: (j['position'] as num).toInt(),
      total: (j['total'] as num).toInt(),
      nextExercise: next == null
          ? null
          : Exercise.fromJson(next as Map<String, dynamic>),
    );
  }
}

/// Response of `POST /diagnostic/:runId/answers`. The diagnostic flow
/// never reveals correctness in-line per V1 spec §10, so the client
/// reads `runComplete` and `nextExercise` and ignores `result` /
/// `canonicalAnswer` / `explanation` in the probe phase. They are
/// still on the wire for parity with lesson-session evaluation +
/// future use (e.g. a "review what you got wrong" surface in the
/// completion phase).
class DiagnosticAnswerResult {
  final String result; // 'correct' | 'wrong'
  final String evaluationSource;
  final String canonicalAnswer;
  final String? explanation;
  final bool runComplete;
  final int position;
  final int total;
  final Exercise? nextExercise;

  const DiagnosticAnswerResult({
    required this.result,
    required this.evaluationSource,
    required this.canonicalAnswer,
    required this.explanation,
    required this.runComplete,
    required this.position,
    required this.total,
    required this.nextExercise,
  });

  factory DiagnosticAnswerResult.fromJson(Map<String, dynamic> j) {
    final next = j['next_exercise'];
    return DiagnosticAnswerResult(
      result: j['result'] as String,
      evaluationSource: j['evaluation_source'] as String,
      canonicalAnswer: (j['canonical_answer'] as String?) ?? '',
      explanation: j['explanation'] as String?,
      runComplete: (j['run_complete'] as bool?) ?? false,
      position: (j['position'] as num).toInt(),
      total: (j['total'] as num).toInt(),
      nextExercise: next == null
          ? null
          : Exercise.fromJson(next as Map<String, dynamic>),
    );
  }
}

/// Response of `POST /diagnostic/:runId/complete`. Idempotent — a
/// second call returns the persisted derivation with
/// `alreadyCompleted = true`.
class DiagnosticCompletion {
  final String runId;
  final String cefrLevel; // 'A2' | 'B1' | 'B2' | 'C1'
  /// skill_id → status label per LEARNING_ENGINE.md §7.2. Today the
  /// V1 derivation only emits 'started' or 'practicing'; richer
  /// statuses are V1.5 territory.
  final Map<String, String> skillMap;
  final DateTime? completedAt;
  final bool alreadyCompleted;

  const DiagnosticCompletion({
    required this.runId,
    required this.cefrLevel,
    required this.skillMap,
    required this.completedAt,
    required this.alreadyCompleted,
  });

  factory DiagnosticCompletion.fromJson(Map<String, dynamic> j) {
    final skillMapRaw = j['skill_map'];
    final Map<String, String> skillMap = {};
    if (skillMapRaw is Map<String, dynamic>) {
      for (final entry in skillMapRaw.entries) {
        skillMap[entry.key] = entry.value.toString();
      }
    }
    final completedAtRaw = j['completed_at'];
    return DiagnosticCompletion(
      runId: j['run_id'] as String,
      cefrLevel: j['cefr_level'] as String,
      skillMap: skillMap,
      completedAt: completedAtRaw is String
          ? DateTime.tryParse(completedAtRaw)
          : null,
      alreadyCompleted: (j['already_completed'] as bool?) ?? false,
    );
  }
}
