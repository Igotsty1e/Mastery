import { normalize } from './normalize';
import { minLevenshtein } from './levenshtein';
import type { AiProvider } from '../ai/interface';
import { AiResponseSchema } from '../schemas';

export interface SentenceCorrectionResult {
  correct: boolean;
  evaluation_source: 'deterministic' | 'ai_fallback';
  feedback: string | null;
  canonical_answer: string;
}

/**
 * Runs the deterministic gate and borderline classifier.
 * Returns a settled result when the answer can be decided without AI,
 * or null when the answer is borderline and should be sent to AI.
 */
export function evaluateSentenceCorrectionDeterministic(
  userAnswer: string,
  acceptedCorrections: string[],
  exercisePrompt: string
): SentenceCorrectionResult | null {
  const canonical = acceptedCorrections[0];
  const normUser = normalize(userAnswer);
  const normPrompt = normalize(exercisePrompt);
  const normAccepted = acceptedCorrections.map(normalize);

  if (!normUser) {
    return { correct: false, evaluation_source: 'deterministic', feedback: null, canonical_answer: canonical };
  }

  if (normAccepted.includes(normUser)) {
    return { correct: true, evaluation_source: 'deterministic', feedback: null, canonical_answer: canonical };
  }

  // Submitting the original (uncorrected) prompt wastes AI tokens — short-circuit.
  if (normPrompt && normUser === normPrompt) {
    return { correct: false, evaluation_source: 'deterministic', feedback: null, canonical_answer: canonical };
  }

  const minDist = minLevenshtein(normUser, normAccepted);
  const shortestLen = Math.min(...normAccepted.map(s => s.length));
  const userLen = normUser.length;
  const borderline =
    minDist <= 3 &&
    userLen >= shortestLen * 0.5 &&
    userLen <= shortestLen * 2.0;

  if (!borderline) {
    return { correct: false, evaluation_source: 'deterministic', feedback: null, canonical_answer: canonical };
  }

  return null;
}

export async function evaluateSentenceCorrection(
  userAnswer: string,
  acceptedCorrections: string[],
  exercisePrompt: string,
  ai: AiProvider,
  timeoutMs = 5000
): Promise<SentenceCorrectionResult> {
  const canonical = acceptedCorrections[0];

  const deterministic = evaluateSentenceCorrectionDeterministic(userAnswer, acceptedCorrections, exercisePrompt);
  if (deterministic !== null) {
    return deterministic;
  }

  const normUser = normalize(userAnswer);

  try {
    const controller = new AbortController();
    let timeoutId: ReturnType<typeof setTimeout> | undefined;
    const timeout = new Promise<null>(resolve => {
      timeoutId = setTimeout(() => { controller.abort(); resolve(null); }, timeoutMs);
    });
    const aiCall = ai.evaluateSentenceCorrection({
      exercisePrompt, acceptedCorrections, userAnswer: normUser, signal: controller.signal,
    });
    aiCall.catch(() => {}); // suppress AbortError unhandled rejection after timeout
    const result = await Promise.race([aiCall, timeout]);
    clearTimeout(timeoutId);

    if (!result) {
      return { correct: false, evaluation_source: 'deterministic', feedback: null, canonical_answer: canonical };
    }

    const parsed = AiResponseSchema.safeParse(result);
    if (!parsed.success) {
      return { correct: false, evaluation_source: 'deterministic', feedback: null, canonical_answer: canonical };
    }

    return {
      correct: parsed.data.correct,
      evaluation_source: 'ai_fallback',
      feedback: parsed.data.feedback || null,
      canonical_answer: canonical,
    };
  } catch {
    return { correct: false, evaluation_source: 'deterministic', feedback: null, canonical_answer: canonical };
  }
}
