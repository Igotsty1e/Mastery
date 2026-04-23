import type { AiProvider, AiEvaluationArgs, AiEvaluationResult } from './interface';

// Safe stub — always returns incorrect. Replace with real provider before production.
export class StubAiProvider implements AiProvider {
  async evaluateSentenceCorrection(_args: AiEvaluationArgs): Promise<AiEvaluationResult> {
    return { correct: false, feedback: '' };
  }
}
