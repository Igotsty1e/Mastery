// Wave A — LatencyHistoryStore covers the per-skill response-time
// collector that feeds the future Wave B latency band UI and the
// Wave D mastery-gate signal. Measurement-only today: no mastery
// formula reads from it yet.

import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/learner/latency_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    await LatencyHistoryStore.clearForTests();
  });

  test('record persists a single attempt and historyFor reads it back',
      () async {
    await LatencyHistoryStore.record(
      skillId: 'skill-x',
      responseTimeMs: 1234,
    );

    final history = await LatencyHistoryStore.historyFor('skill-x');
    expect(history, [1234]);
  });

  test('record appends in order (FIFO insertion)', () async {
    await LatencyHistoryStore.record(skillId: 'skill-x', responseTimeMs: 1000);
    await LatencyHistoryStore.record(skillId: 'skill-x', responseTimeMs: 2000);
    await LatencyHistoryStore.record(skillId: 'skill-x', responseTimeMs: 3000);

    final history = await LatencyHistoryStore.historyFor('skill-x');
    expect(history, [1000, 2000, 3000]);
  });

  test('historyFor caps at historyCap (oldest entries drop)', () async {
    for (var i = 0; i < LatencyHistoryStore.historyCap + 5; i++) {
      await LatencyHistoryStore.record(
        skillId: 'skill-cap',
        responseTimeMs: i,
      );
    }

    final history = await LatencyHistoryStore.historyFor('skill-cap');
    expect(history.length, LatencyHistoryStore.historyCap);
    // Oldest 5 entries (0..4) dropped; newest entry is the last value
    // we wrote (historyCap + 4).
    expect(history.first, 5);
    expect(history.last, LatencyHistoryStore.historyCap + 4);
  });

  test('negative response times are dropped silently', () async {
    await LatencyHistoryStore.record(
      skillId: 'skill-neg',
      responseTimeMs: -1,
    );
    final history = await LatencyHistoryStore.historyFor('skill-neg');
    expect(history, isEmpty);
  });

  test('historyFor on an unknown skill returns empty list', () async {
    final history = await LatencyHistoryStore.historyFor('nope');
    expect(history, isEmpty);
  });

  test('medianFor returns null on empty history', () async {
    expect(await LatencyHistoryStore.medianFor('nope'), isNull);
  });

  test('medianFor on odd-length history returns the middle value', () async {
    for (final ms in const [1000, 2000, 3000, 4000, 5000]) {
      await LatencyHistoryStore.record(skillId: 's', responseTimeMs: ms);
    }
    expect(await LatencyHistoryStore.medianFor('s'), 3000);
  });

  test('medianFor on even-length history returns the rounded average',
      () async {
    for (final ms in const [1000, 2000, 3000, 4000]) {
      await LatencyHistoryStore.record(skillId: 's', responseTimeMs: ms);
    }
    // Median of [1000, 2000, 3000, 4000] = (2000 + 3000) / 2 = 2500.
    expect(await LatencyHistoryStore.medianFor('s'), 2500);
  });

  test('medianFor is robust to insertion order (median is order-free)',
      () async {
    for (final ms in const [4000, 1000, 5000, 2000, 3000]) {
      await LatencyHistoryStore.record(skillId: 's', responseTimeMs: ms);
    }
    expect(await LatencyHistoryStore.medianFor('s'), 3000);
  });

  test('multiple skills do not bleed into each other', () async {
    await LatencyHistoryStore.record(skillId: 'a', responseTimeMs: 1000);
    await LatencyHistoryStore.record(skillId: 'b', responseTimeMs: 2000);
    await LatencyHistoryStore.record(skillId: 'a', responseTimeMs: 3000);

    expect(await LatencyHistoryStore.historyFor('a'), [1000, 3000]);
    expect(await LatencyHistoryStore.historyFor('b'), [2000]);
  });

  test('clearForTests wipes every recorded skill', () async {
    await LatencyHistoryStore.record(skillId: 'a', responseTimeMs: 100);
    await LatencyHistoryStore.record(skillId: 'b', responseTimeMs: 200);

    await LatencyHistoryStore.clearForTests();

    expect(await LatencyHistoryStore.historyFor('a'), isEmpty);
    expect(await LatencyHistoryStore.historyFor('b'), isEmpty);
  });
}
