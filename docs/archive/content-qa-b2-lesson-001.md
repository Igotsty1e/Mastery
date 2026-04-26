# Content QA — B2 Lesson 001

**Lesson file:** `backend/data/lessons/b2-lesson-001.json`  
**Status:** Local QA review only. No content changes applied.  
**Last updated:** 2026-04-20

## Summary

The lesson is coherent and aligned with the MVP: focused grammar targets, clean separation across the three exercise types, and no obviously broken fixtures.

Main weakness is not syntax quality but scoring fairness. The `sentence_correction` items are narrow enough that some valid learner answers would likely be marked wrong, not because the backend is broken, but because accepted corrections are too sparse for the current deterministic-first + narrow-borderline-AI policy.

## Overall Rating

- grammar target clarity: `8/10`
- exercise quality: `7/10`
- scoring fairness under current backend rules: `6/10`
- AI readiness of current content: `6/10`

## What Looks Strong

- intro rule and examples align with the exercise mix
- `fill_blank` items mostly test one precise target at a time
- `multiple_choice` distractors are plausible enough for B2-level review
- `sentence_correction` prompts are short, legible, and tied to the stated grammar targets

## Main Risks

### 1. `sentence_correction` accepted corrections are too narrow

Current implementation only accepts exact normalized matches deterministically and uses AI only for typo-level borderline cases. That means valid but differently worded corrections may be rejected unfairly.

Highest-risk items:
- `...00018` — likely valid variant: `She has worked at this company for ten years.`
- `...00019` — likely valid variant space is small, but still only one accepted correction is listed
- `...00001a` — valid alternatives are limited, but the single accepted correction still leaves little room

### 2. Some `fill_blank` items depend on very narrow author intent

These are not broken, but they are sensitive to wording:
- `...00014` expects `as` because the prompt already includes `though`
- `...00013` allows three gerunds, which is good, but still depends on content authors guessing learner variants in advance

### 3. The lesson is good for controlled practice, but harsh for production scoring

As a teaching asset it is fine. As a scored lesson under current acceptance rules, it may under-credit competent learners who produce correct rephrasings instead of the listed correction.

## Per-Exercise Notes

## Fill Blank

### `...00011` By the time the ambulance arrived...

Assessment:
- good target isolation
- answer space is narrow and appropriate

Risk:
- low

### `...00012` responsible ___ protecting

Assessment:
- clean collocation test
- deterministic scoring is appropriate

Risk:
- low

### `...00013` suggested ___ less caffeine

Assessment:
- good gerund target
- allowing `drinking`, `consuming`, `having` is better than a single-answer setup

Risk:
- medium

Reason:
- still possible for users to enter a valid equivalent not listed, depending on product philosophy

### `...00014` spoke ___ though

Assessment:
- technically valid
- somewhat more “pattern recognition” than natural sentence completion

Risk:
- medium

Reason:
- the answer is only recoverable if the learner notices the fixed expression split across the blank

## Multiple Choice

### `...00015` future perfect passive

Assessment:
- strong item
- distractors are plausible

Risk:
- low

### `...00016` regret about a past event

Assessment:
- strong item
- clear single correct answer

Risk:
- low

### `...00017` despite ___ for the role

Assessment:
- grammatically targeted and plausible

Risk:
- low to medium

Reason:
- some learners may feel the sentence is slightly stiff stylistically, but the grammar target is clear

## Sentence Correction

### `...00018` since ten years

Assessment:
- clear and common learner error
- excellent instructional target

Risk:
- high scoring fairness risk

Why:
- valid corrections can be farther than typo-distance from the single accepted correction
- current AI fallback will not rescue many legitimate rephrasings

Examples to consider in a future content pass:
- `She has worked at this company for ten years.`

### `...00019` If I would have studied more...

Assessment:
- clear target
- good B2 conditional item

Risk:
- medium scoring fairness risk

Why:
- fewer valid alternatives than `...00018`, but still only one accepted correction is listed

### `...00001a` advices / were

Assessment:
- strong target because it combines countability and agreement

Risk:
- medium scoring fairness risk

Why:
- single accepted correction may be sufficient for MVP, but still gives little space for equivalent learner phrasing

## Recommended Non-Code Follow-Ups

These are preparation tasks only:

1. Expand each `sentence_correction` item with 3-5 acceptable corrections before any serious AI tuning.
2. Mark each item with expected valid variants and likely invalid near-misses.
3. Build eval rows from real learner-like answers, not just canonical solutions.
4. Review whether the product wants to reward only exact target rewrites or also meaning-preserving valid rephrasings.

## Policy Is Frozen

The policy question is resolved: `sentence_correction` rewards only listed teacher-approved rewrites. Grammatical meaning-preserving corrections not in `accepted_corrections` are correctly rejected under the MVP teacher-list policy.

Scoring fairness notes above are content-expansion opportunities, not open product decisions. Prompt tuning does not address narrow `accepted_corrections`; expanding the teacher-provided list does.
