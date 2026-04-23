export interface AttemptRecord {
  exercise_id: string;
  correct: boolean;
  evaluation_source: 'deterministic' | 'ai_fallback';
  feedback: string | null;
  canonical_answer: string;
}

export interface LessonAttemptsRecord {
  lesson_id: string;
  attempts: Map<string, AttemptRecord>;
}

// Keyed by `${sessionId}:${lessonId}` to isolate attempts per client session.
const store = new Map<string, LessonAttemptsRecord>();

function storeKey(sessionId: string, lessonId: string): string {
  return `${sessionId}:${lessonId}`;
}

export function getOrCreateLessonAttempts(sessionId: string, lessonId: string): LessonAttemptsRecord {
  const key = storeKey(sessionId, lessonId);
  if (!store.has(key)) {
    store.set(key, { lesson_id: lessonId, attempts: new Map() });
  }
  return store.get(key)!;
}

export function getLessonAttempts(sessionId: string, lessonId: string): LessonAttemptsRecord | undefined {
  return store.get(storeKey(sessionId, lessonId));
}

export function recordAttempt(sessionId: string, lessonId: string, attempt: AttemptRecord): void {
  const record = getOrCreateLessonAttempts(sessionId, lessonId);
  record.attempts.set(attempt.exercise_id, attempt);
}

export function resetMemoryStore(): void {
  store.clear();
}
