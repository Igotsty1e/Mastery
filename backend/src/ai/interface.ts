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

/// Wave 14.4 — V1.5 open-answer family, phase 4
/// (`short_free_sentence`).
///
/// Different semantics from `evaluateSentenceCorrection`: there is no
/// canonical answer list to match against. The exercise asks the
/// learner to write any sentence that (a) is grammatically correct
/// and (b) uses the target rule. The model judges rule conformance
/// + grammar rather than equivalence to a known answer.
///
/// `acceptedExamples` is optional — when present, the model uses
/// them as concrete grounding for what "uses the rule" looks like.
/// Authors should keep the list short (≤3) to avoid biasing the
/// model toward verbatim mimicry.
export interface AiFreeSentenceArgs {
  targetRule: string;
  instruction: string;
  acceptedExamples: string[];
  userAnswer: string;
  signal?: AbortSignal;
}

export type DebriefType = 'strong' | 'mixed' | 'needs_work';

export interface DebriefMissedItem {
  canonical_answer: string;
  explanation: string;
}

export interface DebriefArgs {
  lessonTitle: string;
  level: string;
  targetRule: string;
  correctCount: number;
  totalExercises: number;
  debriefType: DebriefType;
  missedItems: DebriefMissedItem[];
  signal?: AbortSignal;
}

export interface DebriefAiResult {
  headline: string;
  body: string;
  watch_out: string | null;
  next_step: string | null;
}

export interface AiProvider {
  evaluateSentenceCorrection(args: AiEvaluationArgs): Promise<AiEvaluationResult>;
  /// Wave 14.4 — V1.5 `short_free_sentence` evaluator. Optional during
  /// the rollout window: providers used by tests that don't exercise
  /// the type may omit it. The service routes `short_free_sentence`
  /// items to a deterministic-fail when the method is missing so the
  /// runtime stays sane on a stub provider.
  evaluateFreeSentence?(args: AiFreeSentenceArgs): Promise<AiEvaluationResult>;
  // Optional: providers may omit this in test scaffolding where only the
  // /answers route is exercised. The result route guards on its absence and
  // falls back to deterministic copy.
  generateDebrief?(args: DebriefArgs): Promise<DebriefAiResult>;
}
