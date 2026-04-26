// Trusted-proxy boundary helper. Anywhere we make a security decision based
// on the caller's IP (rate limiting, audit logs, session metadata), we must
// route through here so a public client cannot spoof their bucket via XFF.
//
// Rule: only trust X-Forwarded-For when the socket connection itself came
// from loopback or RFC 1918. When trusted, take the *rightmost* XFF entry —
// that is the one our own proxy appended, not what the client prepended.

import type { Request } from 'express';

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
  return TRUSTED_PROXY_RE.some((r) => r.test(ip));
}

export function resolveClientIp(req: Request): string | undefined {
  const socketIp = req.socket?.remoteAddress;
  if (!socketIp) return undefined;

  if (isTrustedProxyIp(socketIp)) {
    const xff = req.headers['x-forwarded-for'];
    const xffStr = Array.isArray(xff) ? xff[0] : xff;
    if (xffStr) {
      const rightmost = xffStr
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean)
        .at(-1);
      if (rightmost) return rightmost;
    }
  }

  return socketIp;
}
