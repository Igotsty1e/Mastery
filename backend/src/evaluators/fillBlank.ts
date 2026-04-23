import { normalize } from './normalize';

export interface FillBlankResult {
  correct: boolean;
  evaluation_source: 'deterministic';
  feedback: null;
  canonical_answer: string;
}

export function evaluateFillBlank(
  userAnswer: string,
  acceptedAnswers: string[]
): FillBlankResult {
  const norm = normalize(userAnswer);
  const correct = norm !== '' && acceptedAnswers.some(a => normalize(a) === norm);
  return { correct, evaluation_source: 'deterministic', feedback: null, canonical_answer: acceptedAnswers[0] };
}
