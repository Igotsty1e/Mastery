/// Wave 7.4 access + refresh token pair returned by `/auth/apple/stub/login`
/// and `/auth/refresh`. Mirrors the backend's `LoginResponse` shape.
class AuthTokens {
  /// Stateless HMAC access token. Sent as `Authorization: Bearer <token>`.
  /// 15-minute TTL on the backend; the client refreshes on 401.
  final String accessToken;

  /// Opaque refresh token. 30-day TTL on the backend; rotates on every
  /// successful refresh. Treat as a bearer secret — never log it, never
  /// send anywhere except the `/auth/refresh` endpoint.
  final String refreshToken;

  /// Wall-clock expiry for the access token. Computed at sign-in /
  /// refresh time as `now + 15min`. The client uses this for cheap
  /// pre-checks before each request; the source of truth is still the
  /// server's signature verification.
  final DateTime accessExpiresAt;

  /// Opaque user id from the server. Stored alongside tokens for client
  /// debugging only — the server identifies the caller from the access
  /// token signature, never from this field.
  final String userId;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.userId,
  });

  factory AuthTokens.fromLoginJson(Map<String, dynamic> j) {
    final accessToken = j['accessToken'] as String?;
    final refreshToken = j['refreshToken'] as String?;
    if (accessToken == null || refreshToken == null) {
      throw const FormatException('Login response missing tokens');
    }
    final user = j['user'] as Map<String, dynamic>?;
    final userId = user?['id'] as String?;
    if (userId == null) {
      throw const FormatException('Login response missing user id');
    }
    final expiresInSeconds = (j['accessTokenExpiresIn'] as num?)?.toInt() ?? 900;
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessExpiresAt:
          DateTime.now().toUtc().add(Duration(seconds: expiresInSeconds)),
      userId: userId,
    );
  }

  factory AuthTokens.fromRefreshJson(
    Map<String, dynamic> j,
    String fallbackUserId,
  ) {
    final accessToken = j['accessToken'] as String?;
    final refreshToken = j['refreshToken'] as String?;
    if (accessToken == null || refreshToken == null) {
      throw const FormatException('Refresh response missing tokens');
    }
    final expiresInSeconds = (j['accessTokenExpiresIn'] as num?)?.toInt() ?? 900;
    return AuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessExpiresAt:
          DateTime.now().toUtc().add(Duration(seconds: expiresInSeconds)),
      userId: (j['user'] as Map<String, dynamic>?)?['id'] as String? ??
          fallbackUserId,
    );
  }

  bool get accessNearExpiry =>
      DateTime.now().toUtc().isAfter(
            accessExpiresAt.subtract(const Duration(seconds: 30)),
          );
}
