import type { AppDatabase } from '../db/client';
import { getLessonById, getLessonMeta, type Lesson, type Exercise, type LessonMeta } from '../data/lessons';
import { evaluateFillBlank } from '../evaluators/fillBlank';
import { evaluateMultipleChoice } from '../evaluators/multipleChoice';
import { evaluateListeningDiscrimination } from '../evaluators/listeningDiscrimination';
import {
  evaluateSentenceCorrection,
  evaluateSentenceCorrectionDeterministic,
  type SentenceCorrectionResult,
} from '../evaluators/sentenceCorrection';
import { normalize } from '../evaluators/normalize';
import { checkAiRateLimit } from '../middleware/aiRateLimit';
import {
  getAiResult,
  getDebriefResult,
  setAiResult,
  setDebriefResult,
  type AttemptRecord,
} from '../store/memory';
import { buildDebrief, type DebriefDto } from '../debrief/debrief';
import type { AiProvider } from '../ai/interface';
import { isUniqueViolation } from '../db/errors';
import {
  recordAttemptStats,
  type AttemptOutcome,
} from '../observability/exerciseStats';
import {
  finalizeSessionCompletion,
  findActiveSession,
  findAttemptByClientId,
  findSessionById,
  insertAttempt,
  insertSession,
  listLatestAttemptsForSession,
  touchSession,
  type ExerciseAttemptRow,
  type LessonSessionRow,
} from './repository';
import { detectFrictionEvent, type FrictionEvent } from './friction';

export type SessionStartReason = 'created' | 'resumed';

export interface StartSessionResult {
  reason: SessionStartReason;
  session: LessonSessionRow;
  latestAttempts: ExerciseAttemptRow[];
}

export class LessonSessionError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

function lessonOr404(lessonId: string): { lesson: Lesson; meta: LessonMeta } {
  const lesson = getLessonById(lessonId);
  const meta = getLessonMeta(lessonId);
  if (!lesson || !meta) {
    throw new LessonSessionError(404, 'lesson_not_found');
  }
  return { lesson, meta };
}

/**
 * Resume-or-create. The unique partial index on
 * `lesson_sessions(user_id, lesson_id) WHERE status = 'in_progress'` is the
 * race gate: if two parallel calls both miss the read and try to insert,
 * exactly one wins. The loser re-reads and returns the winner's row.
 */
export async function startSession(
  db: AppDatabase,
  userId: string,
  lessonId: string
): Promise<StartSessionResult> {
  const { meta } = lessonOr404(lessonId);

  const existing = await findActiveSession(db, userId, lessonId);
  if (existing) {
    const latestAttempts = await listLatestAttemptsForSession(db, existing.id);
    return { reason: 'resumed', session: existing, latestAttempts };
  }

  try {
    const created = await insertSession(db, {
      userId,
      lessonId,
      lessonVersion: meta.lesson_version,
      contentHash: meta.content_hash,
      unitId: meta.unit_id,
      ruleTag: meta.rule_tag,
      microRuleTag: meta.micro_rule_tag,
      exerciseCount: meta.exercise_count,
    });
    return { reason: 'created', session: created, latestAttempts: [] };
  } catch (err) {
    // Race lost — only swallow the unique-violation that the partial
    // index is designed to raise. Anything else (FK violation, conn drop,
    // etc.) must propagate so the caller sees a real failure instead of a
    // misleading "resumed" reply.
    if (!isUniqueViolation(err)) throw err;
    const after = await findActiveSession(db, userId, lessonId);
    if (after) {
      const latestAttempts = await listLatestAttemptsForSession(db, after.id);
      return { reason: 'resumed', session: after, latestAttempts };
    }
    throw err;
  }
}

export async function getCurrentSession(
  db: AppDatabase,
  userId: string,
  lessonId: string
): Promise<{ session: LessonSessionRow; latestAttempts: ExerciseAttemptRow[] } | null> {
  const session = await findActiveSession(db, userId, lessonId);
  if (!session) return null;
  const latestAttempts = await listLatestAttemptsForSession(db, session.id);
  return { session, latestAttempts };
}

interface OwnedSession {
  session: LessonSessionRow;
  lesson: Lesson;
  meta: LessonMeta;
}

interface LoadOwnedSessionOptions {
  // When `true` (default for write paths), the call rejects if the lesson
  // fixture has been edited since the session started — evaluating the
  // user's answer against a different question would be silently wrong.
  // Read paths (`/result`) tolerate drift on completed sessions because
  // the persisted `debrief_snapshot` and frozen `correct_count` already
  // capture the original outcome.
  enforceContentHash?: boolean;
}

async function loadOwnedSession(
  db: AppDatabase,
  userId: string,
  sessionId: string,
  opts: LoadOwnedSessionOptions = { enforceContentHash: true }
): Promise<OwnedSession> {
  const session = await findSessionById(db, sessionId);
  if (!session) throw new LessonSessionError(404, 'session_not_found');
  if (session.userId !== userId) {
    throw new LessonSessionError(404, 'session_not_found');
  }
  // Wave 11.2 — dynamic sessions carry the sentinel `DYNAMIC_SESSION_LESSON_ID`
  // and are not bound to a single lesson fixture. Their exercise lookups go
  // through the bank instead; surface a synthetic Lesson + Meta so the
  // existing call-sites (submitAnswer, getResult, etc.) keep working.
  if (session.lessonId === '00000000-0000-0000-0000-000000000000') {
    return {
      session,
      lesson: {
        lesson_id: session.lessonId,
        title: 'Today\u2019s session',
        language: 'en',
        level: 'B2',
        intro_rule: '',
        intro_examples: [],
        exercises: [],
      } as unknown as Lesson,
      meta: {
        lesson_id: session.lessonId,
        title: 'Today\u2019s session',
        slug: 'todays-session',
        level: 'B2',
        language: 'en',
        exercise_count: session.exerciseCount,
        unit_id: session.unitId,
        rule_tag: session.ruleTag,
        micro_rule_tag: session.microRuleTag,
        content_hash: session.contentHash,
        lesson_version: session.lessonVersion,
        order: 0,
      } as LessonMeta,
    };
  }
  const lesson = getLessonById(session.lessonId);
  const meta = getLessonMeta(session.lessonId);
  if (!lesson || !meta) {
    // The lesson fixture was deleted out from under a live session — treat
    // the same as a missing session rather than 500'ing the request.
    throw new LessonSessionError(410, 'lesson_content_missing');
  }
  if (
    opts.enforceContentHash !== false &&
    session.status === 'in_progress' &&
    meta.content_hash !== session.contentHash
  ) {
    // The lesson fixture changed since the session started. Refuse to keep
    // grading against a different question set; the client must abandon
    // this session and start a fresh one.
    throw new LessonSessionError(409, 'lesson_content_changed');
  }
  return { session, lesson, meta };
}

export interface AnswerInput {
  exerciseId: string;
  exerciseType: Exercise['type'];
  userAnswer: string;
  submittedAt: Date;
  // Client-supplied idempotency key. When the same key is replayed against
  // the same session, the original attempt row is returned — no new
  // evaluator run, no duplicate row in `exercise_attempts`.
  clientAttemptId: string;
  // Resolved client IP for the AI rate-limiter. Consumed only when the
  // submission actually needs an AI call (deterministic miss + cache
  // miss). Null disables rate-limit gating (e.g. internal callers /
  // tests with no client context); the service still calls AI in that
  // path, useful for unit tests.
  clientIp: string | null;
}

export interface AnswerResult {
  attempt: ExerciseAttemptRow;
  evaluation: SentenceCorrectionResult;
  exercise: Exercise;
  explanation: string | null;
  // Set when `clientAttemptId` matched an existing row and we returned it
  // verbatim instead of running the evaluator again.
  idempotentReplay: boolean;
}

function attemptRowToEvaluation(
  row: ExerciseAttemptRow
): SentenceCorrectionResult {
  return {
    correct: row.correct,
    evaluation_source: row.evaluationSource as
      SentenceCorrectionResult['evaluation_source'],
    feedback: null,
    canonical_answer: row.canonicalAnswer,
  };
}

/**
 * Submit one answer against a server-owned session. Re-uses the existing
 * deterministic evaluators and the in-memory AI cache (keyed on
 * `sessionId:exerciseId:normalisedAnswer` so retries don't burn quota).
 *
 * `clientAttemptId` is the wire-level idempotency key. The partial unique
 * index on `(session_id, client_attempt_id)` makes a replay return the
 * original attempt row instead of inserting a duplicate; this also covers
 * a network-retry that crosses with the original write.
 */
export async function submitAnswer(
  db: AppDatabase,
  userId: string,
  sessionId: string,
  ai: AiProvider,
  input: AnswerInput
): Promise<AnswerResult> {
  const { session, lesson } = await loadOwnedSession(db, userId, sessionId);
  if (session.status !== 'in_progress') {
    throw new LessonSessionError(409, 'session_not_in_progress');
  }
  // Wave 11.2 — dynamic sessions look up the exercise in the bank
  // because the synthetic lesson DTO has an empty `exercises` array.
  let exercise = lesson.exercises.find(
    (e) => e.exercise_id === input.exerciseId
  );
  if (!exercise) {
    const { getBankEntry } = await import('../data/exerciseBank');
    const entry = getBankEntry(input.exerciseId);
    if (entry) exercise = entry.exercise;
  }
  if (!exercise) {
    throw new LessonSessionError(404, 'exercise_not_found');
  }
  if (exercise.type !== input.exerciseType) {
    throw new LessonSessionError(400, 'invalid_payload');
  }

  // Cheap pre-check: a known attempt_id short-circuits before any
  // evaluator runs (avoids re-charging the AI on retries). The partial
  // unique index is still the correctness gate — see `insertAttempt`.
  const replay = await findAttemptByClientId(
    db,
    sessionId,
    input.clientAttemptId
  );
  if (replay) {
    return {
      attempt: replay,
      evaluation: attemptRowToEvaluation(replay),
      exercise,
      explanation: replay.explanation,
      idempotentReplay: true,
    };
  }

  let evaluation: SentenceCorrectionResult;

  if (exercise.type === 'fill_blank') {
    evaluation = evaluateFillBlank(input.userAnswer, exercise.accepted_answers);
  } else if (exercise.type === 'multiple_choice') {
    evaluation = evaluateMultipleChoice(
      input.userAnswer,
      exercise.correct_option_id,
      exercise.options
    );
  } else if (exercise.type === 'listening_discrimination') {
    evaluation = evaluateListeningDiscrimination(
      input.userAnswer,
      exercise.correct_option_id,
      exercise.options
    );
  } else {
    // sentence_correction + sentence_rewrite share the deterministic
    // → AI fallback path. The two types differ only in the field name
    // that holds the canonical variants (`accepted_corrections` vs
    // `accepted_answers`) and in pedagogical framing — semantically
    // both ask the AI "is the student answer equivalent to one of
    // these accepted variants given this prompt?". The OpenAI prompt
    // template treats both identically (Wave 14.2 — V1.5 open-answer
    // family, phase 1).
    const acceptedVariants =
      exercise.type === 'sentence_rewrite'
        ? exercise.accepted_answers
        : exercise.accepted_corrections;
    const deterministic = evaluateSentenceCorrectionDeterministic(
      input.userAnswer,
      acceptedVariants,
      exercise.prompt
    );
    if (deterministic) {
      evaluation = deterministic;
    } else {
      const normAnswer = normalize(input.userAnswer);
      const cached = getAiResult(sessionId, input.exerciseId, normAnswer);
      if (cached) {
        evaluation = cached;
      } else {
        // Rate-limit consumption is lazy: only fires when AI is actually
        // about to be called. Deterministic-correct submissions don't
        // burn quota (Codex P1 fix). When the limiter rejects the call,
        // surface as a typed error so the route can return 429 — the
        // attempt is NOT inserted; learner can retry once budget frees.
        if (input.clientIp !== null && !checkAiRateLimit(input.clientIp)) {
          throw new LessonSessionError(429, 'rate_limit_exceeded');
        }
        const aiResult = await evaluateSentenceCorrection(
          input.userAnswer,
          acceptedVariants,
          exercise.prompt,
          ai
        );
        setAiResult(sessionId, input.exerciseId, normAnswer, aiResult);
        evaluation = aiResult;
      }
    }
  }

  const explanation =
    !evaluation.correct && exercise.feedback ? exercise.feedback.explanation : null;

  // Wave 7.1.1 Codex P2.2: snapshot the review-time copy at insert. For
  // listening_discrimination items the prompt-equivalent is the audio
  // transcript. For everything else, the exercise prompt directly.
  const promptSnapshot =
    exercise.type === 'listening_discrimination'
      ? exercise.audio.transcript
      : 'prompt' in exercise
        ? exercise.prompt
        : null;
  const explanationSnapshot = exercise.feedback?.explanation ?? null;

  // Wave 14.3 phase 3 — friction detection (V1: repeated_error only).
  // Computed BEFORE the insert so it lands on the row, and surfaced
  // back to the caller so the client can fire the after-friction
  // feedback prompt without a follow-up round-trip.
  const frictionEvent: FrictionEvent | null = await detectFrictionEvent(db, {
    sessionId,
    currentSkillId: exercise.skill_id ?? null,
    currentCorrect: evaluation.correct,
  });

  const inserted = await insertAttempt(db, {
    sessionId,
    userId,
    lessonId: session.lessonId,
    lessonVersion: session.lessonVersion,
    contentHash: session.contentHash,
    unitId: session.unitId,
    ruleTag: session.ruleTag,
    microRuleTag: session.microRuleTag,
    exerciseId: input.exerciseId,
    exerciseType: exercise.type,
    userAnswer: input.userAnswer.slice(0, 500),
    correct: evaluation.correct,
    canonicalAnswer: evaluation.canonical_answer,
    evaluationSource: evaluation.evaluation_source,
    explanation,
    promptSnapshot,
    explanationSnapshot,
    clientAttemptId: input.clientAttemptId,
    submittedAt: input.submittedAt,
    frictionEvent,
  });

  if (inserted.duplicate) {
    // Race: a concurrent replay with the same attempt_id won the insert.
    // Return that row's verdict — never the second evaluator run.
    return {
      attempt: inserted.row,
      evaluation: attemptRowToEvaluation(inserted.row),
      exercise,
      explanation: inserted.row.explanation,
      idempotentReplay: true,
    };
  }

  await touchSession(db, sessionId, input.submittedAt);

  // Wave 9 — daily exercise health counters per `LEARNING_ENGINE.md §17`.
  // Outcome maps directly from the deterministic boolean today; the
  // partial outcome is reserved for Wave 6 multi-unit families and
  // remains 0 in V1 buckets. Time-to-answer is the gap between
  // session start and submission for now — when Wave 11 surfaces the
  // per-exercise displayed_at timestamp we'll narrow it.
  const outcome: AttemptOutcome = evaluation.correct ? 'correct' : 'wrong';
  const timeToAnswerMs =
    input.submittedAt.getTime() - session.lastActivityAt.getTime();
  void recordAttemptStats(db, {
    exerciseId: input.exerciseId,
    outcome,
    timeToAnswerMs,
  });

  return {
    attempt: inserted.row,
    evaluation,
    exercise,
    explanation,
    idempotentReplay: false,
  };
}

function attemptRowToRecord(row: ExerciseAttemptRow): AttemptRecord {
  return {
    exercise_id: row.exerciseId,
    correct: row.correct,
    evaluation_source: row.evaluationSource as AttemptRecord['evaluation_source'],
    feedback: null,
    canonical_answer: row.canonicalAnswer,
  };
}

export interface ResultPayload {
  lesson_id: string;
  total_exercises: number;
  correct_count: number;
  conclusion: string;
  answers: Array<{
    exercise_id: string;
    correct: boolean;
    prompt: string | null;
    canonical_answer: string;
    explanation: string | null;
  }>;
  debrief: DebriefDto | null;
  session_id: string;
  status: string;
  started_at: string;
  completed_at: string | null;
}

function pickConclusion(correct: number, total: number): string {
  const pct = total > 0 ? correct / total : 0;
  if (total > 0 && correct === total) {
    return 'Perfect score — every item correct. Well done.';
  }
  if (pct >= 0.8) {
    return 'Strong performance. Review the mistakes below to close the gaps.';
  }
  if (pct >= 0.6) {
    return 'Good progress. The patterns below are worth drilling.';
  }
  return 'Keep practicing — these grammar patterns need more attention.';
}

function buildAnswers(
  lesson: Lesson,
  latest: ExerciseAttemptRow[]
): ResultPayload['answers'] {
  return latest.map((attempt) => {
    const exercise = lesson.exercises.find(
      (e) => e.exercise_id === attempt.exerciseId
    );
    // Wave 7.1.1 Codex P2.2: prefer the at-attempt snapshots so
    // completed-session reads stay stable across content edits. Fall
    // back to the live lesson only for legacy rows that pre-date the
    // migration (snapshot is null).
    let explanation: string | null = null;
    if (!attempt.correct) {
      explanation = attempt.explanationSnapshot
        ?? attempt.explanation
        ?? exercise?.feedback?.explanation
        ?? null;
    }
    const promptForReview =
      attempt.promptSnapshot
        ?? (exercise?.type === 'listening_discrimination'
              ? exercise.audio.transcript
              : exercise && 'prompt' in exercise
                ? exercise.prompt
                : null);
    return {
      exercise_id: attempt.exerciseId,
      correct: attempt.correct,
      prompt: promptForReview,
      canonical_answer: attempt.canonicalAnswer,
      explanation,
    };
  });
}

function debriefFingerprint(attempts: ExerciseAttemptRow[]): string {
  return attempts
    .map((a) => `${a.exerciseId}:${a.correct ? '1' : '0'}`)
    .sort()
    .join('|');
}

export async function getResult(
  db: AppDatabase,
  userId: string,
  sessionId: string,
  ai: AiProvider
): Promise<ResultPayload> {
  // Codex P2.1 fix: drift handling is status-aware. Completed sessions
  // tolerate content drift (the persisted debrief + frozen counts carry
  // the original outcome — refusing the read would block the learner
  // from ever seeing their own report after a fixture edit). For
  // in-progress sessions, drift must still 409 — otherwise GET /result
  // returns 200 against a stale fixture while the next /answers + /complete
  // correctly reject with `lesson_content_changed`. Two-step load so the
  // status-aware second pass runs the same hash check the write paths use.
  let { session, lesson } = await loadOwnedSession(db, userId, sessionId, {
    enforceContentHash: false,
  });
  if (session.status === 'in_progress') {
    ({ session, lesson } = await loadOwnedSession(db, userId, sessionId));
  }

  // Sort attempts by exercise position in the lesson so the result list
  // mirrors the lesson order, not insertion order.
  const exerciseOrder = new Map<string, number>(
    lesson.exercises.map((ex, idx) => [ex.exercise_id, idx])
  );
  const latestAttempts = (
    await listLatestAttemptsForSession(db, session.id)
  ).sort((a, b) => {
    const ai = exerciseOrder.get(a.exerciseId) ?? 0;
    const bi = exerciseOrder.get(b.exerciseId) ?? 0;
    return ai - bi;
  });

  // `total_exercises` reads from the session row, not the live lesson, so
  // it stays consistent with the dashboard's `last_lesson_report` (which
  // also uses `session.exerciseCount`) and survives content edits.
  const totalExercises = session.exerciseCount;
  const correctCount = latestAttempts.filter((a) => a.correct).length;
  const conclusion = pickConclusion(correctCount, totalExercises);
  const answers = buildAnswers(lesson, latestAttempts);

  let debrief: DebriefDto | null = null;
  if (session.status === 'completed' && session.debriefSnapshot) {
    debrief = session.debriefSnapshot as DebriefDto;
  } else if (latestAttempts.length > 0) {
    // In-progress sessions can hit /result repeatedly (the result screen
    // re-renders, the client polls). Cache the live debrief by attempt
    // fingerprint so the same outcome doesn't pay for a fresh AI call
    // every time. Cache invalidates automatically when any attempt flips.
    const fingerprint = debriefFingerprint(latestAttempts);
    const cached = getDebriefResult<DebriefDto>(
      session.id,
      session.lessonId,
      fingerprint
    );
    if (cached) {
      debrief = cached;
    } else {
      debrief = await buildDebrief(
        ai,
        lesson,
        latestAttempts.map(attemptRowToRecord),
        correctCount,
        totalExercises,
        { aiEnabled: true }
      );
      setDebriefResult(session.id, session.lessonId, fingerprint, debrief);
    }
  }

  return {
    lesson_id: session.lessonId,
    total_exercises: totalExercises,
    correct_count: correctCount,
    conclusion,
    answers,
    debrief,
    session_id: session.id,
    status: session.status,
    started_at: session.startedAt.toISOString(),
    completed_at: session.completedAt ? session.completedAt.toISOString() : null,
  };
}

/**
 * Mark the session completed, persist the debrief snapshot, and roll the
 * outcome into `lesson_progress`. Idempotent: replaying `/complete` on an
 * already-completed session returns the same payload without rebuilding
 * the debrief or re-incrementing `attempts_count`.
 *
 * Concurrent calls on the same session are made safe by a row-level
 * conditional UPDATE inside `finalizeSessionCompletion`: only the
 * transaction that flips `status = 'in_progress'` to `'completed'` writes
 * the snapshot and upserts progress. The losing transaction sees the
 * already-finalised row and returns the persisted payload unchanged.
 */
export async function completeSession(
  db: AppDatabase,
  userId: string,
  sessionId: string,
  ai: AiProvider,
  now: Date = new Date()
): Promise<ResultPayload> {
  const { session, lesson } = await loadOwnedSession(db, userId, sessionId);
  if (session.status === 'completed') {
    return getResult(db, userId, sessionId, ai);
  }
  if (session.status !== 'in_progress') {
    throw new LessonSessionError(409, 'session_not_in_progress');
  }

  const latestAttempts = await listLatestAttemptsForSession(db, session.id);
  const totalExercises = session.exerciseCount;
  const correctCount = latestAttempts.filter((a) => a.correct).length;

  // Build the debrief outside the transaction — the AI call can take
  // seconds and we don't want it holding a row lock. If we lose the
  // race we discard this debrief and return the winner's snapshot.
  const debrief: DebriefDto =
    latestAttempts.length === 0
      ? {
          debrief_type: 'needs_work',
          headline: 'No items completed yet.',
          body: 'You finished without submitting any answers. Restart the lesson to receive a coach\'s note.',
          watch_out: null,
          next_step: 'Restart the lesson and answer each item.',
          source: 'fallback',
        }
      : await buildDebrief(
          ai,
          lesson,
          latestAttempts.map(attemptRowToRecord),
          correctCount,
          totalExercises,
          { aiEnabled: true }
        );

  await finalizeSessionCompletion(db, {
    sessionId: session.id,
    userId,
    lessonId: session.lessonId,
    correctCount,
    totalCount: totalExercises,
    completedAt: now,
    debriefSnapshot: debrief,
  });

  return getResult(db, userId, sessionId, ai);
}
