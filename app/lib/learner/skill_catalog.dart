// Wave 12.7 — runtime skill catalog.
//
// Single source of truth for skill display names + per-skill rule
// snapshots on the client. Replaces the hardcoded
// `_shippedSkillTitles` map in `skill_titles.dart` (which still
// stays as an offline-first fallback so the first frame after a
// cold launch never renders raw skill_ids).
//
// Lifecycle:
//   1. App boots → cache empty.
//   2. HomeScreen mount → SkillCatalog.refresh() fetches /skills.
//   3. Cache populated; consumers (`skillTitleFor`, dashboard
//      Rules card, future Wave 4 surfaces) read from it.
//   4. On any fetch failure (offline, 5xx) the cache stays as it
//      was; consumers fall through to the hardcoded fallback so
//      the UI never flashes raw skill_ids.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/rule_card.dart';

class SkillCatalogEntry {
  final String skillId;
  final String title;
  final String? description;
  final String cefrLevel;
  final String? introRule;
  final List<String> introExamples;
  /// Wave H1 — textbook-format rule card from the source lesson.
  /// When present, the dashboard `_RuleSheetBody` and any future
  /// per-skill rule surface render this in place of the flat
  /// `introRule` string.
  final RuleCardData? ruleCard;

  const SkillCatalogEntry({
    required this.skillId,
    required this.title,
    required this.description,
    required this.cefrLevel,
    required this.introRule,
    required this.introExamples,
    this.ruleCard,
  });

  factory SkillCatalogEntry.fromJson(Map<String, dynamic> j) =>
      SkillCatalogEntry(
        skillId: j['skill_id'] as String,
        title: (j['title'] as String?) ?? (j['skill_id'] as String),
        description: j['description'] as String?,
        cefrLevel: (j['cefr_level'] as String?) ?? 'B2',
        introRule: j['intro_rule'] as String?,
        introExamples: (j['intro_examples'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[],
        ruleCard: RuleCardData.maybeFromJson(
          j['rule_card'] as Map<String, dynamic>?,
        ),
      );
}

class SkillCatalog extends ChangeNotifier {
  SkillCatalog._();
  static final SkillCatalog instance = SkillCatalog._();

  final Map<String, SkillCatalogEntry> _bySkillId = {};
  List<SkillCatalogEntry> _ordered = const [];
  bool _hasFetched = false;
  Object? _lastError;

  bool get hasFetched => _hasFetched;
  Object? get lastError => _lastError;
  List<SkillCatalogEntry> get all => List.unmodifiable(_ordered);

  SkillCatalogEntry? entryFor(String skillId) => _bySkillId[skillId];

  /// Test-only: clear the cache so consecutive widget tests see a
  /// fresh catalog. The cache is a global singleton, so without
  /// this every test after the first inherits the prior fetch.
  @visibleForTesting
  void resetForTests() {
    _bySkillId.clear();
    _ordered = const [];
    _hasFetched = false;
    _lastError = null;
  }

  /// Test-only: seed the cache with hand-built entries so widget
  /// tests can render dependent surfaces without a real HTTP call.
  @visibleForTesting
  void seedForTests(List<SkillCatalogEntry> entries) {
    _bySkillId
      ..clear()
      ..addEntries(entries.map((e) => MapEntry(e.skillId, e)));
    _ordered = List.unmodifiable(entries);
    _hasFetched = true;
    _lastError = null;
    notifyListeners();
  }

  /// Fetch /skills. Idempotent — call from HomeScreen mount and on
  /// any explicit "refresh catalog" affordance.
  Future<void> refresh({
    required String baseUrl,
    http.Client? httpClient,
  }) async {
    final client = httpClient ?? http.Client();
    final ownsClient = httpClient == null;
    try {
      final res = await client
          .get(Uri.parse('$baseUrl/skills'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _lastError = StateError(
          'GET /skills returned ${res.statusCode}',
        );
        return;
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! List) {
        _lastError = const FormatException('GET /skills body not a List');
        return;
      }
      final entries = decoded
          .whereType<Map<String, dynamic>>()
          .map(SkillCatalogEntry.fromJson)
          .toList();
      _bySkillId
        ..clear()
        ..addEntries(entries.map((e) => MapEntry(e.skillId, e)));
      _ordered = List.unmodifiable(entries);
      _hasFetched = true;
      _lastError = null;
      notifyListeners();
    } catch (e) {
      _lastError = e;
      // Cache stays as it was — consumers continue to read prior
      // values or fall back to the hardcoded map.
    } finally {
      if (ownsClient) client.close();
    }
  }
}
