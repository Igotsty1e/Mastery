import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import type { SentenceCorrectionExercise } from '../src/data/lessons';
import { LessonSchema } from '../src/data/lessonSchema';
import { StubAiProvider } from '../src/ai/stub';
import { evaluateSentenceCorrection } from '../src/evaluators/sentenceCorrection';

const lessonPath = path.resolve(__dirname, '../data/lessons/b2-lesson-001.json');
const lessonRaw = fs.readFileSync(lessonPath, 'utf8');
const parsedLesson = LessonSchema.parse(JSON.parse(lessonRaw));
const sentenceCorrectionExercises = parsedLesson.exercises.filter(
  (exercise): exercise is SentenceCorrectionExercise => exercise.type === 'sentence_correction'
);

describe('B2 lesson content fairness', () => {
  it('keeps the expected sentence_correction coverage in the shipped lesson', () => {
    expect(sentenceCorrectionExercises).toHaveLength(3);
  });

  for (const exercise of sentenceCorrectionExercises) {
    it(`${exercise.exercise_id} accepts every listed correction deterministically`, async () => {
      const ai = new StubAiProvider();
      const canonicalAnswer = exercise.accepted_corrections[0];

      for (const correction of exercise.accepted_corrections) {
        const result = await evaluateSentenceCorrection(
          correction,
          exercise.accepted_corrections,
          exercise.prompt,
          ai
        );

        expect(result.correct).toBe(true);
        expect(result.evaluation_source).toBe('deterministic');
        expect(result.feedback).toBeNull();
        expect(result.canonical_answer).toBe(canonicalAnswer);
      }
    });
  }
});
