/**
 * Offline image-generation pipeline for the Visual Context Layer
 * (exercise_structure.md §2.9).
 *
 * Reads every lesson fixture under backend/data/lessons/, finds every
 * exercise that carries an `image` block with a non-empty authoring brief,
 * and asks the kie.ai 4o-image API to render it. The generated PNG is then
 * downloaded and saved to:
 *
 *   backend/public/images/{lesson_id}/{exercise_id}.png
 *   backend/public/images/{lesson_id}/{exercise_id}.meta.json
 *
 * The sidecar carries a sha256 hash of role + brief + dont_show, so re-runs
 * skip items whose authoring inputs are unchanged.
 *
 * Usage:
 *   KIE_API_KEY=... npm run gen:image
 *   KIE_API_KEY=... npm run gen:image -- --force
 *   KIE_API_KEY=... npm run gen:image -- --dry-run
 *
 * API references:
 *   POST https://api.kie.ai/api/v1/gpt4o-image/generate
 *   GET  https://api.kie.ai/api/v1/gpt4o-image/record-info?taskId=...
 *
 * Authoritative spec: docs/implementation-scope.md Workstream I.
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { LessonSchema, type Lesson } from '../src/data/lessonSchema';

const KIE_BASE_URL = process.env.KIE_BASE_URL?.replace(/\/+$/, '') || 'https://api.kie.ai/api/v1';
// Flux Kontext is the workhorse: open-weights model with permissive
// safetyTolerance, faster generation, and no upstream OpenAI content
// moderation gate that flagged our editorial scenes when we tried
// gpt4o-image.
const KIE_GENERATE_PATH = '/flux/kontext/generate';
const KIE_POLL_PATH = '/flux/kontext/record-info';
const POLL_INTERVAL_MS = 3000;
const POLL_TIMEOUT_MS = 180000;
const ASPECT_RATIO = '4:3';
const FLUX_MODEL = 'flux-kontext-pro';
const SAFETY_TOLERANCE = 6;

// Brand-anchored style prefix (mirrors DESIGN.md art direction). Kept short
// and free of negations to minimise false positives from upstream content
// moderation. Negation lives on the per-item `dont_show` line instead.
const STYLE_PREFIX = [
  'Soft hand-drawn illustration, editorial educational style.',
  'Warm palette: dusty rose, oat, muted clay, parchment, with quiet sage accents.',
  'Calm and breathable composition.',
].join(' ');

type Args = { force: boolean; dryRun: boolean };

function parseArgs(argv: string[]): Args {
  return {
    force: argv.includes('--force'),
    dryRun: argv.includes('--dry-run'),
  };
}

function lessonsDir(): string {
  return path.resolve(process.cwd(), 'data', 'lessons');
}

function imagesDir(lessonId: string): string {
  return path.resolve(process.cwd(), 'public', 'images', lessonId);
}

interface ImageMetaSidecar {
  role: string;
  brief: string;
  dont_show: string;
  hash: string;
  generated_at: string;
  bytes: number;
  source_url: string;
}

function hashContent(role: string, brief: string, dontShow: string): string {
  return crypto
    .createHash('sha256')
    .update(`${role}\n${brief}\n${dontShow}`)
    .digest('hex');
}

async function readLessonFile(file: string): Promise<Lesson | null> {
  const raw = await fs.readFile(file, 'utf8');
  const parsed = JSON.parse(raw);
  const result = LessonSchema.safeParse(parsed);
  if (!result.success) {
    console.warn(`[gen-image] skipping invalid lesson ${file}: ${result.error.issues[0]?.message ?? 'schema error'}`);
    return null;
  }
  return result.data;
}

async function readMeta(file: string): Promise<ImageMetaSidecar | null> {
  try {
    const raw = await fs.readFile(file, 'utf8');
    return JSON.parse(raw) as ImageMetaSidecar;
  } catch {
    return null;
  }
}

function buildPrompt(brief: string, _dontShow: string): string {
  // We deliberately omit the `dont_show` clause from the upstream prompt:
  // listing forbidden objects ("phone screens", "signs with text") trips
  // OpenAI's image-content moderation more often than it actually steers
  // the model. The field stays in the lesson JSON as authoring-time QA
  // metadata so the human reviewer can flag any clip that drifts.
  return `${STYLE_PREFIX} Scene: ${brief.trim()}.`;
}

interface KieGenerateResponse {
  code: number;
  msg: string;
  data?: { taskId?: string };
}

interface KieRecordInfoResponse {
  code: number;
  msg: string;
  data?: {
    successFlag?: number;
    progress?: string;
    response?: { resultImageUrl?: string; originImageUrl?: string | null };
    errorCode?: string | null;
    errorMessage?: string | null;
  };
}

async function createTask(apiKey: string, prompt: string): Promise<string> {
  const res = await fetch(`${KIE_BASE_URL}${KIE_GENERATE_PATH}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      prompt,
      aspectRatio: ASPECT_RATIO,
      outputFormat: 'png',
      model: FLUX_MODEL,
      safetyTolerance: SAFETY_TOLERANCE,
      promptUpsampling: false,
    }),
  });

  if (!res.ok) {
    const errText = await res.text().catch(() => '');
    throw new Error(`kie.ai generate ${res.status} ${res.statusText}: ${errText}`);
  }

  const json = (await res.json()) as KieGenerateResponse;
  const taskId = json.data?.taskId;
  if (!taskId) {
    throw new Error(`kie.ai generate returned no taskId: ${JSON.stringify(json)}`);
  }
  return taskId;
}

async function pollTask(apiKey: string, taskId: string): Promise<string> {
  const start = Date.now();
  while (Date.now() - start < POLL_TIMEOUT_MS) {
    const res = await fetch(
      `${KIE_BASE_URL}${KIE_POLL_PATH}?taskId=${encodeURIComponent(taskId)}`,
      {
        headers: { Authorization: `Bearer ${apiKey}` },
      }
    );
    if (!res.ok) {
      const errText = await res.text().catch(() => '');
      throw new Error(`kie.ai record-info ${res.status} ${res.statusText}: ${errText}`);
    }
    const json = (await res.json()) as KieRecordInfoResponse;
    const data = json.data ?? {};
    if (data.errorCode) {
      throw new Error(`kie.ai task ${taskId} failed: ${data.errorCode} ${data.errorMessage ?? ''}`);
    }
    if (data.successFlag === 1) {
      const url = data.response?.resultImageUrl;
      if (!url) {
        throw new Error(`kie.ai task ${taskId} succeeded but had no resultImageUrl`);
      }
      return url;
    }
    await new Promise(r => setTimeout(r, POLL_INTERVAL_MS));
  }
  throw new Error(`kie.ai task ${taskId} timed out after ${POLL_TIMEOUT_MS}ms`);
}

async function downloadBinary(url: string): Promise<Uint8Array> {
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`download ${url} → ${res.status} ${res.statusText}`);
  }
  return new Uint8Array(await res.arrayBuffer());
}

async function ensureImagesForLesson(lesson: Lesson, args: Args, apiKey: string | null): Promise<{ generated: number; skipped: number; failed: number; planned: number }> {
  const stats = { generated: 0, skipped: 0, failed: 0, planned: 0 };
  const outDir = imagesDir(lesson.lesson_id);

  // Only items whose author left a non-empty brief are candidates for the
  // pipeline. `image.policy` may be `optional` without a brief, in which case
  // there is nothing to generate.
  const items = lesson.exercises.filter(
    (e): e is typeof e & { image: { brief: string } } =>
      Boolean(e.image && e.image.brief && e.image.brief.trim()),
  );
  if (items.length === 0) return stats;

  await fs.mkdir(outDir, { recursive: true });

  for (const ex of items) {
    if (!ex.image) continue;
    const role = ex.image.role;
    const brief = ex.image.brief ?? '';
    const dontShow = ex.image.dont_show ?? '';
    const hash = hashContent(role, brief, dontShow);
    const pngPath = path.join(outDir, `${ex.exercise_id}.png`);
    const metaPath = path.join(outDir, `${ex.exercise_id}.meta.json`);

    const existing = await readMeta(metaPath);
    const upToDate = existing && existing.hash === hash;

    if (upToDate && !args.force) {
      stats.skipped += 1;
      continue;
    }

    stats.planned += 1;
    const action = args.force ? 'regenerate' : (existing ? 'update' : 'generate');
    console.log(`[gen-image] ${lesson.lesson_id} ${ex.exercise_id} ${action} role=${role} chars=${brief.length}`);

    if (args.dryRun) {
      stats.generated += 1;
      continue;
    }

    if (!apiKey) {
      console.error(`[gen-image] KIE_API_KEY is required to generate images. Set it or pass --dry-run.`);
      stats.failed += 1;
      continue;
    }

    try {
      const prompt = buildPrompt(brief, dontShow);
      const taskId = await createTask(apiKey, prompt);
      const url = await pollTask(apiKey, taskId);
      const bytes = await downloadBinary(url);
      await fs.writeFile(pngPath, bytes);
      const meta: ImageMetaSidecar = {
        role,
        brief,
        dont_show: dontShow,
        hash,
        generated_at: new Date().toISOString(),
        bytes: bytes.length,
        source_url: url,
      };
      await fs.writeFile(metaPath, `${JSON.stringify(meta, null, 2)}\n`);
      stats.generated += 1;
    } catch (err) {
      console.error(`[gen-image] FAILED ${lesson.lesson_id} ${ex.exercise_id}: ${(err as Error).message}`);
      stats.failed += 1;
    }
  }

  return stats;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const apiKey = process.env.KIE_API_KEY ?? null;

  if (!apiKey && !args.dryRun) {
    console.error('KIE_API_KEY is not set. Pass --dry-run to plan without generating, or export the key.');
    process.exitCode = 1;
    return;
  }

  const dir = lessonsDir();
  let entries: string[];
  try {
    entries = (await fs.readdir(dir)).filter(f => f.endsWith('.json'));
  } catch {
    console.error(`No lessons directory found at ${dir}`);
    process.exitCode = 1;
    return;
  }

  let totalGenerated = 0;
  let totalSkipped = 0;
  let totalFailed = 0;
  let totalPlanned = 0;

  for (const file of entries) {
    const lesson = await readLessonFile(path.join(dir, file));
    if (!lesson) continue;
    const stats = await ensureImagesForLesson(lesson, args, apiKey);
    totalGenerated += stats.generated;
    totalSkipped += stats.skipped;
    totalFailed += stats.failed;
    totalPlanned += stats.planned;
  }

  console.log(`[gen-image] done. generated=${totalGenerated} skipped=${totalSkipped} failed=${totalFailed} (planned=${totalPlanned})`);
  if (totalFailed > 0) process.exitCode = 1;
}

main().catch(err => {
  console.error('[gen-image] unhandled error:', err);
  process.exit(1);
});
