import { Router } from 'express';
import { eq } from 'drizzle-orm';
import type { AppDatabase } from '../db/client';
import { requireAuth, type AuthedRequest } from '../auth/middleware';
import { userProfiles } from '../db/schema';
import { getAllLessonMeta, getLessonById } from '../data/lessons';
import {
  countAnsweredPerSession,
  findMostRecentCompletedSession,
  listInProgressSessions,
  listProgressForUser,
  type LessonSessionRow,
} from '../lessonSessions/repository';

interface DashboardLessonDto {
  lesson_id: string;
  title: string;
  slug: string;
  level: string;
  language: string;
  unit_id: string | null;
  exercise_count: number;
  order: number;
  status: 'available' | 'in_progress' | 'done';
  attempts_count: number;
  completed: boolean;
  latest_correct: number | null;
  latest_total: number | null;
  best_correct: number | null;
  best_total: number | null;
  last_completed_at: string | null;
  active_session_id: string | null;
}

interface DashboardActiveSessionDto {
  session_id: string;
  lesson_id: string;
  started_at: string;
  last_activity_at: string;
  exercise_count: number;
  answered_count: number;
}

interface DashboardLastReportDto {
  session_id: string;
  lesson_id: string;
  lesson_title: string;
  completed_at: string;
  total_exercises: number;
  correct_count: number;
  debrief: unknown;
}

function lastReportFromSession(
  session: LessonSessionRow
): DashboardLastReportDto | null {
  if (!session.completedAt) return null;
  const lesson = getLessonById(session.lessonId);
  return {
    session_id: session.id,
    lesson_id: session.lessonId,
    lesson_title: lesson?.title ?? 'Lesson',
    completed_at: session.completedAt.toISOString(),
    total_exercises: session.exerciseCount,
    correct_count: session.correctCount,
    debrief: session.debriefSnapshot ?? null,
  };
}

export function makeDashboardRouter(db: AppDatabase): Router {
  const router = Router();
  const auth = requireAuth(db);

  router.get('/dashboard', auth, async (req, res, next) => {
    try {
      const userId = (req as AuthedRequest).auth.userId;
      const allLessons = getAllLessonMeta();
      const [progressRows, activeSessions, lastCompletedSession, profileRow] =
        await Promise.all([
          listProgressForUser(db, userId),
          listInProgressSessions(db, userId),
          findMostRecentCompletedSession(db, userId),
          db
            .select({ level: userProfiles.level })
            .from(userProfiles)
            .where(eq(userProfiles.userId, userId))
            .limit(1),
        ]);

      // `lesson_sessions.correct_count` is only refreshed at completion,
      // so for in-progress sessions it is always 0. Compute the real
      // answered_count from `exercise_attempts` (one count per session,
      // distinct on exercise_id) rather than reusing that frozen field.
      const answeredBySession = await countAnsweredPerSession(
        db,
        activeSessions.map((s) => s.id)
      );

      const progressByLesson = new Map(
        progressRows.map((p) => [p.lessonId, p])
      );
      const activeByLesson = new Map<string, LessonSessionRow>();
      for (const s of activeSessions) {
        // The partial unique index guarantees one active session per
        // (user, lesson). Using a Map here is just defensive.
        activeByLesson.set(s.lessonId, s);
      }

      const lessons: DashboardLessonDto[] = allLessons.map((meta) => {
        const progress = progressByLesson.get(meta.lesson_id);
        const active = activeByLesson.get(meta.lesson_id);
        const status: DashboardLessonDto['status'] = active
          ? 'in_progress'
          : progress?.completed
            ? 'done'
            : 'available';
        return {
          lesson_id: meta.lesson_id,
          title: meta.title,
          slug: meta.slug,
          level: meta.level,
          language: meta.language,
          unit_id: meta.unit_id,
          exercise_count: meta.exercise_count,
          order: meta.order,
          status,
          attempts_count: progress?.attemptsCount ?? 0,
          completed: progress?.completed ?? false,
          latest_correct: progress?.latestCorrect ?? null,
          latest_total: progress?.latestTotal ?? null,
          best_correct: progress?.bestCorrect ?? null,
          best_total: progress?.bestTotal ?? null,
          last_completed_at:
            progress?.lastCompletedAt?.toISOString() ?? null,
          active_session_id: active?.id ?? null,
        };
      });

      // Recommended-next selection. Ordered progression exists, but any
      // lesson can still be selected by the learner; this field is a hint,
      // not a hard lock.
      let recommendedNext: string | null = null;
      const inProgressLesson = lessons.find((l) => l.status === 'in_progress');
      if (inProgressLesson) {
        recommendedNext = inProgressLesson.lesson_id;
      } else {
        const nextAvailable = lessons.find((l) => l.status !== 'done');
        recommendedNext = nextAvailable?.lesson_id ?? null;
      }

      const activeSessionsDto: DashboardActiveSessionDto[] = activeSessions.map(
        (s) => ({
          session_id: s.id,
          lesson_id: s.lessonId,
          started_at: s.startedAt.toISOString(),
          last_activity_at: s.lastActivityAt.toISOString(),
          exercise_count: s.exerciseCount,
          answered_count: answeredBySession.get(s.id) ?? 0,
        })
      );

      res.json({
        level: profileRow[0]?.level ?? null,
        lessons,
        recommended_next_lesson_id: recommendedNext,
        active_sessions: activeSessionsDto,
        last_lesson_report: lastCompletedSession
          ? lastReportFromSession(lastCompletedSession)
          : null,
      });
    } catch (err) {
      next(err);
    }
  });

  return router;
}
