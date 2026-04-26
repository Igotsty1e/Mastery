# GRAM_STRATEGY — Mastery

## Status

Top-level canonical source of truth for how Mastery teaches English grammar and usage.

This file defines the pedagogical model above:
- lesson fixtures
- exercise templates
- screen flows
- scoring contracts

Authority chain:
- `GRAM_STRATEGY.md` — top-level pedagogy
- `exercise_structure.md` — exercise system and authoring rules derived from this pedagogy
- unit blueprints and lesson fixtures — concrete planning and shipped content
- technical/runtime docs — implementation constraints only

If a lower-level content document conflicts with this strategy, the lower document
must be updated unless the conflict is caused by a hard runtime limit in the current
app.

---

## 1. Teaching Thesis

Mastery teaches English as a system of:
- meaning
- use
- form
- contrast
- repair

We do not teach grammar as isolated labels to memorize.
We teach learners to:
- understand what a pattern means
- recognize when it is needed
- produce it accurately
- distinguish it from nearby alternatives
- detect and repair common errors
- retain it across later review

In short:
- grammar is not the goal by itself
- accurate, natural English is the goal
- grammar is the tool that makes accurate, natural English possible

---

## 2. Learner Promise

Mastery is for adult and late-teen learners who want serious, high-trust English
practice.

The product promise is:
- clear explanation before practice
- no childish gamification
- no random AI improvisation
- no trick questions
- no vague correction
- a calm but exacting learning experience

The learner should feel:
- "I understand what this structure does."
- "I can see why my answer was wrong."
- "I know what to do next time."

---

## 3. What We Teach

Every grammar target in Mastery should be taught through five dimensions:

1. `Meaning`
   What idea the structure expresses.

2. `Use`
   When a speaker or writer chooses this structure instead of another one.

3. `Form`
   How the structure is built.

4. `Contrast`
   What nearby structure learners may confuse it with.

5. `Repair`
   How to detect and fix the most common learner errors.

Weak teaching explains form only.
Strong teaching makes all five dimensions visible without becoming dense.

---

## 4. Core Pedagogical Principles

### 4.1 Form-Meaning-Use Before Labels

Explanations should prioritize:
1. what it means
2. when we use it
3. how we form it

Metalanguage is allowed only when it improves clarity.
Terminology must never carry the teaching load by itself.

### 4.2 One Dominant Decision At A Time

Each lesson teaches one dominant rule.
Each exercise tests one dominant decision.
Each explanation resolves one dominant confusion.

The learner should always be able to answer:
"What exact choice is this lesson asking me to make?"

### 4.3 Move From Recognition To Retrieval

Learning should progress from easier cognitive work to harder cognitive work:
- notice
- recognize
- choose
- complete
- repair
- recall

Mastery should not jump straight into open production when the learner has not yet
built a stable pattern.

### 4.4 Teach Through Contrast, Not Through Lists Alone

Learners often fail because they confuse one valid-looking option with another.

So lessons must highlight contrasts such as:
- `-ing` vs `to + infinitive`
- present perfect vs past simple
- `for` vs `since`
- `if I had` vs `if I would have`

### 4.5 Error Correction Must Be Diagnostic

Feedback must identify:
- the wrong choice
- the reason it is wrong
- the correct pattern
- the exact local repair

### 4.6 Natural English Beats Artificial Testese

Examples and items should sound like plausible adult English.

Reject:
- nonsense
- trivial filler
- strange collocations written only to force one answer
- fake-difficult sentences that no one would naturally say

### 4.7 Mastery Requires Return, Not Just Exposure

A learner has not mastered a rule because they got several similar items correct in
one sitting.

Mastery requires:
- initial understanding
- accurate controlled practice
- later retrieval
- later contrast against competing forms
- later use in mixed review

### 4.8 Reinforce Immediately After Error

An error is a learning opportunity that must be cashed in before it cools down.
The learner who just made a wrong choice on a specific micro-rule should meet
the same micro-rule again, soon, while the correction is still fresh.

Operational consequence:

- Every lesson must be authored so that each micro-rule named in an explanation
  appears in at least two adjacent positions in the exercise sequence.
- The follow-up item should test the same micro-rule on a different surface
  (different trigger verb, different distractors, different exercise type) so
  the learner repractices the rule, not the prompt.
- This is a static authoring rule baked into the fixture, not an adaptive
  runtime feature. Every learner sees the same sequence; the design simply
  guarantees that errors land near a re-test of the same rule.

This is the product hook that turns feedback into learning instead of just
information. See `exercise_structure.md §6.5 Reinforcement After Error` for
the operational contract.

### 4.9 Visual Context Serves Meaning, Not Decoration

When an image accompanies an exercise, it must do pedagogical work — most
often clarifying meaning, anchoring a scenario, or supporting noticing for
listening items. It must never serve as decoration, branding, or a
substitute for clear language.

Operational consequences:

- Every exercise starts as text-only. The default `image_policy` is `none`.
  The burden of proof is on adding the image, not on omitting it.
- An image is allowed only when it carries one of four explicit roles:
  scene-setting, context support, disambiguation, or listening support.
- An image must not make the correct answer obvious. It clarifies the
  context of the decision, never the decision itself.
- The visual layer is governed by `exercise_structure.md §2.9` (the
  authoring rules) and `DESIGN.md §15` (the rendering rules); pedagogy
  decides *whether* to add an image, design decides *how* it looks.

---

## 5. Lesson Model

### 5.1 Full Pedagogical Arc

The full Mastery learning arc is:
1. concept introduction
2. controlled practice
3. semi-controlled practice
4. guided production
5. consolidation
6. later review / recycling

### 5.2 Current MVP Translation

The current MVP cannot yet represent the full arc as separate widgets.

So the current lesson must compress the pedagogy into:
1. intro screen that teaches the rule clearly
2. exercise sequence that moves from lower to higher decision load
3. immediate diagnostic feedback
4. summary-based review

This means the intro screen is not decorative.
It is the first teaching phase.

### 5.3 What The Intro Must Teach

Each lesson intro must make four things clear:
- `Use`: when the pattern is used
- `Form`: how the pattern is built
- `Contrast`: what not to confuse it with
- `Red flag`: the common wrong version the learner must avoid

Good intro teaching answers:
- What does this structure do?
- When do I choose it?
- What shape does it take?
- What common mistake should I watch for?

### 5.3.1 How The Intro Must Show Contrast

The intro screen is not a prose block.
It is a noticing surface.

When two forms are being contrasted, the learner must be able to see the
changing slot immediately, before reading a long explanation.

Operational rules:

- highlight only the variable part of the pattern, not the whole formula
- keep the shared part neutral and visually quieter
- present paired forms vertically and align the changing slot like a diff
- mirror the same highlight from the rule formula into the examples below it
- use examples in pairs under each contrasted form, not as one undifferentiated list

Examples of the changing slot:
- `been + verb-ing` vs `past participle`
- `for` vs `since`
- `do` vs `make`
- `say` vs `tell`

Pedagogical reason:
- the learner should notice the exact contrast first, then read the explanation
- if the whole sentence or whole formula is highlighted, the signal is diluted
- if the visual treatment changes between FORM and EXAMPLES, the learner loses the rule-to-example bridge

### 5.4 What The Exercise Sequence Must Then Do

After the intro, exercises must gradually force the learner to:
- identify the right pattern
- reject the wrong contrast
- retrieve the correct form without seeing it
- repair a typical learner error
- hold the rule steady in a slightly more realistic context

---

## 6. Curriculum Architecture

### 6.1 Unit Logic

A grammar area may be split into multiple lessons when the target rule contains more
than one real learner decision.

Good split:
- one lesson for `verb + -ing`
- one lesson for `verb + to + infinitive`
- one lesson for verbs that take both with a change in meaning

Bad split:
- one giant lesson that mixes all of the above in the intro and the exercise set

### 6.2 Lesson Archetypes

Mastery should use a small set of clear lesson archetypes:
- `Rule Introduction`
- `Contrast Lesson`
- `Consolidation Lesson`
- `Mixed Review`

Each archetype may use different exercise distributions, but all still obey:
- one dominant lesson goal
- explicit contrast design
- clear feedback

### 6.3 Shippable Rule

For the current app:
- one shipped lesson = one dominant grammar rule
- mixed content is acceptable only when review is the explicit lesson goal

---

## 7. CEFR Gate

Every lesson must explicitly declare:
- `target form`
- `target CEFR level`
- `why this target belongs at that level`
- `adjacent contrast forms below or above that level`

This gate exists to stop lessons from being:
- formally correct but off-level
- level-appropriate in grammar but too advanced in lexical load
- built around a contrast the learner is not yet ready to handle

A lesson is not ready for authoring until the CEFR fit is stated in plain language.

---

## 8. Lesson Context

Every lesson must also declare a lexical or topical context.

Typical contexts:
- work
- study
- travel
- daily life
- relationships
- news and current affairs

Rule:
- the lesson does not need a fake narrative
- but most examples and exercises should live inside a coherent context frame

This prevents the content from becoming a pile of grammatically valid but emotionally
flat sentences.

---

## 9. Authoring Inputs

Before a lesson or exercise set is authored, these inputs must be fixed:
- `target form`
- `target CEFR`
- `lesson archetype`
- `lexical / topical context`
- `core contrast`
- `expected common learner errors`
- `scoring mode`

If these inputs are unclear, authoring should stop until they are clarified.

---

## 10. Exercise Sequencing Rules

The detailed exercise rules live in `exercise_structure.md`, but every lesson must
follow this sequencing logic:

### 10.1 Early Exercises

Purpose:
- stabilize the target pattern
- reduce noise
- confirm the learner understood the intro

### 10.2 Middle Exercises

Purpose:
- introduce contrast
- increase retrieval load
- require bounded decision-making in context

### 10.3 Late Exercises

Purpose:
- test repair
- test short-range recall
- consolidate the rule without changing the lesson into open production

---

## 11. Mastery Definition

A learner can be treated as strong on a rule only when they can:
- recognize the correct structure among plausible distractors
- produce the form accurately in controlled conditions
- repair a common incorrect version
- retain the rule in later mixed review

So mastery is not just `accuracy`.
It is:
- `accuracy`
- `stability`
- `contrast control`
- `error awareness`

---

## 12. Error Philosophy

### 12.1 Errors Are Signals

An error is evidence of a specific wrong decision, not learner failure.

### 12.2 Explanations Must Be Specific

Weak:
- "Incorrect."
- "Remember the rule."
- "Use the right tense."

Strong:
- "After `suggest`, use the `-ing` form, not `to + infinitive`."

### 12.3 Controlled Tasks Must Be Described Honestly

Controlled tasks should reward the target pattern.
They are not mini-essays.

Therefore:
- narrow answer spaces are acceptable in controlled practice
- but we must not pretend a controlled repair task is free production

---

## 13. Source And Authoring Policy

### 13.1 Source Principle

Grammar explanations and core patterns must come from:
- open textbooks
- open educational sources
- reputable publicly accessible educational publishers

Do not rely on raw model invention for the rule itself.

### 13.2 AI Use Principle

AI may assist offline authoring for:
- structuring drafts
- generating candidate items
- expanding variant lists
- checking consistency

AI must not be treated as final authority for:
- the rule explanation
- canonical grammar patterns
- final accepted answers
- shipped lesson text

### 13.3 Runtime Principle

No AI-generated lesson content at runtime in the current app.

---

## 14. Current MVP Boundaries

The current MVP is a controlled-practice grammar product, not a full four-skills
course.

Current strengths:
- clear explanation
- deterministic scoring
- clean rule isolation
- precise feedback

Current limitations:
- no open production
- no speaking tasks (out of scope — see §15)
- no adaptive recycle based on learner weakness
- four runtime exercise types: `fill_blank`, `multiple_choice`, `sentence_correction`, `listening_discrimination`

Pedagogical consequence:
- we can build a strong accuracy-and-repair grammar trainer now
- we should not pretend the current product already measures broad communicative command

---

## 15. Long-Term Teaching Direction

When the app expands, new capabilities should serve this pedagogy in this order:
1. better review and retrieval across lessons
2. richer exercise families for contrast and transformation
3. listening support for noticing and discrimination
4. more open written production once scoring and feedback are trustworthy

Listening is desirable because it improves transfer, not because it is a
fashionable feature.

### 15.1 Speaking Is Out Of Scope

Mastery does not plan spoken production. The learner is never asked to speak
into a microphone, in any phase, in any lesson archetype, in any roadmap step.

This is a deliberate product decision:

- microphone capture, speech-to-text, and pronunciation scoring introduce
  reliability and fairness risks that contradict the product promise of
  precise, high-trust feedback
- listening discrimination already covers the auditory channel without
  asking the learner to produce sound

If this position changes, this section must be revised first, then
`exercise_structure.md §5.7` and `docs/plans/roadmap.md`. Until then,
no speaking-based exercise, screen, scoring path, or backend payload should
be introduced.

---

## 16. Non-Negotiables

Mastery must not:
- teach through random AI improvisation
- confuse grammar labels with actual learning
- mix multiple major rules inside one ordinary lesson
- rely on vague explanations
- use artificial trick questions to inflate difficulty
- market controlled rewrite tasks as full communicative production
- introduce new exercise types without defining their pedagogical role first

---

## 17. Validation Standard

Any lesson or exercise is below standard if:
- the learner cannot tell what decision is being tested
- the rule explanation lacks meaning/use/form/contrast
- the language is unnatural
- the item tests two different major choices at once
- the explanation could fit many unrelated rules
- the exercise sequence never escalates beyond repetition

Tier-1 quality in Mastery means:
- tight rule isolation
- natural English
- strong contrast design
- precise feedback
- deliberate sequencing
- honest alignment between pedagogy and scoring
