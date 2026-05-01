import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_client.dart';
import '../models/evaluation.dart';
import '../models/lesson.dart';
import 'diagnostic_dtos.dart';

class ApiException implements Exception {
  final int statusCode;
  final String body;

  const ApiException(this.statusCode, this.body);

  @override
  String toString() => 'ApiException($statusCode): $body';
}

/// HTTP gateway for the Flutter client. Wave 8 (legacy drop) shifted
/// every mutation off the unauthenticated `/lessons/:id/answers` and
/// `/lessons/:id/result` routes and onto the auth-protected server-owned
/// session endpoints. The two read-only public routes — `GET /lessons`
/// (curriculum manifest) and `GET /lessons/:id` (lesson content) —
/// remain unauthenticated so the dashboard's first paint and the lesson
/// loader work even before the AuthClient is attached.
///
/// Tests use the constructor's `client:` and `authClient:` slots to
/// inject `MockClient` / a fake AuthClient. Production wiring lives in
/// `main.dart`: a single `ApiClient` is registered as a Provider, then
/// `HomeScreen._activateAuthenticatedClients` calls `attachAuth` once
/// the sign-in (or silent-stub) flow has minted a session.
class ApiClient {
  final String baseUrl;
  final http.Client _client;
  AuthClient? _auth;

  ApiClient({
    required this.baseUrl,
    http.Client? client,
    AuthClient? authClient,
  })  : _client = client ?? http.Client(),
        _auth = authClient;

  /// Wave 8: HomeScreen calls this once the auth flow has produced a
  /// live session (returning user with a refresh token, fresh sign-in,
  /// or silent-stub Skip). Idempotent — a second call replaces the
  /// reference. The MutableProvider pattern keeps the same ApiClient
  /// instance alive across the auth transition so SessionController and
  /// other downstream consumers do not need to be torn down.
  void attachAuth(AuthClient authClient) {
    _auth = authClient;
  }

  AuthClient _requireAuth() {
    final a = _auth;
    if (a == null) {
      throw const ApiException(
        401,
        'auth_not_attached: ApiClient mutations require attachAuth() first',
      );
    }
    return a;
  }

  Future<List<LessonSummary>> fetchLessons() async {
    final res = await _client.get(Uri.parse('$baseUrl/lessons'));
    _assertOk(res);

    final decoded = jsonDecode(res.body);
    final lessonsJson = switch (decoded) {
      List<dynamic> list => list,
      Map<String, dynamic> map when map['lessons'] is List<dynamic> =>
        map['lessons'] as List<dynamic>,
      _ => throw const FormatException('Invalid lessons response'),
    };

    return lessonsJson
        .map((lesson) => LessonSummary.fromJson(lesson as Map<String, dynamic>))
        .toList();
  }

  Future<List<LessonSummary>> getLessons() => fetchLessons();

  Future<Lesson> getLesson(String lessonId) async {
    final res = await _client.get(Uri.parse('$baseUrl/lessons/$lessonId'));
    _assertOk(res);
    return Lesson.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Wave 8 — `POST /lessons/:lessonId/sessions/start`. Resume-or-create
  /// per the Wave 7.2 contract. Returns the server-owned session id;
  /// SessionController uses it for every subsequent answer + the final
  /// result fetch.
  Future<LessonSessionStart> startLessonSession(String lessonId) async {
    final auth = _requireAuth();
    final res = await auth.send(
      'POST',
      Uri.parse('$baseUrl/lessons/$lessonId/sessions/start'),
    );
    _assertOk(res);
    return LessonSessionStart.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Wave 11.3 — `POST /sessions/start` (dynamic). Creates a server-
  /// owned session NOT bound to a single lesson fixture; the Decision
  /// Engine assembles each exercise from the bank.
  ///
  /// Returns the session id, frame metadata ("Today's session", level),
  /// and the first picked exercise. SessionController uses it as the
  /// new entry point in place of `startLessonSession + getLesson`.
  Future<DynamicSessionStart> startSession() async {
    final auth = _requireAuth();
    final res = await auth.send(
      'POST',
      Uri.parse('$baseUrl/sessions/start'),
    );
    _assertOk(res);
    return DynamicSessionStart.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Wave 11.3 — `POST /lesson-sessions/:sessionId/next`. After an
  /// answer is recorded, the client polls this endpoint to get the
  /// next exercise the Decision Engine picked. `next` is null when
  /// the session has reached its target length; the client should
  /// then call `completeLessonSession` + `getResult`.
  Future<DynamicNextResult> nextExercise(String sessionId) async {
    final auth = _requireAuth();
    final res = await auth.send(
      'POST',
      Uri.parse('$baseUrl/lesson-sessions/$sessionId/next'),
    );
    _assertOk(res);
    return DynamicNextResult.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Wave 8 — `POST /lesson-sessions/:sessionId/answers`. The body shape
  /// matches Wave 7.2 `Wave2AnswerSchema`; the `sessionId` from
  /// `startLessonSession` replaces the legacy lesson-scoped route.
  Future<EvaluateResponse> submitAnswer(
    String sessionId,
    EvaluateRequest request,
  ) async {
    final auth = _requireAuth();
    final body = {
      'attempt_id': request.attemptId,
      'exercise_id': request.exerciseId,
      'exercise_type': request.exerciseType,
      'user_answer': request.userAnswer,
      'submitted_at': request.submittedAt,
    };
    final res = await auth.send(
      'POST',
      Uri.parse('$baseUrl/lesson-sessions/$sessionId/answers'),
      body: body,
    );
    _assertOk(res);
    return EvaluateResponse.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Wave 8 — `GET /lesson-sessions/:sessionId/result`. Used by
  /// SessionController.fetchSummary; the legacy lesson-scoped route is
  /// gone.
  Future<LessonResultResponse> getResult(String sessionId) async {
    final auth = _requireAuth();
    final res = await auth.send(
      'GET',
      Uri.parse('$baseUrl/lesson-sessions/$sessionId/result'),
    );
    _assertOk(res);
    return LessonResultResponse.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Wave 8 — `POST /lesson-sessions/:sessionId/complete`. Builds the
  /// debrief snapshot and upserts `lesson_progress`. Idempotent. Called
  /// once per finished session, before the result fetch.
  Future<LessonResultResponse> completeLessonSession(String sessionId) async {
    final auth = _requireAuth();
    final res = await auth.send(
      'POST',
      Uri.parse('$baseUrl/lesson-sessions/$sessionId/complete'),
    );
    _assertOk(res);
    return LessonResultResponse.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Wave 12.3 — `GET /me`. Returns `profile.level` (`null` when the
  /// learner has never finished a diagnostic). The HomeScreen routing
  /// gate uses this to decide whether to surface the probe between
  /// sign-in and onboarding. Errors → null so the gate falls through
  /// to the onboarding ritual rather than blocking the app on a
  /// transient network failure.
  Future<String?> getMyLevel() async {
    try {
      final auth = _requireAuth();
      final res = await auth.send(
        'GET',
        Uri.parse('$baseUrl/me'),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final profile = body['profile'];
      if (profile is Map<String, dynamic>) {
        return profile['level'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // Wave 14.3 phase 2 — V1.5 feedback system. The SummaryScreen prompt
  // is the only consumer today; phase 3 will add the after-friction
  // surface in the exercise screen. Both endpoints are auth-gated and
  // share the same 24h per-prompt-kind cooldown enforced server-side.
  // ────────────────────────────────────────────────────────────────────

  /// `GET /me/feedback/cooldown`. Quiet, idempotent gate the client
  /// reads before deciding whether to render either prompt. Network
  /// failures resolve to `null` so the caller can treat that as
  /// "do not prompt" without surfacing an error to the learner.
  Future<FeedbackCooldown?> getFeedbackCooldown() async {
    try {
      final auth = _requireAuth();
      final res = await auth.send(
        'GET',
        Uri.parse('$baseUrl/me/feedback/cooldown'),
      );
      if (res.statusCode != 200) return null;
      return FeedbackCooldown.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// `POST /me/feedback`. Best-effort: 429 (cooldown raced our gate
  /// read) is silently absorbed so the caller does not bother the
  /// learner with a "you can't rate again" message. Other errors
  /// throw so the caller can surface a generic toast if it wants.
  Future<void> submitFeedback({
    required String promptKind, // 'after_summary' | 'after_friction'
    required String outcome, // 'submitted' | 'dismissed'
    int? rating,
    String? commentText,
    Map<String, dynamic>? context,
  }) async {
    final auth = _requireAuth();
    final body = <String, dynamic>{
      'prompt_kind': promptKind,
      'outcome': outcome,
      if (rating != null) 'rating': rating,
      if (commentText != null && commentText.trim().isNotEmpty)
        'comment_text': commentText.trim(),
      if (context != null && context.isNotEmpty) 'context': context,
    };
    final res = await auth.send(
      'POST',
      Uri.parse('$baseUrl/me/feedback'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode == 201 || res.statusCode == 429) return;
    _assertOk(res);
  }

  /// Wave G4 — analytics ingest. Best-effort: any non-200 response
  /// (including 401 when auth has not been attached yet) is
  /// swallowed silently. Analytics MUST NEVER block the user-facing
  /// flow, so callers don't need to handle exceptions; this method
  /// returns `true` when the batch landed and `false` otherwise so
  /// the `Analytics` queue can decide whether to drop or retry.
  Future<bool> trackEvents(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return true;
    final auth = _auth;
    if (auth == null) return false;
    try {
      final res = await auth.send(
        'POST',
        Uri.parse('$baseUrl/me/events'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'events': events}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // Wave 12.3 — diagnostic-mode endpoints (V1 spec §15). Auth-protected.
  // The probe is a 5-item multiple_choice run that scores into a CEFR
  // level + per-skill status map. The client orchestrates one /answers
  // call per pick, then /complete to land the derivation.
  // ────────────────────────────────────────────────────────────────────

  /// `POST /diagnostic/start`. Creates a fresh run if none is active;
  /// resumes the active one otherwise (HTTP 200 vs 201 — both
  /// accepted). The DTO carries `resumed=true` on the resume path so
  /// the client can word the welcome screen accordingly.
  Future<DiagnosticStart> startDiagnostic() async {
    final auth = _requireAuth();
    final res = await auth.send(
      'POST',
      Uri.parse('$baseUrl/diagnostic/start'),
    );
    _assertOk(res);
    return DiagnosticStart.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// `POST /diagnostic/:runId/answers`. The diagnostic flow records
  /// the attempt server-side and returns the next item in the same
  /// response, so the client never has to call a separate `/next`
  /// endpoint.
  Future<DiagnosticAnswerResult> submitDiagnosticAnswer({
    required String runId,
    required String exerciseId,
    required String exerciseType,
    required String userAnswer,
    DateTime? submittedAt,
  }) async {
    final auth = _requireAuth();
    final body = <String, dynamic>{
      'exercise_id': exerciseId,
      'exercise_type': exerciseType,
      'user_answer': userAnswer,
      'submitted_at':
          (submittedAt ?? DateTime.now().toUtc()).toIso8601String(),
    };
    final res = await auth.send(
      'POST',
      Uri.parse('$baseUrl/diagnostic/$runId/answers'),
      body: body,
    );
    _assertOk(res);
    return DiagnosticAnswerResult.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// `POST /diagnostic/:runId/complete`. Idempotent — a second call
  /// returns the persisted derivation with `alreadyCompleted=true`.
  Future<DiagnosticCompletion> completeDiagnostic(String runId) async {
    final auth = _requireAuth();
    final res = await auth.send(
      'POST',
      Uri.parse('$baseUrl/diagnostic/$runId/complete'),
    );
    _assertOk(res);
    return DiagnosticCompletion.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// `POST /diagnostic/restart`. Abandons any active run + writes a
  /// `diagnostic_abandoned` audit event, then starts a fresh run.
  /// Returns the same DTO shape as `startDiagnostic`.
  Future<DiagnosticStart> restartDiagnostic() async {
    final auth = _requireAuth();
    final res = await auth.send(
      'POST',
      Uri.parse('$baseUrl/diagnostic/restart'),
    );
    _assertOk(res);
    return DiagnosticStart.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// `POST /diagnostic/skip`. Fire-and-forget — records the
  /// `diagnostic_skipped` audit event for D1 retention cohort
  /// analysis. Failures are swallowed because telemetry is
  /// best-effort and must not block the skip path.
  Future<void> skipDiagnostic() async {
    try {
      final auth = _requireAuth();
      final res = await auth.send(
        'POST',
        Uri.parse('$baseUrl/diagnostic/skip'),
      );
      // 204 No Content is the success path; 401 is acceptable here
      // because the skip is best-effort.
      if (res.statusCode >= 500) {
        // Still swallow — server outages must not block onboarding.
      }
    } on ApiException {
      // Swallow — see method docstring.
    } on Exception {
      // Swallow.
    }
  }

  void _assertOk(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, res.body);
    }
  }

  void dispose() => _client.close();
}

/// Response of `POST /lessons/:lessonId/sessions/start`. The DTO carries
/// more than the session id (lesson_version, started_at, answers_so_far
/// for resume); the client only reads `sessionId` today, but the rest is
/// kept for resume-mid-session in a follow-up wave.
class LessonSessionStart {
  final String sessionId;
  final String lessonId;
  final String lessonVersion;
  final String status;
  final int exerciseCount;

  const LessonSessionStart({
    required this.sessionId,
    required this.lessonId,
    required this.lessonVersion,
    required this.status,
    required this.exerciseCount,
  });

  factory LessonSessionStart.fromJson(Map<String, dynamic> j) {
    return LessonSessionStart(
      sessionId: j['session_id'] as String,
      lessonId: j['lesson_id'] as String,
      lessonVersion: j['lesson_version'] as String? ?? '',
      status: j['status'] as String? ?? 'in_progress',
      exerciseCount: (j['exercise_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Wave 11.3 — response of `POST /sessions/start`. Carries the server's
/// session id, the "Today's session" framing copy, and the first
/// picked exercise. SessionController consumes the exercise directly
/// (no separate `getLesson` round-trip needed).
class DynamicSessionStart {
  final String sessionId;
  final String title;
  final String level;
  final int exerciseCount;
  final Exercise firstExercise;

  const DynamicSessionStart({
    required this.sessionId,
    required this.title,
    required this.level,
    required this.exerciseCount,
    required this.firstExercise,
  });

  factory DynamicSessionStart.fromJson(Map<String, dynamic> j) {
    return DynamicSessionStart(
      sessionId: j['session_id'] as String,
      title: j['title'] as String? ?? "Today\u2019s session",
      level: j['level'] as String? ?? 'B2',
      exerciseCount: (j['exercise_count'] as num?)?.toInt() ?? 10,
      firstExercise:
          Exercise.fromJson(j['first_exercise'] as Map<String, dynamic>),
    );
  }
}

/// Wave 11.3 — response of `POST /lesson-sessions/:sid/next`. `next` is
/// null when the session has reached the engine's target length; the
/// client should then complete + fetch the result.
class DynamicNextResult {
  final String? reason;
  final int position;
  final Exercise? next;

  const DynamicNextResult({
    required this.reason,
    required this.position,
    required this.next,
  });

  factory DynamicNextResult.fromJson(Map<String, dynamic> j) {
    final raw = j['next_exercise'];
    return DynamicNextResult(
      reason: j['reason'] as String?,
      position: (j['position'] as num?)?.toInt() ?? 0,
      next: raw is Map<String, dynamic> ? Exercise.fromJson(raw) : null,
    );
  }
}

/// Wave 14.3 phase 2 — V1.5 feedback cooldown gate. Both
/// `*_allowed` flags are computed server-side from a 24h sliding
/// window over `feedback_responses.created_at` (regardless of
/// outcome).
class FeedbackCooldown {
  final int cooldownHours;
  final bool afterSummaryAllowed;
  final bool afterFrictionAllowed;

  const FeedbackCooldown({
    required this.cooldownHours,
    required this.afterSummaryAllowed,
    required this.afterFrictionAllowed,
  });

  factory FeedbackCooldown.fromJson(Map<String, dynamic> j) =>
      FeedbackCooldown(
        cooldownHours: (j['cooldown_hours'] as num).toInt(),
        afterSummaryAllowed: j['after_summary_allowed'] as bool,
        afterFrictionAllowed: j['after_friction_allowed'] as bool,
      );
}
