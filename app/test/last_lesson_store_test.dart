// Wave 14.9 — LastLessonStore now carries the full LessonResultResponse
// so the dashboard's `Review mistakes` / `See full report` CTAs can
// render the per-exercise mistake list, not just headline counts.
//
// Pre-14.9 the store kept only headline metadata (lessonId, title,
// completedAt, totalExercises, correctCount, debrief) — meaning the
// dashboard CTAs opened SummaryScreen with `summary: null` and the
// mistakes section was skipped entirely.

import 'package:flutter_test/flutter_test.dart';
import 'package:mastery/models/evaluation.dart';
import 'package:mastery/session/last_lesson_store.dart';

LessonResultResponse _seedSummary() {
  // Minimal valid LessonResultResponse with 1 mistake to verify the
  // mistake list survives the round-trip through the store.
  return const LessonResultResponse(
    lessonId: 'b2-lesson-001',
    correctCount: 9,
    totalExercises: 10,
    answers: [
      LessonResultAnswer(
        exerciseId: 'ex-1',
        correct: false,
        prompt: 'I have ___ here for five years.',
        canonicalAnswer: 'lived',
        explanation: 'Past simple cannot describe a state continuing into the present.',
      ),
    ],
    debrief: LessonDebrief(
      debriefType: LessonDebriefType.mixed,
      headline: 'You got close.',
      body: 'One slip on present perfect continuous.',
      source: 'fallback',
    ),
  );
}

void main() {
  setUp(() {
    LastLessonStore.instance.reset();
  });

  test('record without summary still validates (legacy fallback path)',
      () {
    LastLessonStore.instance.recordLesson(LastLessonRecord(
      lessonId: 'b2-lesson-001',
      lessonTitle: 'B2 lesson',
      completedAt: DateTime.utc(2026, 4, 28, 12),
      totalExercises: 10,
      correctCount: 9,
    ));
    final r = LastLessonStore.instance.record!;
    expect(r.summary, isNull);
    expect(r.mistakesCount, 1);
  });

  test('record carries the full LessonResultResponse when provided', () {
    final summary = _seedSummary();
    LastLessonStore.instance.recordLesson(LastLessonRecord(
      lessonId: summary.lessonId,
      lessonTitle: 'B2 lesson',
      completedAt: DateTime.utc(2026, 4, 28, 12),
      totalExercises: summary.totalExercises,
      correctCount: summary.correctCount,
      debrief: summary.debrief,
      summary: summary,
    ));
    final r = LastLessonStore.instance.record!;
    expect(r.summary, isNotNull);
    expect(r.summary!.answers.length, 1);
    expect(r.summary!.answers.first.correct, isFalse);
    expect(r.summary!.answers.first.canonicalAnswer, 'lived');
  });

  test('mistakesCount derives from total - correct, not from summary',
      () {
    // Round-trip honesty: even when summary is set, mistakesCount stays
    // the canonical count. Summary is the SOURCE for the mistake LIST,
    // not the headline count.
    final summary = _seedSummary();
    LastLessonStore.instance.recordLesson(LastLessonRecord(
      lessonId: summary.lessonId,
      lessonTitle: 'B2 lesson',
      completedAt: DateTime.utc(2026, 4, 28, 12),
      totalExercises: 10,
      correctCount: 7,
      summary: summary,
    ));
    final r = LastLessonStore.instance.record!;
    expect(r.mistakesCount, 3);
  });

  test('reset clears the record', () {
    LastLessonStore.instance.recordLesson(LastLessonRecord(
      lessonId: 'b2-lesson-001',
      lessonTitle: 'B2 lesson',
      completedAt: DateTime.utc(2026, 4, 28, 12),
      totalExercises: 10,
      correctCount: 9,
      summary: _seedSummary(),
    ));
    expect(LastLessonStore.instance.record, isNotNull);
    LastLessonStore.instance.reset();
    expect(LastLessonStore.instance.record, isNull);
  });
}
