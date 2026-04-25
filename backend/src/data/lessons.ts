import fs from 'fs';
import path from 'path';
import { LessonSchema } from './lessonSchema';

export interface ExerciseFeedback {
  explanation: string;
}

export interface FillBlankExercise {
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

export interface MultipleChoiceExercise {
  exercise_id: string;
  type: 'multiple_choice';
  instruction: string;
  prompt: string;
  options: MultipleChoiceOption[];
  correct_option_id: string;
  image?: ExerciseImage;
  feedback?: ExerciseFeedback;
}

export interface SentenceCorrectionExercise {
  exercise_id: string;
  type: 'sentence_correction';
  instruction: string;
  prompt: string;
  accepted_corrections: string[];
  borderline_ai_fallback: true;
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

export interface ListeningDiscriminationExercise {
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

function loadLessons(): Lesson[] {
  const dataDir = path.resolve(__dirname, '../../data');
  const manifestPath = path.join(dataDir, 'manifest.json');
  const manifestRaw = fs.readFileSync(manifestPath, 'utf8');
  const manifest = JSON.parse(manifestRaw) as Manifest;

  if (!manifest.lessons?.length) {
    throw new Error(`No lessons found in manifest: ${manifestPath}`);
  }

  return manifest.lessons.map((entry) => {
    const lessonPath = path.join(dataDir, entry.file);
    const lessonRaw = fs.readFileSync(lessonPath, 'utf8');
    const lesson = assertLesson(JSON.parse(lessonRaw), lessonPath);

    if (lesson.lesson_id !== entry.lesson_id) {
      throw new Error(
        `Lesson id mismatch for ${lessonPath}: manifest=${entry.lesson_id}, payload=${lesson.lesson_id}`
      );
    }

    return lesson;
  });
}

const LESSONS = loadLessons();
const INDEX = new Map(LESSONS.map((lesson) => [lesson.lesson_id, lesson]));

export function getLessonById(id: string): Lesson | undefined {
  return INDEX.get(id);
}

export function getAllLessons(): Lesson[] {
  return LESSONS;
}
