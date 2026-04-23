import { Router } from 'express';
import { getAllLessons, getLessonById } from '../data/lessons';
import type { Exercise } from '../data/lessons';
import { AnswerRequestSchema } from '../schemas';
import { evaluateFillBlank } from '../evaluators/fillBlank';
import { evaluateMultipleChoice } from '../evaluators/multipleChoice';
import { evaluateSentenceCorrection, evaluateSentenceCorrectionDeterministic } from '../evaluators/sentenceCorrection';
import type { SentenceCorrectionResult } from '../evaluators/sentenceCorrection';
import { getLessonAttempts, recordAttempt } from '../store/memory';
import { checkAiRateLimit, resolveRateLimitIp } from '../middleware/aiRateLimit';
import type { AiProvider } from '../ai/interface';

type EvaluationResult = SentenceCorrectionResult;

function slugifyLessonTitle(title: string): string {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function stripSecrets(exercise: Exercise): object {
  if (exercise.type === 'fill_blank') {
    const { accepted_answers: _a, ...pub } = exercise;
    return pub;
  }
  if (exercise.type === 'multiple_choice') {
    const { correct_option_id: _c, ...pub } = exercise;
    return pub;
  }
  // sentence_correction
  const { accepted_corrections: _ac, ...pub } = exercise;
  return pub;
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
      exercises: lesson.exercises.map(stripSecrets),
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
    } else {
      const deterministicResult = evaluateSentenceCorrectionDeterministic(
        user_answer,
        exercise.accepted_corrections,
        exercise.prompt
      );

      if (deterministicResult) {
        result = deterministicResult;
      } else {
        const ip = resolveRateLimitIp(req);
        if (!ip) {
          return res.status(400).json({ error: 'invalid_request' });
        }
        if (!checkAiRateLimit(ip)) {
          return res.status(429).json({ error: 'rate_limit_exceeded' });
        }
        result = await evaluateSentenceCorrection(
          user_answer,
          exercise.accepted_corrections,
          exercise.prompt,
          ai
        );
      }
    }

    recordAttempt(session_id, lessonId, { exercise_id, ...result });

    return res.json({
      attempt_id,
      exercise_id,
      correct: result.correct,
      evaluation_source: result.evaluation_source,
      feedback: result.correct && result.evaluation_source === 'deterministic' ? null : result.feedback,
      canonical_answer: result.canonical_answer,
    });
  });

  router.get('/lessons/:lessonId/result', (req, res) => {
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

    return res.json({
      lesson_id: lessonId,
      total_exercises,
      correct_count,
      answers: attempts.map(a => ({ exercise_id: a.exercise_id, correct: a.correct })),
    });
  });

  return router;
}
