import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/lesson.dart';

/// Per-learner per-skill mastery state per `LEARNING_ENGINE.md §7.1`.
///
/// Wave 2 of `docs/plans/learning-engine-mvp-2.md`: device-scoped local
/// persistence via SharedPreferences, mirroring `LocalProgressStore`.
/// Server-side learner storage is a follow-up wave once accounts exist.
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

class LearnerSkillRecord {
  final String skillId;

  /// Internal 0–100 score per §7.1. V0 score deltas live in
  /// `LearnerSkillStore._scoreDelta` and are tunable.
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

  /// Status derivation per `LEARNING_ENGINE.md §7.2`. Labels are part of
  /// the contract; thresholds are tunable. Wave 2 ships the V0 set
  /// described in `docs/plans/learning-engine-mvp-2.md` Wave 2.
  SkillStatus statusAt(DateTime now) {
    final hasStrongOrStronger = (evidenceSummary[EvidenceTier.strong] ?? 0) +
            (evidenceSummary[EvidenceTier.strongest] ?? 0) >
        0;

    if (productionGateCleared && hasStrongOrStronger && masteryScore >= 80) {
      // §7.2: mastered + 21d recency window expired → review_due
      if (lastAttemptAt != null &&
          now.difference(lastAttemptAt!) > const Duration(days: 21)) {
        return SkillStatus.reviewDue;
      }
      return SkillStatus.mastered;
    }
    if (masteryScore >= 70 && hasStrongOrStronger) {
      return SkillStatus.almostMastered;
    }
    if (masteryScore >= 50 && hasStrongOrStronger) {
      return SkillStatus.gettingThere;
    }
    if (masteryScore >= 30) {
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

class LearnerSkillStore {
  static const _keyPrefix = 'learner_skill_v1_';
  static const _indexKey = 'learner_skill_v1_index';

  /// Bound on `recent_errors[]` per §7.1. Tunable; Wave 3's Decision
  /// Engine will read this list to decide in-session loop behaviour.
  static const int recentErrorsCap = 5;

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
        if (errors.length > recentErrorsCap) {
          errors.removeRange(0, errors.length - recentErrorsCap);
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
      // Tolerate persistence failure — the lesson flow must keep working.
      return null;
    }
  }

  static Future<LearnerSkillRecord> getRecord(String skillId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _readRecord(prefs, skillId) ?? LearnerSkillRecord.empty(skillId);
    } catch (_) {
      return LearnerSkillRecord.empty(skillId);
    }
  }

  static Future<List<LearnerSkillRecord>> allRecords() async {
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

  /// Test-only: clears the entire learner skill store so each test starts
  /// from a clean slate.
  static Future<void> clearForTests() async {
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
