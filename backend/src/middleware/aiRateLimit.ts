// Sliding window per-IP rate limiter for AI-triggering requests.
// Pure in-memory, no external deps. Keyed by resolved client IP.

import type { Request } from 'express';

const WINDOW_MS = 60_000;
const MAX_AI_CALLS_PER_IP = 10;
const MAX_BUCKETS = 10_000;

const buckets = new Map<string, number[]>();

// Loopback and RFC 1918 private ranges — only these are trusted to set XFF.
const TRUSTED_PROXY_RE = [
  /^127\./,
  /^::1$/,
  /^::ffff:127\./,
  /^10\./,
  /^172\.(1[6-9]|2\d|3[01])\./,
  /^192\.168\./,
  /^::ffff:10\./,
  /^::ffff:172\.(1[6-9]|2\d|3[01])\./,
  /^::ffff:192\.168\./,
];

function isTrustedProxyIp(ip: string): boolean {
  return TRUSTED_PROXY_RE.some(r => r.test(ip));
}

/**
 * Resolve the client IP for rate-limiting.
 *
 * X-Forwarded-For is only trusted when the socket connection comes from a
 * loopback or RFC 1918 address (our own infrastructure). Clients connecting
 * from a public IP cannot spoof their rate-limit bucket via XFF.
 *
 * When trusting a proxy, the RIGHTMOST XFF entry is used — this is the one
 * appended by our proxy, not prepended by the client.
 */
export function resolveRateLimitIp(req: Request): string | undefined {
  const socketIp = req.socket?.remoteAddress;
  if (!socketIp) return undefined;

  if (isTrustedProxyIp(socketIp)) {
    const xff = req.headers['x-forwarded-for'];
    const xffStr = Array.isArray(xff) ? xff[0] : xff;
    if (xffStr) {
      const rightmost = xffStr.split(',').map(s => s.trim()).filter(Boolean).at(-1);
      if (rightmost) return rightmost;
    }
  }

  return socketIp;
}

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
