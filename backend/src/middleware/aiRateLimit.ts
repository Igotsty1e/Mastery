// Sliding window per-IP rate limiter for AI-triggering requests.
// Pure in-memory, no external deps. Keyed by remote address.

const WINDOW_MS = 60_000;
const MAX_AI_CALLS_PER_IP = 10;

const buckets = new Map<string, number[]>();

export function checkAiRateLimit(ip: string): boolean {
  const now = Date.now();
  const timestamps = (buckets.get(ip) ?? []).filter(t => now - t < WINDOW_MS);
  if (timestamps.length >= MAX_AI_CALLS_PER_IP) {
    buckets.set(ip, timestamps);
    return false;
  }
  timestamps.push(now);
  buckets.set(ip, timestamps);
  return true;
}

export function resetAiRateLimitStore(): void {
  buckets.clear();
}
