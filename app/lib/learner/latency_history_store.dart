import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Wave A — per-skill response-time history.
///
/// Pure measurement collector. Lives independently of
/// `LearnerSkillStore` because:
///
/// 1. Server has no `response_time_ms` column on `/me/skills/...` —
///    keeping this client-only avoids a backend contract change in the
///    measurement-only wave.
/// 2. Latency is a per-device signal (different keyboard / different
///    median); cross-device sync would dilute it.
/// 3. The store can be promoted to a pluggable backend later, without
///    touching the existing Mastery Model.
///
/// FIFO list of last `historyCap` (default 20) response times per
/// `skill_id`. No mastery formula consumes this yet — Wave A is
/// measurement-only. Wave B introduces the latency band UI; Wave D
/// wires the median into the §6.4 production gate.
class LatencyHistoryStore {
  /// Maximum number of attempts kept per skill. Older entries drop out
  /// of the FIFO. Tunable.
  static const int historyCap = 20;

  static const _keyPrefix = 'latency_v1_';
  static const _indexKey = 'latency_v1_index';

  /// Records one response time (ms) for the given skill. Tolerates
  /// persistence failures silently — a measurement gap is preferable
  /// to a broken session. Negative values are dropped.
  static Future<void> record({
    required String skillId,
    required int responseTimeMs,
  }) async {
    if (responseTimeMs < 0) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = _read(prefs, skillId);
      history.add(responseTimeMs);
      if (history.length > historyCap) {
        history.removeRange(0, history.length - historyCap);
      }
      await prefs.setString(_keyPrefix + skillId, jsonEncode(history));
      await _addToIndex(prefs, skillId);
    } catch (_) {
      // Measurement-only — never escalate to the session.
    }
  }

  /// Returns the recorded history (oldest first). Empty list when the
  /// skill has no attempts yet, or when the underlying store fails.
  static Future<List<int>> historyFor(String skillId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _read(prefs, skillId);
    } catch (_) {
      return const [];
    }
  }

  /// Minimum number of recorded attempts before
  /// `stableMedianFor` returns a value. Below this floor the median
  /// is too volatile to feed any gating decision (Wave D mastery
  /// formula). Tunable; conservative default of 5 keeps the gate
  /// fair for new learners.
  static const int defaultMinSamplesForStableMedian = 5;

  /// Median of the recorded history, or `null` when there are no
  /// attempts yet. Used by the Wave B latency band (advisory only).
  /// Wave D consumers should prefer `stableMedianFor` so a single
  /// fast attempt can not flip the mastery gate.
  static Future<int?> medianFor(String skillId) async {
    final h = await historyFor(skillId);
    if (h.isEmpty) return null;
    return _medianOf(h);
  }

  /// Same as `medianFor` but returns `null` when fewer than
  /// `minSamples` attempts are recorded. The Mastery Model uses this
  /// instead of the raw median so a one-shot fast attempt cannot
  /// promote a skill into `mastered` on its own.
  static Future<int?> stableMedianFor(
    String skillId, {
    int minSamples = defaultMinSamplesForStableMedian,
  }) async {
    final h = await historyFor(skillId);
    if (h.length < minSamples) return null;
    return _medianOf(h);
  }

  static int _medianOf(List<int> samples) {
    final sorted = [...samples]..sort();
    final n = sorted.length;
    if (n.isOdd) return sorted[n ~/ 2];
    return ((sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2).round();
  }

  /// Test-only: wipes every skill's recorded history.
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

  static List<int> _read(SharedPreferences prefs, String skillId) {
    final raw = prefs.getString(_keyPrefix + skillId);
    if (raw == null) return <int>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <int>[];
      return decoded.whereType<num>().map((n) => n.toInt()).toList();
    } catch (_) {
      return <int>[];
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
