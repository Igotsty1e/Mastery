import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistence boundary for the refresh-token pair. Refresh tokens are
/// bearer secrets — they grant the holder the ability to mint new
/// access tokens for the lifetime of the session window. Storing them
/// in SharedPreferences (plain plist on iOS, plain XML on Android)
/// would be a real compromise vector if the device is rooted /
/// jailbroken or backed up unencrypted.
///
/// `flutter_secure_storage` uses:
/// - iOS: Keychain (encrypted, app-scoped, optional biometric lock)
/// - Android: KeyStore-wrapped AES via the EncryptedSharedPreferences shim
/// - macOS: Keychain
/// - Linux: libsecret
/// - Windows: DPAPI
/// - Web: AES-encrypted localStorage with a per-origin key derived in
///   the SubtleCrypto API. Web is genuinely best-effort — anyone who
///   can run script in our origin can read the key the same way the
///   app can. The mitigation is the same as for any browser-based app:
///   no XSS, strict CSP, refresh-token rotation on every use, server-side
///   session revocation. The Wave 7.1 backend already implements
///   rotation + immediate `logout` / `logout-all` revocation.
///
/// Access tokens stay in memory only. They have a 15-minute TTL so the
/// blast radius of a memory disclosure is bounded.
class AuthStorage {
  static const _refreshKey = 'mastery_refresh_token_v1';
  static const _userIdKey = 'mastery_user_id_v1';
  static const _accessExpiryKey = 'mastery_access_expiry_v1';

  final FlutterSecureStorage _storage;

  AuthStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> writeRefresh({
    required String refreshToken,
    required String userId,
    DateTime? accessExpiresAt,
  }) async {
    await _storage.write(key: _refreshKey, value: refreshToken);
    await _storage.write(key: _userIdKey, value: userId);
    if (accessExpiresAt != null) {
      await _storage.write(
        key: _accessExpiryKey,
        value: accessExpiresAt.toUtc().toIso8601String(),
      );
    }
  }

  Future<String?> readRefresh() async {
    return _storage.read(key: _refreshKey);
  }

  Future<String?> readUserId() async {
    return _storage.read(key: _userIdKey);
  }

  Future<DateTime?> readAccessExpiry() async {
    final raw = await _storage.read(key: _accessExpiryKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// Clear everything. Called on logout, logout-all, hard-delete
  /// (`DELETE /me`), and on any 401 we receive after a fresh refresh
  /// (which means the refresh-token chain itself was revoked).
  Future<void> clear() async {
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _accessExpiryKey);
  }
}
