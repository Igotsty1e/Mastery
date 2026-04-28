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
    // 5 shipped B2 lessons × 12 exercises each = 60 entries.
    // Wave 14.2 phase 2 authored 10 sentence_rewrite items behind the
    // RUNTIME_SUPPORTED_EXERCISE_TYPES gate; phase 3 (this wave)
    // shipped the Flutter widget and flipped the gate, so the items
    // are now engine-eligible.
    expect(flat.length).toBe(60);
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

  // Wave 14.2 — runtime-supported-types gate.
  describe('RUNTIME_SUPPORTED_EXERCISE_TYPES gate', () => {
    it('includes sentence_rewrite after the phase-3 lockstep flip', () => {
      // Phase 2 shipped the items behind the gate; phase 3 ships the
      // Flutter widget and turns the gate on. If this regresses the
      // engine would serve items the client cannot render — break the
      // build before that lands in prod.
      expect(RUNTIME_SUPPORTED_EXERCISE_TYPES.has('sentence_rewrite')).toBe(true);
    });

    it('every supported type is renderable by the shipped Flutter build', () => {
      // Snapshot the contract so adding a type without thinking about
      // the Flutter widget needs an explicit test edit.
      expect([...RUNTIME_SUPPORTED_EXERCISE_TYPES].sort()).toEqual([
        'fill_blank',
        'listening_discrimination',
        'multiple_choice',
        'sentence_correction',
        'sentence_rewrite',
      ]);
    });

    it('looks up sentence_rewrite items by exercise_id', () => {
      // Spot-check one of the 10 phase-2 items (lesson 001, slot 3b).
      const id = 'a1b2c3d4-0001-4000-8000-00000000003b';
      const entry = getBankEntry(id);
      expect(entry).toBeDefined();
      expect(entry?.exercise.type).toBe('sentence_rewrite');
    });

    it('every per-skill index entry is a runtime-supported type', () => {
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
