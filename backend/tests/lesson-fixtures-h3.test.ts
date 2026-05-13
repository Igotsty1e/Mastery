// Wave H3 fixture pinning — covers phases 2 + 3.
//
// Phase 2 (shipped 2026-05-14): Lessons 3 + 5 converted to question-driven
// SFS with dual-form `target_rule` on Lesson 5.
//
// Phase 3 (shipped 2026-05-14): Lesson 4 partial conversion + retired 03d +
// fresh-UUID regret SFS, all with the strict 5-component `target_rule`
// contract (trigger / immediate complement / target meaning / rejected
// counter-form / explicit reject clause).
//
// The grader prompt at backend/src/ai/openai.ts:150-167 carries only
// TARGET_RULE / INSTRUCTION / STUDENT_ANSWER (accepted_examples are NOT
// substituted), so the rule itself MUST encode the meaning + form contract.

import fs from 'node:fs';
import path from 'node:path';
import { describe, it, expect } from 'vitest';
import { LessonSchema } from '../src/data/lessonSchema';

const LESSON_3 = 'b2-lesson-003.json';
const LESSON_4 = 'b2-lesson-004.json';
const LESSON_5 = 'b2-lesson-005.json';

// Wave H3 phase 2 — Lesson 5 dual-form converted IDs.
const LESSON_5_CONVERTED: Array<{ id: string; trigger: string }> = [
  { id: 'a1b2c3d4-0005-4000-8000-000000000031', trigger: 'like' },
  { id: 'a1b2c3d4-0005-4000-8000-000000000033', trigger: 'love' },
  { id: 'a1b2c3d4-0005-4000-8000-000000000034', trigger: 'hate' },
  { id: 'a1b2c3d4-0005-4000-8000-000000000038', trigger: 'began' },
];
const LESSON_5_CONVERTED_IDS = new Set(LESSON_5_CONVERTED.map((c) => c.id));

// Wave H3 phase 3 — Lesson 4 meaning-contrast SFS items. Trigger is the
// verb in the question's "Start with «...»" anchor; the form is the
// expected complement shape immediately after the trigger (ing-form or
// `to + base verb`).
type LessonFour = { id: string; trigger: string; form: 'ing' | 'to' };
const LESSON_4_SFS: LessonFour[] = [
  // 031 — remember + to (future obligation)
  { id: 'a1b2c3d4-0004-4000-8000-000000000031', trigger: 'remember', form: 'to' },
  // 032 — remember + -ing (past recall). The anchor is "I clearly remember
  // …", so the trigger token in `accepted_examples` is plain `remember`.
  { id: 'a1b2c3d4-0004-4000-8000-000000000032', trigger: 'remember', form: 'ing' },
  // 034 — forget + -ing (past recall). The anchor is "I'll never forget".
  { id: 'a1b2c3d4-0004-4000-8000-000000000034', trigger: 'forget', form: 'ing' },
  // 038 — try + -ing (experiment). The anchor is "I'd try".
  { id: 'a1b2c3d4-0004-4000-8000-000000000038', trigger: 'try', form: 'ing' },
  // NEW — regret + -ing (past regret) on a fresh UUID. Replaces the
  // retired remember+-ing SFS at …03d.
  { id: 'a1b2c3d4-0004-4000-8000-000000000040', trigger: 'regret', form: 'ing' },
];
const LESSON_4_RETIRED_ID = 'a1b2c3d4-0004-4000-8000-00000000003d';
const LESSON_4_FB_PRESERVED_IDS = new Set([
  // The `stop` pair stays as fill_blank to preserve the recognition contrast.
  'a1b2c3d4-0004-4000-8000-000000000035', // stop + to (purpose)
  'a1b2c3d4-0004-4000-8000-000000000036', // stop + -ing (cease)
]);

function loadLesson(file: string): any {
  const fp = path.resolve(__dirname, '../data/lessons', file);
  return JSON.parse(fs.readFileSync(fp, 'utf8'));
}

describe('Wave H3 fixtures parse + rule shape contracts', () => {
  it('b2-lesson-003.json parses cleanly through LessonSchema', () => {
    const parsed = LessonSchema.safeParse(loadLesson(LESSON_3));
    if (!parsed.success) {
      throw new Error(JSON.stringify(parsed.error.issues, null, 2));
    }
    expect(parsed.success).toBe(true);
  });

  it('b2-lesson-004.json parses cleanly through LessonSchema', () => {
    const parsed = LessonSchema.safeParse(loadLesson(LESSON_4));
    if (!parsed.success) {
      throw new Error(JSON.stringify(parsed.error.issues, null, 2));
    }
    expect(parsed.success).toBe(true);
  });

  it('b2-lesson-005.json parses cleanly through LessonSchema', () => {
    const parsed = LessonSchema.safeParse(loadLesson(LESSON_5));
    if (!parsed.success) {
      throw new Error(JSON.stringify(parsed.error.issues, null, 2));
    }
    expect(parsed.success).toBe(true);
  });

  // ── Phase 2 — Lesson 5 dual-form ────────────────────────────────────────
  it('Lesson 5 converted SFS items carry dual-form acceptance in target_rule', () => {
    const lesson = loadLesson(LESSON_5);
    const checked = new Set<string>();
    for (const ex of lesson.exercises) {
      if (!LESSON_5_CONVERTED_IDS.has(ex.exercise_id)) continue;
      expect(ex.type, `item ${ex.exercise_id}`).toBe('short_free_sentence');
      expect(ex.target_rule, `item ${ex.exercise_id}`).toContain('verb-ing');
      expect(ex.target_rule, `item ${ex.exercise_id}`).toContain('to + base verb');
      checked.add(ex.exercise_id);
    }
    expect(checked).toEqual(LESSON_5_CONVERTED_IDS);
  });

  it('Lesson 5 converted SFS items have one -ing and one to + V example immediately after the trigger verb', () => {
    const lesson = loadLesson(LESSON_5);
    const byId = new Map<string, any>();
    for (const ex of lesson.exercises) {
      if (LESSON_5_CONVERTED_IDS.has(ex.exercise_id)) byId.set(ex.exercise_id, ex);
    }
    for (const { id, trigger } of LESSON_5_CONVERTED) {
      const ex = byId.get(id);
      expect(ex, `missing item ${id}`).toBeDefined();
      const examples: string[] = ex.accepted_examples ?? [];
      const ingPattern = new RegExp(`\\b${trigger}\\s+[a-z]+ing\\b`, 'i');
      const toPattern = new RegExp(`\\b${trigger}\\s+to\\s+[a-z]+\\b`, 'i');
      const hasIng = examples.some((s) => ingPattern.test(s));
      const hasTo = examples.some((s) => toPattern.test(s));
      expect(hasIng, `item ${id} accepted_examples missing immediate '${trigger} + Ving'`).toBe(true);
      expect(hasTo, `item ${id} accepted_examples missing immediate '${trigger} to + V'`).toBe(true);
    }
  });

  // ── Phase 3 — Lesson 4 meaning-contrast ─────────────────────────────────
  it('Lesson 4 ships exactly 5 SFS items at the expected exercise_ids', () => {
    const lesson = loadLesson(LESSON_4);
    const sfsIds = new Set<string>();
    for (const ex of lesson.exercises) {
      if (ex.type === 'short_free_sentence') sfsIds.add(ex.exercise_id);
    }
    const expected = new Set(LESSON_4_SFS.map((c) => c.id));
    expect(sfsIds).toEqual(expected);
  });

  it('Lesson 4 retired item …03d is no longer present', () => {
    const lesson = loadLesson(LESSON_4);
    const found = lesson.exercises.find(
      (ex: any) => ex.exercise_id === LESSON_4_RETIRED_ID,
    );
    expect(found, 'retired …03d must be removed').toBeUndefined();
  });

  it('Lesson 4 preserves the stop fill_blank pair (035 + 036) for contrast pedagogy', () => {
    const lesson = loadLesson(LESSON_4);
    const fbIds = new Set<string>();
    for (const ex of lesson.exercises) {
      if (ex.type === 'fill_blank') fbIds.add(ex.exercise_id);
    }
    for (const id of LESSON_4_FB_PRESERVED_IDS) {
      expect(fbIds.has(id), `expected fill_blank to survive at ${id}`).toBe(true);
    }
  });

  it('Lesson 4 SFS target_rule follows the strict 5-component contract', () => {
    const lesson = loadLesson(LESSON_4);
    const byId = new Map<string, any>();
    for (const ex of lesson.exercises) {
      if (ex.type === 'short_free_sentence') byId.set(ex.exercise_id, ex);
    }
    for (const { id, trigger, form } of LESSON_4_SFS) {
      const ex = byId.get(id);
      expect(ex, `missing item ${id}`).toBeDefined();
      const rule: string = ex.target_rule ?? '';
      // 1. trigger named (case-insensitive substring is fine — the rules
      //    use the lowercase form throughout).
      expect(rule.toLowerCase(), `item ${id} target_rule missing trigger`)
          .toContain(trigger.toLowerCase());
      // 2 + 3. "immediately" appears (immediate complement shape).
      expect(rule, `item ${id} target_rule missing "must be immediately"`)
          .toContain('must be immediately');
      // 4. rejected counter-form named (explicit "NOT the target" clause).
      expect(rule, `item ${id} target_rule missing "NOT the target"`)
          .toContain('NOT the target');
      // 5. explicit reject clause.
      expect(rule, `item ${id} target_rule missing "Reject answers"`)
          .toContain('Reject answers');
      // Target-form shape: the rule must name the specific form being tested.
      if (form === 'ing') {
        expect(rule, `item ${id} target_rule should name -ing form`)
            .toContain('-ing form');
      } else {
        expect(rule, `item ${id} target_rule should name to + base verb`)
            .toContain('to + base verb');
      }
    }
  });

  it('Lesson 4 SFS accepted_examples use the target form immediately after the trigger', () => {
    const lesson = loadLesson(LESSON_4);
    const byId = new Map<string, any>();
    for (const ex of lesson.exercises) {
      if (ex.type === 'short_free_sentence') byId.set(ex.exercise_id, ex);
    }
    for (const { id, trigger, form } of LESSON_4_SFS) {
      const ex = byId.get(id);
      const examples: string[] = ex.accepted_examples ?? [];
      expect(examples.length, `item ${id} should have 2 accepted_examples`).toBeGreaterThanOrEqual(2);
      // The trigger must be immediately followed by the target form in
      // BOTH examples — Lesson 4 is meaning-contrast, not dual-form,
      // so every example demonstrates the SAME target sense.
      const pattern = form === 'ing'
          ? new RegExp(`\\b${trigger}\\s+[a-z]+ing\\b`, 'i')
          : new RegExp(`\\b${trigger}\\s+to\\s+[a-z]+\\b`, 'i');
      for (const ex of examples) {
        expect(pattern.test(ex), `item ${id} example "${ex}" should use ${trigger} + ${form}`).toBe(true);
      }
    }
  });
});
