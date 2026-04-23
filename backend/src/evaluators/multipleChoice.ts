export interface MultipleChoiceOption {
  id: string;
  text: string;
}

export interface MultipleChoiceResult {
  correct: boolean;
  evaluation_source: 'deterministic';
  feedback: null;
  canonical_answer: string;
}

export function evaluateMultipleChoice(
  userAnswer: string,
  correctOptionId: string,
  options: MultipleChoiceOption[]
): MultipleChoiceResult {
  const norm = userAnswer.trim().toLowerCase();
  const correct = norm !== '' && norm === correctOptionId.trim().toLowerCase();
  const canonicalText = options.find(o => o.id === correctOptionId)?.text ?? correctOptionId;
  return { correct, evaluation_source: 'deterministic', feedback: null, canonical_answer: canonicalText };
}
