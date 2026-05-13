// Wave F — corpus guard for the §4.1 `(verb)` hint pattern.
//
// Loads every shipped fill_blank exercise from `backend/data/lessons/`
// and verifies the `stripFillBlankHint` helper either preserves the
// prompt (no hint present) OR strips exactly the `(<base-verb>)`
// substring while preserving the surrounding text + the `___` blank.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/widgets/fill_blank_widget.dart';

void main() {
  test('all shipped fill_blank items survive hint stripping', () {
    final lessonsDir = Directory('../backend/data/lessons');
    expect(lessonsDir.existsSync(), isTrue,
        reason: 'cannot locate backend/data/lessons');

    final items = <Map<String, dynamic>>[];
    for (final file in lessonsDir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final raw = file.readAsStringSync();
      final lesson = jsonDecode(raw) as Map<String, dynamic>;
      final exercises = (lesson['exercises'] as List).cast<Map<String, dynamic>>();
      for (final ex in exercises) {
        if (ex['type'] == 'fill_blank') items.add(ex);
      }
    }

    expect(items.length, greaterThanOrEqualTo(15),
        reason: 'expected at least 15 shipped fill_blank items');

    final hintRegex = RegExp(r'(_{2,})\s*\(([a-z][^)]*)\)');
    for (final ex in items) {
      final id = ex['exercise_id'] as String? ?? '<no id>';
      final prompt = ex['prompt'] as String;
      final stripped = stripFillBlankHint(prompt);

      // Match must NOT remain after stripping — the helper is idempotent
      // and complete.
      expect(hintRegex.hasMatch(stripped), isFalse,
          reason: '$id: hint should be fully stripped, got "$stripped"');

      // The blank marker must survive.
      expect(stripped, contains('___'),
          reason: '$id: ___ blank must be preserved after stripping');

      if (hintRegex.hasMatch(prompt)) {
        // Item carried a hint. Stripped result should differ.
        expect(stripped, isNot(equals(prompt)),
            reason: '$id: prompt had a hint but stripping produced no change');
      } else {
        // No hint in original → stripping is a no-op.
        expect(stripped, equals(prompt),
            reason: '$id: hint-less prompt should pass through unchanged');
      }
    }
  });
}
