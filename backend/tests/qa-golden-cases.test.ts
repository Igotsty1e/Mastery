import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { evaluateFillBlank } from '../src/evaluators/fillBlank';
import { evaluateMultipleChoice } from '../src/evaluators/multipleChoice';
import { evaluateSentenceCorrection } from '../src/evaluators/sentenceCorrection';
import type { AiProvider } from '../src/ai/interface';

// Mirrors docs/qa-golden-cases.md (kept intentionally table-driven).

describe('QA golden cases', () => {
  describe('fill_blank', () => {
    const accepted_answers = ['walks', 'goes'];

    it.each([
      ['walks'],
      ['goes'],
      ['  walks  '],
      ['Walks'],
      ['walks.'],
      ['GOES'],
    ])('accepts %o', (user_answer) => {
      const r = evaluateFillBlank(user_answer, accepted_answers);
      expect(r.correct).toBe(true);
      expect(r.evaluation_source).toBe('deterministic');
      expect(r.canonical_answer).toBe('walks');
    });

    it.each([['walk'], ['walked'], ['run'], [''], ['   '], ['walks quickly']])(
      'rejects %o',
      (user_answer) => {
        const r = evaluateFillBlank(user_answer, accepted_answers);
        expect(r.correct).toBe(false);
        expect(r.evaluation_source).toBe('deterministic');
        expect(r.canonical_answer).toBe('walks');
      }
    );
  });

  describe('multiple_choice', () => {
    const correct_option_id = 'b';
    const options = [
      { id: 'a', text: 'Sad' },
      { id: 'b', text: 'Joyful' },
      { id: 'c', text: 'Angry' },
      { id: 'd', text: 'Tired' },
    ];

    it.each([['b'], ['B'], [' b ']])('accepts %o', (user_answer) => {
      const r = evaluateMultipleChoice(user_answer, correct_option_id, options);
      expect(r.correct).toBe(true);
      expect(r.evaluation_source).toBe('deterministic');
      expect(r.canonical_answer).toBe('Joyful');
    });

    it.each([['a'], ['c'], ['d'], ['Joyful'], [''], ['e']])('rejects %o', (user_answer) => {
      const r = evaluateMultipleChoice(user_answer, correct_option_id, options);
      expect(r.correct).toBe(false);
      expect(r.evaluation_source).toBe('deterministic');
      expect(r.canonical_answer).toBe('Joyful');
    });
  });

  describe('sentence_correction', () => {
    const prompt = "She don't like coffee.";
    const accepted_corrections = ["She doesn't like coffee.", 'She does not like coffee.'];
    const canonical_answer = accepted_corrections[0];

    it.each([
      ["She doesn't like coffee."],
      ['She does not like coffee.'],
      ["  She doesn't like coffee.  "],
      ["SHE DOESN'T LIKE COFFEE"],
      ["She doesn't like coffee"],
    ])('accepts deterministically %o', async (user_answer) => {
      const ai: AiProvider = { evaluateSentenceCorrection: vi.fn() };
      const r = await evaluateSentenceCorrection(user_answer, accepted_corrections, prompt, ai);
      expect(r.correct).toBe(true);
      expect(r.evaluation_source).toBe('deterministic');
      expect(r.feedback).toBeNull();
      expect(r.canonical_answer).toBe(canonical_answer);
      expect(ai.evaluateSentenceCorrection).not.toHaveBeenCalled();
    });

    it.each([["She don't like coffee."], [''], ["She doesn't like tea."]])(
      'rejects deterministically (no AI) %o',
      async (user_answer) => {
        const ai: AiProvider = { evaluateSentenceCorrection: vi.fn() };
        const r = await evaluateSentenceCorrection(user_answer, accepted_corrections, prompt, ai);
        expect(r.correct).toBe(false);
        expect(r.evaluation_source).toBe('deterministic');
        expect(r.feedback).toBeNull();
        expect(r.canonical_answer).toBe(canonical_answer);
        expect(ai.evaluateSentenceCorrection).not.toHaveBeenCalled();
      }
    );

    it('borderline cases call AI and use its decision', async () => {
      const ai: AiProvider = {
        evaluateSentenceCorrection: vi.fn(async ({ userAnswer }) => {
          // evaluateSentenceCorrection() passes normalized userAnswer (lowercased, no trailing punctuation).
          if (userAnswer === 'she does not like coffe') return { correct: true, feedback: 'Minor typo.' };
          if (userAnswer === "she doesn't likes coffee") return { correct: false, feedback: 'Still incorrect.' };
          if (userAnswer === "she doesn't like coffeee") return { correct: true, feedback: 'Minor typo.' };
          return { correct: false, feedback: '' };
        }),
      };

      const cases: Array<[string, boolean]> = [
        ['She does not like coffe.', true],
        ["She doesn't likes coffee.", false],
        ["She doesn't like coffeee.", true],
      ];

      for (const [user_answer, expectedCorrect] of cases) {
        const r = await evaluateSentenceCorrection(user_answer, accepted_corrections, prompt, ai);
        expect(r.correct).toBe(expectedCorrect);
        expect(r.evaluation_source).toBe('ai_fallback');
        expect(r.canonical_answer).toBe(canonical_answer);
      }

      expect(ai.evaluateSentenceCorrection).toHaveBeenCalledTimes(cases.length);
    });

    beforeEach(() => vi.useFakeTimers());
    afterEach(() => vi.useRealTimers());

    it('AI timeout returns ai_timeout (no feedback)', async () => {
      const ai: AiProvider = {
        evaluateSentenceCorrection: vi.fn(
          () => new Promise(() => {
            /* never resolves */
          })
        ),
      };

      const promise = evaluateSentenceCorrection('She does not like coffe.', accepted_corrections, prompt, ai, 5000);
      await vi.advanceTimersByTimeAsync(5000);
      const r = await promise;

      expect(r.correct).toBe(false);
      expect(r.evaluation_source).toBe('ai_timeout');
      expect(r.feedback).toBeNull();
      expect(r.canonical_answer).toBe(canonical_answer);
      expect(ai.evaluateSentenceCorrection).toHaveBeenCalledOnce();
    });
  });
});
