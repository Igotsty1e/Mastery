// Wave 12.7 — SkillCatalog + skill_titles fallback coverage.
//
// SkillCatalog is a singleton, so tests must call resetForTests()
// in setUp to avoid carry-over.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/learner/skill_catalog.dart';
import 'package:mastery/learner/skill_titles.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() {
    SkillCatalog.instance.resetForTests();
  });

  test('skillTitleFor falls back to hardcoded map when catalog empty', () {
    expect(
      skillTitleFor('verb-ing-after-gerund-verbs'),
      equals('Verbs followed by -ing'),
    );
    // Unknown skill_id falls through to the raw id.
    expect(skillTitleFor('no-such-skill'), equals('no-such-skill'));
  });

  test('skillTitleFor reads from catalog when populated', () {
    SkillCatalog.instance.seedForTests(const [
      SkillCatalogEntry(
        skillId: 'verb-ing-after-gerund-verbs',
        title: 'Server-fed -ing title',
        description: null,
        cefrLevel: 'B2',
        introRule: null,
        introExamples: [],
      ),
    ]);
    expect(
      skillTitleFor('verb-ing-after-gerund-verbs'),
      equals('Server-fed -ing title'),
    );
    // Skill not in seed still falls back to hardcoded map.
    expect(
      skillTitleFor('verb-to-inf-after-aspirational-verbs'),
      equals('Verbs followed by to + infinitive'),
    );
  });

  test('refresh() populates the catalog on a 200 response', () async {
    final mock = MockClient((req) async {
      expect(req.url.path, '/skills');
      return http.Response(
        jsonEncode([
          {
            'skill_id': 'verb-ing-after-gerund-verbs',
            'title': 'Verbs followed by -ing',
            'description': 'After enjoy, avoid, suggest…',
            'cefr_level': 'B2',
            'intro_rule': 'Use -ing after these verbs.',
            'intro_examples': [
              'I enjoy reading.',
              'She suggested taking a taxi.',
            ],
          },
          {
            'skill_id': 'present-perfect-continuous-vs-simple',
            'title': 'Present perfect continuous vs simple',
            'description': null,
            'cefr_level': 'B2',
            'intro_rule': 'Use the continuous for duration.',
            'intro_examples': ['I have been working.'],
          },
        ]),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await SkillCatalog.instance.refresh(
      baseUrl: 'http://test.invalid',
      httpClient: mock,
    );

    expect(SkillCatalog.instance.hasFetched, isTrue);
    expect(SkillCatalog.instance.lastError, isNull);
    expect(SkillCatalog.instance.all, hasLength(2));
    final ing = SkillCatalog.instance.entryFor('verb-ing-after-gerund-verbs');
    expect(ing, isNotNull);
    expect(ing!.title, 'Verbs followed by -ing');
    expect(ing.cefrLevel, 'B2');
    expect(ing.introRule, 'Use -ing after these verbs.');
    expect(ing.introExamples, hasLength(2));
  });

  test('refresh() leaves cache intact + records error on 500', () async {
    SkillCatalog.instance.seedForTests(const [
      SkillCatalogEntry(
        skillId: 'verb-ing-after-gerund-verbs',
        title: 'Stale title',
        description: null,
        cefrLevel: 'B2',
        introRule: null,
        introExamples: [],
      ),
    ]);
    final mock = MockClient((req) async => http.Response('boom', 500));
    await SkillCatalog.instance.refresh(
      baseUrl: 'http://test.invalid',
      httpClient: mock,
    );
    // Cache stays — consumers keep reading the prior entry.
    expect(SkillCatalog.instance.lastError, isNotNull);
    expect(SkillCatalog.instance.all, hasLength(1));
    expect(
      SkillCatalog.instance.entryFor('verb-ing-after-gerund-verbs')?.title,
      'Stale title',
    );
  });
}
