// Wave J.1a — UI language enum + lightweight Accept-Language parser.
//
// Per `docs/plans/roadmap.md §11.6 Workstream J`, Mastery supports three
// L1s: English (default), Russian, Vietnamese. The target English the
// learner is practising stays English; only the scaffolding around it
// (UI chrome, instructions, rule explanations, feedback copy) is
// localised.
//
// J.1a only stores the preference and seeds it from `Accept-Language`
// on first login. J.2 + J.3 will thread the value through projection
// layers when actual translations land in the bank.
//
// We deliberately do not pull a full RFC 7231 quality-value parser —
// we have three supported tags and no ranking subtlety beyond
// "first supported tag in the header wins, else default to English".

import { eq } from 'drizzle-orm';
import type { AppDatabase } from '../db/client';
import { userProfiles } from '../db/schema';

export const UI_LANGUAGES = ['en', 'ru', 'vi'] as const;
export type UiLanguage = (typeof UI_LANGUAGES)[number];
export const DEFAULT_UI_LANGUAGE: UiLanguage = 'en';

export function isUiLanguage(value: string): value is UiLanguage {
  return (UI_LANGUAGES as readonly string[]).includes(value);
}

export function parseUiLanguage(value: unknown): UiLanguage | null {
  return typeof value === 'string' && isUiLanguage(value) ? value : null;
}

/// First supported tag in the header wins. Tags are normalised to
/// lowercase and stripped of region suffix (`en-US` → `en`).
/// Empty / undefined / unsupported headers fall back to English.
export function pickUiLanguageFromAcceptLanguage(
  header: string | undefined | null
): UiLanguage {
  if (!header) return DEFAULT_UI_LANGUAGE;
  const tags = header
    .split(',')
    .map((part) => part.split(';')[0].trim().toLowerCase())
    .filter((tag) => tag.length > 0);
  for (const tag of tags) {
    const primary = tag.split('-')[0];
    if (isUiLanguage(primary)) return primary;
  }
  return DEFAULT_UI_LANGUAGE;
}

/// Reads the persisted `ui_language` for an authenticated user. Returns
/// the default when the profile row does not exist (which only happens
/// before first login). Foundation-only — no caller threads the result
/// through projection yet.
export async function getUiLanguageForUser(
  db: AppDatabase,
  userId: string
): Promise<UiLanguage> {
  const rows = await db
    .select({ uiLanguage: userProfiles.uiLanguage })
    .from(userProfiles)
    .where(eq(userProfiles.userId, userId))
    .limit(1);
  const value = rows[0]?.uiLanguage;
  return parseUiLanguage(value) ?? DEFAULT_UI_LANGUAGE;
}
