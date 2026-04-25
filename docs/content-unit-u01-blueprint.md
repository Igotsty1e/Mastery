# Unit 01 Blueprint — Infinitive vs -ing

## Status

Working blueprint for the first curriculum unit under the canonical content system in [ROUNDUP_AI_CONTENT_SYSTEM.md](/Users/ivankhanaev/Mastery/ROUNDUP_AI_CONTENT_SYSTEM.md).

This file is not the runtime lesson fixture. It is the authoring blueprint that the shipped lessons should be built from.

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

This is the most textbook-like and B2-relevant subtopic in the unit.

Shippable as current MVP lesson:
- yes

## U01_L05 — Mixed Review

**Type:** consolidation  
**Objective:** check recognition and correction across U01 concepts

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
- recommended distribution:
  - 4 `fill_blank`
  - 3 `multiple_choice`
  - 3 `sentence_correction`
- no hints
- every item must include a rule-specific explanation
- use realistic B2 vocabulary only
- no item should test more than the verb pattern itself

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

Author the JSON lesson fixture for:

`U01_L01 — Verbs followed by -ing`

using the source set above and compile it into the current backend lesson schema.
