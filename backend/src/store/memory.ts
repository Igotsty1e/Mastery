const SESSION_TTL_MS = 4 * 60 * 60 * 1000; // 4 hours
const MAX_SESSIONS = 10_000;

// aiCache uses the same TTL and cap as the session store.
// Keys embed sessionId, so entries naturally expire with their session.
const AI_CACHE_TTL_MS = SESSION_TTL_MS;
const MAX_AI_CACHE = 10_000;

export interface AiEvalResult {
  correct: boolean;
  evaluation_source: 'deterministic' | 'ai_fallback' | 'ai_timeout' | 'ai_error';
  feedback: string | null;
  canonical_answer: string;
}

interface AiCacheEntry {
  result: AiEvalResult;
  lastAccessMs: number;
}

// Keyed by `${sessionId}:${exerciseId}:${normAnswer}` to deduplicate identical
// AI evaluations within a session, avoiding redundant API calls on resubmission.
const aiCache = new Map<string, AiCacheEntry>();

function aiCacheKey(sessionId: string, exerciseId: string, normAnswer: string): string {
  return `${sessionId}:${exerciseId}:${normAnswer}`;
}

export function getAiResult(sessionId: string, exerciseId: string, normAnswer: string): AiEvalResult | undefined {
  const key = aiCacheKey(sessionId, exerciseId, normAnswer);
  const entry = aiCache.get(key);
  if (!entry) return undefined;
  const now = Date.now();
  if (now - entry.lastAccessMs > AI_CACHE_TTL_MS) {
    aiCache.delete(key);
    return undefined;
  }
  // Re-insert at tail to maintain MRU order for O(1) LRU eviction.
  entry.lastAccessMs = now;
  aiCache.delete(key);
  aiCache.set(key, entry);
  return entry.result;
}

export function setAiResult(sessionId: string, exerciseId: string, normAnswer: string, result: AiEvalResult): void {
  const key = aiCacheKey(sessionId, exerciseId, normAnswer);
  const now = Date.now();
  if (!aiCache.has(key) && aiCache.size >= MAX_AI_CACHE) {
    const oldest = (aiCache.keys().next().value) as string | undefined;
    if (oldest !== undefined) aiCache.delete(oldest);
  }
  aiCache.set(key, { result, lastAccessMs: now });
}

export interface AttemptRecord {
  exercise_id: string;
  correct: boolean;
  evaluation_source: 'deterministic' | 'ai_fallback' | 'ai_timeout' | 'ai_error';
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

// Cache the AI debrief per `${sessionId}:${lessonId}`. Same TTL as the
// session store, so it expires alongside the underlying attempts. Only the
// AI-sourced debrief is cached — deterministic perfect-score and fallback
// copies are cheap to recompute and depend on lesson title only.
interface DebriefCacheEntry {
  result: unknown;
  fingerprint: string;
  lastAccessMs: number;
}

const debriefCache = new Map<string, DebriefCacheEntry>();
const MAX_DEBRIEF_CACHE = 10_000;
const DEBRIEF_CACHE_TTL_MS = SESSION_TTL_MS;

function debriefCacheKey(sessionId: string, lessonId: string): string {
  return `${sessionId}:${lessonId}`;
}

export function getDebriefResult<T = unknown>(
  sessionId: string,
  lessonId: string,
  fingerprint: string
): T | undefined {
  const key = debriefCacheKey(sessionId, lessonId);
  const entry = debriefCache.get(key);
  if (!entry) return undefined;
  const now = Date.now();
  if (now - entry.lastAccessMs > DEBRIEF_CACHE_TTL_MS) {
    debriefCache.delete(key);
    return undefined;
  }
  if (entry.fingerprint !== fingerprint) {
    // Attempts changed since the cached debrief was built — invalidate so
    // the next request rebuilds against the current outcome.
    debriefCache.delete(key);
    return undefined;
  }
  entry.lastAccessMs = now;
  debriefCache.delete(key);
  debriefCache.set(key, entry);
  return entry.result as T;
}

export function setDebriefResult(
  sessionId: string,
  lessonId: string,
  fingerprint: string,
  result: unknown
): void {
  const key = debriefCacheKey(sessionId, lessonId);
  const now = Date.now();
  if (!debriefCache.has(key) && debriefCache.size >= MAX_DEBRIEF_CACHE) {
    const oldest = (debriefCache.keys().next().value) as string | undefined;
    if (oldest !== undefined) debriefCache.delete(oldest);
  }
  debriefCache.set(key, { result, fingerprint, lastAccessMs: now });
}

export function resetMemoryStore(): void {
  store.clear();
  aiCache.clear();
  debriefCache.clear();
}

// Exposed for testing only.
export function _storeSize(): number {
  return store.size;
}

export function _oldestKey(): string | undefined {
  return (store.keys().next().value) as string | undefined;
}

export function _aiCacheSize(): number {
  return aiCache.size;
}
