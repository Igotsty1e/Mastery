// Wave H3 phase 2 — pin the shipped shape of the converted Lesson 3 + 5
// fixtures. Two contracts:
//   1. The full lesson JSONs parse cleanly through LessonSchema after
//      the SFS conversions; this catches missing/renamed fields that
//      the broader test suite would otherwise miss because it doesn't
//      load 003/005 by name.
//   2. Every Lesson 5 short_free_sentence in the wave-converted set
//      carries the dual-form rule shape in target_rule. Without those
//      substrings, the production grader at backend/src/ai/openai.ts
//      cannot recognise both forms as correct (the prompt body does
//      not currently include accepted_examples).
import fs from 'node:fs';
import path from 'node:path';
import { describe, it, expect } from 'vitest';
import { LessonSchema } from '../src/data/lessonSchema';

const LESSON_3 = 'b2-lesson-003.json';
const LESSON_5 = 'b2-lesson-005.json';

// Wave H3 phase 2 converted IDs in Lesson 5 with the trigger word the
// dual-form rule keys off. The accepted_examples assertion checks that
// the trigger is immediately followed by either a verb-ing form or
// `to + base verb` — not just any -ing or `to` anywhere in the sentence.
const LESSON_5_CONVERTED: Array<{ id: string; trigger: string }> = [
  { id: 'a1b2c3d4-0005-4000-8000-000000000031', trigger: 'like' },
  { id: 'a1b2c3d4-0005-4000-8000-000000000033', trigger: 'love' },
  { id: 'a1b2c3d4-0005-4000-8000-000000000034', trigger: 'hate' },
  { id: 'a1b2c3d4-0005-4000-8000-000000000038', trigger: 'began' },
];
const LESSON_5_CONVERTED_IDS = new Set(LESSON_5_CONVERTED.map((c) => c.id));

function loadLesson(file: string): any {
  const fp = path.resolve(__dirname, '../data/lessons', file);
  return JSON.parse(fs.readFileSync(fp, 'utf8'));
}

describe('Wave H3 phase 2 — lesson fixtures parse + dual-form rule shape', () => {
  it('b2-lesson-003.json parses cleanly through LessonSchema', () => {
    const parsed = LessonSchema.safeParse(loadLesson(LESSON_3));
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
      // Trigger may carry the contracted "I'd" / capitalised start; we
      // match the trigger token as a whole word followed by a single
      // space. The complement must be EITHER an `-ing` form (...ing<space>)
      // OR `to <base-verb>` immediately after the trigger.
      const ingPattern = new RegExp(`\\b${trigger}\\s+[a-z]+ing\\b`, 'i');
      const toPattern = new RegExp(`\\b${trigger}\\s+to\\s+[a-z]+\\b`, 'i');
      const hasIng = examples.some((s) => ingPattern.test(s));
      const hasTo = examples.some((s) => toPattern.test(s));
      expect(hasIng, `item ${id} accepted_examples missing immediate '${trigger} + Ving'`).toBe(true);
      expect(hasTo, `item ${id} accepted_examples missing immediate '${trigger} to + V'`).toBe(true);
    }
  });
});
