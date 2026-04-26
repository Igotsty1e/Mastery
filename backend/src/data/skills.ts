import fs from 'fs';
import path from 'path';
import { z } from 'zod';
import { TargetErrorSchema, EvidenceTierSchema } from './lessonSchema';

// Skill graph registry per LEARNING_ENGINE.md §4.2 + §6 evidence model.
// Wave 1 (additive): the file is loaded if present; the runtime does not
// require it yet, so absence yields an empty registry. Future engine
// waves (Mastery Model, Decision Engine) will tighten this contract.

const CefrLevelSchema = z.enum(['A1', 'A2', 'B1', 'B2', 'C1', 'C2']);

export const SkillSchema = z.object({
  skill_id: z.string().min(1),
  title: z.string().min(1),
  cefr_level: CefrLevelSchema,
  prerequisites: z.array(z.string().min(1)).default([]),
  contrasts_with: z.array(z.string().min(1)).default([]),
  target_errors: z.array(TargetErrorSchema).default([]),
  mastery_signals: z.array(EvidenceTierSchema).default([]),
  // Authoring metadata carried by the shipped registry. Future engine
  // waves (Mastery Model) consume `lesson_refs` to know which lessons
  // exercise which skills; `description` is human-readable rationale.
  // Optional during Wave 1 — declared so Zod stops silently dropping them.
  description: z.string().min(1).optional(),
  lesson_refs: z.array(z.string().min(1)).default([]),
});

export const SkillsRegistrySchema = z
  .object({
    // Top-level authoring metadata. Optional and runtime-ignored in Wave 1;
    // declared so the registry's own provenance fields survive parsing.
    version: z.string().min(1).optional(),
    engine_spec_ref: z.string().min(1).optional(),
    notes: z.string().min(1).optional(),
    skills: z.array(SkillSchema).default([]),
  })
  .superRefine((value, ctx) => {
    const ids = new Set<string>();
    value.skills.forEach((skill, index) => {
      if (ids.has(skill.skill_id)) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: `duplicate skill_id: ${skill.skill_id}`,
          path: ['skills', index, 'skill_id'],
        });
      }
      ids.add(skill.skill_id);
    });

    const declared = new Set(value.skills.map((s) => s.skill_id));
    value.skills.forEach((skill, index) => {
      skill.prerequisites.forEach((p, pi) => {
        if (!declared.has(p)) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: `prerequisite ${p} is not a declared skill`,
            path: ['skills', index, 'prerequisites', pi],
          });
        }
      });
      skill.contrasts_with.forEach((c, ci) => {
        if (!declared.has(c)) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: `contrasts_with ${c} is not a declared skill`,
            path: ['skills', index, 'contrasts_with', ci],
          });
        }
      });
      if (skill.prerequisites.includes(skill.skill_id)) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: 'a skill cannot list itself as a prerequisite',
          path: ['skills', index, 'prerequisites'],
        });
      }
    });
  });

export type Skill = z.infer<typeof SkillSchema>;
export type SkillsRegistry = z.infer<typeof SkillsRegistrySchema>;

export function parseSkillsRegistry(value: unknown, source: string): SkillsRegistry {
  const parsed = SkillsRegistrySchema.safeParse(value);
  if (!parsed.success) {
    throw new Error(
      `Invalid skills registry in ${source}: ${parsed.error.issues
        .map((i) => `${i.path.join('.') || '<root>'}: ${i.message}`)
        .join('; ')}`
    );
  }
  return parsed.data;
}

const REGISTRY_PATH = path.resolve(__dirname, '../../data/skills.json');

let CACHED_REGISTRY: SkillsRegistry | null = null;
let CACHED_INDEX: Map<string, Skill> | null = null;

function loadRegistry(): SkillsRegistry {
  if (!fs.existsSync(REGISTRY_PATH)) {
    return { skills: [] };
  }
  const raw = fs.readFileSync(REGISTRY_PATH, 'utf8');
  return parseSkillsRegistry(JSON.parse(raw), REGISTRY_PATH);
}

function getRegistry(): SkillsRegistry {
  if (!CACHED_REGISTRY) {
    CACHED_REGISTRY = loadRegistry();
    CACHED_INDEX = new Map(CACHED_REGISTRY.skills.map((s) => [s.skill_id, s]));
  }
  return CACHED_REGISTRY;
}

export function getAllSkills(): Skill[] {
  return getRegistry().skills;
}

export function getSkillById(id: string): Skill | undefined {
  getRegistry();
  return CACHED_INDEX?.get(id);
}

export function hasSkillsRegistry(): boolean {
  return getRegistry().skills.length > 0;
}

// Test-only: clear the in-process cache so a freshly written fixture is
// re-read on the next call.
export function _resetSkillsRegistryCacheForTests(): void {
  CACHED_REGISTRY = null;
  CACHED_INDEX = null;
}
