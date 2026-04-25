# ROUNDUP AI Content System

## Status

This document is the canonical source of truth for the **content system** of Mastery / Roundups AI Assistant.

It governs:
- curriculum structure
- lesson authoring rules
- exercise authoring rules
- pedagogy and progression inside a lesson
- content validation rules
- content generation workflow

It does **not** replace the application's technical source of truth.

Technical/runtime authority remains in:
- [CLAUDE.md](/Users/ivankhanaev/Mastery/CLAUDE.md)
- [docs/approved-spec.md](/Users/ivankhanaev/Mastery/docs/approved-spec.md)
- [docs/backend-contract.md](/Users/ivankhanaev/Mastery/docs/backend-contract.md)
- [docs/mobile-architecture.md](/Users/ivankhanaev/Mastery/docs/mobile-architecture.md)

If this content document conflicts with unsupported runtime features, the content model must be adapted to the app, not the other way around.

---

## 0. Purpose

This document defines the canonical content system for building a B2 English grammar-learning application inspired by textbook roundups.

The goal is to:
- eliminate random content generation
- enforce consistent pedagogy
- standardize exercise authoring
- make content scalable through **AI-assisted offline authoring**, not runtime generation

This file is the single source of truth for:
- curriculum structure
- exercise templates
- generation rules
- validation constraints
- textbook-style lesson composition

---

## 1. Pedagogical Model (Non-Negotiable)

### 1.1 Core Principle

Each grammar area must follow this pedagogical sequence:

1. concept introduction
2. controlled practice
3. semi-controlled practice
4. free production
5. consolidation

This is the **curriculum-level** sequence.

Important technical clarification:
- the current MVP app does **not** yet support all five stages as separate interactive runtime lesson types
- the full five-stage model is the long-term content system
- the current shipped MVP implements the subset that fits the app: concept introduction + controlled/semi-controlled/consolidation through fixed exercises

### 1.2 Cognitive Load Progression

| Stage | Difficulty | Freedom | Goal |
|---|---|---:|---|
| Controlled | Low | Low | Pattern recognition |
| Semi-controlled | Medium | Medium | Guided transformation |
| Free | High | High | Recall and production |

### 1.3 Error-Based Learning

The system must:
- detect error type
- map the error to the grammar rule being tested
- provide structured feedback:
  - what is wrong
  - why it is wrong
  - what the correct pattern is

In the current MVP runtime:
- feedback shown to the learner is **curated lesson content**, not free-form AI tutoring
- AI may help decide correctness only for borderline `sentence_correction` cases

---

## 2. Curriculum Structure (B2)

### 2.1 Units Overview

Target curriculum size: **15 units**

1. Infinitive vs -ing
2. Modal verbs (advanced)
3. Present tenses
4. Past tenses
5. Future forms
6. Conditionals
7. Mixed conditionals + wish
8. Passive voice
9. Reported speech
10. Relative clauses
11. Articles & determiners
12. Prepositions
13. Comparisons
14. Word formation
15. Phrasal verbs

This is the **curriculum planning layer**, not a claim that all 15 units are already shipped.

### 2.2 Unit Schema

```json
{
  "unit_id": "U01",
  "title": "Infinitive vs -ing",
  "concepts": [],
  "lessons": []
}
```

---

## 3. Lesson Structure

### 3.1 Curriculum-Level Lesson Types

Each unit may be planned as 5 lessons:

1. L1: Rule Introduction
2. L2: Controlled Practice
3. L3: Semi-controlled
4. L4: Production
5. L5: Mixed Test / Consolidation

This is the **content design model**.

### 3.2 Current MVP Runtime Constraint

The current app does **not** yet support:
- unit selection
- lesson unlocking
- saved progress
- adaptive sequencing
- open production tasks
- matching tasks
- transformation tasks as a separate runtime widget

Therefore, all shipped MVP lessons must currently compile down to the app's supported runtime lesson format:

- one lesson = one grammar rule
- linear lesson flow
- 10 exercises
- supported runtime exercise types only:
  - `fill_blank`
  - `multiple_choice`
  - `sentence_correction`

### 3.3 Current Shippable Lesson Schema

Any lesson intended for the current app must ultimately fit:

```json
{
  "lesson_id": "uuid",
  "title": "string",
  "language": "en",
  "level": "B2",
  "intro_rule": "string",
  "intro_examples": ["string"],
  "exercises": []
}
```

---

## 4. Exercise System

### 4.1 Authoring-Level Exercise Intent

The original proposal includes:
- fill gap
- multiple choice
- transformation
- error correction
- matching
- open production

This is acceptable as an **authoring taxonomy**.

### 4.2 Runtime-Allowed Exercise Set (Current MVP)

Only these runtime types are currently allowed in shipped lessons:

#### `fill_blank`

```json
{
  "type": "fill_blank",
  "instruction": "Complete the gap with the correct verb form.",
  "prompt": "I enjoy ___ (read)",
  "accepted_answers": ["reading"],
  "feedback": {
    "explanation": "After enjoy, we use the -ing form."
  }
}
```

#### `multiple_choice`

```json
{
  "type": "multiple_choice",
  "instruction": "Choose the correct option.",
  "prompt": "She ___ to school yesterday.",
  "options": [
    { "id": "a", "text": "go" },
    { "id": "b", "text": "went" },
    { "id": "c", "text": "gone" }
  ],
  "correct_option_id": "b",
  "feedback": {
    "explanation": "Yesterday signals past simple, so we use went."
  }
}
```

#### `sentence_correction`

```json
{
  "type": "sentence_correction",
  "instruction": "Rewrite the sentence correctly.",
  "prompt": "She don't like coffee.",
  "accepted_corrections": [
    "She doesn't like coffee."
  ],
  "borderline_ai_fallback": true,
  "feedback": {
    "explanation": "With she/he/it in the present simple negative, use doesn't."
  }
}
```

### 4.3 Mapping From Proposed Types To Current Runtime

| Proposed content type | Current runtime status | Mapping |
|---|---|---|
| `fill_gap` | supported | map to `fill_blank` |
| `mcq` | supported | map to `multiple_choice` |
| `error_correction` | supported | map to `sentence_correction` |
| `transformation` | not yet supported | defer or rewrite as `fill_blank` / `multiple_choice` / `sentence_correction` |
| `matching` | not yet supported | defer |
| `open_production` | not yet supported | defer |

Rule:
- do not invent runtime widgets the app does not support
- if a target exercise cannot compile to the current runtime set, it is roadmap content, not shippable MVP content

### 4.4 Instruction Rule (Mandatory)

Every shipped exercise must include a short learner-facing instruction.

The instruction must:
- say exactly what the learner should do
- match the runtime exercise type
- be visible in the UI before the prompt itself

Examples:
- `Complete the gap with the correct verb form.`
- `Choose the correct option.`
- `Rewrite the sentence correctly.`

---

## 5. Content Generation Rules (Critical)

### 5.1 No Random Sentences

Sentences must:
- be realistic
- be B2-relevant
- avoid nonsense

Bad:
- "The purple cat had eaten philosophy."

Good:
- "She has been working here for five years."

### 5.2 Vocabulary Constraints

- CEFR B2 target
- no rare words
- no slang unless explicitly required

### 5.3 Grammar Isolation

Each exercise must test **one** concept only.

Bad:
- tense + modal + passive in one sentence

Good:
- only tense contrast

### 5.4 Lesson Distribution Rule (Current MVP)

Each shipped MVP lesson should contain **10 exercises**.

Recommended current mix:

| Runtime type | Count |
|---|---:|
| `fill_blank` | 4 |
| `multiple_choice` | 3 |
| `sentence_correction` | 3 |

This is the current productized distribution because it matches the app and keeps evaluation quality stable.

### 5.5 Rule-First Teaching

The rule screen must carry the teaching load.

Therefore:
- each lesson intro must contain a clear rule explanation
- each lesson intro must contain clear examples
- post-answer hints are not part of the current MVP
- after an incorrect answer, the learner sees a precise explanation of the tested rule, not a generic tip

---

## 6. Source Quality Rules

### 6.1 Allowed Source Principle

Grammar explanations and example patterns must come from:
- open textbooks
- open educational sources
- reputable educational publishers where content is publicly accessible

Do **not** rely on raw model invention for the rule itself.

### 6.2 AI Use In Content Workflow

AI may be used only for:
- structuring drafts
- generating candidate exercises offline
- checking consistency
- helping expand variant lists

AI must **not** be treated as the final authority for:
- the rule explanation
- canonical grammar patterns
- final accepted answers
- shipped lesson text

Every shipped lesson must be curated against source material and validated against the runtime schema.

---

## 7. Feedback System

### 7.1 Runtime Feedback Schema

```json
{
  "user_answer": "",
  "is_correct": false,
  "error_type": "wrong_form",
  "explanation": "",
  "correct_answer": ""
}
```

### 7.2 Error Types

- wrong tense
- wrong form
- agreement error
- missing article
- preposition error
- wrong conditional structure

### 7.3 Explanation Rules

Each explanation must:
1. name the rule
2. show the correct pattern
3. explain the learner's specific error

In the current MVP:
- explanations are written ahead of time in lesson content
- explanations should be short, exact, and rule-specific
- no extra hint/tip block is shown to the learner

---

## 8. User Flow vs Content Flow

### 8.1 Long-Term Curriculum Flow

Long-term content vision may include:
1. Select Unit
2. Select Lesson
3. Do exercises
4. Get feedback
5. Save progress
6. Unlock next

### 8.2 Current MVP Flow

Current shipped app flow is:
1. Home
2. Minimal onboarding
3. Lesson intro with rule + examples
4. Linear exercise flow
5. Feedback after each task
6. Summary

Do not author content assuming unlocks, persistence, adaptive difficulty, or unit selection already exist in the app.

---

## 9. Progression System

### 9.1 Current MVP

Not implemented:
- unlock logic
- saved progress
- adaptive difficulty
- repetition based on prior user history

### 9.2 Content Roadmap

These remain valid future content-system ideas:
- 80% threshold unlock
- repeating weak concepts
- controlled increase in complexity

But they are roadmap items, not current runtime assumptions.

---

## 10. Example Unit

### Unit 01: Infinitive vs -ing

Concepts:
- verb + to
- verb + -ing
- stop / remember / try

Example controlled items:

```json
[
  {
    "type": "fill_blank",
    "prompt": "I enjoy ___ (read)",
    "accepted_answers": ["reading"],
    "feedback": {
      "explanation": "After enjoy, use the -ing form."
    }
  },
  {
    "type": "fill_blank",
    "prompt": "She decided ___ (leave)",
    "accepted_answers": ["to leave"],
    "feedback": {
      "explanation": "After decide, use the infinitive with to."
    }
  },
  {
    "type": "multiple_choice",
    "prompt": "He stopped ___",
    "options": [
      { "id": "a", "text": "to smoke" },
      { "id": "b", "text": "smoking" }
    ],
    "correct_option_id": "b",
    "feedback": {
      "explanation": "Stop + -ing means to quit an activity."
    }
  }
]
```

---

## 11. Content Generation Pipeline

### Current approved pipeline

1. load unit definition
2. select one grammar target for one shippable lesson
3. collect open-source textbook references
4. draft lesson intro and examples from those references
5. generate candidate exercises within supported runtime types
6. validate:
   - one concept per item
   - CEFR level
   - no ambiguity
   - natural sentence quality
   - schema compatibility
7. attach rule-specific explanations
8. human/curator review
9. export JSON-compatible lesson fixture

### Important rule

Runtime lesson content must be **prebuilt and validated before shipping**.

No AI-generated lesson content at runtime in the current app.

---

## 12. Validation Rules (Hard)

Reject content if:
- multiple correct answers exist but are not enumerated
- ambiguity is present
- the grammar rule is unclear
- the sentence is unnatural
- the item tests more than one concept
- the item cannot be represented by the current runtime schema

---

## 13. Output Format

All shippable lesson content must be JSON-compatible.

No free-form final content blobs.

Authoring notes may exist in Markdown, but runtime lesson output must compile to the backend lesson schema.

---

## Final Rule

This document is authoritative for the **content system**.

AI must not:
- invent new shipped runtime exercise types
- skip pedagogical stages
- mix grammar rules inside one lesson
- generate final runtime lesson content without source-backed curation
- assume unsupported app features already exist

Deviation = invalid content.
