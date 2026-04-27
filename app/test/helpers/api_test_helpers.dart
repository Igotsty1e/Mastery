// Wave 8 (legacy drop) test helpers.
//
// After the legacy `/lessons/:id/answers` + `/lessons/:id/result` routes
// were dropped, every Flutter test that drives `SessionController` has
// to:
//
//   1. Seed an authenticated session (so `ApiClient` can call
//      `attachAuth` and the `_requireAuth` guard does not throw).
//   2. Mock five HTTP routes instead of two:
//      - `POST /auth/refresh`
//      - `POST /lessons/:id/sessions/start`
//      - `POST /lesson-sessions/:sid/answers`
//      - `POST /lesson-sessions/:sid/complete`
//      - `GET  /lesson-sessions/:sid/result`
//
// `buildAuthedApiClient` packages these into a single helper so tests
// stay focused on what they're verifying instead of repeating the auth
// + session plumbing.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mastery/api/api_client.dart';
import 'package:mastery/auth/auth_client.dart';
import 'package:mastery/auth/auth_storage.dart';

const _testRefreshToken = 'test-refresh-1';
const _testAccessToken = 'test-access-1';
const _testUserId = 'test-user-1';
const _testSessionId = '11111111-2222-4333-8444-555555555555';

class _FakeSecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> _values = {};

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      _values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _values.clear();
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      _values[key];

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(_values);

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _values[key] = value;
  }
}

http.Response jsonResponse(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// Test sessionId baked into the helper. Tests that need a deterministic
/// id can read it from here; tests that don't care just ignore it.
String get testSessionId => _testSessionId;

/// Returns a session-start DTO matching the Wave 7.2 server shape.
/// Passed straight to `jsonResponse(...)` for the mock client.
Map<String, dynamic> sessionStartDto(String lessonId,
    {int exerciseCount = 1}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return {
    'reason': 'created',
    'session_id': _testSessionId,
    'lesson_id': lessonId,
    'lesson_version': 'test-v1',
    'status': 'in_progress',
    'started_at': now,
    'last_activity_at': now,
    'completed_at': null,
    'exercise_count': exerciseCount,
    'answers_so_far': const [],
  };
}

/// Test signature for the per-route dispatch passed by callers. Each
/// closure receives the matched http request and returns the response.
typedef RouteHandler = http.Response Function(http.Request req);

/// Wraps a raw test handler in the auth + secure-storage scaffolding so
/// tests written before Wave 8 (legacy drop) can keep their inline
/// dispatch logic without rewriting boilerplate. The helper:
///
///  - seeds a fake `FlutterSecureStorage` with a usable refresh token,
///  - intercepts `/auth/refresh` and returns a fresh access token,
///  - dispatches every other request through `raw`,
///  - returns an `ApiClient` already wired to the resulting AuthClient.
///
/// Use `buildAuthedApiClient` (below) if you prefer a routes-map.
ApiClient mountAuthedApiClient({
  required String baseUrl,
  required http.Response Function(http.Request req) raw,
}) {
  final fake = _FakeSecureStorage();
  FlutterSecureStoragePlatform.instance = fake;
  fake._values['mastery_refresh_token_v1'] = _testRefreshToken;
  fake._values['mastery_user_id_v1'] = _testUserId;
  fake._values['mastery_access_expiry_v1'] =
      DateTime.now().toUtc().add(const Duration(minutes: 14)).toIso8601String();

  final client = MockClient((req) async {
    if (req.url.path.endsWith('/auth/refresh')) {
      return jsonResponse({
        'accessToken': _testAccessToken,
        'refreshToken': _testRefreshToken,
        'accessTokenExpiresIn': 900,
      });
    }
    return raw(req);
  });

  final authClient = AuthClient(
    baseUrl: baseUrl,
    http: client,
    storage: AuthStorage(storage: const FlutterSecureStorage()),
  );

  return ApiClient(baseUrl: baseUrl, client: client, authClient: authClient);
}

/// Returns an `ApiClient` already wired to a fake `AuthClient` whose
/// secure storage is seeded with a valid refresh token. The MockClient
/// dispatches based on URL path:
///
///  - `/auth/refresh` → mints a fresh access token (always 200).
///  - `routes` map → user-provided handlers keyed by URL substring.
///    First substring match wins.
///  - Anything else → 404 with body `unmocked_route`.
ApiClient buildAuthedApiClient({
  required String baseUrl,
  required Map<String, RouteHandler> routes,
}) {
  final fake = _FakeSecureStorage();
  FlutterSecureStoragePlatform.instance = fake;
  fake._values['mastery_refresh_token_v1'] = _testRefreshToken;
  fake._values['mastery_user_id_v1'] = _testUserId;
  fake._values['mastery_access_expiry_v1'] =
      DateTime.now().toUtc().add(const Duration(minutes: 14)).toIso8601String();

  final client = MockClient((req) async {
    final path = req.url.path;
    if (path.endsWith('/auth/refresh')) {
      return jsonResponse({
        'accessToken': _testAccessToken,
        'refreshToken': _testRefreshToken,
        'accessTokenExpiresIn': 900,
      });
    }
    for (final entry in routes.entries) {
      if (path.contains(entry.key)) return entry.value(req);
    }
    return jsonResponse({'error': 'unmocked_route', 'path': path}, status: 404);
  });

  final authClient = AuthClient(
    baseUrl: baseUrl,
    http: client,
    storage: AuthStorage(storage: const FlutterSecureStorage()),
  );

  final api = ApiClient(baseUrl: baseUrl, client: client, authClient: authClient);
  return api;
}
