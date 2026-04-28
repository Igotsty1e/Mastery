/**
 * Wave 14.7 — Content QA agent (V1.5 §20 second half).
 *
 * Pure rubric helpers for the offline QA reviewer pass that runs over
 * a `gen-content.ts` staging file. The CLI driver lives in
 * `backend/scripts/qa-content.ts`; this module is the testable core.
 *
 * Authoritative spec:
 * - `LEARNING_ENGINE.md §12.2` (Two-Agent QA — generator + reviewer
 *   identities, must record rule / target error / evidence tier /
 *   distractor logic / verdict).
 * - `LEARNING_ENGINE.md §8.4.1` (per-family safeguards: bounded answer
 *   space, no interdependent blanks, no-error decoy rule, etc.).
 * - `exercise_structure.md §§5.1, 5.5, 5.6, 5.7, 5.8` (authoring
 *   contracts per family).
 *
 * The reviewer is a *different identity* than the generator: a
 * different system prompt, optionally a different model family. The
 * methodologist remains the human-in-the-loop gate before items move
 * from `staging/` into `lessons/`.
 */

export type Verdict = 'pass' | 'revise' | 'reject';

export type Severity = 'ok' | 'minor' | 'major';

export interface Criterion {
  id: string;
  question: string;
}

export interface CriterionResult {
  ok: boolean;
  severity: Severity;
  note: string;
}

export interface ItemQa {
  verdict: Verdict;
  criteria: Record<string, CriterionResult>;
  summary: string;
  reviewer_model: string;
}

const COMMON_CRITERIA: Criterion[] = [
  {
    id: 'rule_alignment',
    question:
      'Does this item force the learner to apply the declared skill_id rule, or could it be solved by surface pattern-matching without engaging that rule?',
  },
  {
    id: 'natural_english',
    question:
      'Is the English natural at the declared CEFR level — no awkward, archaic, contrived, or implausible phrasing?',
  },
  {
    id: 'target_error_match',
    question:
      'Does primary_target_error correctly name the failure mode this item is designed to expose? (form / contrast / conceptual / careless)',
  },
  {
    id: 'evidence_tier_defensible',
    question:
      'Is evidence_tier defensible? `strongest` items must require meaning-coupled production with a `meaning_frame`; weak items must not be marked stronger than they earn.',
  },
];

const TYPE_CRITERIA: Record<string, Criterion[]> = {
  fill_blank: [
    {
      id: 'answer_coverage',
      question:
        'Do accepted_answers cover the obvious natural variants a competent learner might write (contractions, equivalent forms)?',
    },
    {
      id: 'unambiguous_blank',
      question:
        'Is the blank unambiguous? Exactly one rule applies, and the surrounding context disambiguates the answer without requiring outside knowledge.',
    },
  ],
  multiple_choice: [
    {
      id: 'distractor_plausibility',
      question:
        'Is each distractor plausible-but-wrong — the kind of mistake a real B2 learner makes — not silly, off-topic, or trivially eliminable?',
    },
    {
      id: 'distractor_diversity',
      question:
        'Do distractors target distinct learner errors? No two distractors should be paraphrases or surface variants of each other.',
    },
    {
      id: 'single_correct',
      question:
        'Is exactly one option correct, with the other options unambiguously wrong under any reasonable reading?',
    },
  ],
  sentence_correction: [
    {
      id: 'single_target_error',
      question:
        'Does the original sentence contain exactly one teacher-marked error tied to the target skill — not two errors, not zero (no-error decoy is forbidden here)?',
    },
    {
      id: 'bounded_corrections',
      question:
        'Is accepted_corrections small (≤5) and well-justified? Could a learner reasonably write a correct rewrite that is NOT in accepted_corrections?',
    },
  ],
  sentence_rewrite: [
    {
      id: 'bounded_rewrites',
      question:
        'Is accepted_rewrites ≤3 and reasonably exhaustive of the natural rewrites a learner might produce under the declared skill?',
    },
    {
      id: 'transformation_targeted',
      question:
        'Does the rewrite instruction force application of the declared skill, not generic paraphrase or vocabulary substitution?',
    },
  ],
  short_free_sentence: [
    {
      id: 'target_rule_clarity',
      question:
        'Is target_rule unambiguous enough for an AI evaluator to judge grammaticality + rule conformance reliably, without sliding into stylistic taste?',
    },
    {
      id: 'instruction_bounded',
      question:
        'Is the learner instruction tight enough to bound the answer space? A learner cannot write something grammatical-but-unrelated and have it pass.',
    },
    {
      id: 'accepted_examples_quality',
      question:
        'Are accepted_examples natural, varied, and aligned with target_rule — and not so few that the AI evaluator has nothing to anchor against?',
    },
  ],
  multi_blank: [
    {
      id: 'no_interdependent_blanks',
      question:
        'Are the blanks independent? §8.4.1 forbids one blank whose answer depends on another blank — each must be solvable from the surrounding context alone.',
    },
    {
      id: 'answer_coverage',
      question:
        'For each blank, do accepted_answers cover the obvious natural variants?',
    },
  ],
  multi_select: [
    {
      id: 'non_gameable',
      question:
        'Is the scoring non-gameable? §8.4.1 forbids letting the learner score by selecting all options or none — partial credit must require deliberate selection.',
    },
    {
      id: 'distractor_plausibility',
      question:
        'Is each non-correct option plausible-but-wrong, not trivially eliminable?',
    },
  ],
  multi_error_correction: [
    {
      id: 'same_skill_rollup',
      question:
        'Do all flagged errors in the sentence target the same primary skill / target_error? §8.4.1 forbids mixing skills in one item.',
    },
    {
      id: 'no_no_error_decoy',
      question:
        'Does the sentence actually contain at least one error? §8.4.1 forbids no-error decoys here.',
    },
  ],
};

export function criteriaForType(type: string): Criterion[] {
  return [...COMMON_CRITERIA, ...(TYPE_CRITERIA[type] ?? [])];
}

export function aggregateVerdict(
  criteria: Record<string, CriterionResult>
): Verdict {
  const severities = Object.values(criteria).map((c) => c.severity);
  if (severities.includes('major')) return 'reject';
  if (severities.includes('minor')) return 'revise';
  return 'pass';
}

export function buildReviewPrompt(args: {
  skill: string;
  type: string;
  item: Record<string, unknown>;
  criteria: Criterion[];
}): string {
  const lines: string[] = [
    `You are an INDEPENDENT REVIEWER of a single English-grammar exercise candidate. You did NOT generate this item. Your job is to verify it against the criteria below and flag every issue. Be strict — your default disposition is skeptical.`,
    '',
    `Skill (declared): ${args.skill}`,
    `Type: ${args.type}`,
    '',
    `[CANDIDATE]`,
    JSON.stringify(args.item, null, 2),
    '',
    `[CRITERIA]`,
    ...args.criteria.map((c) => `- ${c.id}: ${c.question}`),
    '',
    `For each criterion return:`,
    `- "ok": boolean — true only if the criterion is fully satisfied`,
    `- "severity": "ok" if satisfied, "minor" if needs revision but not broken, "major" if the item must be rejected or rewritten`,
    `- "note": one short sentence explaining your call. Point at the exact phrase, option, or field — never generic.`,
    '',
    `Then return "summary": one sentence on the most important issue, or the literal string "looks defensible" if no issues.`,
    '',
    `Output strict JSON only — no prose outside JSON:`,
    `{`,
    `  "criteria": {`,
    `    "<criterion_id>": { "ok": <bool>, "severity": "<ok|minor|major>", "note": "<string>" },`,
    `    ...`,
    `  },`,
    `  "summary": "<string>"`,
    `}`,
  ];
  return lines.join('\n');
}
