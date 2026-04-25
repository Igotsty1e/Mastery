import type {
  AiProvider,
  DebriefAiResult,
  DebriefArgs,
  DebriefMissedItem,
  DebriefType,
} from '../ai/interface';
import type { Lesson } from '../data/lessons';
import type { AttemptRecord } from '../store/memory';

export type DebriefSource = 'ai' | 'fallback' | 'deterministic_perfect';

export interface DebriefDto {
  debrief_type: DebriefType;
  headline: string;
  body: string;
  watch_out: string | null;
  next_step: string | null;
  source: DebriefSource;
}

export const DEBRIEF_AI_TIMEOUT_MS = 6_000;
export const DEBRIEF_HEADLINE_MAX = 80;
export const DEBRIEF_BODY_MAX = 600;
export const DEBRIEF_TAIL_MAX = 140;

export function pickDebriefType(correct: number, total: number): DebriefType {
  if (total <= 0) return 'needs_work';
  if (correct === total) return 'strong';
  const pct = correct / total;
  if (pct >= 0.6) return 'mixed';
  return 'needs_work';
}

function firstSentence(text: string): string {
  const trimmed = text.trim().replace(/\s+/g, ' ');
  const m = trimmed.match(/^.+?[.!?](?=\s|$)/);
  return (m ? m[0] : trimmed).trim();
}

export function buildMissedItems(
  lesson: Lesson,
  attempts: AttemptRecord[]
): DebriefMissedItem[] {
  const out: DebriefMissedItem[] = [];
  for (const a of attempts) {
    if (a.correct) continue;
    const ex = lesson.exercises.find(e => e.exercise_id === a.exercise_id);
    const explanation = ex?.feedback?.explanation ?? '';
    if (!explanation) continue;
    out.push({
      canonical_answer: a.canonical_answer,
      explanation: firstSentence(explanation).slice(0, 220),
    });
  }
  return out;
}

function clamp(s: string, max: number): string {
  const trimmed = s.trim().replace(/\s+/g, ' ');
  return trimmed.length > max ? trimmed.slice(0, max) : trimmed;
}

export function fallbackDebrief(
  type: DebriefType,
  lessonTitle: string
): DebriefDto {
  if (type === 'strong') {
    return {
      debrief_type: 'strong',
      headline: 'Solid grasp of this rule.',
      body: `You completed every item in "${lessonTitle}" correctly. The contrast is landing — keep using it in your own writing so the choice becomes automatic.`,
      watch_out: null,
      next_step: 'Use this rule in two sentences of your own today.',
      source: 'deterministic_perfect',
    };
  }
  if (type === 'mixed') {
    return {
      debrief_type: 'mixed',
      headline: 'Good progress — patterns to tighten.',
      body: 'You handled most items, but a few went the other way. Reread the rule, then redo the missed items below to lock in the contrast.',
      watch_out: 'Re-check the cue word before you choose the form.',
      next_step: 'Redo the missed items in the list below.',
      source: 'fallback',
    };
  }
  return {
    debrief_type: 'needs_work',
    headline: 'This rule still needs reps.',
    body: 'Several items pulled the wrong form. Review the rule at the top of the lesson, study the missed items below, then come back and try again.',
    watch_out: 'Read the cue word before choosing the verb form.',
    next_step: 'Reread the rule and retry the lesson.',
    source: 'fallback',
  };
}

function withTimeout<T>(p: Promise<T>, ms: number, controller: AbortController): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => {
      controller.abort();
      reject(new Error('debrief_timeout'));
    }, ms);
    p.then(
      v => {
        clearTimeout(timer);
        resolve(v);
      },
      e => {
        clearTimeout(timer);
        reject(e);
      }
    );
  });
}

function sanitizeAi(ai: DebriefAiResult, type: DebriefType): DebriefDto | null {
  const headline = clamp(ai.headline ?? '', DEBRIEF_HEADLINE_MAX);
  const body = clamp(ai.body ?? '', DEBRIEF_BODY_MAX);
  if (!headline || !body) return null;
  const watch_out = ai.watch_out && ai.watch_out.trim()
    ? clamp(ai.watch_out, DEBRIEF_TAIL_MAX)
    : null;
  const next_step = ai.next_step && ai.next_step.trim()
    ? clamp(ai.next_step, DEBRIEF_TAIL_MAX)
    : null;
  return { debrief_type: type, headline, body, watch_out, next_step, source: 'ai' };
}

export async function buildDebrief(
  ai: AiProvider,
  lesson: Lesson,
  attempts: AttemptRecord[],
  correctCount: number,
  totalExercises: number,
  opts: { aiEnabled: boolean; timeoutMs?: number; logger?: (msg: string) => void } = {
    aiEnabled: true,
  }
): Promise<DebriefDto> {
  const type = pickDebriefType(correctCount, totalExercises);
  const log = opts.logger ?? (() => {});

  // Zero-error path: never call AI. The deterministic copy is the source of
  // truth for "perfect score" debriefs (also avoids cost and latency for the
  // most common celebration flow).
  if (type === 'strong') {
    return fallbackDebrief('strong', lesson.title);
  }

  if (!opts.aiEnabled || !ai.generateDebrief) {
    return fallbackDebrief(type, lesson.title);
  }

  const missed = buildMissedItems(lesson, attempts);
  if (missed.length === 0) {
    // Score < 100% but no missed items had explanations — fall back rather
    // than send a thin payload to the model.
    return fallbackDebrief(type, lesson.title);
  }

  const args: DebriefArgs = {
    lessonTitle: lesson.title,
    level: lesson.level,
    targetRule: firstSentence(lesson.intro_rule).slice(0, 240),
    correctCount,
    totalExercises,
    debriefType: type,
    missedItems: missed,
  };

  const timeoutMs = opts.timeoutMs ?? DEBRIEF_AI_TIMEOUT_MS;
  const controller = new AbortController();

  try {
    const aiResult = await withTimeout(
      ai.generateDebrief!({ ...args, signal: controller.signal }),
      timeoutMs,
      controller
    );
    const sanitized = sanitizeAi(aiResult, type);
    if (!sanitized) {
      log('debrief_ai_empty_fields');
      return fallbackDebrief(type, lesson.title);
    }
    return sanitized;
  } catch (err) {
    log(`debrief_ai_failed: ${err instanceof Error ? err.message : String(err)}`);
    return fallbackDebrief(type, lesson.title);
  }
}
