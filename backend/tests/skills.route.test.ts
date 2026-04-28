// Wave 12.7 — public /skills + /skills/:id route coverage.

import { describe, it, expect } from 'vitest';
import { createApp } from '../src/app';
import type { AiProvider } from '../src/ai/interface';
import { inject } from './helpers/inject';

const stubAi: AiProvider = {
  evaluateSentenceCorrection: () =>
    Promise.resolve({ correct: false, feedback: '' }),
};
const app = createApp(stubAi);

const SKILL_ING = 'verb-ing-after-gerund-verbs';
const SKILL_PPC = 'present-perfect-continuous-vs-simple';

describe('GET /skills', () => {
  it('returns all shipped skills with title + cefr_level + intro snapshot', async () => {
    const res = await inject(app, { method: 'GET', path: '/skills' });
    expect(res.status).toBe(200);
    const body = res.json as Array<Record<string, unknown>>;
    expect(Array.isArray(body)).toBe(true);
    // Wave 10.5 shipped 5 skills (4 U01 sibling + present perfect).
    expect(body.length).toBe(5);

    for (const dto of body) {
      expect(typeof dto.skill_id).toBe('string');
      expect(typeof dto.title).toBe('string');
      expect((dto.title as string).length).toBeGreaterThan(0);
      expect(['A1', 'A2', 'B1', 'B2', 'C1', 'C2']).toContain(dto.cefr_level);
      // Every shipped skill has an intro_rule + at least one example
      // joined from its source lesson.
      expect(typeof dto.intro_rule).toBe('string');
      expect((dto.intro_rule as string).length).toBeGreaterThan(0);
      expect(Array.isArray(dto.intro_examples)).toBe(true);
      expect((dto.intro_examples as string[]).length).toBeGreaterThan(0);
    }
  });

  it('skill ids cover the shipped registry', async () => {
    const res = await inject(app, { method: 'GET', path: '/skills' });
    const ids = (res.json as Array<{ skill_id: string }>).map(
      (s) => s.skill_id
    );
    expect(ids).toContain(SKILL_ING);
    expect(ids).toContain(SKILL_PPC);
  });
});

describe('GET /skills/:skillId', () => {
  it('returns the matching skill', async () => {
    const res = await inject(app, {
      method: 'GET',
      path: `/skills/${SKILL_ING}`,
    });
    expect(res.status).toBe(200);
    const body = res.json as any;
    expect(body.skill_id).toBe(SKILL_ING);
    expect(body.title).toBe('Verb + -ing after gerund-taking verbs');
    expect(body.cefr_level).toBe('B2');
    expect(typeof body.intro_rule).toBe('string');
    expect(body.intro_rule).toContain('-ing');
  });

  it('returns 404 for an unknown skill_id', async () => {
    const res = await inject(app, {
      method: 'GET',
      path: '/skills/no-such-skill',
    });
    expect(res.status).toBe(404);
    expect((res.json as any).error).toBe('skill_not_found');
  });
});
