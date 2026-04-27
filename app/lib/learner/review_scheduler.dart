import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_client.dart';

/// Cross-session review cadence per `LEARNING_ENGINE.md §§9.2, 9.3, 9.4`.
///
/// Wave 3 V0 shipped a device-scoped SharedPreferences store. Wave 7.4
/// part 2B turns this into a pluggable facade with two backends:
///
/// - `LocalReviewSchedulerBackend` — the original SharedPreferences
///   path, used in unauth'd builds and in guest mode after Skip.
/// - `RemoteReviewSchedulerBackend` — calls
///   `/me/skills/.../review-cadence` and `/me/reviews/due` against the
///   auth-protected backend. Used after sign-in.
///
/// Cadence steps and intervals (§9.3):
///
/// | Step | Interval after this step's correct review |
/// |------|-------------------------------------------|
/// | 1    | 1 day                                     |
/// | 2    | 3 days                                    |
/// | 3    | 7 days                                    |
/// | 4    | 21 days                                   |
/// | 5+   | 21 days, capped (or graduated per §9.4)   |
abstract class ReviewSchedulerBackend {
  Future<ReviewSchedule?> recordSessionEnd({
    required String skillId,
    required int mistakesInSession,
    DateTime? occurredAt,
  });

  Future<List<ReviewSchedule>> dueAt(DateTime now);

  Future<ReviewSchedule?> get(String skillId);

  Future<List<ReviewSchedule>> all();

  Future<void> clearAll();
}

/// Wave 3 / part 2B local backend — keeps the original SharedPreferences
/// keys so reinstalls without sign-in keep their device-scoped cadence.
class LocalReviewSchedulerBackend implements ReviewSchedulerBackend {
  static const _keyPrefix = 'review_schedule_v1_';
  static const _indexKey = 'review_schedule_v1_index';

  @override
  Future<ReviewSchedule?> recordSessionEnd({
    required String skillId,
    required int mistakesInSession,
    DateTime? occurredAt,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = _read(prefs, skillId);
      final now = (occurredAt ?? DateTime.now().toUtc());

      // Outcome rules per §9.1 + §9.3:
      // - 3+ mistakes → §9.1 weak → cadence step 1, status practicing
      // - 1–2 mistakes → cadence reset to step 1 (the §9.3 "wrong review"
      //   reset rule, applied here as a conservative default since Wave 3
      //   does not yet differentiate "review session" vs "first lesson")
      // - 0 mistakes → step advances by 1 (capped at 5)
      final hadAnyMistakes = mistakesInSession > 0;
      final priorStep = existing?.step ?? 0;
      final nextStep =
          hadAnyMistakes ? 1 : (priorStep + 1).clamp(1, 5);

      final dueAt = now.add(ReviewScheduler.intervalForStep(nextStep));
      final graduated = !hadAnyMistakes && nextStep >= 5;

      final next = ReviewSchedule(
        skillId: skillId,
        step: nextStep,
        dueAt: dueAt,
        lastOutcomeAt: now,
        lastOutcomeMistakes: mistakesInSession,
        graduated: graduated,
      );

      await prefs.setString(_keyPrefix + skillId, jsonEncode(next.toJson()));
      await _addToIndex(prefs, skillId);
      return next;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<ReviewSchedule>> dueAt(DateTime now) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_indexKey) ?? const <String>[];
      final out = <ReviewSchedule>[];
      for (final id in ids) {
        final r = _read(prefs, id);
        if (r != null && !r.graduated && !r.dueAt.isAfter(now)) {
          out.add(r);
        }
      }
      out.sort((a, b) => a.dueAt.compareTo(b.dueAt));
      return out;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<ReviewSchedule?> get(String skillId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _read(prefs, skillId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<ReviewSchedule>> all() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_indexKey) ?? const <String>[];
      final out = <ReviewSchedule>[];
      for (final id in ids) {
        final r = _read(prefs, id);
        if (r != null) out.add(r);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_indexKey) ?? const <String>[];
      for (final id in ids) {
        await prefs.remove(_keyPrefix + id);
      }
      await prefs.remove(_indexKey);
    } catch (_) {}
  }

  static ReviewSchedule? _read(SharedPreferences prefs, String skillId) {
    final raw = prefs.getString(_keyPrefix + skillId);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return null;
      return ReviewSchedule.tryFromJson(skillId, j);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _addToIndex(
      SharedPreferences prefs, String skillId) async {
    final ids = prefs.getStringList(_indexKey) ?? <String>[];
    if (!ids.contains(skillId)) {
      ids.add(skillId);
      await prefs.setStringList(_indexKey, ids);
    }
  }
}

/// Wave 7.4 part 2B remote backend — calls the auth-protected
/// `/me/skills/.../review-cadence` and `/me/reviews/due` endpoints.
/// Server is the source of truth; this backend never reads from local
/// storage. Tolerates network errors with the same null/empty contract
/// as the local backend so the lesson flow keeps working offline.
class RemoteReviewSchedulerBackend implements ReviewSchedulerBackend {
  final AuthClient _authClient;
  final String baseUrl;

  RemoteReviewSchedulerBackend({
    required AuthClient authClient,
    required this.baseUrl,
  }) : _authClient = authClient;

  @override
  Future<ReviewSchedule?> recordSessionEnd({
    required String skillId,
    required int mistakesInSession,
    DateTime? occurredAt,
  }) async {
    try {
      final resp = await _authClient.send(
        'POST',
        Uri.parse('$baseUrl/me/skills/$skillId/review-cadence'),
        body: {'mistakes_in_session': mistakesInSession},
      );
      if (resp.statusCode != 200) return null;
      return _parseScheduleDto(skillId, jsonDecode(resp.body));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<ReviewSchedule>> dueAt(DateTime now) async {
    try {
      final resp = await _authClient.send(
        'GET',
        Uri.parse('$baseUrl/me/reviews/due')
            .replace(queryParameters: {'at': now.toUtc().toIso8601String()}),
      );
      if (resp.statusCode != 200) return const [];
      final j = jsonDecode(resp.body);
      if (j is! Map<String, dynamic>) return const [];
      final reviews = j['reviews'];
      if (reviews is! List) return const [];
      final out = <ReviewSchedule>[];
      for (final item in reviews) {
        if (item is Map<String, dynamic>) {
          final id = item['skill_id'];
          if (id is String) {
            final s = _parseScheduleDto(id, item);
            if (s != null) out.add(s);
          }
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<ReviewSchedule?> get(String skillId) async {
    try {
      final resp = await _authClient.send(
        'GET',
        Uri.parse('$baseUrl/me/skills/$skillId/review-cadence'),
      );
      if (resp.statusCode != 200) return null;
      return _parseScheduleDto(skillId, jsonDecode(resp.body));
    } catch (_) {
      return null;
    }
  }

  /// `/me/reviews/due` only returns due-and-not-graduated entries; it's
  /// the closest server-side endpoint to "every schedule entry". V0
  /// remote `all()` returns the same set so the dashboard's "Coming up"
  /// rendering stays consistent. A dedicated list-all endpoint can land
  /// later if/when a screen needs the full set.
  @override
  Future<List<ReviewSchedule>> all() async {
    return dueAt(DateTime.now().toUtc());
  }

  /// No local rows to clear server-side; the migration trigger relies on
  /// the bulk-import endpoint's idempotency rather than client-driven
  /// deletion.
  @override
  Future<void> clearAll() async {}

  static ReviewSchedule? _parseScheduleDto(String skillId, dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    return ReviewSchedule.tryFromJson(skillId, raw);
  }
}

/// Wave 7.4 part 2B static facade. Existing call-sites
/// (`ReviewScheduler.dueAt(...)`, `ReviewScheduler.recordSessionEnd(...)`)
/// stay unchanged.
class ReviewScheduler {
  static ReviewSchedulerBackend _backend = LocalReviewSchedulerBackend();

  /// Test-only: replace the active backend wholesale.
  // ignore: avoid_setters_without_getters
  static set backendForTests(ReviewSchedulerBackend b) {
    _backend = b;
  }

  /// Returns the active backend so callers (e.g., the migration trigger)
  /// can drive backend-specific paths.
  static ReviewSchedulerBackend get backend => _backend;

  /// `LEARNING_ENGINE.md §9.3` cadence intervals indexed by step number.
  /// Step 1..4 walk the expanding interval; step 5+ caps at 21 days.
  static Duration intervalForStep(int step) {
    if (step <= 1) return const Duration(days: 1);
    if (step == 2) return const Duration(days: 3);
    if (step == 3) return const Duration(days: 7);
    return const Duration(days: 21);
  }

  static void useLocal() {
    _backend = LocalReviewSchedulerBackend();
  }

  static void useRemote({
    required AuthClient authClient,
    required String baseUrl,
  }) {
    _backend = RemoteReviewSchedulerBackend(
      authClient: authClient,
      baseUrl: baseUrl,
    );
  }

  /// Records the in-session outcome for one skill at session end.
  static Future<ReviewSchedule?> recordSessionEnd({
    required String skillId,
    required int mistakesInSession,
    DateTime? occurredAt,
  }) =>
      _backend.recordSessionEnd(
        skillId: skillId,
        mistakesInSession: mistakesInSession,
        occurredAt: occurredAt,
      );

  /// Returns every skill whose review is due at or before `now`. Sorted
  /// by `dueAt` (oldest first).
  static Future<List<ReviewSchedule>> dueAt(DateTime now) =>
      _backend.dueAt(now);

  /// Returns the schedule entry for one skill, or `null` if the skill
  /// has not yet entered the cadence.
  static Future<ReviewSchedule?> get(String skillId) => _backend.get(skillId);

  /// Returns every schedule entry the active backend can list.
  static Future<List<ReviewSchedule>> all() => _backend.all();

  /// Test-only: clears the active backend's persisted state and resets
  /// the facade to local.
  static Future<void> clearForTests() async {
    await _backend.clearAll();
    _backend = LocalReviewSchedulerBackend();
  }
}

class ReviewSchedule {
  /// Skill the schedule is for.
  final String skillId;

  /// Cadence step per `LEARNING_ENGINE.md §9.3`. 1..5; 5 means graduated
  /// (or capped at 21 days if not graduated).
  final int step;

  /// UTC timestamp when this skill is next due for review.
  final DateTime dueAt;

  /// UTC timestamp of the most recent session that touched this skill.
  final DateTime lastOutcomeAt;

  /// Mistakes recorded on this skill during the most recent session.
  final int lastOutcomeMistakes;

  /// True when the skill has cleared four reviews without resetting per
  /// §9.4. Soft signal — graduated skills still surface in mixed-review
  /// lessons but not as standalone review prompts.
  final bool graduated;

  const ReviewSchedule({
    required this.skillId,
    required this.step,
    required this.dueAt,
    required this.lastOutcomeAt,
    required this.lastOutcomeMistakes,
    required this.graduated,
  });

  Map<String, dynamic> toJson() => {
        'skill_id': skillId,
        'step': step,
        'due_at': dueAt.toUtc().toIso8601String(),
        'last_outcome_at': lastOutcomeAt.toUtc().toIso8601String(),
        'last_outcome_mistakes': lastOutcomeMistakes,
        'graduated': graduated,
      };

  static ReviewSchedule? tryFromJson(String skillId, Map<String, dynamic> j) {
    try {
      final dueRaw = j['due_at'];
      final lastRaw = j['last_outcome_at'];
      if (dueRaw is! String || lastRaw is! String) return null;
      final due = DateTime.tryParse(dueRaw);
      final last = DateTime.tryParse(lastRaw);
      if (due == null || last == null) return null;
      return ReviewSchedule(
        skillId: skillId,
        step: (j['step'] as num?)?.toInt() ?? 1,
        dueAt: due,
        lastOutcomeAt: last,
        lastOutcomeMistakes: (j['last_outcome_mistakes'] as num?)?.toInt() ?? 0,
        graduated: j['graduated'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}
