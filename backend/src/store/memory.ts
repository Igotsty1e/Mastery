const SESSION_TTL_MS = 4 * 60 * 60 * 1000; // 4 hours
const MAX_SESSIONS = 10_000;

export interface AiEvalResult {
  correct: boolean;
  evaluation_source: 'deterministic' | 'ai_fallback';
  feedback: string | null;
  canonical_answer: string;
}

// Keyed by `${sessionId}:${exerciseId}:${normAnswer}` to deduplicate identical
// AI evaluations within a session, avoiding redundant API calls on resubmission.
const aiCache = new Map<string, AiEvalResult>();

function aiCacheKey(sessionId: string, exerciseId: string, normAnswer: string): string {
  return `${sessionId}:${exerciseId}:${normAnswer}`;
}

export function getAiResult(sessionId: string, exerciseId: string, normAnswer: string): AiEvalResult | undefined {
  return aiCache.get(aiCacheKey(sessionId, exerciseId, normAnswer));
}

export function setAiResult(sessionId: string, exerciseId: string, normAnswer: string, result: AiEvalResult): void {
  aiCache.set(aiCacheKey(sessionId, exerciseId, normAnswer), result);
}

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
// Map preserves insertion order; re-inserting on access keeps MRU at the end,
// so the first key is always the LRU — O(1) eviction with no scan.
function evictOldestIfFull(): void {
  if (store.size < MAX_SESSIONS) return;
  const oldest = (store.keys().next().value) as string | undefined;
  if (oldest !== undefined) store.delete(oldest);
}

export function getOrCreateLessonAttempts(sessionId: string, lessonId: string): LessonAttemptsRecord {
  const key = storeKey(sessionId, lessonId);
  const now = Date.now();
  evictIfExpired(key, now);
  if (!store.has(key)) {
    evictOldestIfFull();
    store.set(key, { record: { lesson_id: lessonId, attempts: new Map() }, lastAccessMs: now });
  } else {
    const entry = store.get(key)!;
    entry.lastAccessMs = now;
    // Re-insert at end to maintain MRU-at-tail insertion order for O(1) LRU eviction.
    store.delete(key);
    store.set(key, entry);
  }
  return store.get(key)!.record;
}

export function getLessonAttempts(sessionId: string, lessonId: string): LessonAttemptsRecord | undefined {
  const key = storeKey(sessionId, lessonId);
  const now = Date.now();
  evictIfExpired(key, now);
  const entry = store.get(key);
  if (entry) {
    entry.lastAccessMs = now;
    // Re-insert at end to maintain MRU-at-tail insertion order for O(1) LRU eviction.
    store.delete(key);
    store.set(key, entry);
  }
  return entry?.record;
}

export function recordAttempt(sessionId: string, lessonId: string, attempt: AttemptRecord): void {
  const record = getOrCreateLessonAttempts(sessionId, lessonId);
  record.attempts.set(attempt.exercise_id, attempt);
}

export function resetMemoryStore(): void {
  store.clear();
  aiCache.clear();
}

// Exposed for testing only.
export function _storeSize(): number {
  return store.size;
}

export function _oldestKey(): string | undefined {
  return (store.keys().next().value) as string | undefined;
}
