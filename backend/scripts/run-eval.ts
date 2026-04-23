#!/usr/bin/env tsx
/**
 * Eval runner for docs/ai-eval-dataset.v1.jsonl
 *
 * Usage:
 *   cd backend && npx tsx scripts/run-eval.ts
 *
 * Reads .env for OPENAI_API_KEY, AI_PROVIDER, OPENAI_MODEL.
 * Runs all 36 rows and prints a structured result table + summary.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const DOCS = path.resolve(ROOT, '../docs');

// --- Load .env manually ---
function loadEnv(file: string) {
  try {
    const lines = fs.readFileSync(file, 'utf-8').split('\n');
    for (const line of lines) {
      const m = line.match(/^\s*([A-Z_][A-Z0-9_]*)=(.*)$/);
      if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
    }
  } catch {}
}
loadEnv(path.join(ROOT, '.env'));

// --- Import evaluator and providers after env is loaded ---
import { evaluateSentenceCorrection } from '../src/evaluators/sentenceCorrection.js';
import { OpenAiProvider } from '../src/ai/openai.js';
import { StubAiProvider } from '../src/ai/stub.js';

// --- Load dataset ---
interface EvalRow {
  id: string;
  exercise_id: string;
  prompt: string;
  accepted_corrections: string[];
  user_answer: string;
  target_skill: string;
  rubric_label: string;
  expected_current_correct: boolean;
  expected_current_evaluation_source: string;
  desired_human_correct: boolean;
  notes: string;
}

const datasetPath = path.join(DOCS, 'ai-eval-dataset.v1.jsonl');
const rows: EvalRow[] = fs
  .readFileSync(datasetPath, 'utf-8')
  .split('\n')
  .filter(Boolean)
  .map(l => JSON.parse(l));

// --- Build provider ---
const apiKey = process.env.OPENAI_API_KEY || '';
const model = process.env.OPENAI_MODEL || 'gpt-4o-mini';
const baseUrl = process.env.OPENAI_BASE_URL || undefined;
const providerName = process.env.AI_PROVIDER === 'openai' && apiKey ? 'openai' : 'stub';

const ai =
  providerName === 'openai'
    ? new OpenAiProvider({ apiKey, model, baseUrl })
    : new StubAiProvider();

interface EvalResult {
  id: string;
  rubric_label: string;
  expected_current_correct: boolean;
  desired_human_correct: boolean;
  actual_correct: boolean | null;
  actual_source: string | null;
  expected_source: string;
  matched_expected: boolean;
  matched_desired: boolean;
  review_bucket: string;
  error?: string;
}

// --- Run all rows ---
async function run() {
  console.log(`\n=== MASTERY AI EVAL RUN ===`);
  console.log(`Date:     ${new Date().toISOString()}`);
  console.log(`Provider: ${providerName}`);
  console.log(`Model:    ${model}`);
  console.log(`Dataset:  ai-eval-dataset.v1.jsonl (${rows.length} rows)`);
  console.log('');

  const results: EvalResult[] = [];

  for (const row of rows) {
    let actual_correct: boolean | null = null;
    let actual_source: string | null = null;
    let error: string | undefined;

    try {
      const res = await evaluateSentenceCorrection(
        row.user_answer,
        row.accepted_corrections,
        row.prompt,
        ai,
        8000
      );
      actual_correct = res.correct;
      actual_source = res.evaluation_source;
    } catch (e: any) {
      error = e?.message || 'unknown error';
    }

    const matched_expected = actual_correct === row.expected_current_correct;
    const matched_desired = actual_correct === row.desired_human_correct;

    let review_bucket = 'expected_behavior';
    if (error) {
      review_bucket = 'ops_issue';
    } else if (
      row.rubric_label === 'content_gap' &&
      actual_correct === row.expected_current_correct &&
      actual_correct !== row.desired_human_correct
    ) {
      review_bucket = 'content_issue';
    } else if (!matched_expected) {
      // Unexpected runtime deviation
      if (row.rubric_label.startsWith('borderline_ai_accept') && actual_correct === false) {
        review_bucket = 'prompt_issue';
      } else if (row.rubric_label.startsWith('borderline_ai_reject') && actual_correct === true) {
        review_bucket = 'prompt_issue';
      } else if (row.rubric_label.startsWith('deterministic')) {
        review_bucket = 'threshold_issue';
      } else {
        review_bucket = 'model_issue';
      }
    } else if (!matched_desired && row.rubric_label !== 'content_gap') {
      review_bucket = 'model_issue';
    }

    results.push({
      id: row.id,
      rubric_label: row.rubric_label,
      expected_current_correct: row.expected_current_correct,
      desired_human_correct: row.desired_human_correct,
      actual_correct,
      actual_source,
      expected_source: row.expected_current_evaluation_source,
      matched_expected,
      matched_desired,
      review_bucket,
      error,
    });

    const flag = !matched_expected ? '  MISMATCH' : !matched_desired ? '  DESIRED_MISMATCH' : '';
    console.log(
      `${row.id.padEnd(12)} ${row.rubric_label.padEnd(22)} expected=${String(row.expected_current_correct).padEnd(5)} desired=${String(row.desired_human_correct).padEnd(5)} actual=${String(actual_correct).padEnd(5)} src=${(actual_source || 'error').padEnd(13)} bucket=${review_bucket}${flag}`
    );
  }

  // --- Summary ---
  const total = results.length;
  const detRows = results.filter(r => r.expected_source === 'deterministic');
  const aiRows = results.filter(r => r.expected_source === 'ai_fallback');
  const contentGapRows = results.filter(r => r.rubric_label === 'content_gap');

  const detCorrect = detRows.filter(r => r.matched_expected).length;
  const aiCorrectVsDesired = aiRows.filter(r => r.matched_desired).length;
  const fps = aiRows.filter(r => r.actual_correct === true && r.desired_human_correct === false).length;
  const fns = aiRows.filter(r => r.actual_correct === false && r.desired_human_correct === true).length;

  const bucketCounts: Record<string, number> = {};
  for (const r of results) {
    bucketCounts[r.review_bucket] = (bucketCounts[r.review_bucket] || 0) + 1;
  }

  console.log('\n=== SUMMARY ===');
  console.log(`Total rows:                       ${total}`);
  console.log(`Deterministic rows correct:       ${detCorrect}/${detRows.length}`);
  console.log(`AI-fallback rows vs desired:      ${aiCorrectVsDesired}/${aiRows.length}`);
  console.log(`False positives (AI over-accept): ${fps}`);
  console.log(`False negatives (AI over-strict): ${fns}`);
  console.log(`Content-gap rows (confirmed):     ${contentGapRows.length}`);

  console.log('\n=== FAILURE BUCKETS ===');
  for (const [bucket, count] of Object.entries(bucketCounts).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${bucket.padEnd(25)} ${count}`);
  }

  // --- Mismatches detail ---
  const mismatches = results.filter(r => !r.matched_expected || r.error);
  if (mismatches.length > 0) {
    console.log('\n=== UNEXPECTED MISMATCHES (actual != expected_current) ===');
    for (const r of mismatches) {
      console.log(`  ${r.id}: ${r.rubric_label} | expected=${r.expected_current_correct} actual=${r.actual_correct} src=${r.actual_source} ${r.error ? `ERROR=${r.error}` : ''}`);
    }
  }

  const desiredMismatches = results.filter(r => !r.matched_desired && r.rubric_label !== 'content_gap');
  if (desiredMismatches.length > 0) {
    console.log('\n=== NON-CONTENT-GAP DESIRED MISMATCHES ===');
    for (const r of desiredMismatches) {
      console.log(`  ${r.id}: ${r.rubric_label} | desired=${r.desired_human_correct} actual=${r.actual_correct} bucket=${r.review_bucket}`);
    }
  }

  console.log('\n=== CONTENT GAP ROWS (product policy decision needed) ===');
  for (const r of contentGapRows) {
    console.log(`  ${r.id}: actual=${r.actual_correct} desired=${r.desired_human_correct} (${r.review_bucket})`);
  }

  console.log('\n');
}

run().catch(e => { console.error('EVAL FAILED:', e); process.exit(1); });
