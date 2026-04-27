// Wave 7.4 part 2B — coverage for the dual-mode storage refactor and the
// first-sign-in bulk migrator. Verifies:
//
//   1. LearnerSkillStore + ReviewScheduler facade swaps the active backend
//      between local + remote and persists writes through the chosen one.
//   2. RemoteLearnerSkillBackend + RemoteReviewSchedulerBackend send the
//      right HTTP shape and parse server DTOs.
//   3. LearnerStateMigrator collects the local snapshot, POSTs to
//      /me/state/bulk-import, parses imported/skipped IDs, and flips the
//      facades to remote even on transport / 4xx failures (so signed-in
//      writes still target the server next time).

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mastery/auth/auth_client.dart';
import 'package:mastery/auth/auth_storage.dart';
import 'package:mastery/learner/learner_skill_store.dart';
import 'package:mastery/learner/learner_state_migrator.dart';
import 'package:mastery/learner/review_scheduler.dart';
import 'package:mastery/models/lesson.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _base = 'https://test.local';
const _userId = 'user-1';
const _accessToken = 'access-1';
const _refreshToken = 'refresh-1';

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

AuthStorage _seedStorage() {
  final fake = _FakeSecureStorage();
  FlutterSecureStoragePlatform.instance = fake;
  // Pre-populate so AuthClient considers itself signed in without doing
  // a network round-trip first.
  fake._values['mastery_refresh_token_v1'] = _refreshToken;
  fake._values['mastery_user_id_v1'] = _userId;
  fake._values['mastery_access_expiry_v1'] =
      DateTime.now().toUtc().add(const Duration(minutes: 14)).toIso8601String();
  return AuthStorage(storage: const FlutterSecureStorage());
}

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

class _CapturingClient extends MockClient {
  final List<http.Request> requests = [];

  _CapturingClient._(super.handler);

  factory _CapturingClient.with_(
      Future<http.Response> Function(http.Request) handler) {
    final captured = <http.Request>[];
    final client = _CapturingClient._((req) async {
      captured.add(req);
      return handler(req);
    });
    client.requests.addAll(captured);
    // We rely on closure capture below — assignment after construction
    // would reset .requests to the empty literal. Keep the references
    // bound through the synthetic helper field.
    client._captured = captured;
    return client;
  }

  // The reference returned by .requests is the same list the closure
  // appends to, so test assertions read the live capture.
  List<http.Request> get capturedRequests => _captured;
  late List<http.Request> _captured;
}

AuthClient _makeAuthClient(_CapturingClient http_) {
  final storage = _seedStorage();
  // Use the same response that AuthTokens.fromRefreshJson expects so
  // the in-memory cache primes itself on the first send().
  // Instead we set _cached via a no-op login — easier here: pre-bake a
  // refresh response that the AuthClient consumes lazily.
  return AuthClient(
    baseUrl: _base,
    http: http_,
    storage: storage,
  );
}

Future<void> _primeAuthClient(AuthClient c) async {
  // The MockClient closure will see the /auth/refresh request and
  // respond with a valid token pair so subsequent sends carry an Authorization
  // header. The test handlers expect this path to be the first call.
  await c.hydrateFromStorage();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LearnerSkillStore.useLocal();
    ReviewScheduler.useLocal();
  });

  group('LearnerSkillStore facade — backend swap', () {
    test('useRemote routes recordAttempt at /me/skills/.../attempts', () async {
      final client = _CapturingClient.with_((req) async {
        if (req.url.path.endsWith('/auth/refresh')) {
          return _json({
            'accessToken': _accessToken,
            'refreshToken': _refreshToken,
            'accessTokenExpiresIn': 900,
          });
        }
        if (req.url.path.endsWith('/me/skills/skill-x/attempts')) {
          return _json({
            'skill_id': 'skill-x',
            'mastery_score': 35,
            'last_attempt_at': '2026-04-26T10:00:00.000Z',
            'evidence_summary': {
              'weak': 0,
              'medium': 1,
              'strong': 0,
              'strongest': 0
            },
            'recent_errors': [],
            'production_gate_cleared': false,
            'gate_cleared_at_version': null,
            'status': 'practicing',
          });
        }
        return _json({}, status: 404);
      });
      final auth = _makeAuthClient(client);
      await _primeAuthClient(auth);
      LearnerSkillStore.useRemote(authClient: auth, baseUrl: _base);

      final updated = await LearnerSkillStore.recordAttempt(
        skillId: 'skill-x',
        evidenceTier: EvidenceTier.medium,
        correct: true,
      );

      expect(updated, isNotNull);
      expect(updated!.masteryScore, 35);
      expect(updated.evidenceSummary[EvidenceTier.medium], 1);

      // Verify request shape: server snake_case + Authorization header.
      final attemptsReq = client.capturedRequests.firstWhere((r) =>
          r.url.path.endsWith('/me/skills/skill-x/attempts'));
      expect(attemptsReq.method, 'POST');
      expect(attemptsReq.headers['authorization'],
          'Bearer $_accessToken');
      final body = jsonDecode(attemptsReq.body);
      expect(body['evidence_tier'], 'medium');
      expect(body['correct'], true);
    });

    test('useRemote then useLocal restores SharedPreferences-backed writes',
        () async {
      final client = _CapturingClient.with_(
          (req) async => _json({}, status: 401));
      final auth = _makeAuthClient(client);
      await _primeAuthClient(auth);

      LearnerSkillStore.useRemote(authClient: auth, baseUrl: _base);
      LearnerSkillStore.useLocal();

      final updated = await LearnerSkillStore.recordAttempt(
        skillId: 'g.skill.local',
        evidenceTier: EvidenceTier.weak,
        correct: true,
      );

      expect(updated, isNotNull);
      // Local backend wrote to SharedPreferences — cross-check via a
      // fresh local instance.
      final fresh = await LocalLearnerSkillBackend().getRecord('g.skill.local');
      expect(fresh.masteryScore, updated!.masteryScore);
    });
  });

  group('ReviewScheduler facade — backend swap', () {
    test('useRemote routes recordSessionEnd at /me/skills/.../review-cadence',
        () async {
      final client = _CapturingClient.with_((req) async {
        if (req.url.path.endsWith('/auth/refresh')) {
          return _json({
            'accessToken': _accessToken,
            'refreshToken': _refreshToken,
            'accessTokenExpiresIn': 900,
          });
        }
        if (req.url.path
            .endsWith('/me/skills/skill-x/review-cadence')) {
          return _json({
            'skill_id': 'skill-x',
            'step': 2,
            'due_at': '2026-04-30T00:00:00.000Z',
            'last_outcome_at': '2026-04-27T00:00:00.000Z',
            'last_outcome_mistakes': 0,
            'graduated': false,
          });
        }
        return _json({}, status: 404);
      });
      final auth = _makeAuthClient(client);
      await _primeAuthClient(auth);
      ReviewScheduler.useRemote(authClient: auth, baseUrl: _base);

      final next = await ReviewScheduler.recordSessionEnd(
        skillId: 'skill-x',
        mistakesInSession: 0,
      );

      expect(next, isNotNull);
      expect(next!.step, 2);
      expect(next.dueAt.toUtc(), DateTime.utc(2026, 4, 30));

      final cadenceReq = client.capturedRequests.firstWhere((r) =>
          r.url.path.endsWith('/me/skills/skill-x/review-cadence'));
      expect(cadenceReq.method, 'POST');
      final body = jsonDecode(cadenceReq.body);
      expect(body['mistakes_in_session'], 0);
    });

    test('remote dueAt parses /me/reviews/due reviews array', () async {
      final client = _CapturingClient.with_((req) async {
        if (req.url.path.endsWith('/auth/refresh')) {
          return _json({
            'accessToken': _accessToken,
            'refreshToken': _refreshToken,
            'accessTokenExpiresIn': 900,
          });
        }
        if (req.url.path.endsWith('/me/reviews/due')) {
          return _json({
            'at': '2026-04-27T00:00:00.000Z',
            'reviews': [
              {
                'skill_id': 'skill-a',
                'step': 1,
                'due_at': '2026-04-26T00:00:00.000Z',
                'last_outcome_at': '2026-04-25T00:00:00.000Z',
                'last_outcome_mistakes': 1,
                'graduated': false,
              },
              {
                'skill_id': 'skill-b',
                'step': 3,
                'due_at': '2026-04-26T01:00:00.000Z',
                'last_outcome_at': '2026-04-19T01:00:00.000Z',
                'last_outcome_mistakes': 0,
                'graduated': false,
              },
            ],
          });
        }
        return _json({}, status: 404);
      });
      final auth = _makeAuthClient(client);
      await _primeAuthClient(auth);
      ReviewScheduler.useRemote(authClient: auth, baseUrl: _base);

      final due = await ReviewScheduler.dueAt(DateTime.utc(2026, 4, 27));

      expect(due.length, 2);
      expect(due.map((s) => s.skillId).toList(), ['skill-a', 'skill-b']);
    });
  });

  group('LearnerStateMigrator', () {
    test('empty local snapshot → no POST, facades flipped to remote',
        () async {
      var importCalls = 0;
      final client = _CapturingClient.with_((req) async {
        if (req.url.path.endsWith('/auth/refresh')) {
          return _json({
            'accessToken': _accessToken,
            'refreshToken': _refreshToken,
            'accessTokenExpiresIn': 900,
          });
        }
        if (req.url.path.endsWith('/me/state/bulk-import')) {
          importCalls += 1;
          return _json({
            'imported_skill_ids': [],
            'skipped_skill_ids': [],
            'imported_schedule_skill_ids': [],
            'skipped_schedule_skill_ids': [],
          });
        }
        return _json({}, status: 404);
      });
      final auth = _makeAuthClient(client);
      await _primeAuthClient(auth);

      final migrator =
          LearnerStateMigrator(authClient: auth, baseUrl: _base);
      final result = await migrator.migrate();

      expect(importCalls, 0);
      expect(result.isFailure, false);
      expect(result.importedSkills, isEmpty);
      expect(LearnerSkillStore.backend, isA<RemoteLearnerSkillBackend>());
      expect(ReviewScheduler.backend, isA<RemoteReviewSchedulerBackend>());
    });

    test('local snapshot is POSTed and result reports imported + skipped',
        () async {
      // Seed local progress directly through the local backend so the
      // migrator picks it up via LocalLearnerSkillBackend.allRecords.
      final localSkills = LocalLearnerSkillBackend();
      await localSkills.recordAttempt(
        skillId: 'g.tense.past_simple',
        evidenceTier: EvidenceTier.strong,
        correct: true,
      );
      final localCadence = LocalReviewSchedulerBackend();
      await localCadence.recordSessionEnd(
        skillId: 'g.tense.past_simple',
        mistakesInSession: 0,
      );

      Map<String, dynamic>? capturedBody;
      final client = _CapturingClient.with_((req) async {
        if (req.url.path.endsWith('/auth/refresh')) {
          return _json({
            'accessToken': _accessToken,
            'refreshToken': _refreshToken,
            'accessTokenExpiresIn': 900,
          });
        }
        if (req.url.path.endsWith('/me/state/bulk-import')) {
          capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
          return _json({
            'imported_skill_ids': ['g.tense.past_simple'],
            'skipped_skill_ids': [],
            'imported_schedule_skill_ids': ['g.tense.past_simple'],
            'skipped_schedule_skill_ids': [],
          });
        }
        return _json({}, status: 404);
      });
      final auth = _makeAuthClient(client);
      await _primeAuthClient(auth);

      final migrator =
          LearnerStateMigrator(authClient: auth, baseUrl: _base);
      final result = await migrator.migrate();

      expect(result.isFailure, false);
      expect(result.importedSkills, ['g.tense.past_simple']);
      expect(result.importedSchedules, ['g.tense.past_simple']);
      expect(capturedBody, isNotNull);
      expect((capturedBody!['learner_skills'] as List).length, 1);
      expect((capturedBody!['review_schedules'] as List).length, 1);
      // First learner_skills entry carries the canonical snake_case keys
      // server-side Zod expects.
      final firstSkill =
          (capturedBody!['learner_skills'] as List).first
              as Map<String, dynamic>;
      expect(firstSkill['skill_id'], 'g.tense.past_simple');
      expect(firstSkill['mastery_score'], isA<int>());
      expect(firstSkill['production_gate_cleared'], isA<bool>());

      expect(LearnerSkillStore.backend, isA<RemoteLearnerSkillBackend>());
      expect(ReviewScheduler.backend, isA<RemoteReviewSchedulerBackend>());
    });

    test('server returns 4xx → failure result, facades still flipped',
        () async {
      final localSkills = LocalLearnerSkillBackend();
      await localSkills.recordAttempt(
        skillId: 'skill-y',
        evidenceTier: EvidenceTier.medium,
        correct: true,
      );

      final client = _CapturingClient.with_((req) async {
        if (req.url.path.endsWith('/auth/refresh')) {
          return _json({
            'accessToken': _accessToken,
            'refreshToken': _refreshToken,
            'accessTokenExpiresIn': 900,
          });
        }
        if (req.url.path.endsWith('/me/state/bulk-import')) {
          return _json({'error': 'invalid_payload'}, status: 400);
        }
        return _json({}, status: 404);
      });
      final auth = _makeAuthClient(client);
      await _primeAuthClient(auth);

      final migrator =
          LearnerStateMigrator(authClient: auth, baseUrl: _base);
      final result = await migrator.migrate();

      expect(result.isFailure, true);
      expect(result.failureReason, contains('http_400'));
      // Facades still flipped so subsequent writes target the server.
      expect(LearnerSkillStore.backend, isA<RemoteLearnerSkillBackend>());
      expect(ReviewScheduler.backend, isA<RemoteReviewSchedulerBackend>());
    });

    test('network exception → failure result, facades still flipped',
        () async {
      final localSkills = LocalLearnerSkillBackend();
      await localSkills.recordAttempt(
        skillId: 'skill-z',
        evidenceTier: EvidenceTier.weak,
        correct: false,
        primaryTargetError: TargetError.form,
      );

      final client = _CapturingClient.with_((req) async {
        if (req.url.path.endsWith('/auth/refresh')) {
          return _json({
            'accessToken': _accessToken,
            'refreshToken': _refreshToken,
            'accessTokenExpiresIn': 900,
          });
        }
        if (req.url.path.endsWith('/me/state/bulk-import')) {
          throw http.ClientException('boom');
        }
        return _json({}, status: 404);
      });
      final auth = _makeAuthClient(client);
      await _primeAuthClient(auth);

      final migrator =
          LearnerStateMigrator(authClient: auth, baseUrl: _base);
      final result = await migrator.migrate();

      expect(result.isFailure, true);
      expect(result.failureReason, contains('network_'));
      expect(LearnerSkillStore.backend, isA<RemoteLearnerSkillBackend>());
      expect(ReviewScheduler.backend, isA<RemoteReviewSchedulerBackend>());
    });

    test('schedule and skill DTOs use correct snake_case keys', () async {
      final localSkills = LocalLearnerSkillBackend();
      await localSkills.recordAttempt(
        skillId: 'skill-q',
        evidenceTier: EvidenceTier.strongest,
        correct: true,
        meaningFrame: 'meaning ok',
        evaluationVersion: 5,
      );
      final localCadence = LocalReviewSchedulerBackend();
      await localCadence.recordSessionEnd(
        skillId: 'skill-q',
        mistakesInSession: 0,
      );

      Map<String, dynamic>? body;
      final client = _CapturingClient.with_((req) async {
        if (req.url.path.endsWith('/auth/refresh')) {
          return _json({
            'accessToken': _accessToken,
            'refreshToken': _refreshToken,
            'accessTokenExpiresIn': 900,
          });
        }
        if (req.url.path.endsWith('/me/state/bulk-import')) {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _json({
            'imported_skill_ids': ['skill-q'],
            'skipped_skill_ids': [],
            'imported_schedule_skill_ids': ['skill-q'],
            'skipped_schedule_skill_ids': [],
          });
        }
        return _json({}, status: 404);
      });
      final auth = _makeAuthClient(client);
      await _primeAuthClient(auth);

      final migrator =
          LearnerStateMigrator(authClient: auth, baseUrl: _base);
      await migrator.migrate();

      expect(body, isNotNull);
      final skill =
          (body!['learner_skills'] as List).first as Map<String, dynamic>;
      expect(skill.keys, containsAll([
        'skill_id',
        'mastery_score',
        'last_attempt_at',
        'evidence_summary',
        'recent_errors',
        'production_gate_cleared',
        'gate_cleared_at_version',
      ]));
      final schedule =
          (body!['review_schedules'] as List).first as Map<String, dynamic>;
      expect(schedule.keys, containsAll([
        'skill_id',
        'step',
        'due_at',
        'last_outcome_at',
        'last_outcome_mistakes',
        'graduated',
      ]));
    });
  });
}
