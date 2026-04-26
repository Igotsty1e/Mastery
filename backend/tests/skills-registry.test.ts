import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import {
  SkillsRegistrySchema,
  parseSkillsRegistry,
  getAllSkills,
  hasSkillsRegistry,
  _resetSkillsRegistryCacheForTests,
} from '../src/data/skills';
import { getAllLessons } from '../src/data/lessons';

describe('SkillsRegistrySchema', () => {
  const baseSkill = {
    skill_id: 'verbs.suggest_ing',
    title: 'After "suggest", use -ing',
    cefr_level: 'B2',
    prerequisites: [],
    contrasts_with: [],
    target_errors: ['form_error'],
    mastery_signals: ['medium', 'strong'],
  };

  it('parses an empty registry', () => {
    const parsed = SkillsRegistrySchema.safeParse({ skills: [] });
    expect(parsed.success).toBe(true);
  });

  it('parses a registry with valid skills', () => {
    const parsed = SkillsRegistrySchema.safeParse({
      skills: [
        baseSkill,
        {
          ...baseSkill,
          skill_id: 'verbs.recommend_ing',
          title: 'After "recommend", use -ing',
          prerequisites: ['verbs.suggest_ing'],
          contrasts_with: ['verbs.suggest_ing'],
        },
      ],
    });
    expect(parsed.success).toBe(true);
  });

  it('defaults missing array fields to []', () => {
    const minimal = {
      skill_id: 'verbs.bare',
      title: 'Bare skill',
      cefr_level: 'A2',
    };
    const parsed = SkillsRegistrySchema.safeParse({ skills: [minimal] });
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      const skill = parsed.data.skills[0];
      expect(skill.prerequisites).toEqual([]);
      expect(skill.contrasts_with).toEqual([]);
      expect(skill.target_errors).toEqual([]);
      expect(skill.mastery_signals).toEqual([]);
    }
  });

  it('rejects missing required fields', () => {
    const parsed = SkillsRegistrySchema.safeParse({
      skills: [{ skill_id: 'no.title', cefr_level: 'B1' }],
    });
    expect(parsed.success).toBe(false);
  });

  it('rejects unknown cefr_level values', () => {
    const parsed = SkillsRegistrySchema.safeParse({
      skills: [{ ...baseSkill, cefr_level: 'X9' }],
    });
    expect(parsed.success).toBe(false);
  });

  it('rejects unknown target_errors codes', () => {
    const parsed = SkillsRegistrySchema.safeParse({
      skills: [{ ...baseSkill, target_errors: ['spelling_error'] }],
    });
    expect(parsed.success).toBe(false);
  });

  it('rejects duplicate skill_id values', () => {
    const parsed = SkillsRegistrySchema.safeParse({
      skills: [baseSkill, baseSkill],
    });
    expect(parsed.success).toBe(false);
  });

  it('rejects prerequisites that reference unknown skills', () => {
    const parsed = SkillsRegistrySchema.safeParse({
      skills: [
        {
          ...baseSkill,
          prerequisites: ['verbs.does_not_exist'],
        },
      ],
    });
    expect(parsed.success).toBe(false);
  });

  it('rejects contrasts_with that reference unknown skills', () => {
    const parsed = SkillsRegistrySchema.safeParse({
      skills: [
        {
          ...baseSkill,
          contrasts_with: ['verbs.also_missing'],
        },
      ],
    });
    expect(parsed.success).toBe(false);
  });

  it('rejects a skill that lists itself as a prerequisite', () => {
    const parsed = SkillsRegistrySchema.safeParse({
      skills: [
        {
          ...baseSkill,
          prerequisites: [baseSkill.skill_id],
        },
      ],
    });
    expect(parsed.success).toBe(false);
  });

  it('parseSkillsRegistry throws with a detailed message on invalid input', () => {
    expect(() =>
      parseSkillsRegistry(
        { skills: [{ skill_id: 'a', title: 'A', cefr_level: 'X9' }] },
        'test-registry.json'
      )
    ).toThrow(/test-registry\.json/);
  });

  it('parseSkillsRegistry returns parsed data on valid input', () => {
    const data = parseSkillsRegistry({ skills: [baseSkill] }, 'fixture.json');
    expect(data.skills).toHaveLength(1);
    expect(data.skills[0].skill_id).toBe(baseSkill.skill_id);
  });
});

// File-presence behaviour: the registry file is owned by the content
// pipeline and may not exist yet during the additive Wave 1 rollout. The
// loader must tolerate that without throwing.
describe('skills registry file loader', () => {
  const registryPath = path.resolve(__dirname, '../data/skills.json');

  it('returns an empty registry when skills.json is absent', () => {
    const existed = fs.existsSync(registryPath);
    let backup: string | null = null;
    if (existed) {
      backup = fs.readFileSync(registryPath, 'utf8');
      fs.unlinkSync(registryPath);
    }
    try {
      _resetSkillsRegistryCacheForTests();
      expect(hasSkillsRegistry()).toBe(false);
      expect(getAllSkills()).toEqual([]);
    } finally {
      if (backup !== null) {
        fs.writeFileSync(registryPath, backup);
      }
      _resetSkillsRegistryCacheForTests();
    }
  });
});

// Cross-reference contract per docs/content-contract.md §1.2: any
// exercise.skill_id present on a shipped lesson must be declared in the
// registry. LessonSchema does not couple to the registry at parse time —
// this test runs the check in CI so drift is caught before merge.
describe('skills registry cross-reference', () => {
  it('every shipped exercise.skill_id is declared in skills.json', () => {
    _resetSkillsRegistryCacheForTests();
    const declared = new Set(getAllSkills().map((s) => s.skill_id));
    const undeclared: Array<{ lesson: string; exercise: string; skill_id: string }> = [];
    for (const lesson of getAllLessons()) {
      for (const ex of lesson.exercises) {
        if (ex.skill_id && !declared.has(ex.skill_id)) {
          undeclared.push({
            lesson: lesson.lesson_id,
            exercise: ex.exercise_id,
            skill_id: ex.skill_id,
          });
        }
      }
    }
    expect(undeclared).toEqual([]);
  });
});
