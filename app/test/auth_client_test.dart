import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mastery/auth/auth_client.dart';
import 'package:mastery/auth/auth_storage.dart';
import 'package:mastery/auth/auth_tokens.dart';

const _base = 'https://test.local';

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

AuthStorage _makeStorage() {
  final fake = _FakeSecureStorage();
  FlutterSecureStoragePlatform.instance = fake;
  return AuthStorage(storage: const FlutterSecureStorage());
}

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

void main() {
  group('AuthTokens', () {
    test('fromLoginJson parses the canonical Wave 7.1 login response', () {
      final tokens = AuthTokens.fromLoginJson({
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
        'accessTokenExpiresIn': 900,
        'user': {'id': 'user-1'},
      });
      expect(tokens.accessToken, 'access-1');
      expect(tokens.refreshToken, 'refresh-1');
      expect(tokens.userId, 'user-1');
      expect(tokens.accessExpiresAt.isAfter(DateTime.now().toUtc()), isTrue);
    });

    test('fromLoginJson throws when tokens are missing', () {
      expect(
        () => AuthTokens.fromLoginJson({'user': {'id': 'u'}}),
        throwsFormatException,
      );
    });

    test('accessNearExpiry flips inside the 30-second window', () {
      final tokens = AuthTokens(
        accessToken: 'a',
        refreshToken: 'r',
        accessExpiresAt:
            DateTime.now().toUtc().add(const Duration(seconds: 10)),
        userId: 'u',
      );
      expect(tokens.accessNearExpiry, isTrue);
      final fresh = AuthTokens(
        accessToken: 'a',
        refreshToken: 'r',
        accessExpiresAt:
            DateTime.now().toUtc().add(const Duration(minutes: 10)),
        userId: 'u',
      );
      expect(fresh.accessNearExpiry, isFalse);
    });
  });

  group('AuthClient.signInWithAppleStub', () {
    test('persists refresh token + user id on success', () async {
      final storage = _makeStorage();
      final mock = MockClient((req) async {
        expect(req.url.path, '/auth/apple/stub/login');
        expect((jsonDecode(req.body) as Map)['subject'], 'tester');
        return _json({
          'accessToken': 'access-1',
          'refreshToken': 'refresh-1',
          'accessTokenExpiresIn': 900,
          'user': {'id': 'user-1'},
        });
      });
      final client = AuthClient(baseUrl: _base, http: mock, storage: storage);
      final tokens = await client.signInWithAppleStub(subject: 'tester');
      expect(tokens.accessToken, 'access-1');
      expect(tokens.userId, 'user-1');
      expect(await storage.readRefresh(), 'refresh-1');
      expect(await storage.readUserId(), 'user-1');
    });

    test('throws AuthSessionExpired on non-200 status', () async {
      final storage = _makeStorage();
      final mock = MockClient((_) async => _json({'error': 'no'}, status: 401));
      final client = AuthClient(baseUrl: _base, http: mock, storage: storage);
      expect(
        () => client.signInWithAppleStub(subject: 'tester'),
        throwsA(isA<AuthSessionExpired>()),
      );
      expect(await storage.readRefresh(), isNull);
    });
  });

  group('AuthClient.send — happy path', () {
    test('attaches Authorization: Bearer to outbound requests', () async {
      final storage = _makeStorage();
      String? observedAuthHeader;
      int loginCalls = 0;
      final mock = MockClient((req) async {
        if (req.url.path == '/auth/apple/stub/login') {
          loginCalls++;
          return _json({
            'accessToken': 'access-1',
            'refreshToken': 'refresh-1',
            'accessTokenExpiresIn': 900,
            'user': {'id': 'user-1'},
          });
        }
        observedAuthHeader = req.headers['authorization'];
        return _json({'ok': true});
      });
      final client = AuthClient(baseUrl: _base, http: mock, storage: storage);
      await client.signInWithAppleStub(subject: 'tester');
      final resp = await client.send('GET', Uri.parse('$_base/me'));
      expect(resp.statusCode, 200);
      expect(observedAuthHeader, 'Bearer access-1');
      expect(loginCalls, 1);
    });
  });

  group('AuthClient.send — 401 refresh path', () {
    test('on 401 the client refreshes once and retries with the new token',
        () async {
      final storage = _makeStorage();
      var meCalls = 0;
      final mock = MockClient((req) async {
        final path = req.url.path;
        if (path == '/auth/apple/stub/login') {
          return _json({
            'accessToken': 'access-1',
            'refreshToken': 'refresh-1',
            'accessTokenExpiresIn': 900,
            'user': {'id': 'user-1'},
          });
        }
        if (path == '/auth/refresh') {
          expect(jsonDecode(req.body)['refreshToken'], 'refresh-1');
          return _json({
            'accessToken': 'access-2',
            'refreshToken': 'refresh-2',
            'accessTokenExpiresIn': 900,
            'user': {'id': 'user-1'},
          });
        }
        if (path == '/me') {
          meCalls++;
          if (meCalls == 1) return _json({'error': 'expired'}, status: 401);
          // Second call must use the freshly minted access token.
          expect(req.headers['authorization'], 'Bearer access-2');
          return _json({'ok': true});
        }
        return _json({'unexpected': req.url.toString()}, status: 500);
      });
      final client = AuthClient(baseUrl: _base, http: mock, storage: storage);
      await client.signInWithAppleStub(subject: 'tester');
      final resp = await client.send('GET', Uri.parse('$_base/me'));
      expect(resp.statusCode, 200);
      expect(meCalls, 2);
      expect(await storage.readRefresh(), 'refresh-2');
    });

    test('refresh-returns-401 clears storage and throws AuthSessionExpired',
        () async {
      final storage = _makeStorage();
      final mock = MockClient((req) async {
        final path = req.url.path;
        if (path == '/auth/apple/stub/login') {
          return _json({
            'accessToken': 'access-1',
            'refreshToken': 'refresh-1',
            'accessTokenExpiresIn': 900,
            'user': {'id': 'user-1'},
          });
        }
        if (path == '/auth/refresh') {
          return _json({'error': 'revoked'}, status: 401);
        }
        if (path == '/me') {
          return _json({'error': 'expired'}, status: 401);
        }
        return _json({}, status: 500);
      });
      final client = AuthClient(baseUrl: _base, http: mock, storage: storage);
      await client.signInWithAppleStub(subject: 'tester');
      expect(await storage.readRefresh(), 'refresh-1');
      expect(
        () => client.send('GET', Uri.parse('$_base/me')),
        throwsA(isA<AuthSessionExpired>()),
      );
      // After throw, storage must be cleared so the app can show sign-in.
      // Awaiting a throwsA gate first.
      try {
        await client.send('GET', Uri.parse('$_base/me'));
      } catch (_) {}
      expect(await storage.readRefresh(), isNull);
    });

    test('retry that returns 401 clears storage and throws', () async {
      final storage = _makeStorage();
      final mock = MockClient((req) async {
        final path = req.url.path;
        if (path == '/auth/apple/stub/login') {
          return _json({
            'accessToken': 'access-1',
            'refreshToken': 'refresh-1',
            'accessTokenExpiresIn': 900,
            'user': {'id': 'user-1'},
          });
        }
        if (path == '/auth/refresh') {
          return _json({
            'accessToken': 'access-2',
            'refreshToken': 'refresh-2',
            'accessTokenExpiresIn': 900,
            'user': {'id': 'user-1'},
          });
        }
        if (path == '/me') {
          // Always 401 — server-side revocation mid-flight.
          return _json({'error': 'expired'}, status: 401);
        }
        return _json({}, status: 500);
      });
      final client = AuthClient(baseUrl: _base, http: mock, storage: storage);
      await client.signInWithAppleStub(subject: 'tester');
      try {
        await client.send('GET', Uri.parse('$_base/me'));
        fail('expected throw');
      } on AuthSessionExpired {
        // expected
      }
      expect(await storage.readRefresh(), isNull);
    });

    test('without prior login, send throws AuthSessionExpired', () async {
      final storage = _makeStorage();
      final mock = MockClient((_) async => _json({}, status: 200));
      final client = AuthClient(baseUrl: _base, http: mock, storage: storage);
      expect(
        () => client.send('GET', Uri.parse('$_base/me')),
        throwsA(isA<AuthSessionExpired>()),
      );
    });
  });

  group('AuthClient.hydrateFromStorage', () {
    test('rehydrates a session by minting a fresh access token', () async {
      final storage = _makeStorage();
      await storage.writeRefresh(refreshToken: 'r-old', userId: 'u-1');
      final mock = MockClient((req) async {
        if (req.url.path == '/auth/refresh') {
          expect(jsonDecode(req.body)['refreshToken'], 'r-old');
          return _json({
            'accessToken': 'access-new',
            'refreshToken': 'r-new',
            'accessTokenExpiresIn': 900,
            'user': {'id': 'u-1'},
          });
        }
        return _json({}, status: 500);
      });
      final client = AuthClient(baseUrl: _base, http: mock, storage: storage);
      final tokens = await client.hydrateFromStorage();
      expect(tokens, isNotNull);
      expect(tokens!.accessToken, 'access-new');
      expect(await storage.readRefresh(), 'r-new');
    });

    test('returns null when storage is empty', () async {
      final storage = _makeStorage();
      final mock = MockClient((_) async => _json({}, status: 500));
      final client = AuthClient(baseUrl: _base, http: mock, storage: storage);
      final tokens = await client.hydrateFromStorage();
      expect(tokens, isNull);
    });
  });

  group('AuthClient.logout', () {
    test('calls /auth/logout then clears storage', () async {
      final storage = _makeStorage();
      var logoutCalls = 0;
      final mock = MockClient((req) async {
        if (req.url.path == '/auth/apple/stub/login') {
          return _json({
            'accessToken': 'a',
            'refreshToken': 'r',
            'accessTokenExpiresIn': 900,
            'user': {'id': 'u'},
          });
        }
        if (req.url.path == '/auth/logout') {
          logoutCalls++;
          return http.Response('', 204);
        }
        return _json({}, status: 500);
      });
      final client = AuthClient(baseUrl: _base, http: mock, storage: storage);
      await client.signInWithAppleStub(subject: 'x');
      await client.logout();
      expect(logoutCalls, 1);
      expect(await storage.readRefresh(), isNull);
    });

    test('logout swallows network errors and still clears local state',
        () async {
      final storage = _makeStorage();
      var phase = 0;
      final mock = MockClient((req) async {
        phase++;
        if (phase == 1) {
          return _json({
            'accessToken': 'a',
            'refreshToken': 'r',
            'accessTokenExpiresIn': 900,
            'user': {'id': 'u'},
          });
        }
        throw Exception('network down');
      });
      final client = AuthClient(baseUrl: _base, http: mock, storage: storage);
      await client.signInWithAppleStub(subject: 'x');
      await client.logout(); // must not throw
      expect(await storage.readRefresh(), isNull);
    });
  });
}
