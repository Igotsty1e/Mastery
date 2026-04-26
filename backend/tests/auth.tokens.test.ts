import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import {
  ACCESS_TOKEN_TTL_SECONDS,
  assertAuthSecretConfigured,
  generateRefreshToken,
  hashRefreshToken,
  signAccessToken,
  verifyAccessToken,
} from '../src/auth/tokens';

describe('access token signing', () => {
  it('round-trips userId + sessionId', () => {
    const t = signAccessToken('user-1', 'session-1');
    const payload = verifyAccessToken(t.token);
    expect(payload?.userId).toBe('user-1');
    expect(payload?.sessionId).toBe('session-1');
  });

  it('rejects a tampered signature', () => {
    const t = signAccessToken('user-1', 'session-1');
    const broken = t.token.slice(0, -1) + (t.token.endsWith('a') ? 'b' : 'a');
    expect(verifyAccessToken(broken)).toBeNull();
  });

  it('rejects a tampered body', () => {
    const t = signAccessToken('user-1', 'session-1');
    const dot = t.token.indexOf('.');
    const broken = t.token.slice(0, dot - 1) + 'X' + t.token.slice(dot);
    expect(verifyAccessToken(broken)).toBeNull();
  });

  it('expires after the configured TTL', () => {
    const issuedAt = Date.now();
    const t = signAccessToken('user-1', 'session-1', issuedAt);
    const justAfterExpiry = issuedAt + ACCESS_TOKEN_TTL_SECONDS * 1000 + 1000;
    expect(verifyAccessToken(t.token, justAfterExpiry)).toBeNull();
  });

  it('rejects malformed tokens', () => {
    expect(verifyAccessToken('not-a-token')).toBeNull();
    expect(verifyAccessToken('')).toBeNull();
  });
});

describe('AUTH_SECRET production guard', () => {
  const originalNodeEnv = process.env.NODE_ENV;
  const originalSecret = process.env.AUTH_SECRET;

  beforeEach(() => {
    delete process.env.AUTH_SECRET;
    delete process.env.NODE_ENV;
  });

  afterEach(() => {
    if (originalNodeEnv === undefined) delete process.env.NODE_ENV;
    else process.env.NODE_ENV = originalNodeEnv;
    if (originalSecret === undefined) delete process.env.AUTH_SECRET;
    else process.env.AUTH_SECRET = originalSecret;
  });

  it('assertAuthSecretConfigured throws in production when AUTH_SECRET is unset', () => {
    process.env.NODE_ENV = 'production';
    expect(() => assertAuthSecretConfigured()).toThrow(/AUTH_SECRET/);
  });

  it('assertAuthSecretConfigured does not throw in production when AUTH_SECRET is set', () => {
    process.env.NODE_ENV = 'production';
    process.env.AUTH_SECRET = 'real-prod-secret';
    expect(() => assertAuthSecretConfigured()).not.toThrow();
  });

  it('assertAuthSecretConfigured does not throw outside of production', () => {
    process.env.NODE_ENV = 'development';
    expect(() => assertAuthSecretConfigured()).not.toThrow();
  });

  it('signAccessToken refuses to sign with the dev fallback in production', () => {
    process.env.NODE_ENV = 'production';
    expect(() => signAccessToken('user-1', 'session-1')).toThrow(/AUTH_SECRET/);
  });

  it('verifyAccessToken refuses to verify with the dev fallback in production', () => {
    process.env.NODE_ENV = 'production';
    process.env.AUTH_SECRET = 'real-prod-secret';
    const t = signAccessToken('user-1', 'session-1');
    delete process.env.AUTH_SECRET;
    expect(() => verifyAccessToken(t.token)).toThrow(/AUTH_SECRET/);
  });
});

describe('refresh tokens', () => {
  it('generates non-trivial random tokens', () => {
    const a = generateRefreshToken();
    const b = generateRefreshToken();
    expect(a).not.toBe(b);
    expect(a.length).toBeGreaterThanOrEqual(32);
  });

  it('hashes deterministically', () => {
    const t = 'sample';
    expect(hashRefreshToken(t)).toBe(hashRefreshToken(t));
    expect(hashRefreshToken(t)).toMatch(/^[a-f0-9]{64}$/);
  });
});
