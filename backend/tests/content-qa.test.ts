// Wave 14.7 — Content QA agent rubric coverage.
//
// The CLI driver in `backend/scripts/qa-content.ts` is integration-only
// (hits OpenAI). The pure helpers below — criteria selector + verdict
// aggregator + prompt builder — carry the load-bearing logic and need
// unit tests.

import { describe, expect, it } from 'vitest';

import {
  type CriterionResult,
  aggregateVerdict,
  buildReviewPrompt,
  criteriaForType,
} from '../src/content-qa/rubric';

describe('criteriaForType', () => {
  it('always includes the four common criteria', () => {
    const fillBlank = criteriaForType('fill_blank');
    const ids = fillBlank.map((c) => c.id);
    expect(ids).toContain('rule_alignment');
    expect(ids).toContain('natural_english');
    expect(ids).toContain('target_error_match');
    expect(ids).toContain('evidence_tier_defensible');
  });

  it('adds fill_blank-specific criteria for fill_blank items', () => {
    const ids = criteriaForType('fill_blank').map((c) => c.id);
    expect(ids).toContain('answer_coverage');
    expect(ids).toContain('unambiguous_blank');
  });

  it('adds multiple_choice-specific criteria for MC items', () => {
    const ids = criteriaForType('multiple_choice').map((c) => c.id);
    expect(ids).toContain('distractor_plausibility');
    expect(ids).toContain('distractor_diversity');
    expect(ids).toContain('single_correct');
  });

  it('adds sentence_correction criteria including the no-no-error-decoy rule', () => {
    const ids = criteriaForType('sentence_correction').map((c) => c.id);
    expect(ids).toContain('single_target_error');
    expect(ids).toContain('bounded_corrections');
  });

  it('adds sentence_rewrite criteria with the bounded-rewrites cap', () => {
    const ids = criteriaForType('sentence_rewrite').map((c) => c.id);
    expect(ids).toContain('bounded_rewrites');
    expect(ids).toContain('transformation_targeted');
  });

  it('adds short_free_sentence criteria covering target_rule clarity', () => {
    const ids = criteriaForType('short_free_sentence').map((c) => c.id);
    expect(ids).toContain('target_rule_clarity');
    expect(ids).toContain('instruction_bounded');
    expect(ids).toContain('accepted_examples_quality');
  });

  it('encodes §8.4.1 safeguards for the planned multi_* families', () => {
    const multiBlank = criteriaForType('multi_blank').map((c) => c.id);
    expect(multiBlank).toContain('no_interdependent_blanks');

    const multiSelect = criteriaForType('multi_select').map((c) => c.id);
    expect(multiSelect).toContain('non_gameable');

    const multiCorrection = criteriaForType('multi_error_correction').map(
      (c) => c.id
    );
    expect(multiCorrection).toContain('same_skill_rollup');
    expect(multiCorrection).toContain('no_no_error_decoy');
  });

  it('falls back to common-only criteria for unknown types', () => {
    const ids = criteriaForType('does_not_exist').map((c) => c.id);
    expect(ids).toEqual([
      'rule_alignment',
      'natural_english',
      'target_error_match',
      'evidence_tier_defensible',
    ]);
  });
});

const ok = (note = 'fine'): CriterionResult => ({
  ok: true,
  severity: 'ok',
  note,
});
const minor = (note = 'borderline'): CriterionResult => ({
  ok: false,
  severity: 'minor',
  note,
});
const major = (note = 'broken'): CriterionResult => ({
  ok: false,
  severity: 'major',
  note,
});

describe('aggregateVerdict', () => {
  it('returns pass when every criterion is ok', () => {
    expect(
      aggregateVerdict({
        a: ok(),
        b: ok(),
        c: ok(),
      })
    ).toBe('pass');
  });

  it('returns revise when any criterion is minor (and none major)', () => {
    expect(
      aggregateVerdict({
        a: ok(),
        b: minor(),
        c: ok(),
      })
    ).toBe('revise');
  });

  it('returns reject when any criterion is major (even if other minors exist)', () => {
    expect(
      aggregateVerdict({
        a: ok(),
        b: minor(),
        c: major(),
      })
    ).toBe('reject');
  });

  it('returns reject when only one criterion exists and it is major', () => {
    expect(aggregateVerdict({ a: major() })).toBe('reject');
  });

  it('returns pass for an empty rubric (no criteria observed) — caller decides what that means', () => {
    expect(aggregateVerdict({})).toBe('pass');
  });
});

describe('buildReviewPrompt', () => {
  const item = {
    exercise_id: 'REPLACE-WITH-UUID-1',
    type: 'fill_blank',
    skill_id: 'verb-ing-after-gerund-verbs',
    prompt: 'I enjoy ___ in the park.',
    accepted_answers: ['walking', 'running'],
    primary_target_error: 'form_error',
    evidence_tier: 'medium',
  };

  const criteria = criteriaForType('fill_blank');

  it('embeds the candidate JSON verbatim so the reviewer sees the literal item', () => {
    const prompt = buildReviewPrompt({
      skill: 'verb-ing-after-gerund-verbs',
      type: 'fill_blank',
      item,
      criteria,
    });
    expect(prompt).toContain('I enjoy ___ in the park.');
    expect(prompt).toContain('"primary_target_error": "form_error"');
  });

  it('lists every criterion id + question so the model knows what to score', () => {
    const prompt = buildReviewPrompt({
      skill: 'verb-ing-after-gerund-verbs',
      type: 'fill_blank',
      item,
      criteria,
    });
    for (const c of criteria) {
      expect(prompt).toContain(c.id);
      expect(prompt).toContain(c.question);
    }
  });

  it('marks the reviewer identity (not the generator) explicitly in the framing', () => {
    const prompt = buildReviewPrompt({
      skill: 'verb-ing-after-gerund-verbs',
      type: 'fill_blank',
      item,
      criteria,
    });
    expect(prompt).toContain('INDEPENDENT REVIEWER');
    expect(prompt).toContain('did NOT generate');
  });

  it('declares a strict JSON output contract with severity enum', () => {
    const prompt = buildReviewPrompt({
      skill: 'verb-ing-after-gerund-verbs',
      type: 'fill_blank',
      item,
      criteria,
    });
    expect(prompt).toContain('strict JSON');
    expect(prompt).toContain('"severity": "<ok|minor|major>"');
    expect(prompt).toContain('"summary"');
  });
});
