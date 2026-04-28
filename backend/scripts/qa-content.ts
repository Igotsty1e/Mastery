/**
 * Wave 14.7 — V1.5 content QA agent (second half of §20).
 *
 * Reads a `gen-*.json` staging file written by `gen-content.ts` and
 * runs each item through an independent AI reviewer pass. The
 * reviewer is a different identity than the generator (different
 * system prompt, optionally a different model family). The
 * methodologist remains the human-in-the-loop gate before items move
 * from `staging/` into `lessons/`.
 *
 * Usage:
 *   OPENAI_API_KEY=sk-... npm run qa:content -- \
 *     --file=data/staging/gen-verb-ing-after-gerund-verbs-fill_blank-2026-04-28T...json
 *
 *   --file <path>            Required. Staging file from gen:content.
 *   --reviewer-model <id>    Default OPENAI_MODEL or 'gpt-4o-mini'.
 *                            Pass a different model family to get an
 *                            independent identity (recommended).
 *   --dry-run                Print the prompts, do not call the API.
 *
 * Output: a sibling `qa-*.json` file next to the input. Each item
 * gains a `_qa` block carrying verdict (pass / revise / reject),
 * per-criterion notes, and the reviewer model name.
 *
 * Authoritative spec:
 * - LEARNING_ENGINE.md §12.2 (Two-Agent QA)
 * - LEARNING_ENGINE.md §8.4.1 (per-family safeguards)
 * - exercise_structure.md §§5.1, 5.5, 5.6, 5.7, 5.8 (per-family
 *   authoring contracts)
 */
import fs from 'node:fs/promises';
import path from 'node:path';

import {
  type Criterion,
  type CriterionResult,
  type ItemQa,
  type Verdict,
  aggregateVerdict,
  buildReviewPrompt,
  criteriaForType,
} from '../src/content-qa/rubric';

interface CliArgs {
  file: string;
  reviewerModel: string;
  dryRun: boolean;
}

function parseArgs(argv: string[]): CliArgs {
  const get = (flag: string): string | undefined => {
    const idx = argv.findIndex((a) => a === flag || a.startsWith(`${flag}=`));
    if (idx < 0) return undefined;
    if (argv[idx].includes('=')) return argv[idx].split('=', 2)[1];
    return argv[idx + 1];
  };
  const file = get('--file') ?? '';
  const reviewerModel =
    get('--reviewer-model') ?? process.env.OPENAI_MODEL ?? 'gpt-4o-mini';
  const dryRun = argv.includes('--dry-run');
  if (!file) {
    throw new Error('missing --file (path to a gen-*.json staging file)');
  }
  return { file, reviewerModel, dryRun };
}

interface StagingFile {
  generated_at: string;
  skill: string;
  type: string;
  count: number;
  items: Array<
    Record<string, unknown> & {
      _validation?: { ok: boolean; issues?: unknown[] };
    }
  >;
  notes?: string[];
}

async function callReviewer(args: {
  model: string;
  prompt: string;
}): Promise<{
  criteria: Record<string, CriterionResult>;
  summary: string;
}> {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error('OPENAI_API_KEY is not set');
  const baseUrl =
    process.env.OPENAI_BASE_URL?.replace(/\/+$/, '') ||
    'https://api.openai.com/v1';
  const body = {
    model: args.model,
    input: [
      {
        role: 'system',
        content:
          'You are a strict, independent reviewer of English grammar exercises. You did NOT write the candidate item. Your job is to flag every defect that would harm a B2 adult learner. Output strict JSON only.',
      },
      { role: 'user', content: args.prompt },
    ],
    text: { format: { type: 'json_object' } },
  };
  const res = await fetch(`${baseUrl}/responses`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    throw new Error(`OpenAI ${res.status}: ${await res.text()}`);
  }
  const json = (await res.json()) as {
    output_text?: string;
    output?: unknown;
  };
  const text =
    json.output_text ??
    (() => {
      const out =
        (json.output as { content?: Array<{ text?: string }> }[]) ?? [];
      const first = out[0]?.content?.[0]?.text;
      if (typeof first !== 'string') {
        throw new Error('OpenAI returned no text');
      }
      return first;
    })();
  return JSON.parse(text) as {
    criteria: Record<string, CriterionResult>;
    summary: string;
  };
}

function outputPath(inputPath: string): string {
  const dir = path.dirname(inputPath);
  const base = path.basename(inputPath);
  return path.join(dir, base.replace(/^gen-/, 'qa-'));
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const filePath = path.resolve(process.cwd(), args.file);
  const raw = await fs.readFile(filePath, 'utf8');
  const staging = JSON.parse(raw) as StagingFile;
  const criteria: Criterion[] = criteriaForType(staging.type);

  const reviewed: Array<Record<string, unknown>> = [];
  let pass = 0;
  let revise = 0;
  let reject = 0;

  for (let i = 0; i < staging.items.length; i++) {
    const item = staging.items[i];
    const validation = item._validation as
      | { ok: boolean; issues?: unknown[] }
      | undefined;

    if (validation && !validation.ok) {
      // Schema-failed items are auto-rejected — don't burn API tokens
      // reviewing items the methodologist will throw out anyway.
      const qa: ItemQa = {
        verdict: 'reject',
        criteria: {},
        summary:
          'Auto-rejected: failed schema validation in the generator pass.',
        reviewer_model: args.reviewerModel,
      };
      reviewed.push({ ...item, _qa: qa });
      reject++;
      continue;
    }

    const prompt = buildReviewPrompt({
      skill: staging.skill,
      type: staging.type,
      item,
      criteria,
    });

    if (args.dryRun) {
      console.log(`--- ITEM ${i + 1}/${staging.items.length} ---`);
      console.log(prompt);
      console.log('');
      continue;
    }

    process.stdout.write(`Reviewing ${i + 1}/${staging.items.length}... `);
    const review = await callReviewer({
      model: args.reviewerModel,
      prompt,
    });
    const verdict: Verdict = aggregateVerdict(review.criteria);
    const qa: ItemQa = {
      verdict,
      criteria: review.criteria,
      summary: review.summary,
      reviewer_model: args.reviewerModel,
    };
    reviewed.push({ ...item, _qa: qa });
    if (verdict === 'pass') pass++;
    else if (verdict === 'revise') revise++;
    else reject++;
    console.log(verdict);
  }

  if (args.dryRun) {
    console.log('--- DRY RUN ---');
    console.log(`Items:           ${staging.items.length}`);
    console.log(`Criteria/item:   ${criteria.length}`);
    console.log(`Reviewer model:  ${args.reviewerModel}`);
    return;
  }

  const outFile = outputPath(filePath);
  const payload = {
    qa_at: new Date().toISOString(),
    source_file: path.basename(filePath),
    skill: staging.skill,
    type: staging.type,
    reviewer_model: args.reviewerModel,
    summary: { pass, revise, reject, total: staging.items.length },
    items: reviewed,
    notes: [
      'QA-agent pass on the gen-*.json staging file.',
      'verdict pass = no issues / revise = minor edits needed / reject = rewrite or drop.',
      'The QA agent is a different identity than the generator (different system prompt) but',
      'may share the same model family. Pass --reviewer-model with a different family for',
      'stronger independence.',
      'Methodologist review remains the human-in-the-loop gate before items merge into lessons/.',
    ],
  };
  await fs.writeFile(outFile, JSON.stringify(payload, null, 2));
  console.log('');
  console.log(`Pass: ${pass}, Revise: ${revise}, Reject: ${reject}`);
  console.log(`Wrote: ${outFile}`);
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exitCode = 1;
});
