// Wave 11 — runtime exercise bank.
//
// The V1 spec (`docs/plans/learning-engine-v1.md` decision #3) makes the
// Decision Engine the unit of delivery: each session is assembled
// dynamically from a bank, not pulled from a fixed lesson JSON. We keep
// the existing per-lesson JSON files as the **authoring** format —
// authors and the `english-grammar-methodologist` skill continue to
// produce content in that shape — but the runtime flattens all
// lessons' exercises into a single bank index at boot.
//
// Lesson JSON stops being addressable by id from the API surface; the
// only consumers of `getLessonById` / `getAllLessons` left after
// Wave 11 are this module and the bulk-import / lesson-sessions paths
// that need lesson-version + content-hash traceability for the
// `lesson_sessions` row stamp.

import { getAllLessons, getAllLessonMeta, type Exercise, type LessonMeta } from './lessons';

export type EvidenceTier = 'weak' | 'medium' | 'strong' | 'strongest';

/// Wave 14.2 phase 2 — runtime client-support gate for the bank.
///
/// Exercise types listed here are renderable by every shipped Flutter
/// build. Authored items of any other type are still kept in the
/// source lesson JSON (and reachable by id via `getBankEntry`) but are
/// excluded from the per-skill index + the flat list the Decision
/// Engine reads from. This lets us land authoring (`sentence_rewrite`
/// items in the bank) before the matching widget ships in phase 3
/// without the engine handing the client an item it cannot render.
///
/// To turn on a new type at runtime: add it here in lockstep with the
/// Flutter widget that renders it. Removing a type would silently
/// strand existing learner records — don't do that without a
/// migration plan.
export const RUNTIME_SUPPORTED_EXERCISE_TYPES: ReadonlySet<Exercise['type']> =
  new Set([
    'fill_blank',
    'multiple_choice',
    'sentence_correction',
    'sentence_rewrite',
    'short_free_sentence',
    'listening_discrimination',
  ]);

export interface BankEntry {
  /// Raw exercise object as stored in the source lesson JSON. Routes
  /// `/sessions/:id/next` and `/sessions/:id/answers` already speak
  /// this shape via `projectExerciseForClient`.
  exercise: Exercise;
  /// `(unit_id, rule_tag)` pair the source lesson tagged this exercise
  /// with. Decision Engine reads `rule_tag` for the current "topic"
  /// concept (V1 MVP only ships one topic — B2 mixed practice — so
  /// the field is informational today).
  unitId: string | null;
  ruleTag: string | null;
  microRuleTag: string | null;
  /// Source lesson_id — kept so attempt rows can stamp it on the
  /// `lesson_sessions` row for replay traceability.
  sourceLessonId: string;
  sourceLessonVersion: string;
  sourceContentHash: string;
  /// Seven-bit checksum of the source position so a deterministic
  /// "give me a stable order for skill X" call returns the same
  /// shuffle every time.
  positionInSource: number;
}

function buildIndex(): {
  bySkill: Map<string, BankEntry[]>;
  byExerciseId: Map<string, BankEntry>;
  diagnosticPool: BankEntry[];
  flat: BankEntry[];
} {
  const bySkill = new Map<string, BankEntry[]>();
  const byExerciseId = new Map<string, BankEntry>();
  const diagnosticPool: BankEntry[] = [];
  const flat: BankEntry[] = [];

  const lessons = getAllLessons();
  const metaList = getAllLessonMeta();
  const metaById = new Map<string, LessonMeta>(
    metaList.map((m) => [m.lesson_id, m])
  );

  for (const lesson of lessons) {
    const meta = metaById.get(lesson.lesson_id);
    if (!meta) continue;
    lesson.exercises.forEach((exercise, idx) => {
      const entry: BankEntry = {
        exercise,
        unitId: meta.unit_id,
        ruleTag: meta.rule_tag,
        microRuleTag: meta.micro_rule_tag,
        sourceLessonId: lesson.lesson_id,
        sourceLessonVersion: meta.lesson_version,
        sourceContentHash: meta.content_hash,
        positionInSource: idx,
      };
      // Always index by id — answer / result paths look entries up by
      // their exercise_id and the lookup must succeed even for items
      // the engine is not currently allowed to serve. Phase 3 turns
      // these on by adding the type to RUNTIME_SUPPORTED_EXERCISE_TYPES.
      byExerciseId.set(exercise.exercise_id, entry);
      if (!RUNTIME_SUPPORTED_EXERCISE_TYPES.has(exercise.type)) return;
      flat.push(entry);
      const skillId = exercise.skill_id;
      if (skillId) {
        const arr = bySkill.get(skillId) ?? [];
        arr.push(entry);
        bySkill.set(skillId, arr);
      }
      // V1 spec §15: diagnostic exercises share the bank, marked by
      // an authoring-time `is_diagnostic` flag (Wave 12). Items remain
      // eligible for regular sessions; the flag only governs probe
      // inclusion. `getDiagnosticPool()` falls back to the first 5
      // flat entries when no items are tagged so the probe path can
      // boot on a partially-tagged bank.
      if (exercise.is_diagnostic === true) diagnosticPool.push(entry);
    });
  }

  return { bySkill, byExerciseId, diagnosticPool, flat };
}

const INDEX = buildIndex();

export function getBankEntry(exerciseId: string): BankEntry | undefined {
  return INDEX.byExerciseId.get(exerciseId);
}

export function getEntriesForSkill(skillId: string): BankEntry[] {
  return INDEX.bySkill.get(skillId) ?? [];
}

export function getAllBankEntries(): BankEntry[] {
  return INDEX.flat;
}

export function getDiagnosticPool(): BankEntry[] {
  // Wave 11: until authoring sets `is_diagnostic`, fall back to the
  // first five flat entries so the diagnostic flow can still ship.
  if (INDEX.diagnosticPool.length > 0) return INDEX.diagnosticPool;
  return INDEX.flat.slice(0, 5);
}

export function listSkills(): string[] {
  return [...INDEX.bySkill.keys()];
}

export function bankSize(): number {
  return INDEX.flat.length;
}
