import { Router } from 'express';
import { getAllLessons, getLessonById } from '../data/lessons';
import { projectExerciseForClient } from '../data/exerciseProjection';
import { AnswerRequestSchema } from '../schemas';
import { evaluateFillBlank } from '../evaluators/fillBlank';
import { evaluateMultipleChoice } from '../evaluators/multipleChoice';
import { evaluateListeningDiscrimination } from '../evaluators/listeningDiscrimination';
import { evaluateSentenceCorrection, evaluateSentenceCorrectionDeterministic } from '../evaluators/sentenceCorrection';
import type { SentenceCorrectionResult } from '../evaluators/sentenceCorrection';
import {
  getLessonAttempts,
  recordAttempt,
  getAiResult,
  setAiResult,
  getDebriefResult,
  setDebriefResult,
} from '../store/memory';
import { normalize } from '../evaluators/normalize';
import { checkAiRateLimit, resolveRateLimitIp } from '../middleware/aiRateLimit';
import type { AiProvider } from '../ai/interface';
import { buildDebrief, type DebriefDto } from '../debrief/debrief';

type EvaluationResult = SentenceCorrectionResult;

// Wave 5 (LEARNING_ENGINE.md §8.7): bumped when the evaluator's contract
// changes in a way clients should re-route on. Initial release = 1.
// Stored on every attempt response so the future Mastery Model can
// invalidate per-skill production-gate state when the evaluator semantics
// move under it.
const EVALUATION_VERSION = 1;

// Wave 5 partial-credit shape (LEARNING_ENGINE.md §8.7). Single-decision
// items (the families shipped today) emit only `correct` or `wrong` and
// leave `response_units` empty. The `partial` value is reserved for the
// multi-unit families introduced in Wave 6 (multi_blank,
// multi_error_correction, multi_select).
type AttemptResult = 'correct' | 'partial' | 'wrong';

function deriveResult(correct: boolean): AttemptResult {
  return correct ? 'correct' : 'wrong';
}

function slugifyLessonTitle(title: string): string {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

export function makeLessonsRouter(ai: AiProvider): Router {
  const router = Router();

  router.get('/lessons', (_req, res) => {
    return res.json(
      getAllLessons().map((lesson, index) => ({
        id: lesson.lesson_id,
        title: lesson.title,
        slug: slugifyLessonTitle(lesson.title),
        order: index + 1,
      }))
    );
  });

  router.get('/lessons/:lessonId', (req, res) => {
    const lesson = getLessonById(req.params.lessonId);
    if (!lesson) {
      return res.status(404).json({ error: 'lesson_not_found' });
    }
    return res.json({
      lesson_id: lesson.lesson_id,
      title: lesson.title,
      language: lesson.language,
      level: lesson.level,
      intro_rule: lesson.intro_rule,
      intro_examples: lesson.intro_examples,
      exercises: lesson.exercises.map(projectExerciseForClient),
    });
  });

  router.post('/lessons/:lessonId/answers', async (req, res) => {
    const parsed = AnswerRequestSchema.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: 'invalid_payload' });
    }

    const lessonId = req.params.lessonId;
    const { session_id, attempt_id, exercise_id, exercise_type, user_answer } = parsed.data;

    const lesson = getLessonById(lessonId);
    if (!lesson) {
      return res.status(404).json({ error: 'lesson_not_found' });
    }

    const exercise = lesson.exercises.find(e => e.exercise_id === exercise_id);
    if (!exercise) {
      return res.status(404).json({ error: 'exercise_not_found' });
    }

    if (exercise.type !== exercise_type) {
      return res.status(400).json({ error: 'invalid_payload' });
    }

    let result: EvaluationResult;

    if (exercise.type === 'fill_blank') {
      result = evaluateFillBlank(user_answer, exercise.accepted_answers);
    } else if (exercise.type === 'multiple_choice') {
      result = evaluateMultipleChoice(user_answer, exercise.correct_option_id, exercise.options);
    } else if (exercise.type === 'listening_discrimination') {
      result = evaluateListeningDiscrimination(
        user_answer,
        exercise.correct_option_id,
        exercise.options
      );
    } else {
      const deterministicResult = evaluateSentenceCorrectionDeterministic(
        user_answer,
        exercise.accepted_corrections,
        exercise.prompt
      );

      if (deterministicResult) {
        result = deterministicResult;
      } else {
        const normAnswer = normalize(user_answer);
        const cached = getAiResult(session_id, exercise_id, normAnswer);
        if (cached) {
          result = cached;
        } else {
          const ip = resolveRateLimitIp(req);
          if (!ip) {
            return res.status(400).json({ error: 'invalid_request' });
          }
          if (!checkAiRateLimit(ip)) {
            return res.status(429).json({ error: 'rate_limit_exceeded' });
          }
          const aiResult = await evaluateSentenceCorrection(
            user_answer,
            exercise.accepted_corrections,
            exercise.prompt,
            ai
          );
          setAiResult(session_id, exercise_id, normAnswer, aiResult);
          result = aiResult;
        }
      }
    }

    recordAttempt(session_id, lessonId, { exercise_id, ...result });

    let explanation: string | null = null;

    if (!result.correct && exercise.feedback) {
      explanation = exercise.feedback.explanation;
    }

    return res.json({
      attempt_id,
      exercise_id,
      correct: result.correct,
      // Wave 5 partial-credit shape. `correct: bool` is preserved for
      // backwards compat; `result` is the forward-looking field that
      // multi-unit families (Wave 6) extend with `'partial'`.
      result: deriveResult(result.correct),
      response_units: [] as Array<unknown>,
      evaluation_version: EVALUATION_VERSION,
      evaluation_source: result.evaluation_source,
      explanation,
      canonical_answer: result.canonical_answer,
    });
  });

  router.get('/lessons/:lessonId/result', async (req, res) => {
    const lessonId = req.params.lessonId;
    const session_id = req.query.session_id as string | undefined;
    const lesson = getLessonById(lessonId);
    if (!lesson) {
      return res.status(404).json({ error: 'lesson_not_found' });
    }

    const total_exercises = lesson.exercises.length;
    const record = session_id ? getLessonAttempts(session_id, lessonId) : undefined;
    const attempts = record ? Array.from(record.attempts.values()) : [];
    const correct_count = attempts.filter(a => a.correct).length;

    const pct = total_exercises > 0 ? correct_count / total_exercises : 0;
    let conclusion: string;
    if (correct_count === total_exercises) {
      conclusion = 'Perfect score — every item correct. Well done.';
    } else if (pct >= 0.8) {
      conclusion = 'Strong performance. Review the mistakes below to close the gaps.';
    } else if (pct >= 0.6) {
      conclusion = 'Good progress. The patterns below are worth drilling.';
    } else {
      conclusion = 'Keep practicing — these grammar patterns need more attention.';
    }

    const answers = attempts.map(attempt => {
      const exercise = lesson.exercises.find(e => e.exercise_id === attempt.exercise_id);
      let explanation: string | null = null;

      if (!attempt.correct) {
        explanation = exercise?.feedback?.explanation ?? null;
      }

      // Listening items have no `prompt`; surface the transcript so the
      // summary's mistake review still has readable content.
      const promptForReview = exercise?.type === 'listening_discrimination'
        ? exercise.audio.transcript
        : exercise && 'prompt' in exercise ? exercise.prompt : null;

      return {
        exercise_id: attempt.exercise_id,
        correct: attempt.correct,
        prompt: promptForReview,
        canonical_answer: attempt.canonical_answer,
        explanation,
      };
    });

    let debrief: DebriefDto | null = null;
    if (attempts.length > 0) {
      // Fingerprint sorts attempts by exercise_id so re-submission ordering
      // doesn't invalidate a still-valid cached debrief.
      const fp = attempts
        .slice()
        .sort((a, b) => a.exercise_id.localeCompare(b.exercise_id))
        .map(a => `${a.exercise_id}:${a.correct ? 1 : 0}`)
        .join('|');

      const cached = session_id
        ? getDebriefResult<DebriefDto>(session_id, lessonId, fp)
        : undefined;
      if (cached) {
        debrief = cached;
      } else {
        debrief = await buildDebrief(ai, lesson, attempts, correct_count, total_exercises);
        if (session_id) {
          setDebriefResult(session_id, lessonId, fp, debrief);
        }
      }
    }

    return res.json({
      lesson_id: lessonId,
      total_exercises,
      correct_count,
      conclusion,
      answers,
      debrief,
    });
  });

  return router;
}
