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
  // Optional: providers may omit this in test scaffolding where only the
  // /answers route is exercised. The result route guards on its absence and
  // falls back to deterministic copy.
  generateDebrief?(args: DebriefArgs): Promise<DebriefAiResult>;
}
