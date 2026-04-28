/**
 * Wave 14.5 — V1.5 offline content generation pipeline (scaffold).
 *
 * Generates candidate exercises for a target skill using OpenAI. The
 * output is **schema-validated** but **not** pedagogy-validated — a
 * methodologist review pass is still required before items land in
 * the bank. Per the V1 plan §22 + LEARNING_ENGINE.md §20, the
 * full pipeline is generator + QA agent. This script ships only
 * the generator; the QA agent is a follow-up wave.
 *
 * Usage:
 *   OPENAI_API_KEY=sk-... npm run gen:content -- \
 *     --skill=verb-ing-after-gerund-verbs \
 *     --type=fill_blank \
 *     --count=5
 *
 *   --skill <id>      Required. Must exist in backend/data/skills.json.
 *   --type <type>     Required. fill_blank | multiple_choice |
 *                     sentence_correction | sentence_rewrite |
 *                     short_free_sentence.
 *   --count <N>       Default 5. Number of candidate items to generate.
 *   --model <id>      Default OPENAI_MODEL or 'gpt-4o-mini'.
 *   --dry-run         Print the prompt + plan, do not call the API.
 *
 * Output: backend/data/staging/gen-<skill>-<timestamp>.json
 *
 * Authoritative spec: LEARNING_ENGINE.md §20 + docs/plans/learning-engine-v1.md.
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';

import { ExerciseSchema } from '../src/data/lessonSchema';
import { LessonSchema } from '../src/data/lessonSchema';

interface Args {
  skill: string;
  type: string;
  count: number;
  model: string;
  dryRun: boolean;
}

const SUPPORTED_TYPES = new Set([
  'fill_blank',
  'multiple_choice',
  'sentence_correction',
  'sentence_rewrite',
  'short_free_sentence',
  // listening_discrimination intentionally out of scope — generation
  // requires TTS and an audio pipeline that this script doesn't run.
]);

function parseArgs(argv: string[]): Args {
  const get = (flag: string): string | undefined => {
    const idx = argv.findIndex((a) => a === flag || a.startsWith(`${flag}=`));
    if (idx < 0) return undefined;
    if (argv[idx].includes('=')) return argv[idx].split('=', 2)[1];
    return argv[idx + 1];
  };
  const skill = get('--skill') ?? '';
  const type = get('--type') ?? '';
  const count = Number.parseInt(get('--count') ?? '5', 10);
  const model =
    get('--model') ?? process.env.OPENAI_MODEL ?? 'gpt-4o-mini';
  const dryRun = argv.includes('--dry-run');
  if (!skill) throw new Error('missing --skill');
  if (!type || !SUPPORTED_TYPES.has(type)) {
    throw new Error(
      `--type must be one of: ${[...SUPPORTED_TYPES].join(', ')}`
    );
  }
  if (!Number.isFinite(count) || count < 1 || count > 20) {
    throw new Error('--count must be an integer in [1, 20]');
  }
  return { skill, type, count, model, dryRun };
}

interface Skill {
  skill_id: string;
  title: string;
  description?: string;
  cefr_level: string;
  contrasts_with?: string[];
  target_errors?: string[];
}

async function loadSkills(): Promise<Skill[]> {
  const raw = await fs.readFile(
    path.resolve(process.cwd(), 'data', 'skills.json'),
    'utf8'
  );
  const parsed = JSON.parse(raw) as { skills: Skill[] };
  return parsed.skills;
}

interface ReferenceItem {
  exercise_id: string;
  type: string;
  skill_id?: string;
  [key: string]: unknown;
}

async function loadReferenceItems(
  skillId: string,
  type: string
): Promise<ReferenceItem[]> {
  const dir = path.resolve(process.cwd(), 'data', 'lessons');
  const files = (await fs.readdir(dir)).filter((f) => f.endsWith('.json'));
  const items: ReferenceItem[] = [];
  for (const f of files) {
    const raw = await fs.readFile(path.join(dir, f), 'utf8');
    const lesson = LessonSchema.safeParse(JSON.parse(raw));
    if (!lesson.success) continue;
    for (const ex of lesson.data.exercises) {
      if (ex.type !== type) continue;
      if ('skill_id' in ex && ex.skill_id === skillId) {
        items.push(ex as unknown as ReferenceItem);
      }
    }
  }
  // Cap at 3 to keep the prompt focused.
  return items.slice(0, 3);
}

function buildPrompt(args: {
  skill: Skill;
  type: string;
  count: number;
  references: ReferenceItem[];
}): string {
  const { skill, type, count, references } = args;
  const lines: string[] = [
    `You are an English-as-a-Foreign-Language item author writing CEFR ${skill.cefr_level} exercises for adult Russian-speaking learners.`,
    '',
    `Generate ${count} fresh exercise items of type \`${type}\` for the skill below. Each item must teach this rule and only this rule.`,
    '',
    `[SKILL]`,
    `id: ${skill.skill_id}`,
    `title: ${skill.title}`,
    `level: ${skill.cefr_level}`,
    `description: ${skill.description ?? '(none)'}`,
    skill.contrasts_with && skill.contrasts_with.length > 0
      ? `contrasts_with: ${skill.contrasts_with.join(', ')}`
      : '',
    skill.target_errors && skill.target_errors.length > 0
      ? `target_errors: ${skill.target_errors.join(', ')}`
      : '',
    '',
    `[CONSTRAINTS]`,
    `- Use natural, attested English at ${skill.cefr_level} level. No "John went to the store" beige.`,
    `- Each item must engage the SPECIFIC rule. Avoid surface pattern-matching items.`,
    `- Adult contexts only (work, travel, daily life, news).`,
    `- Match the JSON shape of the reference items below exactly. Include all engine metadata fields the references carry (skill_id, primary_target_error, evidence_tier, optional meaning_frame for strongest tier).`,
    `- exercise_id: emit a placeholder string of the form "REPLACE-WITH-UUID-N" — the integration step will assign real UUIDs.`,
    `- Distribute primary_target_error across items: at least one form_error and one contrast_error or conceptual_error per set of 5+.`,
    '',
    `[REFERENCE_ITEMS] (existing high-quality items in the bank for this skill — match this style)`,
    JSON.stringify(references, null, 2),
    '',
    `Return strict JSON: an object with one field "items" whose value is an array of ${count} exercise objects in the same shape as the references. No prose outside JSON.`,
  ];
  return lines.filter((l) => l !== '').join('\n');
}

interface OpenAiResult {
  items: Record<string, unknown>[];
}

async function callOpenAi(
  args: { model: string; prompt: string }
): Promise<OpenAiResult> {
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
          'You author calm, defensible English-grammar exercises. The output must be strictly machine-parsable JSON matching the requested shape. No prose outside JSON.',
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
  const json = (await res.json()) as { output_text?: string; output?: unknown };
  const text =
    json.output_text ??
    (() => {
      const out = (json.output as { content?: Array<{ text?: string }> }[]) ?? [];
      const first = out[0]?.content?.[0]?.text;
      if (typeof first !== 'string') {
        throw new Error('OpenAI returned no text');
      }
      return first;
    })();
  return JSON.parse(text) as OpenAiResult;
}

async function writeStaging(args: {
  skill: string;
  type: string;
  items: Record<string, unknown>[];
}): Promise<string> {
  const stagingDir = path.resolve(process.cwd(), 'data', 'staging');
  await fs.mkdir(stagingDir, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const file = path.join(stagingDir, `gen-${args.skill}-${args.type}-${ts}.json`);
  const payload = {
    generated_at: new Date().toISOString(),
    skill: args.skill,
    type: args.type,
    count: args.items.length,
    items: args.items,
    notes: [
      'This file is a generator output. Each item has been schema-validated.',
      'It has NOT been validated by the english-grammar-methodologist skill.',
      'Manual review + replacement of REPLACE-WITH-UUID placeholders is required',
      'before items are merged into backend/data/lessons/.',
    ],
  };
  await fs.writeFile(file, JSON.stringify(payload, null, 2));
  return file;
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const skills = await loadSkills();
  const skill = skills.find((s) => s.skill_id === args.skill);
  if (!skill) {
    throw new Error(
      `unknown skill: ${args.skill} (available: ${skills.map((s) => s.skill_id).join(', ')})`
    );
  }
  const references = await loadReferenceItems(args.skill, args.type);
  const prompt = buildPrompt({
    skill,
    type: args.type,
    count: args.count,
    references,
  });

  if (args.dryRun) {
    console.log('--- DRY RUN ---');
    console.log(`Model:          ${args.model}`);
    console.log(`Skill:          ${args.skill}`);
    console.log(`Type:           ${args.type}`);
    console.log(`Count:          ${args.count}`);
    console.log(`References:     ${references.length} item(s)`);
    console.log('--- PROMPT ---');
    console.log(prompt);
    return;
  }

  console.log(
    `Generating ${args.count}× ${args.type} for ${args.skill} via ${args.model}...`
  );
  const generated = await callOpenAi({ model: args.model, prompt });
  if (!Array.isArray(generated.items)) {
    throw new Error('OpenAI response missing `items` array');
  }

  // Schema-validate each candidate. Items that fail are kept in the
  // staging file with an `_error` field so the human reviewer can see
  // what the model produced even when it's malformed — easier to spot
  // prompt-template drift that way.
  const validated: Record<string, unknown>[] = [];
  let passing = 0;
  let failing = 0;
  for (const candidate of generated.items) {
    // Patch a real-ish exercise_id so zod's uuid() check doesn't trip
    // on the REPLACE-WITH-UUID placeholder. The reviewer will swap
    // both the placeholder and this throwaway uuid before merging.
    const probe = { ...candidate, exercise_id: crypto.randomUUID() };
    const parsed = ExerciseSchema.safeParse(probe);
    if (parsed.success) {
      validated.push({
        ...candidate,
        _validation: { ok: true },
      });
      passing++;
    } else {
      validated.push({
        ...candidate,
        _validation: {
          ok: false,
          issues: parsed.error.issues.map((i) => ({
            path: i.path.join('.'),
            message: i.message,
          })),
        },
      });
      failing++;
    }
  }

  const file = await writeStaging({
    skill: args.skill,
    type: args.type,
    items: validated,
  });
  console.log(`Schema OK: ${passing}/${validated.length}, failing: ${failing}`);
  console.log(`Wrote: ${file}`);
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exitCode = 1;
});
