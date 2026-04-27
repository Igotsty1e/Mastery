import { Router } from 'express';
import { getAllLessons, getLessonById } from '../data/lessons';
import { projectExerciseForClient } from '../data/exerciseProjection';
import type { AiProvider } from '../ai/interface';

// Wave 8 (legacy drop, 2026-04-26): the unauthenticated routes
// `POST /lessons/:id/answers` and `GET /lessons/:id/result` are gone.
// Every mutation now flows through the auth-protected server-owned
// `/lesson-sessions/...` endpoints (Wave 7.2). The two read-only public
// routes below remain unauthenticated — they expose the curriculum
// manifest and the lesson content, which the dashboard's first paint
// and the lesson loader need before the AuthClient is attached.
//
// `ai` is no longer consumed here (the legacy answer route was the only
// caller); keeping the parameter on the factory keeps the call-site in
// `app.ts` stable while we inventory other lesson-scoped surfaces.

function slugifyLessonTitle(title: string): string {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

export function makeLessonsRouter(_ai: AiProvider): Router {
  const router = Router();

  router.get('/lessons', (_req, res) => {
    return res.json(
      getAllLessons().map((lesson, index) => ({
        id: lesson.lesson_id,
        title: lesson.title,
        slug: slugifyLessonTitle(lesson.title),
        order: index + 1,
        total_exercises: lesson.exercises.length,
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

  return router;
}
