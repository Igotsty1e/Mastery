import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { LessonSchema } from './lessonSchema';

export interface ExerciseFeedback {
  explanation: string;
}

// Learning Engine Wave 1 metadata (LEARNING_ENGINE.md §§5, 6.5).
// Optional during the backfill; meaning_frame is required by the schema
// when evidence_tier is "strongest". The runtime ignores the fields beyond
// validation; they reach the client unchanged so future engine waves can
// use them.
// Wave 10: error model 6→4 per V1 spec.
export type TargetError =
  | 'conceptual_error'
  | 'form_error'
  | 'contrast_error'
  | 'careless_error';

export type EvidenceTier = 'weak' | 'medium' | 'strong' | 'strongest';

export interface ExerciseEngineMetadata {
  skill_id?: string;
  primary_target_error?: TargetError;
  evidence_tier?: EvidenceTier;
  meaning_frame?: string;
  // Wave 12 — diagnostic-probe eligibility flag. Defaults to false.
  // Diagnostic items still serve in regular sessions; the flag is
  // about probe inclusion, not main-bank exclusion.
  is_diagnostic?: boolean;
}

export interface FillBlankExercise extends ExerciseEngineMetadata {
  exercise_id: string;
  type: 'fill_blank';
  instruction: string;
  prompt: string;
  accepted_answers: string[];
  image?: ExerciseImage;
  feedback?: ExerciseFeedback;
}

export interface MultipleChoiceOption {
  id: string;
  text: string;
}

export interface MultipleChoiceExercise extends ExerciseEngineMetadata {
  exercise_id: string;
  type: 'multiple_choice';
  instruction: string;
  prompt: string;
  options: MultipleChoiceOption[];
  correct_option_id: string;
  image?: ExerciseImage;
  feedback?: ExerciseFeedback;
}

export interface SentenceCorrectionExercise extends ExerciseEngineMetadata {
  exercise_id: string;
  type: 'sentence_correction';
  instruction: string;
  prompt: string;
  accepted_corrections: string[];
  image?: ExerciseImage;
  feedback?: ExerciseFeedback;
}

// Wave 14.2 — V1.5 open-answer family, phase 1.
//
// `sentence_rewrite` asks the learner to rewrite the (correct) prompt
// under a transformation constraint stated in `instruction`
// (e.g. "Rewrite using past perfect"). The runtime evaluator mirrors
// `sentence_correction` (deterministic match against
// `accepted_answers`, AI fallback for borderline submissions).
export interface SentenceRewriteExercise extends ExerciseEngineMetadata {
  exercise_id: string;
  type: 'sentence_rewrite';
  instruction: string;
  prompt: string;
  accepted_answers: string[];
  image?: ExerciseImage;
  feedback?: ExerciseFeedback;
}

export interface ExerciseAudio {
  url: string;
  voice: 'nova' | 'onyx';
  transcript: string;
}

export type ExerciseImageRole =
  | 'scene_setting'
  | 'context_support'
  | 'disambiguation'
  | 'listening_support';

export type ExerciseImagePolicy = 'optional' | 'recommended' | 'required';

export interface ExerciseImage {
  url: string;
  alt: string;
  role: ExerciseImageRole;
  policy: ExerciseImagePolicy;
  /** Authoring brief; stripped before client response. */
  brief?: string;
  /** Authoring constraint; stripped before client response. */
  dont_show?: string;
  /** Authoring risk class; stripped before client response. */
  risk?: 'low' | 'medium' | 'high';
}

export interface ListeningDiscriminationExercise extends ExerciseEngineMetadata {
  exercise_id: string;
  type: 'listening_discrimination';
  instruction: string;
  audio: ExerciseAudio;
  options: MultipleChoiceOption[];
  correct_option_id: string;
  image?: ExerciseImage;
  feedback?: ExerciseFeedback;
}

export type Exercise =
  | FillBlankExercise
  | MultipleChoiceExercise
  | SentenceCorrectionExercise
  | SentenceRewriteExercise
  | ListeningDiscriminationExercise;

export interface Lesson {
  lesson_id: string;
  title: string;
  language: string;
  level: string;
  intro_rule: string;
  intro_examples: string[];
  exercises: Exercise[];
}

interface ManifestEntry {
  lesson_id: string;
  file: string;
  unit_id?: string;
  rule_tag?: string;
  micro_rule_tag?: string;
}

export interface LessonMeta {
  lesson_id: string;
  title: string;
  slug: string;
  level: string;
  language: string;
  exercise_count: number;
  unit_id: string | null;
  rule_tag: string | null;
  micro_rule_tag: string | null;
  // sha256 hex of the canonical lesson JSON. Stable across whitespace edits
  // because we re-stringify with sorted keys before hashing.
  content_hash: string;
  // Authoring-side opaque version label. Today equals `content_hash`; left
  // as a separate field so a hand-rolled version (e.g. "v3") can replace it
  // without forcing the persisted attempt history to follow.
  lesson_version: string;
  // Manifest order, 1-indexed. Used by the dashboard for recommended-next
  // selection (lowest order wins among incomplete lessons).
  order: number;
}

interface Manifest {
  lessons: ManifestEntry[];
}

function assertLesson(value: unknown, source: string): Lesson {
  const parsed = LessonSchema.safeParse(value);
  if (!parsed.success) {
    throw new Error(
      `Invalid lesson payload in ${source}: ${parsed.error.issues
        .map((i) => `${i.path.join('.') || '<root>'}: ${i.message}`)
        .join('; ')}`
    );
  }
  return parsed.data as unknown as Lesson;
}

function slugify(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

// Deterministic JSON.stringify that sorts object keys recursively. We want
// the same lesson content to produce the same hash regardless of how the
// fixture file orders its keys, so that whitespace-only or key-order edits
// to the JSON do not invalidate every learner's persisted attempt history.
function canonicalStringify(value: unknown): string {
  if (value === null || typeof value !== 'object') {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((v) => canonicalStringify(v)).join(',')}]`;
  }
  const obj = value as Record<string, unknown>;
  const keys = Object.keys(obj).sort();
  return `{${keys
    .map((k) => `${JSON.stringify(k)}:${canonicalStringify(obj[k])}`)
    .join(',')}}`;
}

interface LoadedLesson {
  lesson: Lesson;
  meta: LessonMeta;
}

function loadLessons(): LoadedLesson[] {
  const dataDir = path.resolve(__dirname, '../../data');
  const manifestPath = path.join(dataDir, 'manifest.json');
  const manifestRaw = fs.readFileSync(manifestPath, 'utf8');
  const manifest = JSON.parse(manifestRaw) as Manifest;

  if (!manifest.lessons?.length) {
    throw new Error(`No lessons found in manifest: ${manifestPath}`);
  }

  return manifest.lessons.map((entry, idx) => {
    const lessonPath = path.join(dataDir, entry.file);
    const lessonRaw = fs.readFileSync(lessonPath, 'utf8');
    const lesson = assertLesson(JSON.parse(lessonRaw), lessonPath);

    if (lesson.lesson_id !== entry.lesson_id) {
      throw new Error(
        `Lesson id mismatch for ${lessonPath}: manifest=${entry.lesson_id}, payload=${lesson.lesson_id}`
      );
    }

    const contentHash = crypto
      .createHash('sha256')
      .update(canonicalStringify(lesson))
      .digest('hex');

    const meta: LessonMeta = {
      lesson_id: lesson.lesson_id,
      title: lesson.title,
      slug: slugify(lesson.title),
      level: lesson.level,
      language: lesson.language,
      exercise_count: lesson.exercises.length,
      unit_id: entry.unit_id ?? null,
      rule_tag: entry.rule_tag ?? null,
      micro_rule_tag: entry.micro_rule_tag ?? null,
      content_hash: contentHash,
      lesson_version: contentHash,
      order: idx + 1,
    };

    return { lesson, meta };
  });
}

const LOADED = loadLessons();
const LESSONS = LOADED.map((l) => l.lesson);
const META_LIST = LOADED.map((l) => l.meta);
const INDEX = new Map(LOADED.map((l) => [l.lesson.lesson_id, l.lesson]));
const META_INDEX = new Map(LOADED.map((l) => [l.meta.lesson_id, l.meta]));

export function getLessonById(id: string): Lesson | undefined {
  return INDEX.get(id);
}

export function getAllLessons(): Lesson[] {
  return LESSONS;
}

export function getLessonMeta(id: string): LessonMeta | undefined {
  return META_INDEX.get(id);
}

export function getAllLessonMeta(): LessonMeta[] {
  return META_LIST;
}
