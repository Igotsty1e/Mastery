import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_client.dart';
import '../models/evaluation.dart';
import '../models/lesson.dart';

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
