import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_client.dart';
import '../models/lesson.dart';

/// Per-learner per-skill mastery state per `LEARNING_ENGINE.md §7.1`.
///
/// Wave 2 of `docs/plans/learning-engine-mvp-2.md` shipped a device-scoped
/// SharedPreferences-backed store. Wave 7.4 part 2B turns this into a
/// pluggable facade with a local backend (the original behavior) and a
/// remote backend that talks to the auth-protected `/me/skills/...`
/// endpoints. Call-sites stay on the static facade —
/// `LearnerSkillStore.recordAttempt(...)` etc. — and switch backends in
/// place when the learner signs in.
///
/// Status is **derived** on read from the stored inputs; only
/// `productionGateCleared` is stored directly per §7.1, so it cannot
/// silently flip back if older attempts are pruned.
enum SkillStatus {
  started,
  practicing,
  gettingThere,
  almostMastered,
  mastered,
  reviewDue,
}

String skillStatusToString(SkillStatus s) => switch (s) {
      SkillStatus.started => 'started',
      SkillStatus.practicing => 'practicing',
      SkillStatus.gettingThere => 'getting_there',
      SkillStatus.almostMastered => 'almost_mastered',
      SkillStatus.mastered => 'mastered',
      SkillStatus.reviewDue => 'review_due',
    };

SkillStatus _parseStatus(String? s) => switch (s) {
      'practicing' => SkillStatus.practicing,
      'getting_there' => SkillStatus.gettingThere,
      'almost_mastered' => SkillStatus.almostMastered,
      'mastered' => SkillStatus.mastered,
      'review_due' => SkillStatus.reviewDue,
      _ => SkillStatus.started,
    };

class LearnerSkillRecord {
  final String skillId;

  /// Internal 0–100 score per §7.1. V0 score deltas live in
  /// `LocalLearnerSkillBackend._scoreDelta` and are tunable.
  final int masteryScore;

  /// Recency for §9.3 review scheduling and the §7.2 `review_due`
  /// transition. ISO-8601 UTC; `null` only on a freshly-constructed
  /// record before the first attempt is recorded.
  final DateTime? lastAttemptAt;

  /// Counts of attempts at each evidence tier per §6.1. The Mastery
  /// Model uses these to enforce the §6.2 floor (no recognition-only
  /// mastery) and to decide §7.2 transitions.
  final Map<EvidenceTier, int> evidenceSummary;

  /// Last N target-error codes seen on this skill per §7.1. FIFO,
  /// capped at `LearnerSkillStore.recentErrorsCap`.
  final List<TargetError> recentErrors;

  /// True once the learner records a strongest-tier correct attempt that
  /// satisfies §6.3 (meaning + form). Stored, not re-derived per §7.1, so
  /// it cannot silently flip back if older attempts are pruned from
  /// `evidenceSummary`.
  final bool productionGateCleared;

  /// `LEARNING_ENGINE.md §12.3`: the evaluator version at which the
  /// production gate cleared. When `recordAttempt` sees a higher
  /// `evaluationVersion` than this, it invalidates the gate (forcing the
  /// learner to re-clear under the new evaluator semantics). Null on
  /// records that never cleared the gate.
  final int? gateClearedAtVersion;

  const LearnerSkillRecord({
    required this.skillId,
    required this.masteryScore,
    required this.lastAttemptAt,
    required this.evidenceSummary,
    required this.recentErrors,
    required this.productionGateCleared,
    this.gateClearedAtVersion,
  });

  factory LearnerSkillRecord.empty(String skillId) => LearnerSkillRecord(
        skillId: skillId,
        masteryScore: 0,
        lastAttemptAt: null,
        evidenceSummary: const {},
        recentErrors: const [],
        productionGateCleared: false,
        gateClearedAtVersion: null,
      );

  LearnerSkillRecord copyWith({
    int? masteryScore,
    DateTime? lastAttemptAt,
    Map<EvidenceTier, int>? evidenceSummary,
    List<TargetError>? recentErrors,
    bool? productionGateCleared,
    int? gateClearedAtVersion,
    bool clearGateClearedAtVersion = false,
  }) =>
      LearnerSkillRecord(
        skillId: skillId,
        masteryScore: masteryScore ?? this.masteryScore,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
        evidenceSummary: evidenceSummary ?? this.evidenceSummary,
        recentErrors: recentErrors ?? this.recentErrors,
        productionGateCleared:
            productionGateCleared ?? this.productionGateCleared,
        gateClearedAtVersion: clearGateClearedAtVersion
            ? null
            : (gateClearedAtVersion ?? this.gateClearedAtVersion),
      );

  /// Status derivation per `LEARNING_ENGINE.md §10` (Mastery Model V1).
  /// Labels are part of the contract; thresholds finalised during the
  /// V1 review on 2026-04-26 — `docs/plans/learning-engine-v1.md`
  /// Decisions log #8.
  ///
  /// V1 boundaries:
  ///   0–20  → started
  ///   21–45 → practicing
  ///   46–70 → getting_there
  ///   71–84 → almost_mastered
  ///   85–100 → mastered
  ///
  /// `productionGateCleared + hasStrongOrStronger + masteryScore ≥ 85`
  /// is the gate for `mastered` (down from ≥80 in V0). `review_due`
  /// fires when a mastered skill's `lastAttemptAt` is more than 21
  /// days stale per §13.
  SkillStatus statusAt(DateTime now) {
    final hasStrongOrStronger = (evidenceSummary[EvidenceTier.strong] ?? 0) +
            (evidenceSummary[EvidenceTier.strongest] ?? 0) >
        0;

    if (productionGateCleared && hasStrongOrStronger && masteryScore >= 85) {
      if (lastAttemptAt != null &&
          now.difference(lastAttemptAt!) > const Duration(days: 21)) {
        return SkillStatus.reviewDue;
      }
      return SkillStatus.mastered;
    }
    if (masteryScore >= 71 && hasStrongOrStronger) {
      return SkillStatus.almostMastered;
    }
    if (masteryScore >= 46 && hasStrongOrStronger) {
      return SkillStatus.gettingThere;
    }
    if (masteryScore >= 21) {
      return SkillStatus.practicing;
    }
    return SkillStatus.started;
  }

  Map<String, dynamic> toJson() => {
        'skill_id': skillId,
        'mastery_score': masteryScore,
        'last_attempt_at': lastAttemptAt?.toUtc().toIso8601String(),
        'evidence_summary': {
          for (final entry in evidenceSummary.entries)
            evidenceTierToString(entry.key): entry.value,
        },
        'recent_errors': recentErrors.map(targetErrorToString).toList(),
        'production_gate_cleared': productionGateCleared,
        'gate_cleared_at_version': gateClearedAtVersion,
      };

  /// Tolerant parser: an invalid record yields `null` so the caller can
  /// fall back to an empty record rather than crashing the session.
  static LearnerSkillRecord? tryFromJson(String skillId, Map<String, dynamic> j) {
    try {
      final tierMap = <EvidenceTier, int>{};
      final rawSummary = j['evidence_summary'];
      if (rawSummary is Map) {
        rawSummary.forEach((k, v) {
          final tier = _parseTier(k as String);
          if (tier != null && v is int) tierMap[tier] = v;
        });
      }
      final errors = <TargetError>[];
      final rawErrors = j['recent_errors'];
      if (rawErrors is List) {
        for (final e in rawErrors) {
          final parsed = _parseError(e as String?);
          if (parsed != null) errors.add(parsed);
        }
      }
      final lastAt = j['last_attempt_at'];
      return LearnerSkillRecord(
        skillId: skillId,
        masteryScore: (j['mastery_score'] as num?)?.toInt() ?? 0,
        lastAttemptAt: lastAt is String ? DateTime.tryParse(lastAt) : null,
        evidenceSummary: tierMap,
        recentErrors: errors,
        productionGateCleared: j['production_gate_cleared'] as bool? ?? false,
        gateClearedAtVersion: (j['gate_cleared_at_version'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

EvidenceTier? _parseTier(String s) => switch (s) {
      'weak' => EvidenceTier.weak,
      'medium' => EvidenceTier.medium,
      'strong' => EvidenceTier.strong,
      'strongest' => EvidenceTier.strongest,
      _ => null,
    };

TargetError? _parseError(String? s) => switch (s) {
      'conceptual_error' => TargetError.conceptual,
      'form_error' => TargetError.form,
      'contrast_error' => TargetError.contrast,
      'careless_error' => TargetError.careless,
      'transfer_error' => TargetError.transfer,
      'pragmatic_error' => TargetError.pragmatic,
      _ => null,
    };

/// Pluggable backend interface for the `LearnerSkillStore` facade.
///
/// Two implementations:
/// - `LocalLearnerSkillBackend` writes to SharedPreferences (the Wave 2
///   default). Used in unauth'd builds and in guest mode after Skip.
/// - `RemoteLearnerSkillBackend` calls the auth-protected
///   `/me/skills/...` endpoints. Used after a learner signs in.
///
/// Both return `null` from `recordAttempt` on persistence failures so
/// the lesson flow stays alive — same contract as the original Wave 2
/// store.
abstract class LearnerSkillBackend {
  Future<LearnerSkillRecord?> recordAttempt({
    required String skillId,
    required EvidenceTier evidenceTier,
    required bool correct,
    TargetError? primaryTargetError,
    String? meaningFrame,
    DateTime? occurredAt,
    int? evaluationVersion,
  });

  Future<LearnerSkillRecord> getRecord(String skillId);

  Future<List<LearnerSkillRecord>> allRecords();

  Future<void> clearAll();
}

/// Wave 2 / Wave 7.4 part 2B local backend. Reads and writes the same
/// SharedPreferences keys the original static `LearnerSkillStore` used,
/// so guest-mode reinstalls and existing devices keep working without
/// migration on the local side.
class LocalLearnerSkillBackend implements LearnerSkillBackend {
  static const _keyPrefix = 'learner_skill_v1_';
  static const _indexKey = 'learner_skill_v1_index';

  /// V0 score deltas (`LEARNING_ENGINE.md §6` weight, tunable). Higher
  /// tiers move the score harder in either direction.
  static int _scoreDelta(EvidenceTier tier, bool correct) {
    final base = switch (tier) {
      EvidenceTier.weak => 5,
      EvidenceTier.medium => 10,
      EvidenceTier.strong => 15,
      EvidenceTier.strongest => 20,
    };
    return correct ? base : -base;
  }

  @override
  Future<LearnerSkillRecord?> recordAttempt({
    required String skillId,
    required EvidenceTier evidenceTier,
    required bool correct,
    TargetError? primaryTargetError,
    String? meaningFrame,
    DateTime? occurredAt,
    int? evaluationVersion,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var existing = _readRecord(prefs, skillId) ??
          LearnerSkillRecord.empty(skillId);

      // §12.3 invalidation. If the gate was previously cleared at a
      // lower evaluator version than what just shipped, drop it before
      // applying this attempt's effect — the learner has to re-clear
      // production under the new evaluator semantics.
      if (existing.productionGateCleared &&
          evaluationVersion != null &&
          existing.gateClearedAtVersion != null &&
          evaluationVersion > existing.gateClearedAtVersion!) {
        existing = existing.copyWith(
          productionGateCleared: false,
          clearGateClearedAtVersion: true,
        );
      }

      final summary = Map<EvidenceTier, int>.from(existing.evidenceSummary);
      summary[evidenceTier] = (summary[evidenceTier] ?? 0) + 1;

      final score = (existing.masteryScore + _scoreDelta(evidenceTier, correct))
          .clamp(0, 100)
          .toInt();

      final errors = List<TargetError>.from(existing.recentErrors);
      if (!correct && primaryTargetError != null) {
        errors.add(primaryTargetError);
        if (errors.length > LearnerSkillStore.recentErrorsCap) {
          errors.removeRange(
              0, errors.length - LearnerSkillStore.recentErrorsCap);
        }
      }

      // Production gate per §6.4: a strongest-tier correct attempt that
      // also carries a `meaning_frame` (the §6.3 meaning+form proof).
      // `meaningFrame` non-empty is the proxy the schema uses to flag a
      // §6.3-compliant item.
      final gateClearedThisAttempt = correct &&
          evidenceTier == EvidenceTier.strongest &&
          (meaningFrame != null && meaningFrame.trim().isNotEmpty);
      final gate = existing.productionGateCleared || gateClearedThisAttempt;
      // Stamp the version when the gate clears (newly or previously).
      // Null `evaluationVersion` leaves the existing stamp untouched —
      // pre-Wave-5 callers still work.
      final newGateVersion = !gate
          ? null
          : (gateClearedThisAttempt
              ? (evaluationVersion ?? existing.gateClearedAtVersion)
              : existing.gateClearedAtVersion);

      final updated = existing.copyWith(
        masteryScore: score,
        lastAttemptAt: occurredAt ?? DateTime.now().toUtc(),
        evidenceSummary: summary,
        recentErrors: errors,
        productionGateCleared: gate,
        gateClearedAtVersion: newGateVersion,
        clearGateClearedAtVersion: !gate,
      );

      await prefs.setString(_keyPrefix + skillId, jsonEncode(updated.toJson()));
      await _addToIndex(prefs, skillId);
      return updated;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<LearnerSkillRecord> getRecord(String skillId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _readRecord(prefs, skillId) ?? LearnerSkillRecord.empty(skillId);
    } catch (_) {
      return LearnerSkillRecord.empty(skillId);
    }
  }

  @override
  Future<List<LearnerSkillRecord>> allRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = prefs.getStringList(_indexKey) ?? const <String>[];
      final out = <LearnerSkillRecord>[];
      for (final id in ids) {
        final rec = _readRecord(prefs, id);
        if (rec != null) out.add(rec);
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

  static LearnerSkillRecord? _readRecord(
      SharedPreferences prefs, String skillId) {
    final raw = prefs.getString(_keyPrefix + skillId);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return null;
      return LearnerSkillRecord.tryFromJson(skillId, j);
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
/// `/me/skills/...` endpoints. The server is the source of truth; this
/// backend never reads from local storage.
///
/// Network failures are tolerated: `recordAttempt` returns `null`,
/// `getRecord` returns an empty record, `allRecords` returns `[]`.
/// Same contract as the local backend so the lesson flow stays alive
/// when the device drops offline mid-session.
class RemoteLearnerSkillBackend implements LearnerSkillBackend {
  final AuthClient _authClient;
  final String baseUrl;

  RemoteLearnerSkillBackend({
    required AuthClient authClient,
    required this.baseUrl,
  }) : _authClient = authClient;

  @override
  Future<LearnerSkillRecord?> recordAttempt({
    required String skillId,
    required EvidenceTier evidenceTier,
    required bool correct,
    TargetError? primaryTargetError,
    String? meaningFrame,
    DateTime? occurredAt,
    int? evaluationVersion,
  }) async {
    try {
      final body = <String, dynamic>{
        'evidence_tier': evidenceTierToString(evidenceTier),
        'correct': correct,
        if (primaryTargetError != null)
          'primary_target_error': targetErrorToString(primaryTargetError),
        if (meaningFrame != null && meaningFrame.trim().isNotEmpty)
          'meaning_frame': meaningFrame,
        if (evaluationVersion != null) 'evaluation_version': evaluationVersion,
      };
      final resp = await _authClient.send(
        'POST',
        Uri.parse('$baseUrl/me/skills/$skillId/attempts'),
        body: body,
      );
      if (resp.statusCode != 200) return null;
      return _parseRecordDto(skillId, jsonDecode(resp.body));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<LearnerSkillRecord> getRecord(String skillId) async {
    try {
      final resp = await _authClient.send(
        'GET',
        Uri.parse('$baseUrl/me/skills/$skillId'),
      );
      if (resp.statusCode != 200) return LearnerSkillRecord.empty(skillId);
      return _parseRecordDto(skillId, jsonDecode(resp.body)) ??
          LearnerSkillRecord.empty(skillId);
    } catch (_) {
      return LearnerSkillRecord.empty(skillId);
    }
  }

  @override
  Future<List<LearnerSkillRecord>> allRecords() async {
    try {
      final resp = await _authClient.send(
        'GET',
        Uri.parse('$baseUrl/me/skills'),
      );
      if (resp.statusCode != 200) return const [];
      final j = jsonDecode(resp.body);
      if (j is! Map<String, dynamic>) return const [];
      final list = j['skills'];
      if (list is! List) return const [];
      final out = <LearnerSkillRecord>[];
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final id = item['skill_id'];
          if (id is String) {
            final rec = _parseRecordDto(id, item);
            if (rec != null) out.add(rec);
          }
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Server-side state is per-account. No local rows to clear; this is
  /// intentionally a no-op so the migration trigger can call clearAll
  /// uniformly across both backends.
  @override
  Future<void> clearAll() async {}

  static LearnerSkillRecord? _parseRecordDto(String skillId, dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    // The server DTO carries a derived `status` field that the client
    // recomputes locally — drop it. The remaining shape matches
    // `LearnerSkillRecord.tryFromJson` exactly. _parseStatus is kept in
    // case future call-sites want to surface the server-derived status.
    _parseStatus(raw['status'] as String?);
    return LearnerSkillRecord.tryFromJson(skillId, raw);
  }
}

/// Wave 7.4 part 2B static facade. Existing call-sites stay on
/// `LearnerSkillStore.recordAttempt(...)` etc. The active backend is
/// swapped in place by `useRemote(authClient)` after the learner signs
/// in, and reset to local by `useLocal()` on logout / Skip.
class LearnerSkillStore {
  /// Bound on `recent_errors[]` per §7.1. Tunable; Wave 3's Decision
  /// Engine reads this list to decide in-session loop behaviour.
  static const int recentErrorsCap = 5;

  static LearnerSkillBackend _backend = LocalLearnerSkillBackend();

  /// Test-only: replace the active backend wholesale. Production code
  /// uses `useLocal` / `useRemote`.
  // ignore: avoid_setters_without_getters
  static set backendForTests(LearnerSkillBackend b) {
    _backend = b;
  }

  /// Returns the active backend so callers (e.g., the migration trigger)
  /// can drive backend-specific paths.
  static LearnerSkillBackend get backend => _backend;

  /// Switches the facade back to the SharedPreferences-backed local
  /// store. Called on logout, Skip, or app start when no session exists.
  /// Idempotent.
  static void useLocal() {
    _backend = LocalLearnerSkillBackend();
  }

  /// Switches the facade to the auth-protected `/me/skills/...` endpoints.
  /// Idempotent — a second call with the same AuthClient just rebuilds
  /// the backend, which is cheap.
  static void useRemote({
    required AuthClient authClient,
    required String baseUrl,
  }) {
    _backend = RemoteLearnerSkillBackend(
      authClient: authClient,
      baseUrl: baseUrl,
    );
  }

  /// Records one attempt for one skill. Returns the updated record (or
  /// `null` if persistence failed — the session must keep working).
  static Future<LearnerSkillRecord?> recordAttempt({
    required String skillId,
    required EvidenceTier evidenceTier,
    required bool correct,
    TargetError? primaryTargetError,
    String? meaningFrame,
    DateTime? occurredAt,
    int? evaluationVersion,
  }) =>
      _backend.recordAttempt(
        skillId: skillId,
        evidenceTier: evidenceTier,
        correct: correct,
        primaryTargetError: primaryTargetError,
        meaningFrame: meaningFrame,
        occurredAt: occurredAt,
        evaluationVersion: evaluationVersion,
      );

  static Future<LearnerSkillRecord> getRecord(String skillId) =>
      _backend.getRecord(skillId);

  static Future<List<LearnerSkillRecord>> allRecords() =>
      _backend.allRecords();

  /// Test-only: clears whatever the active backend persists (local SharedPrefs
  /// for `LocalLearnerSkillBackend`; no-op for `RemoteLearnerSkillBackend`).
  static Future<void> clearForTests() async {
    await _backend.clearAll();
    // Reset the facade to the local default so subsequent tests start
    // from a clean slate.
    _backend = LocalLearnerSkillBackend();
  }
}
