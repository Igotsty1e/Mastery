import type {
  AiProvider,
  AiEvaluationArgs,
  AiEvaluationResult,
  DebriefAiResult,
  DebriefArgs,
} from './interface';

// Safe stub — always returns incorrect. Replace with real provider before production.
export class StubAiProvider implements AiProvider {
  async evaluateSentenceCorrection(_args: AiEvaluationArgs): Promise<AiEvaluationResult> {
    return { correct: false, feedback: '' };
  }

  // The stub returns an empty result so the route falls back to the
  // deterministic debrief copy. Production debrief content only ships when
  // AI_PROVIDER=openai.
  async generateDebrief(_args: DebriefArgs): Promise<DebriefAiResult> {
    return { headline: '', body: '', watch_out: null, next_step: null };
  }
}
