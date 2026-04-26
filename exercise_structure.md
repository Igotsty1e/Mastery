# exercise_structure — Mastery

## Status

Canonical source of truth for exercise design and authoring rules.

This document is one of the **three sibling top-level canonical docs**
(per `GRAM_STRATEGY.md §Authority chain`). It is itself authoritative on
**exercise authoring** questions; it defers to its siblings on questions
they own:

- For **pedagogical** claims (what we teach and why), `GRAM_STRATEGY.md`
  wins.
- For **engine invariants** (skill rollup, evidence tier, multi-error
  rules, mastery accounting), `LEARNING_ENGINE.md` wins; this file is
  updated to follow.

This file governs:
- exercise taxonomy
- hard authoring rules
- sequencing inside lessons
- distractor design
- explanation design
- runtime mapping
- future exercise expansion logic

All shipped exercise output must compile exactly to the runtime schema and scoring
rules defined in `docs/content-contract.md`.

This file is the authoring counterpart to `LEARNING_ENGINE.md`. The engine
spec defines **what an exercise must declare** (skill, target error,
evidence tier); this file defines **how to write the exercise** so those
declarations are honest.

---

## 1. Core Rule

Every exercise must help the learner make one better English decision.

That decision may be:
- choosing the right form
- rejecting a wrong contrast
- retrieving a pattern
- repairing a common learner error
- applying a rule in bounded context

If the author cannot state the exact decision in one sentence, the exercise is not
ready to ship.

---

## 2. Global Authoring Rules

These rules apply to every exercise type.

### 2.1 One Dominant Target

Each item tests one dominant grammar choice.

Allowed:
- one local support fix that is inseparable from the main choice

Not allowed:
- combining multiple unrelated rules into one item

Engine-level statement of the same rule:

> **1 exercise = 1 primary skill + 1 primary target error.**

The metadata fields that operationalise this rule
(`skill_id`, `primary_target_error`, `evidence_tier`, and —
where applicable — `meaning_frame`) are **not yet required** in shipped
fixtures. They are introduced as **optional fields** in
`docs/plans/learning-engine-mvp-2.md` Wave 1 (the metadata layer), become
**required for new content** as that wave rolls out, and are backfilled
on existing fixtures inside the same wave. Until Wave 1 ships, current
fixtures correctly omit the fields and the runtime does not require them.

The pedagogical rule itself (one primary skill, one primary target error
per item) applies at authoring time today. The declarative metadata
representation lands when the engine layer ships (see
`LEARNING_ENGINE.md §4 Skill Model` and `§5 Error Model`). Multi-error
items are a narrow exception governed by §5.8 Multi-Error Correction —
every error in the item must roll up to the **same** primary skill and
the **same** primary target error.

### 2.2 Natural Language Only

Prompts and options must sound like plausible adult English.

Reject:
- nonsense
- strange collocations
- unnatural formalism written only to force one answer

### 2.3 Explicit Task Instruction

The learner must know exactly what to do before reading the prompt.

Weak:
- "Answer the question."

Strong:
- "Choose the correct option."
- "Complete the gap with the correct verb form."
- "Rewrite the sentence correctly."

### 2.4 Observable Scoring Contract

The answer space must be clear enough that:
- a human reviewer would know what counts as correct
- the backend can evaluate it fairly

Do not author items whose correct answer space is unknown or unstable.

### 2.5 Contrast Matters

A strong exercise contains:
- one correct answer
- plausible wrong answers or wrong paths that reflect real learner confusion

### 2.6 Explanation Must Match The Wrong Decision

Feedback must explain the rule actually tested, not a generic grammar fact.

### 2.7 CEFR And Vocabulary Control

Grammar may be B2 while vocabulary remains reasonably accessible.

Do not stack:
- obscure vocabulary
- dense cultural references
- advanced discourse complexity

unless the lesson explicitly targets that domain.

### 2.8 Lesson-Level Inputs Must Be Fixed First

Before authoring an exercise set, define:
- `target form`
- `target CEFR`
- `lesson context`
- `lesson archetype`
- `core contrast`
- `expected learner errors`
- `scoring mode`

If these are not fixed, the set is not ready for generation or review.

### 2.8.1 Intro Contrast Presentation Contract

When a lesson includes a rule-introduction screen with FORM, IMPORTANT, and
EXAMPLES blocks, the author must specify how the contrast will be made visible.

This is not optional decoration.
It is part of the teaching contract.

For every contrasted pattern, define:
- `common_part`
  - the words that stay visually neutral
- `variable_part`
  - the exact slot that must be highlighted
- `contrast_pair`
  - the opposing pattern shown alongside it
- `example_pair`
  - the examples that mirror the same highlighted slot

Hard rules:
- highlight only the minimum slot needed to show the contrast
- never highlight the entire formula if only one local slot carries the decision
- the same slot must receive the same visual treatment in FORM and EXAMPLES
- paired forms should be authored so they can be stacked vertically with aligned changing parts
- IMPORTANT should restate the contrast in a short paired structure, not a long paragraph

Bad:
- highlighting the full sentence
- highlighting auxiliaries, subjects, and punctuation for visual richness
- placing examples in one long list where the learner must infer which form each example belongs to

Good:
- neutral `have / has`, highlighted `been + verb-ing`
- neutral `have / has`, highlighted `past participle`
- neutral sentence frame, highlighted `for`
- neutral sentence frame, highlighted `since`

### 2.9 Visual Context Layer

Some exercises may benefit from an image, illustration, or scene-setting visual.
This is a separate authoring layer, not decoration.

The visual context layer answers one question only:
- does this exercise become clearer and pedagogically stronger with an image?

It does **not** decide:
- visual style
- palette
- illustration rendering technique
- UI placement details beyond the pedagogical role

Those are governed by `DESIGN.md`.

Authoring rule:
- first decide whether the exercise should be text-only or image-supported
- only after that decision may a design/image workflow generate the actual asset

Every exercise that is considered for imagery must define:
- `image_policy`
  - `none`
  - `optional`
  - `recommended`
  - `required`
- `image_role`
  - `scene_setting`
  - `context_support`
  - `disambiguation`
  - `listening_support`
- `image_brief`
  - one short description of what the image must show
- `image_dont_show`
  - what the image must not reveal or imply
- `image_risk`
  - `low`
  - `medium`
  - `high`

Default:
- every exercise starts as `image_policy = none`
- the burden of proof is on adding the image, not on omitting it

An image is allowed only if all of the following are true:
1. it establishes context faster than text alone
2. it does not make the correct answer obvious
3. it does not introduce a second plausible interpretation of the task
4. it fits the calm, adult, high-trust product language in `DESIGN.md`

Reject imagery if:
- it exists only to make the exercise look richer
- it turns the item into a picture-guessing task
- it gives away the right option directly
- it adds emotional noise, humor, or childish tone
- the scene is too ambiguous to support deterministic scoring

Strong candidates for imagery:
- scenario-based `multiple_choice`
- `listening_discrimination`
- selected lesson-intro examples
- contrast items where a scene clarifies who is speaking, what happened, or what timeline is being referenced

Weak candidates for imagery:
- most `fill_blank`
- most `sentence_correction`
- any item where the sentence already carries the full decision cleanly

Operational rule:
- exercise authoring decides `if`
- design decides `how`

See:
- `DESIGN.md §Illustration and Imagery`
- `DESIGN.md §Component System`

---

## 3. Exercise Taxonomy

Mastery uses two layers:
- `pedagogical exercise families` — the long-term learning system
- `runtime exercise widgets` — what the app currently supports

### 3.1 Pedagogical Families

| Family | Primary learner action | Typical purpose | Current app |
|---|---|---|---|
| Recognition choice | identify correct form | early contrast, low-load checking | supported (`multiple_choice`) |
| Plural recognition / multi-select | identify **all** correct items in a small set | dense recognition with anti-gaming guard | roadmap (engine alias `multi_select`, see §5.6) |
| Controlled completion | supply missing form | controlled production | supported (`fill_blank`) |
| Multi-blank controlled completion | supply more than one form against the same rule | parallel retrieval | roadmap (engine alias `multi_blank`, see §5.7) |
| Guided correction | repair wrong sentence | error awareness and repair | supported (`sentence_correction`) |
| Multi-error correction | repair multiple errors that all roll up to the same primary skill | dense repair drilling | roadmap (engine alias `multi_error_correction`, see §5.8) |
| Transformation | rewrite into a target pattern | guided production | roadmap (engine alias `sentence_rewrite`, see §5.1) |
| Matching / sorting | pair forms, meanings, or triggers | noticing and contrast | roadmap |
| Ordering / build-a-sentence | construct correct syntax | word order and structure control | roadmap |
| Dialogue completion | choose or produce a line in context | contextualized grammar choice | roadmap |
| Constrained short production | produce one short original sentence within limits | bounded transfer | roadmap (engine alias `short_free_sentence`, see §5.5) |
| Listening discrimination | hear and identify the target form | auditory noticing | shipped — see §5.9 |
| Speaking production | say the target form aloud | production + transfer | out of scope |

The five families with engine aliases above are the new families
sequenced into `docs/plans/learning-engine-mvp-2.md Wave 6`. Their
engine-side safeguards live in `LEARNING_ENGINE.md §8.4.1`.

### 3.2 Current Runtime Widgets

Current shipped runtime supports:
- `fill_blank`
- `multiple_choice`
- `sentence_correction`
- `listening_discrimination`

These are the exercise widgets that may appear in current shipped lessons.

---

## 4. Current Runtime Types — Hard Rules

## 4.1 `fill_blank`

### Pedagogical role

Use `fill_blank` when the learner should retrieve one specific form from a controlled
context.

Best for:
- verb form after a trigger
- article / preposition / linker choice when answer space is narrow
- tense or structure retrieval when the context clearly points to one answer

Not good for:
- broad paraphrase
- open expression
- cases with many equally valid completions

### Hard authoring rules

- exactly one blank
- exactly one dominant target
- prompt must contain enough context to justify the answer
- accepted answers must enumerate all teacher-approved valid completions
- if the valid answer space is too wide, do not use `fill_blank`
- every `fill_blank` prompt must include the **base form** of the target
  verb in parentheses immediately after the blank, e.g.
  `"She _____ (live) here since 2019."`. This is the canonical EFL gap-fill
  convention (Cambridge / Murphy / Swan): it removes lexical ambiguity (the
  learner does not have to guess *which* verb is being tested) while
  preserving the grammatical decision (the learner still has to choose
  tense, aspect, or form). Validated by the
  `english-grammar-methodologist` skill canon, `references/exercise-types.md
  §C1 Gap-fill recipe step 2`.
- the verb hint must be the **base form** (`work`, not `worked`); supplying
  an inflected form would defeat the test of grammatical retrieval.
- the verb hint may be replaced by an image with role `disambiguation`
  (image carries the lexical content, the learner derives the verb from the
  picture and applies the grammar). This is the only allowed substitute,
  and only when the image cannot also reveal tense, aspect, completion, or
  any other dimension under test (`§2.9 acceptance criteria`,
  `§6.6.1 image+audio edge case`).

### Preferred difficulty profile

- early-to-middle lesson
- low-to-medium freedom
- medium retrieval load

### Good example

Instruction:
`Complete the gap with the correct verb form.`

Prompt:
`She suggested ___ a taxi because it was late.`

Why it works:
- one clear trigger: `suggest`
- one dominant target: `-ing`
- natural sentence

### Weak example

Prompt:
`They ___ after the meeting.`

Why it fails:
- answer space too wide
- not clear what rule is tested

---

## 4.2 `multiple_choice`

### Pedagogical role

Use `multiple_choice` when the learner should recognize the correct pattern among
plausible contrasts.

Best for:
- nearby grammar contrasts
- meaning differences
- early checking after explanation
- review items where distractor design carries the teaching value

Not good for:
- trivial recall where only one option is remotely plausible
- hidden vocabulary tests disguised as grammar tests

### Hard authoring rules

- 2 to 4 options only
- exactly one correct option
- every distractor must be a plausible learner error
- distractors should represent different error logics where possible
- no joke options
- no distractor that is obviously impossible for unrelated reasons

### Distractor design

Good distractors usually come from:
- wrong form of the same verb
- wrong competing structure
- overgeneralized learner rule
- tense confusion
- agreement error

Bad distractors:
- random vocabulary
- impossible semantics
- misspellings used as fake difficulty

### Good example

Prompt:
`He keeps ___ about the same problem.`

Options:
- `complain`
- `complaining`
- `to complain`
- `complained`

Why it works:
- all options are superficially plausible
- only one respects the pattern after `keep`

### Weak example

Prompt:
`I enjoy ___ books.`

Options:
- `reading`
- `banana`
- `purple`
- `yesterday`

Why it fails:
- distractors do not represent real learner confusions

---

## 4.3 `sentence_correction`

### Pedagogical role

Use `sentence_correction` when the learner should detect and repair a typical learner
error.

This is not free production.
It is guided repair.

Best for:
- common high-value learner errors
- rule violations that become clearer in a full sentence
- later lesson items
- consolidation and review

Not good for:
- open stylistic improvement
- broad paraphrasing
- tasks where many distinct correct rewrites are equally likely

### Hard authoring rules

- the prompt must contain a clear grammatical problem
- the item must still have one dominant repair target
- accepted corrections must list teacher-approved valid rewrites
- if multiple natural rewrites are likely, authors must enumerate them
- avoid prompts where correction requires large semantic rewriting

### Accepted correction policy

Default mode:
- `teacher-key narrow`

Optional expanded mode:
- `listed valid variants`

Rules:
- default to one canonical teacher-key correction
- if the prompt naturally allows equivalent repairs of the same target structure,
  authors may list additional accepted corrections
- hard cap: `max 3 accepted_corrections`
- all listed corrections must be meaning-equivalent and must test the same target
- the 3-answer limit must not be used to silently allow different grammar choices

If more than 3 valid corrections are needed for fairness, the item is too open for
the current runtime and must be:
- rewritten
- mapped to a different exercise family
- or deferred until the app supports a better widget

### Important scoring note

In the current app, `sentence_correction` is a controlled scoring task with a narrow
accepted correction set.

Therefore:
- author it as a teacher-key repair task
- do not author it as if the learner is writing freely
- do not rely on AI to rescue broad valid rephrasings

### Good example

Prompt:
`I don't mind to wait for a few minutes.`

Why it works:
- common learner error
- clear local repair
- grammar target is visible

### Weak example

Prompt:
`This report is bad and the company should maybe change many things about it.`

Why it fails:
- too many possible improvements
- unclear target
- scoring space unstable

---

## 5. Planned Exercise Families — Future App

These are valid pedagogical families, but they require new widgets and updated scoring
contracts before they can ship.

## 5.1 Transformation

Engine alias: `sentence_rewrite`. Evidence tier is **strongest** when the
item is meaning-coupled per `LEARNING_ENGINE.md §6.3` (i.e. the prompt
forces the learner to commit to a meaning, not just swap a surface form);
otherwise the item drops to **strong-tier** evidence and does **not**
clear the §6.4 mastery production gate. Strongest-tier sentence_rewrite
items therefore must declare a `meaning_frame` field, the same way
`short_free_sentence` items do (§5.5).

### Use when

The learner should rewrite a sentence into a target structure while preserving meaning.

### Strong use cases

- reported speech
- passive transformations
- conditionals
- infinitive / gerund reformulation

### Hard rules

- the target structure must be explicit
- the meaning to preserve must be stable
- the answer space must be known in advance or robustly judgeable

### Bounded answer-space discipline

Transformation is a **constrained** rewrite, not free production. The author
must:

- name the target structure in the instruction
  (e.g. `Rewrite the sentence using the passive.`)
- enumerate the small set of grammar-equivalent rewrites that should count as
  correct, the same way `sentence_correction` enumerates `accepted_corrections`
- cap the accepted rewrite set with a hard ceiling (suggested `≤ 3`,
  matching the existing `sentence_correction` cap in §4.3) — if more than
  three rewrites are needed for fairness, the prompt is too open and must be
  re-scoped or deferred
- reject any prompt where preserving meaning naturally opens up many
  unrelated paraphrases (those belong in `short_free_sentence`, not here)

Authoring rule: if a human reviewer cannot list the accepted rewrites in
under a minute, the item is not ready.

### Example

`Rewrite the sentence using the passive.`

`People speak English in many countries.`

---

## 5.2 Matching / Sorting

### Use when

The learner should connect:
- form to meaning
- trigger to pattern
- sentence to function

### Strong use cases

- linking time expressions to tense choice
- grouping verbs by pattern
- matching sentence to meaning difference

### Hard rules

- categories must be mutually intelligible
- one item must not fit multiple bins unless explicitly marked

---

## 5.3 Ordering / Sentence Building

### Use when

The learner should build correct syntax from parts.

### Strong use cases

- question formation
- adverb placement
- word order after auxiliaries

### Hard rules

- use only when word order is the real target
- avoid overloading with difficult vocabulary at the same time

---

## 5.4 Dialogue Completion

### Use when

The learner should complete a short exchange where grammar choice depends on context.

### Hard rules

- context must be short and sufficient
- response space must be bounded

---

## 5.5 Constrained Short Production

Engine alias: `short_free_sentence` (strongest evidence tier).

### Use when

The learner should produce one original sentence under clear constraints.

### Hard rules

- the prompt must name the target structure
- scoring must accept a reasonable answer range
- feedback must judge grammar first, not style first

### Target-structure constraint

A `short_free_sentence` item is not "write any sentence on this topic." It
is a bounded production task with a **specific structural commitment** the
learner must satisfy.

Required authoring fields (engine metadata, planned):

- `target_structure` — the exact pattern the produced sentence must use
  (e.g. `present perfect continuous with for + duration`)
- `must_include[]` — the lexical/structural anchors the sentence must contain
  (e.g. `for`, an `-ing` verb form)
- `forbidden_patterns[]` — surface forms the learner often substitutes that
  would prove they sidestepped the target (e.g. `since` in a duration item,
  bare `to + infinitive` after `suggest`)
- `meaning_frame` — the topical / contextual frame the sentence must serve
  (per §11.1 of `GRAM_STRATEGY.md`: production counts only when meaning is
  also at stake)

### Scoring discipline — deterministic-first, AI-bounded

`short_free_sentence` is the family closest to free production but it must
remain scoreable. The scoring stack runs deterministic-first and only falls
back to AI inside an explicit, narrow envelope:

1. **Deterministic structural check.** Verify presence of `must_include[]`
   markers and absence of `forbidden_patterns[]`. A failure here is a
   deterministic `wrong`.
2. **Deterministic meaning frame check.** Verify the sentence respects the
   `meaning_frame` (e.g. duration context for present perfect continuous).
   May be implemented as keyword/regex sets in the simplest version.
3. **AI fallback for borderline grammaticality.** Only after (1) and (2)
   pass. AI is bounded to the same kind of decision as the existing
   `sentence_correction` borderline path: a short `correct/incorrect +
   feedback` verdict on the produced sentence, with the target structure
   explicitly in the prompt context.

Authoring rule: if the item cannot be made deterministic-first plus a
bounded AI fallback, it is not yet a `short_free_sentence` — it is open
production and out of scope for the current product (`GRAM_STRATEGY.md
§14`). The engine boundary statement in `LEARNING_ENGINE.md §12.4` defines
where AI is allowed to enter scoring.

---

## 5.6 Multi-Select

Engine alias: `multi_select` (weak evidence tier — recognition).

### Use when

The learner should identify **all** correct items in a small set, not just
one. Use sparingly — the family exists for cases where two or more options
are simultaneously valid by design (e.g. "Which of these are correct uses
of the past participle?").

### Hard authoring rules

- 3 to 6 options total
- between 1 and `n-1` options are correct (never zero, never all)
- each correct option and each distractor must reflect a real learner
  decision against the target rule (per §7 distractor strategy)
- never author an item where "select all" is the trivially safe answer

### Scoring rule

Multi-select must not be gameable by checking every box. Each item must
declare exactly one of two scoring modes in its metadata:

1. **Exact-set (default).** The item is `correct` only when the learner's
   selected set equals the canonical set exactly. Any other selection is
   `wrong`.
2. **Bounded partial credit (opt-in for engine MVP 2.0).**
   - raw score = `true_positive_count − false_positive_count`
   - normalised score = `raw / num_correct_options`, clamped to
     `[−1, 1]`
   - mapping: `< 0.5` → `wrong`, `0.5 ≤ score < 1.0` → `partial`,
     `score == 1.0` → `correct`

In both modes the same anti-gaming guards apply, regardless of the
formula's numeric output:

- selecting every option is treated as `wrong` by definition (gaming
  guard) — this overrides any partial-credit calculation
- selecting nothing is `wrong`, never `partial`

The chosen scoring mode for a given item must be declared in the exercise
metadata so the runtime cannot silently switch modes between items. The
runtime must reject any item whose declared mode would let
"select everything" outscore "select nothing."

### Distractors

Same rules as `multiple_choice` (§4.2). Every distractor must reflect a
real learner error, not filler.

---

## 5.7 Multi-Blank

Engine alias: `multi_blank` (medium evidence tier — controlled completion).

### Use when

The learner should retrieve more than one form in the same sentence, where
each blank is a separate, independent decision against the same target rule
(e.g. tense agreement across two clauses, two parallel `-ing` slots after
two trigger verbs).

### Hard authoring rules

- 2 or 3 blanks per item, never more
- exactly one primary skill across all blanks (per §2.1)
- exactly one primary target error across all blanks (per `LEARNING_ENGINE.md
  §5`); multi-blank items are **not** a vehicle for combining unrelated rules
- every blank must include the base-form hint convention from §4.1
  (`(work)`) where applicable, the same as single-blank `fill_blank`
- accepted answer set declared per blank, not as a single concatenated
  string — the runtime must score blanks independently

### No interdependent blanks

Interdependent blanks are banned. A blank is **interdependent** when its
correct answer changes depending on what the learner typed in another blank
of the same item (e.g. an item where Blank A is "is/are" and Blank B is
"working/works" and the right pair is `is working` or `are working` but not
`is works`).

This is banned because:

- it forces the evaluator to score against the cross-product of plausible
  pairs, which explodes the answer space
- it mixes one decision (subject-verb agreement) with another (form
  selection) inside one item, violating §2.1
- the learner cannot diagnose which blank they actually got wrong

If the rule under test genuinely requires two slots to agree, write **two
separate single-blank items** that test the agreement rule clearly, or use
a `sentence_correction` item where the agreement violation is fully on
display.

### Scoring rule

- per-blank score: `correct / wrong` (no partial inside a blank)
- aggregate item score, default: `correct` only if all blanks correct;
  `partial` if some blanks correct; `wrong` if zero blanks correct
- the engine emits per-blank evidence so the Mastery Model can credit each
  retrieval independently (`LEARNING_ENGINE.md §8.2 Response Units`)

---

## 5.8 Multi-Error Correction

Engine alias: `multi_error_correction` (strong evidence tier — repair).

### Use when

The learner should detect and repair more than one error in the same
sentence, **and every error rolls up to the same primary skill and the
same primary target error.**

This family exists for items like:

- a sentence with two parallel `-ing` violations after two trigger verbs
- a paragraph-style item where the same tense rule is broken twice
- an item that pairs a primary error with the inseparable local support
  fix it always drags along

### Hard rules

- one `skill_id` for the whole item
- one `primary_target_error` for the whole item
- every error in the item must roll up to that primary — the engine must
  reject items where errors hit different primary skills or different
  primary target errors (see `LEARNING_ENGINE.md §8.3`)
- 2 or 3 correctable spans per item, not more
- each span must be unambiguously corrupt — no "stylistic improvement"
  spans, no "this could also be better" spans
- accepted corrections enumerated per span, not as a single rewrite

### No-error decoy rule

When the rule under test makes "is there an error?" itself a meaningful
decision (e.g. learners commonly hyper-correct a valid `-ing` form),
authors **may** include up to 25% of items in a lesson where the spans
contain no error and the correct response is "no change."

When this is allowed:

- the instruction must explicitly tell the learner that some spans may be
  correct (`Find and fix any errors. Some spans may already be correct.`)
- the engine must support a "no change" answer per span without scoring it
  as a wrong submission of an empty correction
- never use no-error decoys when the item is also the learner's first
  encounter with the rule — decoys belong in consolidation/contrast slots,
  not rule-introduction slots
- declare `allows_no_error_spans: true` in the exercise metadata so the QA
  reviewer and the runtime both know decoys are intentional

When this is not allowed:

- in rule-introduction lessons, no-error decoys are off
- in `sentence_correction` (single-error) items, no-error decoys are off —
  this family is reserved for `multi_error_correction`

### Scoring rule

- per-span score: `correct / wrong` against `accepted_corrections[span]`
  (or against `no_error` when allowed)
- aggregate item score: `correct` if all spans correct; `partial` if some
  spans correct; `wrong` if zero spans correct
- engine emits per-span evidence

### Authoring guard

If two errors in a candidate item roll up to different primary skills or
different primary target errors, the item is not a `multi_error_correction`
— it is two separate `sentence_correction` items fused into one. Split it.

---

## 5.9 Listening Discrimination

### Pedagogical role

Use `listening_discrimination` when the learner should perceive the target form
audibly and discriminate it from a nearby alternative that sounds similar.

This is an auditory grammar test, not a comprehension test. The learner is
choosing which structure they heard, not interpreting a story.

Best for:
- tense distinctions whose contrast hinges on small phonetic cues
  (e.g. `I work` vs `I worked`, `I am working` vs `I have been working`)
- function-word noticing (article, preposition, auxiliary)
- connected-speech features that affect grammar perception
  (e.g. `going to` vs `gonna`, contracted vs full forms)
- contrast lessons where the target form has a near-identical wrong twin

Not good for:
- long discourse comprehension
- accent or dialect training
- vocabulary recognition disguised as grammar
- sentences longer than ~12 words (load gets too high without text)

### Item shape

The learner sees:
- `instruction` (e.g. `Listen and choose what you hear.`)
- a Play / Replay control (no prompt text on screen)
- a `Show transcript` toggle (hidden by default; reveals the spoken text on tap)
- 3-4 text options below

The learner's decision is recognition: which written form matches what was
spoken.

### Voices

Mastery uses two voices, both US accent:

- `nova` — warm female. Default for example sentences and item audio.
- `onyx` — low calm male. Used for the speaker in dialogue items and as the
  alternate voice in two-clip listening contrasts (future).

For the current `listening_discrimination` type (single-clip, A-shape), use
`nova` consistently across a lesson unless a specific item benefits from a
masculine voice (e.g. when the example sentence is in first person and the
content fits a masculine speaker).

Do not switch voices mid-clip. One clip = one voice.

### Hard authoring rules

- exactly one audio clip per item
- one US accent (`nova` or `onyx`); no UK / mixed accents
- clip length 1-4 seconds; longer clips split memory load and hurt the test
- no music, no background noise, no sound design
- `transcript` field must contain the exact spoken text, character-for-character
- the transcript must read as natural adult English (per global rule §2.2)
- 3-4 options, exactly one correct
- every option must be a complete plausible sentence the learner could have
  heard, not a fragment or a labeled form (`-ing`, `to + inf`)
- no option may differ from the correct option in vocabulary alone — the
  contrast must be on the target grammar
- if the only difference between options is punctuation, the item is invalid
  (audio cannot disambiguate punctuation)

### Distractor design

Audio distractors are different from text distractors. They must reflect what
a learner could mishear or misparse, not what they could misread.

Preferred distractor sources:
- minimal pair on the target form
  (`I have been working` vs `I have worked` vs `I am working`)
- contracted vs full alternation that learners conflate
  (`he's working` heard as `he is working` vs `he was working`)
- adjacent tense or aspect that overlaps phonetically
- common learner reanalysis of connected speech

Reject distractors that:
- replace target words with unrelated vocabulary
- introduce semantic absurdity to make the wrong option obvious
- differ only in proper noun, number, or content word irrelevant to the rule

### Difficulty profile

- not for the very first item of a lesson — learners need to stabilise the
  written rule first
- best in middle-to-late slots in a 10-item arc (positions 5-8)
- the item right before a listening item should be a written test of the same
  micro-rule, so the learner enters the listening task already primed
- the item right after a listening item, if the same micro-rule is at risk,
  should reinforce per `§6.5 Reinforcement After Error`

### Schema

See `docs/content-contract.md §2.4 listening_discrimination`. In short:

```json
{
  "exercise_id": "...",
  "type": "listening_discrimination",
  "instruction": "Listen and choose what you hear.",
  "audio": {
    "url": "/audio/{lesson_id}/{exercise_id}.mp3",
    "voice": "nova",
    "transcript": "I have been working here for five years."
  },
  "options": [
    { "id": "a", "text": "I have been working here for five years." },
    { "id": "b", "text": "I have worked here for five years." },
    { "id": "c", "text": "I worked here for five years." }
  ],
  "correct_option_id": "a",
  "feedback": { "explanation": "..." }
}
```

The `transcript` is required even though it is hidden in the UI by default.
It exists for accessibility, for QA review, and for the learner who taps
`Show transcript` after listening.

### Good example

Target rule: present perfect continuous (`B2`).

Audio (voice `nova`): `She has been studying English for two years.`

Options:
- `She has been studying English for two years.` (correct)
- `She has studied English for two years.`
- `She is studying English for two years.`
- `She studied English for two years.`

Why it works:
- one dominant target: present perfect continuous as the expressed structure
- distractors are real learner confusions on the same time reference
- transcript is short, natural, one decision

Explanation (per §10):
- *"You chose 'has studied', but the correct answer is 'has been studying'*
  *because the action is ongoing and emphasized in duration. If you hear*
  *`have/has been + -ing` over a period of time → usually present perfect*
  *continuous, not present perfect simple."*

### Weak example

Audio: `I went to the supermarket yesterday and bought some apples and then I came home and made dinner.`

Options:
- four variations on the verb form somewhere in the clip

Why it fails:
- clip too long; tests memory more than grammar perception
- multiple decisions in one item
- learner cannot keep the entire sentence in working memory while picking

---

## 5.10 Speaking Production — Out Of Scope

Spoken production is currently **not planned** for Mastery. Mastery is a
listen-and-read product. The learner is never asked to speak into a microphone.

This is a deliberate scope decision, not a deferral:

- microphone capture, speech-to-text, and pronunciation scoring add
  reliability risk that conflicts with the product promise of high-trust,
  precise feedback
- listening discrimination provides the auditory channel without forcing the
  learner to produce sound

Authors and planners must not introduce speaking-based exercises, screens, or
scoring until this scope decision is explicitly reversed in this document and
in `docs/plans/roadmap.md`.

---

## 6. Lesson Sequencing Rules

Exercise sequencing must reflect lesson purpose.

### 6.1 Rule Introduction Lessons

Primary goal:
- stabilize a new pattern

Recommended current runtime mix:
- `fill_blank`: 4-5
- `multiple_choice`: 3-4
- `sentence_correction`: 1-3

### 6.2 Contrast Lessons

Primary goal:
- distinguish two nearby valid-looking choices

Recommended current runtime mix:
- `fill_blank`: 3-4
- `multiple_choice`: 4-5
- `sentence_correction`: 1-3

### 6.3 Consolidation / Review Lessons

Primary goal:
- hold previously taught subrules steady

Recommended current runtime mix:
- `fill_blank`: 2-4
- `multiple_choice`: 2-4
- `sentence_correction`: 2-4

### 6.4 Sequence Inside A 10-Exercise Lesson

Default arc:
1. early confirmation
2. controlled retrieval
3. controlled retrieval
4. first contrast item
5. slightly richer context
6. repair or contrast
7. retrieval without gimmicks
8. tighter contrast
9. guided correction
10. consolidation item

Difficulty should rise by decision load, not by random lexical difficulty.

### 6.5 Reinforcement After Error

Errors must trigger an immediate second chance at the same micro-rule. This is a
static authoring rule, not adaptive runtime: the lesson fixture is designed so
that any micro-rule the learner is likely to fail on appears in at least two
adjacent positions in the sequence.

Rules for authors:

- Each micro-rule named in an explanation (per §10) must appear in at least
  two consecutive items in the lesson sequence.
- The follow-up item should test the same micro-rule with a different surface,
  not the same prompt — for example, a `multiple_choice` item testing
  "after `suggest`, use `-ing`" should be followed by a `fill_blank` or
  `sentence_correction` item that tests the same micro-rule on a different
  trigger sentence.
- Adjacency does not require the items to be back-to-back item-1 / item-2;
  it only requires that within the 10-item arc the same micro-rule recurs
  before the lesson moves on for good.
- A learner who errs on the first occurrence then encounters the same
  micro-rule again while it is still cognitively warm.

This rule does not introduce adaptive sequencing or branching. The order is
fixed at authoring time. Runtime behavior remains linear and identical for
every learner.

Pedagogical anchor: see `GRAM_STRATEGY.md §4.8 Reinforce Immediately After
Error`.

### 6.6 Where Listening Items Go In The Arc

A `listening_discrimination` item is a recognition + perception test, not a
production test. It must sit somewhere the written rule has already been
stabilised.

Rules for authors:

- never use a listening item as the very first item of a lesson; the learner
  has not yet internalised the written form
- preferred slots are positions 5-8 in a 10-item arc, after at least one
  controlled retrieval (`fill_blank`) and one written contrast (`multiple_choice`)
- the item immediately before a listening item should test the same
  micro-rule in writing, so the learner enters the auditory task primed
- after a listening item, the very next item should reinforce per §6.5,
  using a written exercise type so the learner sees the form spelled out
  again
- a single 10-item lesson should contain at most two listening items, so the
  lesson does not become an audio drill
- a rule-introduction lesson may include 0 or 1 listening item; contrast and
  consolidation lessons may include 1-2

Listening items inherit all global authoring rules (§2) and the explanation
contract (§10).

### 6.6.1 Image + Audio Together — Edge Case

A `listening_discrimination` item may carry an image with role
`listening_support`, but only if that image does not pre-decide the auditory
answer.

The risk: a learner sees a scene that strongly implies one tense, aspect, or
verb form before they listen. They no longer have to discriminate by ear —
the image already told them. This collapses the pedagogical purpose of the
listening item.

Allowed when the image:
- sets a neutral context that fits *all* options equally (e.g. a person at a
  desk for a contrast between simple and continuous tenses)
- shows a topic anchor (e.g. an office for a workplace listening item)
  without indicating timeline, completion, or duration

Reject when the image:
- shows a clearly finished outcome that fits only the `simple`-tense option
- shows mid-action visuals that fit only the `continuous`-tense option
- displays anything that spells out the answer (a clock, a written word, a
  posture clearly mapped to one option)

Default for `listening_discrimination` items is `image_policy: none`. Only
add an image when the scene gracefully accommodates *all* listed options.

---

## 7. Distractor Strategy Rules

Distractors must be designed deliberately, not filled in mechanically.

Preferred distractor sources:
- adjacent grammar contrast
- overgeneralized learner rule
- common learner error
- wrong form within the same paradigm
- incorrect transfer from a nearby known pattern

A lesson should declare its expected distractor strategy in advance.

Do not build distractors from:
- random unrelated words
- implausible semantics
- fake misspelling noise
- trick logic unrelated to the grammar target

---

## 8. Set-Level Quality Rules

These rules apply to the full exercise set, not just to single items.

- do not repeat the same prompt pattern too many times in a row
- do not recycle the same distractor logic so often that the learner can guess the pattern mechanically
- in a normal rule lesson, include at least:
  - one clear contrast item
  - one clear repair item
- keep the set varied by decision load even when the grammar target stays constant
- lexical variety is allowed, but not at the cost of rule clarity

---

## 9. Instruction Rule

Every shipped exercise must include a short learner-facing instruction.

The instruction must:
- say exactly what the learner should do
- match the exercise type
- be visible before the prompt itself

Examples:
- `Complete the gap with the correct verb form.`
- `Choose the correct option.`
- `Rewrite the sentence correctly.`

---

## 10. Explanation Rules

Explanations must sound like a strong human tutor, not a textbook. They must
focus on the user's specific mistake and give a simple, immediately usable rule.

### 10.1 Mandatory 3-Part Structure

Every explanation must contain exactly three parts, in order:

1. **Error identification.**
   State what the learner chose and that it is incorrect.
   Format: `You chose X, but the correct answer is Y`.

2. **Short reason.**
   Explain why it is wrong in one short sentence. No long theory.
   Format: `because ...`.

3. **Micro-rule (the key insight).**
   Give one simple heuristic the learner can apply right away.
   Format: `If ... → usually ...`.

### 10.2 Tone

- Conversational, human, like a tutor speaking directly to the learner.
- No academic register.
- No metalinguistic jargon unless it adds clarity.
- Non-shaming.

### 10.3 Constraints

- Maximum 2-3 sentences total.
- Exactly one micro-rule per explanation.
- No long grammar definitions.
- No abstract explanations that are not tied to the learner's actual error.
- The micro-rule must be specific to the rule the item tests, not a generic
  grammar fact.

### 10.4 Variability

- Wording should slightly vary across explanations so the lesson does not feel
  like a copy-paste loop.
- The 3-part structure (error → reason → micro-rule) must stay constant.

### 10.5 Worked Example

Task:
- `I have been working here ___ 5 years.`

User answer: `since`. Correct answer: `for`.

Explanation:
- *"You chose 'since', but the correct answer is 'for' because this is a*
  *duration (5 years), not a starting point. If you see a period of time*
  *(5 years, 2 days, a long time) → usually use 'for'."*

### 10.6 Anti-Examples

Reject explanations that look like any of these:

- "Wrong verb." — no error identification, no reason, no rule.
- "Use the past simple." — no link to the learner's actual choice.
- "After verbs like 'enjoy, avoid, suggest, mind, keep, finish, consider' we
  use the gerund form, which is the -ing form of the verb..." — too long,
  too generic, no reference to the specific mistake.

### 10.7 Core Principle

Explain the mistake, not the grammar topic.

If the explanation could be pasted into a different item without changes, it is
not specific enough.

---

## 11. Validation And Rejection Checklist

Reject an exercise if:
- the tested decision is unclear
- more than one major rule is involved
- the language is unnatural
- the answer space is wider than the scoring model can handle
- distractors are fake or silly
- the explanation is generic
- the task type does not fit the pedagogical goal

---

## 12. Runtime Mapping Rule

The app may expand exercise support over time, but current shipped lessons must obey:
- current runtime widgets only
- current scoring contracts only
- no silent introduction of unsupported task families

If adapting a pedagogical family into the current runtime would distort the teaching
goal too much, defer the item until the runtime can support it properly.
