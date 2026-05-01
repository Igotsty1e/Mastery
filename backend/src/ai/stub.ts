import type {
  AiProvider,
  AiEvaluationArgs,
  AiEvaluationResult,
  AiFreeSentenceArgs,
  DebriefAiResult,
  DebriefArgs,
} from './interface';

// Safe stub — always returns incorrect for graded paths, empty for
// debrief. Replace with real provider before production.
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

  /// Wave G3 — graceful degradation for `short_free_sentence` when no
  /// AI is wired up. Without this method the service treats the stub
  /// as "no evaluator" and returns `correct: false` for every answer
  /// (observed in prod 2026-05-01: the Render deploy had no
  /// `OPENAI_API_KEY`, so every short_free_sentence answer scored 0
  /// regardless of content). That's worse than no production: the
  /// learner can't tell whether the engine is broken or they are.
  ///
  /// The stub here is intentionally lenient — it accepts any answer
  /// of at least three words. Real grammaticality + rule-conformance
  /// grading still requires `AI_PROVIDER=openai` + `OPENAI_API_KEY`;
  /// this is only a "session keeps moving" backstop until the env
  /// vars land. Operators MUST replace the stub with a real provider
  /// before treating attempts on this path as ground truth (e.g.,
  /// before flipping mastery to a degree that depends on this signal).
  async evaluateFreeSentence(
    args: AiFreeSentenceArgs
  ): Promise<AiEvaluationResult> {
    const trimmed = (args.userAnswer ?? '').trim();
    const wordCount = trimmed.split(/\s+/).filter((w) => w.length > 0).length;
    if (wordCount < 3) {
      return {
        correct: false,
        feedback: 'Try a full sentence (at least three words).',
      };
    }
    return {
      correct: true,
      feedback: '', // stub can't say more — leave the field empty
    };
  }
}
