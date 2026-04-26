import type { Exercise } from './lessons';

// Image objects carry an authoring layer (brief / dont_show / risk) used by
// the gen-image pipeline. None of those should reach the client.
function stripImageAuthoring(image: NonNullable<Exercise['image']>): object {
  const { brief: _b, dont_show: _d, risk: _r, ...pub } = image;
  return pub;
}

// Produce the wire-level exercise object for GET /lessons/:lessonId.
// Strips correctness signals + curated feedback + image authoring metadata.
// All other fields — including the Wave 1 engine metadata
// (skill_id, primary_target_error, evidence_tier, meaning_frame) — pass
// through unchanged.
export function projectExerciseForClient(exercise: Exercise): object {
  const stripImage = (e: Exercise) =>
    e.image ? { image: stripImageAuthoring(e.image) } : {};

  if (exercise.type === 'fill_blank') {
    const { accepted_answers: _a, feedback: _f, image: _i, ...pub } = exercise;
    return { ...pub, ...stripImage(exercise) };
  }
  if (exercise.type === 'multiple_choice') {
    const { correct_option_id: _c, feedback: _f, image: _i, ...pub } = exercise;
    return { ...pub, ...stripImage(exercise) };
  }
  if (exercise.type === 'listening_discrimination') {
    // Keep audio.transcript on the wire — the client reveals it on demand
    // for accessibility and the `Show transcript` toggle. Only strip the
    // correctness signal and the post-submit feedback string.
    const { correct_option_id: _c, feedback: _f, image: _i, ...pub } = exercise;
    return { ...pub, ...stripImage(exercise) };
  }
  // sentence_correction
  const { accepted_corrections: _ac, feedback: _f, image: _i, ...pub } = exercise;
  return { ...pub, ...stripImage(exercise) };
}
