import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_storage.dart';
import 'auth_tokens.dart';

/// Thrown by the AuthClient when a refresh attempt definitively fails
/// (server returned 401, or refresh token absent). Callers should clear
/// local state and surface a sign-in prompt.
class AuthSessionExpired implements Exception {
  final String reason;
  const AuthSessionExpired(this.reason);
  @override
  String toString() => 'AuthSessionExpired: $reason';
}

/// Wave 7.4 part 1 — auth orchestration layer. Sits between the
/// application code and the bare HTTP client. Knows how to:
///
/// 1. Sign in via the Apple stub (or the real Apple verifier when it
///    lands) and persist the resulting refresh token in
///    `AuthStorage`.
/// 2. Add `Authorization: Bearer <access>` to every outbound request.
/// 3. Transparently refresh the access token on a 401 response and
///    retry the original request once.
/// 4. Refuse to refresh more than once per request — a refresh that
///    returns 401 means the refresh token chain itself is revoked.
///    The client clears storage and throws `AuthSessionExpired`.
///
/// Part 1 ships **dormant**: nothing in the app currently constructs
/// an AuthClient. `ApiClient` keeps using a plain `http.Client`. The
/// part 2 plan-doc design call decides where the sign-in screen
/// appears; only after that lands does anyone wire AuthClient into
/// the request path.
class AuthClient {
  final String baseUrl;
  final http.Client _http;
  final AuthStorage _storage;

  AuthTokens? _cached;
  Future<AuthTokens?>? _inflightRefresh;

  AuthClient({
    required this.baseUrl,
    http.Client? http,
    AuthStorage? storage,
  })  : _http = http ?? _defaultClient(),
        _storage = storage ?? AuthStorage();

  static http.Client _defaultClient() => http.Client();

  /// Apple stub login. The real Sign-In-with-Apple flow swaps the
  /// `provider` and `subject` for an `identityToken` once the iOS
  /// integration lands; the response shape stays the same so this
  /// method's signature does not need to change.
  Future<AuthTokens> signInWithAppleStub({required String subject}) async {
    final resp = await _http.post(
      Uri.parse('$baseUrl/auth/apple/stub/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'subject': subject}),
    );
    if (resp.statusCode != 200) {
      throw AuthSessionExpired('apple_stub_login_${resp.statusCode}');
    }
    final tokens = AuthTokens.fromLoginJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
    );
    _cached = tokens;
    await _storage.writeRefresh(
      refreshToken: tokens.refreshToken,
      userId: tokens.userId,
      accessExpiresAt: tokens.accessExpiresAt,
    );
    return tokens;
  }

  /// Reads the persisted refresh token and mints a fresh access token.
  /// Callers should treat a `null` return as "no session — show
  /// sign-in." The method does **not** throw on a missing refresh; it
  /// throws only when a refresh attempt is made and the server rejects
  /// the chain.
  Future<AuthTokens?> hydrateFromStorage() async {
    final refresh = await _storage.readRefresh();
    final userId = await _storage.readUserId();
    if (refresh == null || userId == null) return null;
    return _refreshWithToken(refresh, userId);
  }

  /// Signed request. Adds `Authorization` from cache, hydrates if cache
  /// is empty, retries once on 401 after a transparent refresh.
  Future<http.Response> send(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final tokens = await _ensureFreshTokens();
    if (tokens == null) {
      throw const AuthSessionExpired('no_session');
    }
    final firstResp = await _sendOnce(method, url, headers, body, tokens);
    if (firstResp.statusCode != 401) return firstResp;

    // 401 path: refresh once and retry.
    final refreshed = await _refresh();
    if (refreshed == null) {
      throw const AuthSessionExpired('refresh_returned_null');
    }
    final retryResp = await _sendOnce(method, url, headers, body, refreshed);
    if (retryResp.statusCode == 401) {
      // The fresh access token was rejected — server-side revocation
      // happened mid-flight. Clear and force re-login.
      await _storage.clear();
      _cached = null;
      throw const AuthSessionExpired('retry_still_401');
    }
    return retryResp;
  }

  /// Logs out the current session on the backend and clears local
  /// storage. Idempotent: missing tokens just clear local state.
  Future<void> logout() async {
    final tokens = _cached ??
        await () async {
          final refresh = await _storage.readRefresh();
          final userId = await _storage.readUserId();
          if (refresh == null || userId == null) return null;
          return AuthTokens(
            accessToken: '',
            refreshToken: refresh,
            accessExpiresAt: DateTime.now().toUtc(),
            userId: userId,
          );
        }();
    if (tokens != null && tokens.accessToken.isNotEmpty) {
      try {
        await _http.post(
          Uri.parse('$baseUrl/auth/logout'),
          headers: {
            'Authorization': 'Bearer ${tokens.accessToken}',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'refreshToken': tokens.refreshToken}),
        );
      } catch (_) {
        // Network failures during logout are non-fatal — local clear
        // happens regardless. The server-side session also expires on
        // its own 30-day timer, so a missed call leaks at most that
        // window for an attacker who already has the refresh token.
      }
    }
    _cached = null;
    await _storage.clear();
  }

  Future<http.Response> _sendOnce(
    String method,
    Uri url,
    Map<String, String>? extraHeaders,
    Object? body,
    AuthTokens tokens,
  ) {
    final headers = <String, String>{
      'Authorization': 'Bearer ${tokens.accessToken}',
      if (body != null) 'Content-Type': 'application/json',
      ...?extraHeaders,
    };
    final encoded = body == null
        ? null
        : body is String
            ? body
            : jsonEncode(body);
    switch (method.toUpperCase()) {
      case 'GET':
        return _http.get(url, headers: headers);
      case 'POST':
        return _http.post(url, headers: headers, body: encoded);
      case 'PATCH':
        return _http.patch(url, headers: headers, body: encoded);
      case 'PUT':
        return _http.put(url, headers: headers, body: encoded);
      case 'DELETE':
        return _http.delete(url, headers: headers);
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }
  }

  Future<AuthTokens?> _ensureFreshTokens() async {
    if (_cached != null && !_cached!.accessNearExpiry) return _cached;
    if (_cached == null) {
      // Try hydrating from storage.
      return hydrateFromStorage();
    }
    // Cache hit but near-expiry — refresh proactively.
    return _refresh();
  }

  Future<AuthTokens?> _refresh() async {
    final inflight = _inflightRefresh;
    if (inflight != null) return inflight;
    final completer = Completer<AuthTokens?>();
    _inflightRefresh = completer.future;
    try {
      final refresh = _cached?.refreshToken ?? await _storage.readRefresh();
      final userId = _cached?.userId ?? await _storage.readUserId();
      if (refresh == null || userId == null) {
        completer.complete(null);
        return null;
      }
      final tokens = await _refreshWithToken(refresh, userId);
      completer.complete(tokens);
      return tokens;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _inflightRefresh = null;
    }
  }

  Future<AuthTokens?> _refreshWithToken(
    String refreshToken,
    String userId,
  ) async {
    final resp = await _http.post(
      Uri.parse('$baseUrl/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    if (resp.statusCode == 401) {
      await _storage.clear();
      _cached = null;
      return null;
    }
    if (resp.statusCode != 200) {
      throw AuthSessionExpired('refresh_${resp.statusCode}');
    }
    final tokens = AuthTokens.fromRefreshJson(
      jsonDecode(resp.body) as Map<String, dynamic>,
      userId,
    );
    _cached = tokens;
    await _storage.writeRefresh(
      refreshToken: tokens.refreshToken,
      userId: tokens.userId,
      accessExpiresAt: tokens.accessExpiresAt,
    );
    return tokens;
  }

  /// Test-only: clear in-memory cache without touching storage.
  void resetMemoryForTests() {
    _cached = null;
    _inflightRefresh = null;
  }
}
