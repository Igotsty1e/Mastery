# Pedagogy Principles

The "why" behind the design choices this skill makes. Read when you need to defend a choice or when the request is unusual enough that defaults don't obviously apply.

## 1. Form / meaning / use — the three faces of grammar

Larsen-Freeman's framework: every grammatical form has three dimensions.

- **Form** — how it's built (morphology, syntax, spelling/sound).
- **Meaning** — what it semantically encodes.
- **Use** — when speakers/writers choose it (register, function, discourse).

A complete grammar exercise touches all three over the course of a sequence. Pure controlled drills only touch *form*. That's why this skill defaults to *mixing* exercise types — gap-fill alone is incomplete.

When designing a single item, identify which face it targets. State it in the design notes so the user can see the coverage of the set.

## 2. PPP and its critique

The traditional sequence: **Presentation → Practice → Production**. Still the dominant lesson architecture, especially at lower levels.

Critique (Thornbury, others): PPP front-loads form before meaning, so the production stage often produces *form-correct but pragmatically odd* output. The alternative (TBLT — Task-Based Language Teaching) starts from a communicative task and brings form in as needed.

This skill is methodologically agnostic. If a project document specifies PPP, default to it. If it specifies TBLT, restructure: task first, with form-focused episodes inserted at points of need. If neither is specified at lower levels, default to PPP; at B2+ default to a hybrid.

## 3. Noticing (Schmidt's hypothesis)

Learners are unlikely to acquire a form they haven't *consciously noticed* in input. Hence the value of Tier 1 noticing exercises (`exercise-types.md` § N1–N3) at the start of any sequence introducing or revisiting a form.

Practical implication: when the user asks for "10 exercises on Present Perfect", don't make all 10 controlled drills. One noticing item up front does more for retention than two extra drills.

## 4. Distractor design (for MCQ and error correction)

The single biggest quality lever in multiple-choice writing.

A good distractor:

- **Encodes a specific predictable error.** A B1 learner of Russian L1 who picks distractor (b) over correct (a) should reveal a known misconception (e.g., L1 transfer of aspect, omission of the article, *do*-support confusion).
- **Is plausible enough to make a learner pause.** If three distractors are obviously wrong, the item tests reading speed, not the form.
- **Differs minimally from the correct answer.** Often this means the same lemma in a different inflection, a confusable preposition, or a word with overlapping but non-identical meaning.
- **Does not contain a *second* error.** A distractor with two errors is "doubly wrong" — it doesn't test what you think it tests.

A common error catalogue for L1-Russian learners (use as a distractor source when the audience is RU-speaking):

- Article omission/over-use (no/the where standard English requires the/zero).
- Aspect transfer — using Present Continuous for habitual ("Every day I am going to work").
- Tense for unreal/conditional — using Past Continuous for "would be doing".
- Word order in indirect questions ("I don't know what is it").
- Verb + preposition mismatches (`depend on` vs `depend from`, `marry to`/`marry with`).
- *Make* vs *do*; *say* vs *tell*; *win* vs *beat*; *learn* vs *teach*.
- Confusion of *advice* (uncountable) and *advices*.
- *Since/for* substitution.
- Auxiliary omission in negatives/questions ("She not like coffee").
- *The* before generic plurals ("The Russians like tea").

For exam alignment, the *Cambridge English: Item Writer Guidelines* (internal but well-summarised in many EFL books) call this "diagnostic distractor design" — every distractor explains a different misconception.

## 5. Authentic-feeling context

Avoid "John went to the shop" sentences disconnected from any world. Each item set should have an implicit (or explicit) context: a person, a place, a situation. This:

- Makes items more memorable (episodic anchoring).
- Makes the *reason* for the form's appearance more honest (you wouldn't naturally say "She has lived here since 2010" without a reason — give it one).
- Makes the set feel like real curriculum content, not generator filler.

Suggested heuristic: pick *one* context for the whole exercise (one character / one scenario) and write all items inside it.

## 6. Lexical level alignment

A grammar exercise targeting a B1 form *must* use vocabulary the learner knows. Otherwise it stops being a grammar exercise and becomes a vocabulary test in disguise.

Cross-check vocabulary against:
- English Vocabulary Profile (Cambridge) — gold standard.
- Or, as a heuristic: would a learner who passed the corresponding Cambridge exam (PET for B1, FCE for B2…) know this word?

If you must use a higher-level word for context, gloss it inline.

## 7. Rubrics and instructions

Bad rubrics break good exercises. Patterns to follow:

- Use the imperative. "Complete the sentences with the correct form of the verb in brackets." Not "Students should complete…"
- One sentence per rubric, ideally.
- Match the language of the rubric to the learner's level (or below). At A2, "Choose A, B or C" — not "Identify the most appropriate option among the alternatives provided".
- Show *one worked example* before the items if the format is non-trivial. Mark it `0.` or with `(example)`.

## 8. Answer keys and feedback

Each item's answer should include:

- **The answer** (string, list, or position).
- **A short explanation** stating the rule the learner should be applying. ≤ 2 sentences. In learner-level English (or the learner's L1 if the project's metadata language is L1).
- **(Optional) wrong-answer diagnostics** — for MCQ, a one-liner per distractor explaining what mistake it represents.

A teacher reviewing these should be able to use the explanation as-is in feedback.

## 9. Sequencing within a set

If you're producing a set of multiple exercises, sequence them:

1. Tier-1 (noticing) item or two.
2. Tier-2 (controlled) — start with the most form-focused (gap-fill), move to discriminating (MCQ, error correction), then transformation.
3. Tier-3 (meaningful) — personalisation or info-gap.
4. Optional Tier-4 (free) production prompt.

If the user asked for a single exercise type, don't add the others; but flag in design notes "this is single-tier; for a balanced lesson, pair with X and Y."

## 10. Cultural and ethical care

- Avoid sentences that stereotype gender, ethnicity, religion, body shape.
- Avoid politically loaded examples unless the topic is the lesson focus and the project signals it.
- Use a balanced range of names (not all Anglo).
- Don't put learners in unpleasant scenarios (illness, death, violence) unless the exam genre actively requires it (e.g., narrative writing in CAE).

## 11. Variety beats perfection

If you find yourself writing 10 items that all fit the pattern "[Subject] _____ (verb) [object] for/since [time]", stop and vary. Same form, different contexts, different sentence shapes. Repetition of *form* is the goal; repetition of *frame* is laziness.

## 12. When the project's docs override these principles

Project conventions win. If a curriculum document says "all exercises must include 5 items", do 5 even if you'd prefer 8. If it says "no transformation tasks below B2", respect it. The principles in this file are defaults for when the project doesn't say.
