import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/evaluation.dart';
import '../models/lesson.dart';

class ApiException implements Exception {
  final int statusCode;
  final String body;

  const ApiException(this.statusCode, this.body);

  @override
  String toString() => 'ApiException($statusCode): $body';
}

class ApiClient {
  final String baseUrl;
  final http.Client _client;

  ApiClient({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

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

  Future<EvaluateResponse> submitAnswer(
      String lessonId, EvaluateRequest request) async {
    final res = await _client.post(
      Uri.parse('$baseUrl/lessons/$lessonId/answers'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );
    _assertOk(res);
    return EvaluateResponse.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<LessonResultResponse> getResult(
      String lessonId, String sessionId) async {
    final uri = Uri.parse('$baseUrl/lessons/$lessonId/result')
        .replace(queryParameters: {'session_id': sessionId});
    final res = await _client.get(uri);
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
