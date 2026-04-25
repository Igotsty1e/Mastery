# exercise_structure — Mastery

## Status

Canonical source of truth for exercise design and authoring rules.

This document is subordinate to:
- `GRAM_STRATEGY.md`

This file governs:
- exercise taxonomy
- hard authoring rules
- sequencing inside lessons
- distractor design
- explanation design
- runtime mapping
- future exercise expansion logic

If this file conflicts with `GRAM_STRATEGY.md`, `GRAM_STRATEGY.md` wins.

All shipped exercise output must compile exactly to the runtime schema and scoring
rules defined in `docs/content-contract.md`.

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

---

## 3. Exercise Taxonomy

Mastery uses two layers:
- `pedagogical exercise families` — the long-term learning system
- `runtime exercise widgets` — what the app currently supports

### 3.1 Pedagogical Families

| Family | Primary learner action | Typical purpose | Current app |
|---|---|---|---|
| Recognition choice | identify correct form | early contrast, low-load checking | supported |
| Controlled completion | supply missing form | controlled production | supported |
| Guided correction | repair wrong sentence | error awareness and repair | supported |
| Transformation | rewrite into a target pattern | guided production | roadmap |
| Matching / sorting | pair forms, meanings, or triggers | noticing and contrast | roadmap |
| Ordering / build-a-sentence | construct correct syntax | word order and structure control | roadmap |
| Dialogue completion | choose or produce a line in context | contextualized grammar choice | roadmap |
| Constrained short production | produce one short original sentence within limits | bounded transfer | roadmap |
| Listening discrimination | hear and identify the target form | auditory noticing | next priority — see §5.6 |
| Speaking production | say the target form aloud | production + transfer | out of scope |

### 3.2 Current Runtime Widgets

Current shipped runtime supports only:
- `fill_blank`
- `multiple_choice`
- `sentence_correction`

These are the only exercise widgets that may appear in current shipped lessons.

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

### Use when

The learner should produce one original sentence under clear constraints.

### Hard rules

- the prompt must name the target structure
- scoring must accept a reasonable answer range
- feedback must judge grammar first, not style first

---

## 5.6 Listening Discrimination

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

## 5.7 Speaking Production — Out Of Scope

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
in `docs/implementation-scope.md`.

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
