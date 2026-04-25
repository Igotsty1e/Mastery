import type { MultipleChoiceOption } from './multipleChoice';

export interface ListeningDiscriminationResult {
  correct: boolean;
  evaluation_source: 'deterministic';
  feedback: null;
  canonical_answer: string;
}

export function evaluateListeningDiscrimination(
  userAnswer: string,
  correctOptionId: string,
  options: MultipleChoiceOption[]
): ListeningDiscriminationResult {
  const norm = userAnswer.trim().toLowerCase();
  const correct = norm !== '' && norm === correctOptionId.trim().toLowerCase();
  const canonicalText = options.find(o => o.id === correctOptionId)?.text ?? correctOptionId;
  return { correct, evaluation_source: 'deterministic', feedback: null, canonical_answer: canonicalText };
}
