export interface AiEvaluationArgs {
  exercisePrompt: string;
  acceptedCorrections: string[];
  userAnswer: string;
  signal?: AbortSignal;
}

export interface AiEvaluationResult {
  correct: boolean;
  feedback: string;
}

export interface AiProvider {
  evaluateSentenceCorrection(args: AiEvaluationArgs): Promise<AiEvaluationResult>;
}
