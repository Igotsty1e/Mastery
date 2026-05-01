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

export interface AiFreeSentenceRawProbe {
  model: string;
  response_keys: string[];
  extracted_text: string;
  refusal: string | null;
  parsed: unknown;
}

/// Wave H2 — dual-verdict judge.
///
/// Used after the deterministic matcher fails on a closed-form item
/// (today: fill_blank only). The AI is told what's actually under
/// test (`targetForm`) and asked whether the learner's answer hit the
/// target — even when it doesn't match any accepted answer literally.
/// A spelling slip on a non-target word, or a synonym that uses the
/// same form, can return `target_met: true` with `off_target_note`
/// describing the slip the human should mention but not penalise.
export interface AiTargetVerdictArgs {
  /// Plain English description of what the lesson teaches (e.g.
  /// "verb-ing form after gerund-only verbs"). Lesson-level field;
  /// see `docs/content-contract.md §1.4`.
  targetForm: string;
  /// The exercise prompt as the learner saw it (the blank shown as
  /// `___` for fill_blank).
  prompt: string;
  /// The author's accepted answer(s) for the blank — used as positive
  /// grounding for what the target form looks like.
  acceptedAnswers: string[];
  /// What the learner typed.
  userAnswer: string;
  signal?: AbortSignal;
}

export interface AiTargetVerdictResult {
  /// True when the learner's answer demonstrates the target form
  /// correctly, regardless of whether it matches an accepted answer.
  target_met: boolean;
  /// True when the answer has a non-target slip (e.g. a misspelling
  /// of a different word, a wrong noun choice that doesn't affect
  /// the grammar under test). Optional context for the explanation.
  off_target_error: boolean;
  /// Human-facing one-line note about the off-target slip. Empty
  /// when there is none. Used by the service to append a soft note
  /// to the explanation when the verdict is flipped to correct.
  off_target_note: string;
}

export interface AiProvider {
  evaluateSentenceCorrection(args: AiEvaluationArgs): Promise<AiEvaluationResult>;
  /// Wave 14.4 — V1.5 `short_free_sentence` evaluator. Optional during
  /// the rollout window: providers used by tests that don't exercise
  /// the type may omit it. The service routes `short_free_sentence`
  /// items to a deterministic-fail when the method is missing so the
  /// runtime stays sane on a stub provider.
  evaluateFreeSentence?(args: AiFreeSentenceArgs): Promise<AiEvaluationResult>;
  /// Wave G6 — diagnostic-only echo path. Returns the raw OpenAI
  /// response shape so the operator can debug from outside Render's
  /// log capture. Stub providers omit it.
  evaluateFreeSentenceRaw?(args: AiFreeSentenceArgs): Promise<AiFreeSentenceRawProbe>;
  /// Wave H2 — dual-verdict judge for closed-form items. Optional;
  /// the service falls back to the deterministic verdict when the
  /// method is missing or throws. See `AiTargetVerdictArgs`.
  evaluateTargetVerdict?(args: AiTargetVerdictArgs): Promise<AiTargetVerdictResult>;
  // Optional: providers may omit this in test scaffolding where only the
  // /answers route is exercised. The result route guards on its absence and
  // falls back to deterministic copy.
  generateDebrief?(args: DebriefArgs): Promise<DebriefAiResult>;
}
