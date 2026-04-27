import crypto from 'node:crypto';

export const ACCESS_TOKEN_TTL_SECONDS = 15 * 60;
export const REFRESH_TOKEN_TTL_SECONDS = 60 * 60 * 24 * 30;

const DEV_FALLBACK_SECRET = 'dev-only-do-not-use-in-prod-replace-me';

function isProduction(): boolean {
  return process.env.NODE_ENV === 'production';
}

/**
 * Boot-time guard. Call once before binding the listener so a missing
 * `AUTH_SECRET` in production crashes the process loudly instead of
 * silently signing every token with the dev fallback key.
 */
export function assertAuthSecretConfigured(): void {
  if (isProduction() && !process.env.AUTH_SECRET) {
    throw new Error(
      'AUTH_SECRET is required when NODE_ENV=production. Refusing to boot ' +
        'with the dev fallback key.'
    );
  }
}

function getSecret(): Buffer {
  const s = process.env.AUTH_SECRET;
  if (s) return Buffer.from(s, 'utf8');
  if (isProduction()) {
    // Belt-and-braces: even if `assertAuthSecretConfigured` were skipped,
    // any signing/verification attempt in production must fail loudly
    // rather than fall back to a publicly-known constant.
    throw new Error(
      'AUTH_SECRET is required when NODE_ENV=production. Refusing to sign ' +
        'or verify tokens with the dev fallback key.'
    );
  }
  return Buffer.from(DEV_FALLBACK_SECRET, 'utf8');
}

export interface AccessTokenPayload {
  userId: string;
  sessionId: string;
  exp: number; // unix seconds
}

function b64url(buf: Buffer): string {
  return buf
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function b64urlDecode(s: string): Buffer {
  let out = s.replace(/-/g, '+').replace(/_/g, '/');
  while (out.length % 4) out += '=';
  return Buffer.from(out, 'base64');
}

export interface SignedAccessToken {
  token: string;
  expiresAt: Date;
}

export function signAccessToken(
  userId: string,
  sessionId: string,
  now: number = Date.now()
): SignedAccessToken {
  const exp = Math.floor(now / 1000) + ACCESS_TOKEN_TTL_SECONDS;
  const payload: AccessTokenPayload = { userId, sessionId, exp };
  const body = b64url(Buffer.from(JSON.stringify(payload)));
  const sig = b64url(
    crypto.createHmac('sha256', getSecret()).update(body).digest()
  );
  return { token: `${body}.${sig}`, expiresAt: new Date(exp * 1000) };
}

export function verifyAccessToken(
  token: string,
  now: number = Date.now()
): AccessTokenPayload | null {
  if (typeof token !== 'string') return null;
  const dot = token.indexOf('.');
  if (dot === -1) return null;
  const body = token.slice(0, dot);
  const sig = token.slice(dot + 1);
  const expected = b64url(
    crypto.createHmac('sha256', getSecret()).update(body).digest()
  );
  const sigBuf = Buffer.from(sig);
  const expBuf = Buffer.from(expected);
  if (sigBuf.length !== expBuf.length) return null;
  if (!crypto.timingSafeEqual(sigBuf, expBuf)) return null;

  let payload: AccessTokenPayload;
  try {
    payload = JSON.parse(b64urlDecode(body).toString('utf8'));
  } catch {
    return null;
  }
  if (
    !payload ||
    typeof payload.exp !== 'number' ||
    typeof payload.userId !== 'string' ||
    typeof payload.sessionId !== 'string'
  )
    return null;
  if (payload.exp * 1000 < now) return null;
  return payload;
}

export function generateRefreshToken(): string {
  return b64url(crypto.randomBytes(32));
}

export function hashRefreshToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}
