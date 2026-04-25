# Unit 01 Blueprint — Infinitive vs -ing

## Status

Working blueprint for the first curriculum unit under the canonical pedagogy and exercise system in:
- [GRAM_STRATEGY.md](/Users/ivankhanaev/Mastery/GRAM_STRATEGY.md)
- [exercise_structure.md](/Users/ivankhanaev/Mastery/exercise_structure.md)

Pedagogical and exercise-authoring authority for this blueprint also depends on:
- [GRAM_STRATEGY.md](/Users/ivankhanaev/Mastery/GRAM_STRATEGY.md)
- [exercise_structure.md](/Users/ivankhanaev/Mastery/exercise_structure.md)

This file is not the runtime lesson fixture. It is the authoring blueprint that the shipped lessons should be built from.

Execution rule:
- use the `english-grammar-methodologist` skill as the required authoring path for any lesson built from this blueprint
- do not draft `U01` lesson items free-form outside that skill and then backfill compliance afterwards

---

## Unit Identity

```json
{
  "unit_id": "U01",
  "title": "Infinitive vs -ing"
}
```

## Why This Unit Comes First

This is a strong first unit for B2 because:
- it is high-frequency and practical
- it appears constantly in work and everyday English
- it supports textbook-style controlled practice very well
- it can be split into clean, single-rule lessons

---

## Open Source Reference Set

Primary sources for this unit:

1. British Council LearnEnglish — verbs followed by the `-ing` form  
   [LearnEnglish](https://learnenglish.britishcouncil.org/free-resources/grammar/english-grammar-reference/verbs-followed-ing-form)

2. Cambridge Grammar — verb patterns: verb + infinitive or verb + `-ing`  
   [Cambridge Grammar](https://dictionary.cambridge.org/us/grammar/british-grammar/verb-patterns-verb-infinitive-or-verb-ing)

3. British Council LearnEnglish — verbs followed by `-ing` or infinitive with a change in meaning  
   [LearnEnglish B1-B2](https://learnenglish.britishcouncil.org/free-resources/grammar/b1-b2/verbs-followed-ing-or-infinitive-change-meaning)

4. BBC Learning English — infinitive / gerund verb patterns  
   [BBC PDF](https://downloads.bbc.co.uk/worldservice/learningenglish/ask_about_english/pdfs/aae_grees_inf_gerund.pdf)

5. BBC Learning English — verb patterns worksheet  
   [BBC 6 Minute Grammar PDF](https://downloads.bbc.co.uk/learningenglish/lowerintermediate/unit10/141202_6mingram_verb_patterns.pdf)

These sources are enough to build the first unit without relying on runtime AI invention.

---

## Unit Concepts

Core concepts for U01:
- verbs followed by `-ing`
- verbs followed by `to + infinitive`
- verbs that can take both with little/no difference
- verbs that take both with a change in meaning
- mixed recognition and correction

Important technical rule:
- each shipped lesson must still teach **one dominant rule**
- do not mix all concept groups inside one lesson intro

---

## 5-Lesson Breakdown

## U01_L01 — Verbs followed by `-ing`

**Type:** rule introduction + controlled practice  
**Objective:** identify and produce the `-ing` form after common verbs

CEFR rationale:
- target level: `B2`
- this lesson fits B2 because the verb pattern is high-frequency and practical, while
  the learner is expected to control it across realistic adult contexts rather than
  only memorize isolated lists

Lesson context:
- work and everyday adult communication

Core contrast:
- `verb + -ing` vs `verb + to + infinitive`

Common learner errors:
- `to + infinitive` after an `-ing` verb
- bare infinitive after the trigger verb
- finite verb form instead of gerund

Distractor strategy:
- use wrong verb-pattern contrasts first
- then use wrong forms from the same verb paradigm
- avoid distractors that are obviously impossible for unrelated reasons

Focus verbs:
- enjoy
- avoid
- consider
- mind
- suggest
- keep
- finish

Allowed runtime exercise mix:
- `fill_blank`
- `multiple_choice`
- `sentence_correction`

Shippable as current MVP lesson:
- yes

## U01_L02 — Verbs followed by `to + infinitive`

**Type:** controlled practice  
**Objective:** identify and produce the infinitive after common verbs

CEFR rationale:
- target level: `B2`
- this lesson remains B2 because learners are expected to control the structure
  accurately in realistic contexts and distinguish it from nearby verb-pattern contrasts

Lesson context:
- plans, decisions, intentions, and workplace communication

Core contrast:
- `verb + to + infinitive` vs `verb + -ing`

Common learner errors:
- gerund after a `to + infinitive` verb
- missing `to`
- wrong finite verb after the trigger verb

Focus verbs:
- decide
- hope
- plan
- want
- agree
- refuse
- learn

Shippable as current MVP lesson:
- yes

## U01_L03 — Verbs that take both with little or no change in meaning

**Type:** semi-controlled  
**Objective:** recognise verbs that allow both forms in common usage

CEFR rationale:
- target level: `B2`
- this lesson belongs later in the unit because the grammar is not harder in form, but
  fuzzier in use and therefore cognitively less stable for learners

Lesson context:
- preferences, habits, and everyday opinions

Core contrast:
- two acceptable patterns with little or no meaning change

Common learner errors:
- overcorrecting to only one acceptable form
- inventing a meaning difference where none is pedagogically useful
- transferring a strict rule from earlier lessons to flexible verbs

Focus verbs:
- begin
- start
- like
- love
- hate
- prefer

Constraint:
- explanations must be careful and simple
- do not overclaim when the meaning difference is small

Shippable as current MVP lesson:
- yes, but must remain tightly authored

## U01_L04 — Verbs that take both with a change in meaning

**Type:** semi-controlled / high-value B2 rule lesson  
**Objective:** distinguish meaning changes with `remember`, `forget`, `stop`, `try`, `regret`, `go on`

CEFR rationale:
- target level: `B2`
- this lesson is high-value at B2 because the challenge is not just form selection but
  meaning contrast between two closely related structures

Lesson context:
- memory, plans, decisions, attempts, and reported personal experience

Core contrast:
- same trigger verb, different structure, different meaning

Common learner errors:
- treating both forms as interchangeable
- selecting the right form for the wrong meaning
- solving by memorized pattern without reading context carefully

This is the most textbook-like and B2-relevant subtopic in the unit.

Shippable as current MVP lesson:
- yes

## U01_L05 — Mixed Review

**Type:** consolidation  
**Objective:** check recognition and correction across U01 concepts

CEFR rationale:
- target level: `B2`
- this lesson is review-level B2 because it asks the learner to retain and discriminate
  across previously taught verb-pattern decisions without introducing a new core rule

Lesson context:
- mixed adult contexts from the unit, but each item should remain locally coherent

Core contrast:
- mixed U01 contrasts only

Common learner errors:
- overusing one learned pattern across all trigger verbs
- remembering the verb but not the required pattern
- confusing flexible verbs with change-in-meaning verbs

Constraint:
- still keep each individual item isolated to one concept
- mixed lesson is allowed only because the unit review is the explicit goal

Shippable as current MVP lesson:
- yes

---

## Recommended Shipping Order

Because the app currently ships one lesson at a time cleanly, the best near-term order is:

1. `U01_L01` — Verbs followed by `-ing`
2. `U01_L02` — Verbs followed by `to + infinitive`
3. `U01_L04` — change in meaning
4. `U01_L03` — both forms with little difference
5. `U01_L05` — mixed review

Reason:
- `L01` and `L02` are easiest to score deterministically
- `L04` is very valuable pedagogically but needs careful authoring
- `L03` is slightly fuzzier semantically and should come after the learner has the basic patterns

---

## Current Product Decision

The next lesson we should build for the app is:

```json
{
  "unit_id": "U01",
  "lesson_id": "U01_L01",
  "title": "Verbs followed by -ing",
  "status": "next_to_author"
}
```

Why:
- clearest first grammar target
- best fit for current runtime exercise types
- easiest to make fair, deterministic, and textbook-like

---

## Authoring Constraints For U01_L01

For the first shipped lesson:
- one intro rule only
- 2–3 intro examples only
- 10 exercises total
- recommended distribution for a rule-introduction lesson:
  - 4-5 `fill_blank`
  - 3-4 `multiple_choice`
  - 1-3 `sentence_correction`
  - 0 `listening_discrimination` for U01 specifically: verb-pattern contrasts
    (`-ing` vs `to + infinitive`) are large phonetic distinctions, not the
    subtle minimal-pair contrasts that listening items are best at; reserve
    listening items for tense/aspect units (e.g. present perfect vs past
    simple) once the audio widget ships per `docs/implementation-scope.md §3`
- no hints
- every item must include a rule-specific explanation
- explanations must follow the 3-part contract in
  `exercise_structure.md §10` (error → reason → micro-rule)
- use realistic B2 vocabulary only
- no item should test more than the verb pattern itself
- intro must explicitly cover:
  - meaning/use
  - form
  - contrast with `to + infinitive`
  - the red-flag learner error

### Micro-Rule Reinforcement Pairing

Per `exercise_structure.md §6.5`, every micro-rule named in an explanation must
appear in at least two adjacent positions in the 10-item sequence, on different
surfaces.

For U01_L01 specifically, this means:

- pair the trigger verbs across adjacent items so a learner who errs on
  `enjoy + -ing` immediately gets a second shot at the same micro-rule
  through a different exercise type (e.g. multiple_choice → fill_blank), or
  through a different trigger that shares the same `-ing` rule
- the contrast item against `to + infinitive` (the red-flag) must also have
  a paired follow-up that re-tests the contrast on a different verb
- the consolidation item (slot 10) does not need a follow-up but must itself
  re-use a micro-rule already introduced earlier in the lesson

This pairing is fixed at authoring time. The runtime sequence is identical
for every learner; the design simply guarantees that errors land near a
re-test of the same rule while it is still cognitively warm.

---

## Runtime Mapping Note

If source materials contain:
- matching tasks
- transformation drills
- freer production prompts

do **not** ship them directly into the current app.

They must either:
- be rewritten into supported runtime types
- or be deferred until the app supports additional exercise widgets

---

## Next Authoring Step

Invoke `english-grammar-methodologist` to author the JSON lesson fixture for:

`U01_L01 — Verbs followed by -ing`

using the source set above, then compile the approved output into the current backend lesson schema.
