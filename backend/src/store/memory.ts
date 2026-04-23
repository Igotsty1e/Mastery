const SESSION_TTL_MS = 4 * 60 * 60 * 1000; // 4 hours
const MAX_SESSIONS = 10_000;

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

interface StoreEntry {
  record: LessonAttemptsRecord;
  lastAccessMs: number;
}

// Keyed by `${sessionId}:${lessonId}` to isolate attempts per client session.
const store = new Map<string, StoreEntry>();

function storeKey(sessionId: string, lessonId: string): string {
  return `${sessionId}:${lessonId}`;
}

function evictIfExpired(key: string, now: number): void {
  const entry = store.get(key);
  if (entry && now - entry.lastAccessMs > SESSION_TTL_MS) {
    store.delete(key);
  }
}

// Evict the least-recently-used entry when at capacity.
function evictOldestIfFull(): void {
  if (store.size < MAX_SESSIONS) return;
  let oldestKey = '';
  let oldestAccess = Infinity;
  for (const [k, v] of store) {
    if (v.lastAccessMs < oldestAccess) {
      oldestAccess = v.lastAccessMs;
      oldestKey = k;
    }
  }
  if (oldestKey) store.delete(oldestKey);
}

export function getOrCreateLessonAttempts(sessionId: string, lessonId: string): LessonAttemptsRecord {
  const key = storeKey(sessionId, lessonId);
  const now = Date.now();
  evictIfExpired(key, now);
  if (!store.has(key)) {
    evictOldestIfFull();
    store.set(key, { record: { lesson_id: lessonId, attempts: new Map() }, lastAccessMs: now });
  } else {
    store.get(key)!.lastAccessMs = now;
  }
  return store.get(key)!.record;
}

export function getLessonAttempts(sessionId: string, lessonId: string): LessonAttemptsRecord | undefined {
  const key = storeKey(sessionId, lessonId);
  const now = Date.now();
  evictIfExpired(key, now);
  const entry = store.get(key);
  if (entry) entry.lastAccessMs = now;
  return entry?.record;
}

export function recordAttempt(sessionId: string, lessonId: string, attempt: AttemptRecord): void {
  const record = getOrCreateLessonAttempts(sessionId, lessonId);
  record.attempts.set(attempt.exercise_id, attempt);
}

export function resetMemoryStore(): void {
  store.clear();
}

// Exposed for testing only.
export function _storeSize(): number {
  return store.size;
}
