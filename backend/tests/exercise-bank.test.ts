import { describe, it, expect } from 'vitest';
import {
  getAllBankEntries,
  getBankEntry,
  getDiagnosticPool,
  getEntriesForSkill,
  listSkills,
  RUNTIME_SUPPORTED_EXERCISE_TYPES,
} from '../src/data/exerciseBank';

// Wave 12.1 — exercise bank indexing tests. The bank loader builds its
// indexes once at module init from the shipped lesson fixtures, so these
// assertions double as a smoke test that the fixtures themselves are
// well-formed.

describe('exerciseBank indexes', () => {
  it('flattens every shipped lesson into a single bank', () => {
    const flat = getAllBankEntries();
    // 5 shipped B2 lessons × 10 runtime-eligible exercises each = 50
    // entries. Wave 14.2 phase 2 added 2 `sentence_rewrite` items to
    // each lesson but those are gated behind `RUNTIME_SUPPORTED_EXERCISE_TYPES`
    // until the Flutter widget ships in phase 3 — so the bank's
    // engine-facing surface is unchanged.
    expect(flat.length).toBe(50);
  });

  it('groups entries by skill_id when present', () => {
    const skills = listSkills();
    expect(skills).toContain('verb-ing-after-gerund-verbs');
    expect(skills).toContain('verb-to-inf-after-aspirational-verbs');
    expect(skills).toContain('verb-both-forms-meaning-change');
    expect(skills).toContain('verb-both-forms-little-change');
    expect(skills).toContain('present-perfect-continuous-vs-simple');
    for (const skill of skills) {
      // The Wave 10.5 bank guarantees ≥10 entries per shipped skill so
      // the V1 mastery gate (≥4 attempts) is reachable.
      expect(getEntriesForSkill(skill).length).toBeGreaterThanOrEqual(10);
    }
  });

  it('returns the diagnostic-tagged subset, not the fallback', () => {
    // Wave 12.1 tagged exactly 5 weak-tier MC items — one per shipped
    // skill. The fallback path returns `flat.slice(0, 5)`, which would
    // only cover the verb-ing-after-gerund-verbs skill. So if the
    // returned set spans every shipped skill, the tag-based path is
    // active.
    const pool = getDiagnosticPool();
    expect(pool.length).toBe(5);
    const skillsInPool = new Set(
      pool
        .map((entry) => entry.exercise.skill_id)
        .filter((id): id is string => typeof id === 'string')
    );
    expect(skillsInPool.size).toBe(5);
    for (const entry of pool) {
      expect(
        (entry.exercise as { is_diagnostic?: boolean }).is_diagnostic
      ).toBe(true);
      expect(entry.exercise.evidence_tier).toBe('weak');
      expect(entry.exercise.type).toBe('multiple_choice');
    }
  });

  // Wave 14.2 phase 2 — runtime-supported-types gate.
  describe('RUNTIME_SUPPORTED_EXERCISE_TYPES gate', () => {
    it('excludes sentence_rewrite items from the engine-facing flat list', () => {
      // The flag is intentionally NOT in the supported set yet — phase
      // 3 (Flutter widget) flips it on. If this assertion ever fails,
      // the lockstep contract has been broken.
      expect(RUNTIME_SUPPORTED_EXERCISE_TYPES.has('sentence_rewrite' as never)).toBe(false);
      const flat = getAllBankEntries();
      for (const entry of flat) {
        expect(entry.exercise.type).not.toBe('sentence_rewrite');
      }
    });

    it('still indexes sentence_rewrite items by exercise_id (lookup path stays open)', () => {
      // Authoring shipped 10 sentence_rewrite items at IDs ending in
      // -3b / -3c per lesson. Spot-check one — the entry must be
      // reachable via getBankEntry even though the engine cannot serve
      // it yet.
      const id = 'a1b2c3d4-0001-4000-8000-00000000003b';
      const entry = getBankEntry(id);
      expect(entry).toBeDefined();
      expect(entry?.exercise.type).toBe('sentence_rewrite');
    });

    it('keeps the per-skill index free of unsupported types', () => {
      for (const skill of listSkills()) {
        for (const entry of getEntriesForSkill(skill)) {
          expect(
            RUNTIME_SUPPORTED_EXERCISE_TYPES.has(entry.exercise.type)
          ).toBe(true);
        }
      }
    });
  });
});
