import { describe, it, expect, vi } from 'vitest';
import { evaluateFillBlank } from '../src/evaluators/fillBlank';
import { evaluateMultipleChoice } from '../src/evaluators/multipleChoice';
import { evaluateSentenceCorrection, evaluateSentenceCorrectionDeterministic } from '../src/evaluators/sentenceCorrection';
import { levenshtein, minLevenshtein } from '../src/evaluators/levenshtein';
import type { AiProvider } from '../src/ai/interface';
import { StubAiProvider } from '../src/ai/stub';

// --- fill_blank ---
describe('evaluateFillBlank', () => {
  const accepted = ['walks', 'goes'];

  it('exact match', () => expect(evaluateFillBlank('walks', accepted).correct).toBe(true));
  it('alternate accepted', () => expect(evaluateFillBlank('goes', accepted).correct).toBe(true));
  it('trimmed input', () => expect(evaluateFillBlank('  walks  ', accepted).correct).toBe(true));
  it('uppercase input', () => expect(evaluateFillBlank('Walks', accepted).correct).toBe(true));
  it('trailing punct', () => expect(evaluateFillBlank('walks.', accepted).correct).toBe(true));
  it('wrong word', () => expect(evaluateFillBlank('walk', accepted).correct).toBe(false));
  it('empty string', () => expect(evaluateFillBlank('', accepted).correct).toBe(false));
  it('whitespace only', () => expect(evaluateFillBlank('   ', accepted).correct).toBe(false));
  it('canonical_answer is first accepted', () =>
    expect(evaluateFillBlank('goes', accepted).canonical_answer).toBe('walks'));
  it('evaluation_source is deterministic', () =>
    expect(evaluateFillBlank('walks', accepted).evaluation_source).toBe('deterministic'));
});

// --- multiple_choice ---
describe('evaluateMultipleChoice', () => {
  const correct = 'b';
  const options = [
    { id: 'a', text: 'Sad' },
    { id: 'b', text: 'Joyful' },
    { id: 'c', text: 'Angry' },
    { id: 'd', text: 'Tired' },
  ];

  it('exact match', () => expect(evaluateMultipleChoice('b', correct, options).correct).toBe(true));
  it('uppercase', () => expect(evaluateMultipleChoice('B', correct, options).correct).toBe(true));
  it('trimmed', () => expect(evaluateMultipleChoice(' b ', correct, options).correct).toBe(true));
  it('wrong option', () => expect(evaluateMultipleChoice('a', correct, options).correct).toBe(false));
  it('text instead of id', () => expect(evaluateMultipleChoice('Joyful', correct, options).correct).toBe(false));
  it('empty', () => expect(evaluateMultipleChoice('', correct, options).correct).toBe(false));
  it('canonical_answer is correct option text', () =>
    expect(evaluateMultipleChoice('b', correct, options).canonical_answer).toBe('Joyful'));
});

// --- levenshtein ---
describe('levenshtein', () => {
  it('identical strings', () => expect(levenshtein('abc', 'abc')).toBe(0));
  it('single insertion', () => expect(levenshtein('abc', 'abcd')).toBe(1));
  it('single deletion', () => expect(levenshtein('abcd', 'abc')).toBe(1));
  it('single substitution', () => expect(levenshtein('abc', 'axc')).toBe(1));
  it('empty vs string', () => expect(levenshtein('', 'abc')).toBe(3));
  it('both empty', () => expect(levenshtein('', '')).toBe(0));
  it('minLevenshtein picks nearest', () =>
    expect(minLevenshtein('cat', ['bat', 'car', 'cart'])).toBe(1));
});

// --- evaluateSentenceCorrectionDeterministic (canonical gate, sync) ---
describe('evaluateSentenceCorrectionDeterministic', () => {
  const accepted = ["She doesn't like coffee.", "She does not like coffee."];
  const prompt = "She don't like coffee.";

  it('exact match → correct: true, deterministic', () => {
    const r = evaluateSentenceCorrectionDeterministic("She doesn't like coffee.", accepted, prompt);
    expect(r).not.toBeNull();
    expect(r!.correct).toBe(true);
    expect(r!.evaluation_source).toBe('deterministic');
  });

  it('alternate accepted → correct: true, deterministic', () => {
    const r = evaluateSentenceCorrectionDeterministic("She does not like coffee.", accepted, prompt);
    expect(r).not.toBeNull();
    expect(r!.correct).toBe(true);
    expect(r!.evaluation_source).toBe('deterministic');
  });

  it('normalized match → correct: true, deterministic', () => {
    const r = evaluateSentenceCorrectionDeterministic("SHE DOESN'T LIKE COFFEE", accepted, prompt);
    expect(r).not.toBeNull();
    expect(r!.correct).toBe(true);
  });

  it('empty input → correct: false, deterministic', () => {
    const r = evaluateSentenceCorrectionDeterministic('', accepted, prompt);
    expect(r).not.toBeNull();
    expect(r!.correct).toBe(false);
    expect(r!.evaluation_source).toBe('deterministic');
  });

  it('uncorrected prompt submitted → correct: false, deterministic', () => {
    const r = evaluateSentenceCorrectionDeterministic("She don't like coffee.", accepted, prompt);
    expect(r).not.toBeNull();
    expect(r!.correct).toBe(false);
    expect(r!.evaluation_source).toBe('deterministic');
  });

  it('clearly wrong → correct: false, deterministic', () => {
    const r = evaluateSentenceCorrectionDeterministic('She enjoys tea.', accepted, prompt);
    expect(r).not.toBeNull();
    expect(r!.correct).toBe(false);
    expect(r!.evaluation_source).toBe('deterministic');
  });

  it('borderline (1-char typo) → returns null (needs AI)', () => {
    // "She does not like coffe." — 1 edit from accepted
    const r = evaluateSentenceCorrectionDeterministic('She does not like coffe.', accepted, prompt);
    expect(r).toBeNull();
  });

  it('canonical_answer is first accepted', () => {
    const r = evaluateSentenceCorrectionDeterministic('completely wrong', accepted, prompt);
    expect(r).not.toBeNull();
    expect(r!.canonical_answer).toBe(accepted[0]);
  });
});

// --- sentence_correction deterministic ---
describe('evaluateSentenceCorrection deterministic', () => {
  const accepted = ["She doesn't like coffee.", "She does not like coffee."];
  const prompt = "She don't like coffee.";
  const stub = new StubAiProvider();

  it('exact match', async () => {
    const r = await evaluateSentenceCorrection("She doesn't like coffee.", accepted, prompt, stub);
    expect(r.correct).toBe(true);
    expect(r.evaluation_source).toBe('deterministic');
  });

  it('alternate accepted', async () => {
    const r = await evaluateSentenceCorrection("She does not like coffee.", accepted, prompt, stub);
    expect(r.correct).toBe(true);
    expect(r.evaluation_source).toBe('deterministic');
  });

  it('normalized match (trim + case + punct)', async () => {
    const r = await evaluateSentenceCorrection("SHE DOESN'T LIKE COFFEE", accepted, prompt, stub);
    expect(r.correct).toBe(true);
    expect(r.evaluation_source).toBe('deterministic');
  });

  it('empty input', async () => {
    const r = await evaluateSentenceCorrection('', accepted, prompt, stub);
    expect(r.correct).toBe(false);
    expect(r.evaluation_source).toBe('deterministic');
  });

  it('same as prompt (uncorrected)', async () => {
    const r = await evaluateSentenceCorrection("She don't like coffee.", accepted, prompt, stub);
    expect(r.correct).toBe(false);
  });

  it('canonical_answer is first accepted', async () => {
    const r = await evaluateSentenceCorrection('bad answer', accepted, prompt, stub);
    expect(r.canonical_answer).toBe(accepted[0]);
  });
});

// --- sentence_correction borderline / AI path ---
describe('evaluateSentenceCorrection AI fallback', () => {
  const accepted = ["She doesn't like coffee.", "She does not like coffee."];
  const prompt = "She don't like coffee.";

  it('triggers AI for borderline (distance ≤ 3)', async () => {
    // "she does not like the coffee" vs "she does not like coffee" = distance 4 (insert " the")
    // Let's use a closer miss: "she does not like coffe" (1 typo)
    const ai: AiProvider = { evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: true, feedback: 'Minor typo.' }) };
    const r = await evaluateSentenceCorrection("She does not like coffe.", accepted, prompt, ai);
    expect(ai.evaluateSentenceCorrection).toHaveBeenCalled();
    expect(r.correct).toBe(true);
    expect(r.evaluation_source).toBe('ai_fallback');
  });

  it('skips AI when distance > 3', async () => {
    const ai: AiProvider = { evaluateSentenceCorrection: vi.fn() };
    // "She enjoys tea." is far from all accepted corrections
    const r = await evaluateSentenceCorrection("She enjoys tea.", accepted, prompt, ai);
    expect(ai.evaluateSentenceCorrection).not.toHaveBeenCalled();
    expect(r.correct).toBe(false);
    expect(r.evaluation_source).toBe('deterministic');
  });

  it('AI timeout → ai_timeout', async () => {
    const ai: AiProvider = {
      evaluateSentenceCorrection: () => new Promise(resolve => setTimeout(() => resolve({ correct: true, feedback: 'late' }), 200)),
    };
    const r = await evaluateSentenceCorrection("She does not like coffe.", accepted, prompt, ai, 50);
    expect(r.correct).toBe(false);
    expect(r.evaluation_source).toBe('ai_timeout');
    expect(r.feedback).toBeNull();
  });

  it('AI timeout aborts the signal passed to the provider', async () => {
    let capturedSignal: AbortSignal | undefined;
    const ai: AiProvider = {
      evaluateSentenceCorrection: (args) => {
        capturedSignal = args.signal;
        return new Promise(resolve => setTimeout(() => resolve({ correct: true, feedback: '' }), 500));
      },
    };
    await evaluateSentenceCorrection("She does not like coffe.", accepted, prompt, ai, 50);
    expect(capturedSignal?.aborted).toBe(true);
  });

  it('AI error → ai_error', async () => {
    const ai: AiProvider = { evaluateSentenceCorrection: vi.fn().mockRejectedValue(new Error('fail')) };
    const r = await evaluateSentenceCorrection("She does not like coffe.", accepted, prompt, ai);
    expect(r.correct).toBe(false);
    expect(r.evaluation_source).toBe('ai_error');
  });

  it('AI returns malformed response (missing correct field) → ai_error', async () => {
    const ai: AiProvider = { evaluateSentenceCorrection: vi.fn().mockResolvedValue({ feedback: 'looks ok' }) };
    const r = await evaluateSentenceCorrection("She does not like coffe.", accepted, prompt, ai);
    expect(r.correct).toBe(false);
    expect(r.evaluation_source).toBe('ai_error');
    expect(r.feedback).toBeNull();
  });

  it('AI returns wrong types (correct as string) → ai_error', async () => {
    const ai: AiProvider = { evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: 'yes', feedback: 'ok' }) };
    const r = await evaluateSentenceCorrection("She does not like coffe.", accepted, prompt, ai);
    expect(r.correct).toBe(false);
    expect(r.evaluation_source).toBe('ai_error');
  });

  it('AI returns oversized feedback → verdict preserved, feedback truncated to 80 chars', async () => {
    const longFeedback = 'x'.repeat(100);
    const ai: AiProvider = { evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: true, feedback: longFeedback }) };
    const r = await evaluateSentenceCorrection("She does not like coffe.", accepted, prompt, ai);
    expect(r.correct).toBe(true);
    expect(r.evaluation_source).toBe('ai_fallback');
    expect(r.feedback).not.toBeNull();
    expect(r.feedback!.length).toBeLessThanOrEqual(80);
  });
});

// --- Wave G3 stub.evaluateFreeSentence (graceful degradation) ---
describe('StubAiProvider.evaluateFreeSentence', () => {
  const stub = new StubAiProvider();
  const args = (userAnswer: string) => ({
    targetRule: 'After enjoy, the next verb takes -ing.',
    instruction: 'Write a sentence using "enjoy" + the -ing form.',
    acceptedExamples: ['I enjoy reading novels on Sunday mornings.'],
    userAnswer,
  });

  it('rejects empty input', async () => {
    const r = await stub.evaluateFreeSentence(args(''));
    expect(r.correct).toBe(false);
  });

  it('rejects two-word input', async () => {
    const r = await stub.evaluateFreeSentence(args('I enjoy'));
    expect(r.correct).toBe(false);
  });

  it('accepts any three-word-or-longer answer (lenient by design)', async () => {
    const r = await stub.evaluateFreeSentence(
      args('I enjoy smoking at weekends'),
    );
    expect(r.correct).toBe(true);
  });

  it('still accepts answers that miss the rule (real grading needs OpenAI)', async () => {
    // Stub cannot judge rule conformance. The user got a Pass but the
    // sentence does not actually demonstrate the target rule. This is
    // the intentional trade-off — see the comment in stub.ts.
    const r = await stub.evaluateFreeSentence(
      args('The weather is nice today'),
    );
    expect(r.correct).toBe(true);
  });
});
