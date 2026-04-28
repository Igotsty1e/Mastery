// Wave J.1a — UI language helpers (parser + Accept-Language picker).
//
// The DB-bound helper `getUiLanguageForUser` is exercised through the
// integration tests in `me.route.test.ts` + `auth.route.test.ts`; this
// file only covers the pure functions.

import { describe, expect, it } from 'vitest';
import {
  DEFAULT_UI_LANGUAGE,
  isUiLanguage,
  parseUiLanguage,
  pickUiLanguageFromAcceptLanguage,
  UI_LANGUAGES,
} from '../src/users/uiLanguage';

describe('UI_LANGUAGES enum', () => {
  it('is exactly en, ru, vi (locked scope per Workstream J)', () => {
    expect([...UI_LANGUAGES]).toEqual(['en', 'ru', 'vi']);
  });

  it('defaults to en', () => {
    expect(DEFAULT_UI_LANGUAGE).toBe('en');
  });
});

describe('isUiLanguage', () => {
  it('accepts every supported tag', () => {
    expect(isUiLanguage('en')).toBe(true);
    expect(isUiLanguage('ru')).toBe(true);
    expect(isUiLanguage('vi')).toBe(true);
  });

  it('rejects unsupported tags + region-suffixed forms', () => {
    expect(isUiLanguage('de')).toBe(false);
    expect(isUiLanguage('en-US')).toBe(false); // region not stripped here
    expect(isUiLanguage('EN')).toBe(false); // case-sensitive
    expect(isUiLanguage('')).toBe(false);
  });
});

describe('parseUiLanguage', () => {
  it('returns the tag when valid', () => {
    expect(parseUiLanguage('ru')).toBe('ru');
  });

  it('returns null for non-strings or unsupported values', () => {
    expect(parseUiLanguage(null)).toBeNull();
    expect(parseUiLanguage(undefined)).toBeNull();
    expect(parseUiLanguage(42)).toBeNull();
    expect(parseUiLanguage('de')).toBeNull();
  });
});

describe('pickUiLanguageFromAcceptLanguage', () => {
  it('returns en for empty / undefined / null headers', () => {
    expect(pickUiLanguageFromAcceptLanguage(undefined)).toBe('en');
    expect(pickUiLanguageFromAcceptLanguage(null)).toBe('en');
    expect(pickUiLanguageFromAcceptLanguage('')).toBe('en');
  });

  it('picks the first supported tag (region stripped)', () => {
    expect(pickUiLanguageFromAcceptLanguage('en-US,en;q=0.9')).toBe('en');
    expect(pickUiLanguageFromAcceptLanguage('ru-RU,ru;q=0.9,en;q=0.8')).toBe(
      'ru'
    );
    expect(pickUiLanguageFromAcceptLanguage('vi-VN,vi;q=0.9')).toBe('vi');
  });

  it('falls back to en when no supported tag is present', () => {
    expect(pickUiLanguageFromAcceptLanguage('de-DE,de;q=0.9,fr;q=0.8')).toBe(
      'en'
    );
  });

  it('honours the order of tags — first supported tag wins', () => {
    // RFC 7231 q-values would push `ru` above `vi` here, but our
    // lightweight parser is order-only — fine because all three of
    // our tags are equal-priority from a product perspective and
    // the header order in browsers already reflects user preference.
    expect(pickUiLanguageFromAcceptLanguage('vi,ru;q=0.9')).toBe('vi');
    expect(pickUiLanguageFromAcceptLanguage('ru,vi;q=0.9')).toBe('ru');
  });

  it('is case-insensitive against the header', () => {
    expect(pickUiLanguageFromAcceptLanguage('RU-RU')).toBe('ru');
    expect(pickUiLanguageFromAcceptLanguage('VI')).toBe('vi');
  });

  it('skips empty / whitespace fragments without crashing', () => {
    expect(pickUiLanguageFromAcceptLanguage(',,, ru ')).toBe('ru');
    expect(pickUiLanguageFromAcceptLanguage(',,,')).toBe('en');
  });
});
