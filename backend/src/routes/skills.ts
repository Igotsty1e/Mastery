import { Router } from 'express';
import { getAllSkills } from '../data/skills';
import { getEntriesForSkill } from '../data/exerciseBank';
import { getLessonById } from '../data/lessons';
import type { RuleCard } from '../data/lessons';

// Wave 12.7 — public read-only `/skills` route. Source of truth for
// the client's display names + the dashboard Rules library card. The
// title and description live in `backend/data/skills.json`; the
// `intro_rule` and `intro_examples` are joined from the source lesson
// of the FIRST bank entry tagged with that skill.
//
// Why this route is public (no auth): the rules are pedagogical
// reference material, identical for every learner, and the dashboard
// reads them on first paint before the AuthClient is attached.
// Mirrors the Wave 8 carve-out for `GET /lessons` and `GET
// /lessons/:id`.
//
// V1.6 limitation: the skill → source-lesson join picks the first
// lesson_refs entry. If a skill is exercised across multiple lessons
// (Wave 10.5 didn't ship that, but Wave 11/12 might), the route still
// returns one snapshot. Refactor to surface multiple lesson refs when
// the bank actually has them.

interface SkillDto {
  skill_id: string;
  title: string;
  description: string | null;
  cefr_level: string;
  intro_rule: string | null;
  intro_examples: string[];
  rule_card: RuleCard | null;
}

function buildSkillDto(skillId: string): SkillDto | null {
  const skill = getAllSkills().find((s) => s.skill_id === skillId);
  if (!skill) return null;

  // Prefer lesson_refs from the registry; fall back to the first bank
  // entry tagged with this skill. Both should converge on the same
  // lesson today, but lesson_refs is authoritative when content
  // expansion adds skills before the bank reindexes.
  let intro_rule: string | null = null;
  let intro_examples: string[] = [];
  let rule_card: RuleCard | null = null;
  const sourceLessonId = skill.lesson_refs[0] ?? null;
  let sourceLesson = sourceLessonId ? getLessonById(sourceLessonId) : undefined;
  if (!sourceLesson) {
    const fallback = getEntriesForSkill(skillId)[0];
    if (fallback) sourceLesson = getLessonById(fallback.sourceLessonId);
  }
  if (sourceLesson) {
    intro_rule = sourceLesson.intro_rule;
    intro_examples = [...sourceLesson.intro_examples];
    rule_card = sourceLesson.rule_card ?? null;
  }

  return {
    skill_id: skill.skill_id,
    title: skill.title,
    description: skill.description ?? null,
    cefr_level: skill.cefr_level,
    intro_rule,
    intro_examples,
    rule_card,
  };
}

export function makeSkillsRouter(): Router {
  const router = Router();

  router.get('/skills', (_req, res) => {
    const skills = getAllSkills();
    const dtos = skills
      .map((s) => buildSkillDto(s.skill_id))
      .filter((d): d is SkillDto => d !== null);
    res.json(dtos);
  });

  router.get('/skills/:skillId', (req, res) => {
    const dto = buildSkillDto(req.params.skillId);
    if (!dto) {
      res.status(404).json({ error: 'skill_not_found' });
      return;
    }
    res.json(dto);
  });

  return router;
}
