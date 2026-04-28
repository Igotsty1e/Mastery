import { describe, it, expect } from 'vitest';
import {
  getAllBankEntries,
  getDiagnosticPool,
  getEntriesForSkill,
  listSkills,
} from '../src/data/exerciseBank';

// Wave 12.1 — exercise bank indexing tests. The bank loader builds its
// indexes once at module init from the shipped lesson fixtures, so these
// assertions double as a smoke test that the fixtures themselves are
// well-formed.

describe('exerciseBank indexes', () => {
  it('flattens every shipped lesson into a single bank', () => {
    const flat = getAllBankEntries();
    // 5 shipped B2 lessons × 10 exercises each = 50 entries (Wave 10.5).
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
});
