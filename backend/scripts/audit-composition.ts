/**
 * Wave C — composition audit for shipped lesson fixtures.
 *
 * Walks every `*.json` under `backend/data/lessons/` and validates each
 * fixture against the policy in `exercise_structure.md §6.7`:
 *
 *   1. multiple_choice                          ≤ floor(0.2 × total)
 *   2. multiple_choice + listening_discrim      ≤ floor(0.3 × total)
 *   3. ≥ 1 short_free_sentence
 *   4. ≥ 1 sentence_rewrite (or any strongest-tier family)
 *   5. every strong / strongest item carries a non-empty meaning_frame
 *
 * Prints a per-lesson + aggregate report and exits non-zero on any
 * violation. Wired via `npm run audit:composition` so CI can run it as
 * a pre-merge gate next to the existing vitest job.
 *
 * The audit is intentionally read-only — no rewrite, no generator
 * call. Wave C content rewrites happen under methodologist
 * supervision per `docs/plans/automaticity-pivot.md`.
 */
import fs from 'node:fs';
import path from 'node:path';

const LESSONS_DIR = path.resolve(
  process.cwd(),
  // Run-anywhere: when invoked via `npm run audit:composition` from
  // the backend/ root, cwd is backend/, so the relative path resolves
  // to backend/data/lessons. When invoked from the repo root with
  // `tsx backend/scripts/audit-composition.ts`, the CLI flag below
  // overrides this.
  'data/lessons',
);

type Exercise = {
  exercise_id?: string;
  type?: string;
  evidence_tier?: 'weak' | 'medium' | 'strong' | 'strongest';
  meaning_frame?: string;
};

type Lesson = {
  lesson_id?: string;
  title?: string;
  exercises?: Exercise[];
};

type Violation = {
  rule: string;
  detail: string;
};

type LessonReport = {
  file: string;
  title: string;
  total: number;
  byType: Record<string, number>;
  violations: Violation[];
};

function auditLesson(file: string, lesson: Lesson): LessonReport {
  const ex = lesson.exercises ?? [];
  const total = ex.length;
  const byType: Record<string, number> = {};
  for (const e of ex) {
    const t = e.type ?? '?';
    byType[t] = (byType[t] ?? 0) + 1;
  }

  const violations: Violation[] = [];

  // §6.7.1 — recognition cap.
  const mc = byType['multiple_choice'] ?? 0;
  const ld = byType['listening_discrimination'] ?? 0;
  const mcCap = Math.floor(total * 0.2);
  const recCap = Math.floor(total * 0.3);
  if (mc > mcCap) {
    const pct = ((mc / total) * 100).toFixed(1);
    violations.push({
      rule: '§6.7.1 multiple_choice cap',
      detail: `multiple_choice = ${mc} (${pct}% of ${total}); cap = ${mcCap}`,
    });
  }
  if (mc + ld > recCap) {
    const combined = mc + ld;
    const pct = ((combined / total) * 100).toFixed(1);
    violations.push({
      rule: '§6.7.1 recognition cap',
      detail:
        `multiple_choice + listening_discrimination = ${combined} (${pct}% of ${total}); ` +
        `cap = ${recCap}`,
    });
  }

  // §6.7.2 — production floor.
  if ((byType['short_free_sentence'] ?? 0) === 0) {
    violations.push({
      rule: '§6.7.2 production floor',
      detail: 'no short_free_sentence item',
    });
  }
  const strongestFamilies = ['sentence_rewrite', 'short_free_sentence'];
  const hasStrongest = strongestFamilies.some(
    (t) => (byType[t] ?? 0) > 0,
  );
  if (!hasStrongest) {
    violations.push({
      rule: '§6.7.2 production floor',
      detail: 'no strongest-tier family present (sentence_rewrite or short_free_sentence)',
    });
  }
  if ((byType['sentence_rewrite'] ?? 0) === 0) {
    violations.push({
      rule: '§6.7.2 production floor',
      detail: 'no sentence_rewrite item',
    });
  }

  // §6.7.3 — meaning_frame on strong / strongest tier.
  const missingMf: string[] = [];
  for (const e of ex) {
    if (e.evidence_tier !== 'strong' && e.evidence_tier !== 'strongest') {
      continue;
    }
    const mf = (e.meaning_frame ?? '').trim();
    if (!mf) missingMf.push(e.exercise_id ?? '<unknown>');
  }
  if (missingMf.length > 0) {
    violations.push({
      rule: '§6.7.3 meaning_frame mandatory on strong/strongest',
      detail: `${missingMf.length} item(s) missing meaning_frame: ${missingMf.join(', ')}`,
    });
  }

  return {
    file,
    title: lesson.title ?? '<untitled>',
    total,
    byType,
    violations,
  };
}

function formatReport(r: LessonReport): string {
  const head = `${path.basename(r.file)} — ${r.title} (${r.total} items)`;
  const types = Object.entries(r.byType)
    .map(([t, n]) => `${t}=${n}`)
    .join(', ');
  if (r.violations.length === 0) {
    return `  ✓ ${head}\n      ${types}`;
  }
  const v = r.violations
    .map((x) => `      ✗ ${x.rule} — ${x.detail}`)
    .join('\n');
  return `  ✗ ${head}\n      ${types}\n${v}`;
}

function main(): number {
  const flagDir = process.argv
    .find((a) => a.startsWith('--dir='))
    ?.split('=')[1];
  const dir = flagDir ? path.resolve(flagDir) : LESSONS_DIR;

  if (!fs.existsSync(dir)) {
    console.error(`audit-composition: lessons dir not found at ${dir}`);
    return 2;
  }

  const files = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith('.json') && !f.startsWith('_'))
    .sort();

  if (files.length === 0) {
    console.error(`audit-composition: no lesson fixtures found under ${dir}`);
    return 2;
  }

  const reports: LessonReport[] = [];
  for (const f of files) {
    const full = path.join(dir, f);
    let lesson: Lesson;
    try {
      const raw = fs.readFileSync(full, 'utf8');
      lesson = JSON.parse(raw);
    } catch (e) {
      console.error(`audit-composition: failed to parse ${f}: ${e}`);
      return 2;
    }
    reports.push(auditLesson(full, lesson));
  }

  console.log('Composition audit (exercise_structure.md §6.7)');
  console.log('=================================================');
  for (const r of reports) {
    console.log(formatReport(r));
  }

  const totalViolations = reports.reduce(
    (n, r) => n + r.violations.length,
    0,
  );
  const failedLessons = reports.filter((r) => r.violations.length > 0).length;

  console.log('');
  console.log(
    `Summary: ${reports.length} lesson(s); ` +
      `${failedLessons} with violations; ` +
      `${totalViolations} total violation(s).`,
  );
  return totalViolations === 0 ? 0 : 1;
}

const exitCode = main();
process.exit(exitCode);
