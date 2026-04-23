/**
 * eval-run.ts — run the v1 eval dataset against the live AI path
 * Usage: npx tsx scripts/eval-run.ts
 *
 * Reads .env from the backend directory, loads the JSONL dataset,
 * runs each case through evaluateSentenceCorrection, and reports results.
 */

import { readFileSync } from 'fs';
import { resolve } from 'path';

// Load .env manually (no dotenv dependency)
const envPath = resolve(__dirname, '../.env');
try {
  const envText = readFileSync(envPath, 'utf8');
  for (const line of envText.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    const val = trimmed.slice(eq + 1).trim();
    if (!process.env[key]) process.env[key] = val;
  }
} catch {
  // no .env, use existing env
}

import { normalize } from '../src/evaluators/normalize';
import { minLevenshtein } from '../src/evaluators/levenshtein';
import { evaluateSentenceCorrection } from '../src/evaluators/sentenceCorrection';
import { OpenAiProvider } from '../src/ai/openai';
import { StubAiProvider } from '../src/ai/stub';

interface EvalCase {
  id: string;
  lesson_id: string;
  exercise_id: string;
  prompt: string;
  accepted_corrections: string[];
  user_answer: string;
  target_skill: string;
  rubric_label: string;
  expected_current_correct: boolean;
  expected_current_evaluation_source: 'deterministic' | 'ai_fallback';
  desired_human_correct: boolean;
  notes: string;
}

interface EvalResult {
  id: string;
  rubric_label: string;
  expected_current_correct: boolean;
  expected_current_evaluation_source: string;
  desired_human_correct: boolean;
  actual_correct: boolean;
  actual_source: string;
  matches_expected: boolean;
  matches_desired: boolean;
  bucket: string;
  notes: string;
}

function classifyBucket(row: EvalCase, actual_correct: boolean, actual_source: string): string {
  const matchesCurrent = actual_correct === row.expected_current_correct;
  const matchesDesired = actual_correct === row.desired_human_correct;

  if (matchesCurrent && matchesDesired) return 'expected_behavior';
  if (!matchesCurrent && row.rubric_label === 'content_gap') return 'content_issue';
  if (!matchesCurrent && row.expected_current_evaluation_source === 'ai_fallback') {
    // AI called but wrong result
    if (actual_correct && !row.expected_current_correct) return 'ai_false_positive';
    if (!actual_correct && row.expected_current_correct) return 'ai_false_negative';
  }
  if (!matchesCurrent && row.expected_current_evaluation_source === 'deterministic') {
    return 'threshold_issue'; // something that should be deterministic went to AI or vice versa
  }
  return 'other';
}

async function main() {
  const datasetPath = resolve(__dirname, '../../docs/ai-eval-dataset.v1.jsonl');
  const lines = readFileSync(datasetPath, 'utf8').split('\n').filter(Boolean);
  const cases: EvalCase[] = lines.map(l => JSON.parse(l));

  const apiKey = process.env.OPENAI_API_KEY || '';
  const model = process.env.OPENAI_MODEL || 'gpt-4o-mini';
  const baseUrl = process.env.OPENAI_BASE_URL || '';
  const useOpenAI = process.env.AI_PROVIDER === 'openai' && apiKey.length > 0;

  const ai = useOpenAI
    ? new OpenAiProvider({ apiKey, model, baseUrl: baseUrl || undefined })
    : new StubAiProvider();

  console.log(`Provider: ${useOpenAI ? `openai (${model})` : 'stub'}`);
  console.log(`Cases: ${cases.length}`);
  console.log('');

  const results: EvalResult[] = [];
  let done = 0;

  for (const c of cases) {
    process.stdout.write(`[${String(++done).padStart(2)}/${cases.length}] ${c.id}... `);
    try {
      const res = await evaluateSentenceCorrection(
        c.user_answer,
        c.accepted_corrections,
        c.prompt,
        ai,
        8000
      );
      const bucket = classifyBucket(c, res.correct, res.evaluation_source);
      const row: EvalResult = {
        id: c.id,
        rubric_label: c.rubric_label,
        expected_current_correct: c.expected_current_correct,
        expected_current_evaluation_source: c.expected_current_evaluation_source,
        desired_human_correct: c.desired_human_correct,
        actual_correct: res.correct,
        actual_source: res.evaluation_source,
        matches_expected: res.correct === c.expected_current_correct,
        matches_desired: res.correct === c.desired_human_correct,
        bucket,
        notes: c.notes,
      };
      results.push(row);
      const icon = row.matches_expected ? '✓' : '✗';
      const desiredIcon = row.matches_desired ? '✓' : '✗';
      console.log(`${icon}(curr) ${desiredIcon}(desired) [${res.evaluation_source}] correct=${res.correct}`);
    } catch (err) {
      console.log(`ERROR: ${(err as Error).message}`);
      results.push({
        id: c.id,
        rubric_label: c.rubric_label,
        expected_current_correct: c.expected_current_correct,
        expected_current_evaluation_source: c.expected_current_evaluation_source,
        desired_human_correct: c.desired_human_correct,
        actual_correct: false,
        actual_source: 'error',
        matches_expected: false,
        matches_desired: false,
        bucket: 'ops_issue',
        notes: `ERROR: ${(err as Error).message}`,
      });
    }
  }

  console.log('\n═══════════════════════════════════════════════════════');
  console.log('SUMMARY');
  console.log('═══════════════════════════════════════════════════════');

  const total = results.length;
  const matchExpected = results.filter(r => r.matches_expected).length;
  const matchDesired = results.filter(r => r.matches_desired).length;

  const detRows = results.filter(r => r.expected_current_evaluation_source === 'deterministic');
  const aiRows = results.filter(r => r.expected_current_evaluation_source === 'ai_fallback');
  const contentGapRows = results.filter(r => r.rubric_label === 'content_gap');

  const detCorrect = detRows.filter(r => r.matches_expected).length;
  const aiCorrectDesired = aiRows.filter(r => r.matches_desired).length;

  // Bucket counts
  const buckets: Record<string, number> = {};
  for (const r of results) {
    buckets[r.bucket] = (buckets[r.bucket] || 0) + 1;
  }

  console.log(`Total rows:                  ${total}`);
  console.log(`Matches expected behavior:   ${matchExpected}/${total} (${Math.round(matchExpected/total*100)}%)`);
  console.log(`Matches desired judgment:    ${matchDesired}/${total} (${Math.round(matchDesired/total*100)}%)`);
  console.log('');
  console.log(`Deterministic rows correct:  ${detCorrect}/${detRows.length}`);
  console.log(`AI-fallback vs desired:      ${aiCorrectDesired}/${aiRows.length}`);
  console.log(`Content-gap rows (expected rejects): ${contentGapRows.length}`);
  console.log('');
  console.log('Bucket breakdown:');
  for (const [b, n] of Object.entries(buckets).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${b.padEnd(28)} ${n}`);
  }

  console.log('\n───────────────────────────────────────────────────────');
  console.log('DETAIL: rows not matching current expected behavior');
  console.log('───────────────────────────────────────────────────────');

  const failures = results.filter(r => !r.matches_expected);
  if (failures.length === 0) {
    console.log('None — all cases match expected behavior.');
  } else {
    for (const r of failures) {
      const desired = r.desired_human_correct === r.actual_correct ? '(desired agrees)' : '(desired disagrees)';
      console.log(`  ${r.id}  rubric=${r.rubric_label}  actual=${r.actual_correct}  src=${r.actual_source}  bucket=${r.bucket}  ${desired}`);
      console.log(`    Notes: ${r.notes}`);
    }
  }

  console.log('\n───────────────────────────────────────────────────────');
  console.log('DETAIL: rows not matching desired human judgment');
  console.log('───────────────────────────────────────────────────────');

  const desiredFails = results.filter(r => !r.matches_desired);
  if (desiredFails.length === 0) {
    console.log('None — all cases match desired human judgment.');
  } else {
    for (const r of desiredFails) {
      console.log(`  ${r.id}  rubric=${r.rubric_label}  actual=${r.actual_correct}  src=${r.actual_source}  bucket=${r.bucket}`);
      console.log(`    Notes: ${r.notes}`);
    }
  }

  console.log('\n═══════════════════════════════════════════════════════');
}

main().catch(e => { console.error(e); process.exit(1); });
