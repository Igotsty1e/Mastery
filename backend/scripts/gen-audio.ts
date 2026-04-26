/**
 * Offline TTS pipeline for `listening_discrimination` exercises.
 *
 * Reads every lesson fixture under backend/data/lessons/, finds every
 * `listening_discrimination` exercise, and synthesises an mp3 clip per item
 * via the OpenAI TTS API. The output goes to:
 *
 *   backend/public/audio/{lesson_id}/{exercise_id}.mp3
 *   backend/public/audio/{lesson_id}/{exercise_id}.meta.json
 *
 * The sidecar `meta.json` carries a sha256 hash of `voice + transcript`. On
 * re-run we only call the API for items whose hash changed, so authoring
 * iterations are cheap.
 *
 * Usage:
 *   OPENAI_API_KEY=sk-... npm run gen:audio
 *   OPENAI_API_KEY=sk-... npm run gen:audio -- --force      # regenerate all
 *   OPENAI_API_KEY=sk-... npm run gen:audio -- --dry-run    # show plan only
 *
 * Authoritative spec: docs/plans/roadmap.md §3 Workstream B.
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import { LessonSchema, type Lesson } from '../src/data/lessonSchema';

const TTS_MODEL = 'tts-1';
const TTS_BASE_URL = process.env.OPENAI_TTS_BASE_URL?.replace(/\/+$/, '') || 'https://api.openai.com/v1';

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

function audioDir(lessonId: string): string {
  return path.resolve(process.cwd(), 'public', 'audio', lessonId);
}

interface MetaSidecar {
  voice: 'nova' | 'onyx';
  transcript: string;
  hash: string;
  generated_at: string;
  bytes: number;
}

function hashContent(voice: string, transcript: string): string {
  return crypto
    .createHash('sha256')
    .update(`${voice}\n${transcript}`)
    .digest('hex');
}

async function readLessonFile(file: string): Promise<Lesson | null> {
  const raw = await fs.readFile(file, 'utf8');
  const parsed = JSON.parse(raw);
  const result = LessonSchema.safeParse(parsed);
  if (!result.success) {
    console.warn(`[gen-audio] skipping invalid lesson ${file}: ${result.error.issues[0]?.message ?? 'schema error'}`);
    return null;
  }
  return result.data;
}

async function readMeta(file: string): Promise<MetaSidecar | null> {
  try {
    const raw = await fs.readFile(file, 'utf8');
    return JSON.parse(raw) as MetaSidecar;
  } catch {
    return null;
  }
}

async function fetchTtsMp3(voice: 'nova' | 'onyx', transcript: string, apiKey: string): Promise<Uint8Array> {
  const res = await fetch(`${TTS_BASE_URL}/audio/speech`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: TTS_MODEL,
      voice,
      input: transcript,
      response_format: 'mp3',
    }),
  });

  if (!res.ok) {
    const errText = await res.text().catch(() => '');
    throw new Error(`OpenAI TTS error ${res.status} ${res.statusText}: ${errText}`);
  }

  const buf = new Uint8Array(await res.arrayBuffer());
  if (buf.length === 0) {
    throw new Error('OpenAI TTS returned an empty body');
  }
  return buf;
}

async function ensureAudioForLesson(lesson: Lesson, args: Args, apiKey: string | null): Promise<{ generated: number; skipped: number; failed: number }> {
  const stats = { generated: 0, skipped: 0, failed: 0 };
  const outDir = audioDir(lesson.lesson_id);

  const listeningItems = lesson.exercises.filter(e => e.type === 'listening_discrimination');
  if (listeningItems.length === 0) return stats;

  await fs.mkdir(outDir, { recursive: true });

  for (const ex of listeningItems) {
    if (ex.type !== 'listening_discrimination') continue; // narrowing
    const voice = ex.audio.voice;
    const transcript = ex.audio.transcript;
    const hash = hashContent(voice, transcript);
    const mp3Path = path.join(outDir, `${ex.exercise_id}.mp3`);
    const metaPath = path.join(outDir, `${ex.exercise_id}.meta.json`);

    const existing = await readMeta(metaPath);
    const upToDate = existing && existing.hash === hash;

    if (upToDate && !args.force) {
      stats.skipped += 1;
      continue;
    }

    const action = args.force ? 'regenerate' : (existing ? 'update' : 'generate');
    console.log(`[gen-audio] ${lesson.lesson_id} ${ex.exercise_id} ${action} voice=${voice} chars=${transcript.length}`);

    if (args.dryRun) {
      stats.generated += 1;
      continue;
    }

    if (!apiKey) {
      console.error(`[gen-audio] OPENAI_API_KEY is required to generate audio. Set it or pass --dry-run.`);
      stats.failed += 1;
      continue;
    }

    try {
      const mp3 = await fetchTtsMp3(voice, transcript, apiKey);
      await fs.writeFile(mp3Path, mp3);
      const meta: MetaSidecar = {
        voice,
        transcript,
        hash,
        generated_at: new Date().toISOString(),
        bytes: mp3.length,
      };
      await fs.writeFile(metaPath, `${JSON.stringify(meta, null, 2)}\n`);
      stats.generated += 1;
    } catch (err) {
      console.error(`[gen-audio] FAILED ${lesson.lesson_id} ${ex.exercise_id}: ${(err as Error).message}`);
      stats.failed += 1;
    }
  }

  return stats;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const apiKey = process.env.OPENAI_API_KEY ?? null;

  if (!apiKey && !args.dryRun) {
    console.error('OPENAI_API_KEY is not set. Pass --dry-run to plan without generating, or export the key.');
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

  for (const file of entries) {
    const lesson = await readLessonFile(path.join(dir, file));
    if (!lesson) continue;
    const stats = await ensureAudioForLesson(lesson, args, apiKey);
    totalGenerated += stats.generated;
    totalSkipped += stats.skipped;
    totalFailed += stats.failed;
  }

  console.log(`[gen-audio] done. generated=${totalGenerated} skipped=${totalSkipped} failed=${totalFailed}`);
  if (totalFailed > 0) process.exitCode = 1;
}

main().catch(err => {
  console.error('[gen-audio] unhandled error:', err);
  process.exit(1);
});
