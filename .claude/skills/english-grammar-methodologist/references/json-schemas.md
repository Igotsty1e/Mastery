# JSON Schemas (default fallback)

This file defines the **default** JSON shape produced when the host project does not specify its own schema. If the project has its own schema, follow that — these defaults exist so that, in the absence of project conventions, output is still consistent and machine-consumable.

The schemas are JSON Schema draft 2020-12. They live as concrete JSON files at `assets/templates/` (one per exercise type) and as the canonical schema at `assets/schema/exercise.schema.json`.

## Top-level: an `ExerciseSet`

Every generation produces an `ExerciseSet`: one or more exercises sharing target form, level, and (usually) context.

```json
{
  "id": "string (kebab-case, unique within project)",
  "title": "string (human-readable, in English by default; can be in project's metadata language)",
  "level": "A1 | A2 | B1 | B2 | C1 | C2",
  "target_form": "string — the specific form, not just 'tenses'. e.g. 'Present Perfect with for/since'",
  "topic": "string — lexical/topical context. e.g. 'travel', 'work, daily routines'",
  "methodology_notes": "string — short rationale: tier mix, authority, deliberate omissions",
  "sources": [
    "string — reference works consulted, e.g. 'Murphy EGiU 5e Unit 8', 'Swan PEU §455'"
  ],
  "exercises": [ Exercise ]
}
```

## Exercise (discriminated by `type`)

All exercises share a common envelope:

```json
{
  "id": "string (unique within set)",
  "type": "noticing-identify | noticing-sort | gap-fill | multiple-choice | transformation | sentence-completion | error-correction | word-order | matching | personalisation | dictogloss | task-based",
  "tier": "awareness | controlled | meaningful | free",
  "rubric": "string — the instruction the learner sees",
  "context": "string | null — short scene-setter, optional",
  "items": [ Item ]
}
```

The `Item` shape varies by type. Recipes follow.

### gap-fill

```json
{
  "n": 1,
  "stem": "She _____ here since 2019. (live)",
  "answer": "has lived",
  "alternatives": ["has been living"],
  "explanation": "Present Perfect for an action that started in the past and continues to now; 'since' marks the start point."
}
```

### multiple-choice

```json
{
  "n": 1,
  "stem": "I tried calling Sarah, but there was no answer. She ____ at work.",
  "options": {
    "A": "must be",
    "B": "must have been",
    "C": "had to be",
    "D": "was supposed to be"
  },
  "answer": "B",
  "distractor_diagnostics": {
    "A": "Treats the deduction as present, ignoring 'tried calling' (past).",
    "C": "Confuses obligation ('had to') with deduction.",
    "D": "Confuses expectation/plan with deduction."
  },
  "explanation": "'Must have + p.p.' = a confident deduction about the past."
}
```

### transformation (Cambridge-style key word)

```json
{
  "n": 1,
  "source": "They are going to build a new bridge here.",
  "key_word": "GOING",
  "min_words": 2,
  "max_words": 5,
  "frame": "A new bridge ____ here.",
  "answer": "is going to be built",
  "explanation": "Active 'be going to' becomes passive 'is/are going to be + past participle'."
}
```

### sentence-completion

```json
{
  "n": 1,
  "stem": "If I had more time, ____.",
  "sample_answers": [
    "I would learn another language.",
    "I would visit my grandparents more often."
  ],
  "criterion": "Use 'would' + base verb; produce a plausible meaning.",
  "explanation": "Second conditional: hypothetical present/future. Result clause uses 'would + base verb'."
}
```

### error-correction

```json
{
  "n": 1,
  "sentence": "She don't like coffee.",
  "has_error": true,
  "error_span": "don't",
  "correction": "doesn't",
  "explanation": "3rd-person singular present: 'does not / doesn't', not 'do not / don't'."
}
```

(For "no error" items, `has_error: false` and `correction` is the same as the original.)

### word-order

```json
{
  "n": 1,
  "tokens": ["often", "does", "what", "she", "time", "get up", "?"],
  "answer": "What time does she often get up?",
  "explanation": "Wh-question with 'do' auxiliary: Wh- + auxiliary + subject + adverb + main verb."
}
```

### matching

```json
{
  "n": 1,
  "left": ["depend", "marry", "consist", "succeed"],
  "right": ["of", "in", "—", "on"],
  "answer_pairs": [["depend", "on"], ["marry", "—"], ["consist", "of"], ["succeed", "in"]],
  "explanation": "Verb + preposition collocations: 'marry someone' takes no preposition; the others take fixed prepositions."
}
```

### noticing-identify

```json
{
  "n": 1,
  "text": "Hi Mark, I've just got home from the airport. I haven't unpacked yet, but I wanted to write before I forgot. The trip has been amazing.",
  "target_to_underline": "Present Perfect verb forms",
  "answer_spans": ["I've just got", "I haven't unpacked", "has been"],
  "follow_up": "Why does the writer use Present Perfect rather than Past Simple here?"
}
```

### noticing-sort

```json
{
  "n": 1,
  "buckets": ["Present Perfect", "Past Simple"],
  "items_to_sort": [
    "I lived in Berlin for two years.",
    "I have lived in Berlin since 2020.",
    "She visited Paris last summer.",
    "She has just visited Paris."
  ],
  "answer_assignments": {
    "I lived in Berlin for two years.": "Past Simple",
    "I have lived in Berlin since 2020.": "Present Perfect",
    "She visited Paris last summer.": "Past Simple",
    "She has just visited Paris.": "Present Perfect"
  },
  "explanation": "Past Simple for finished time / definite past markers; Present Perfect for periods continuing to now or unspecified past relevant to now."
}
```

### personalisation

```json
{
  "n": 1,
  "stem": "Something I have never tried but want to: ____.",
  "criterion": "Use Present Perfect ('have never + p.p.') + an infinitive purpose clause.",
  "sample_answer": "I have never tried surfing, but I want to learn one day."
}
```

### dictogloss

```json
{
  "n": 1,
  "source_text": "Last weekend, while I was walking through the old town, I noticed a small café I'd never seen before. The owner had been baking cakes since dawn, and the smell was incredible.",
  "target_forms": ["Past Continuous", "Past Simple", "Past Perfect", "Past Perfect Continuous"],
  "instructions": "Listen twice. Take brief notes. Reconstruct the text in pairs.",
  "scoring_rubric": "1 point per target form correctly used; 1 point per accurate clause; deduct 1 per major form error."
}
```

### task-based

```json
{
  "n": 1,
  "outcome": "Write a 60-word email to a friend describing what you have been doing this week.",
  "constraint": "Use at least 5 different verbs in Present Perfect / Present Perfect Continuous.",
  "scenario": "Your friend has been away on a trip and asked for an update.",
  "self_check": [
    "Did I use Present Perfect for completed actions with present relevance?",
    "Did I use Present Perfect Continuous for ongoing actions?",
    "Did I avoid Past Simple unless the time is finished and specified?"
  ]
}
```

## Validation

Run:

```bash
python scripts/validate_task.py path/to/output.json
```

…or pipe stdin:

```bash
cat output.json | python scripts/validate_task.py -
```

The script validates against `assets/schema/exercise.schema.json`.

To validate against a project's own schema:

```bash
python scripts/validate_task.py output.json --schema path/to/project.schema.json
```

## Versioning

The default schema starts at `1.0`. If a project's docs reference an `exercise_schema_version`, follow that; do not assume our default applies.
