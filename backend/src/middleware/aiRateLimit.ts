// Sliding window per-IP rate limiter for AI-triggering requests.
// Pure in-memory, no external deps. Keyed by resolved client IP.

import { resolveClientIp } from './clientIp';

const WINDOW_MS = 60_000;
const MAX_AI_CALLS_PER_IP = 10;
const MAX_BUCKETS = 10_000;

const buckets = new Map<string, number[]>();

/**
 * Resolve the client IP for rate-limiting. Re-exported as
 * `resolveRateLimitIp` for backwards compatibility with the existing
 * lessons route; new call sites should import `resolveClientIp` directly
 * from `./clientIp`.
 */
export const resolveRateLimitIp = resolveClientIp;

export function checkAiRateLimit(ip: string): boolean {
  const now = Date.now();
  const timestamps = (buckets.get(ip) ?? []).filter(t => now - t < WINDOW_MS);
  if (timestamps.length >= MAX_AI_CALLS_PER_IP) {
    buckets.set(ip, timestamps);
    return false;
  }
  timestamps.push(now);
  buckets.set(ip, timestamps);
  // When the map is too large, sweep out buckets whose entire window has expired.
  if (buckets.size > MAX_BUCKETS) {
    for (const [k, ts] of buckets) {
      if (ts.every(t => now - t >= WINDOW_MS)) buckets.delete(k);
    }
  }
  return true;
}

export function resetAiRateLimitStore(): void {
  buckets.clear();
}
