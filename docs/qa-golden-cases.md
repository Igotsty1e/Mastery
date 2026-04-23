# QA Golden Cases — Roundups AI Assistant MVP

All cases are implementation-ready. Each case specifies input, expected `correct`, `evaluation_source`, and `canonical_answer`.

---

## 1. fill_blank

Exercise fixture:
```json
{
  "exercise_id": "00000000-0000-4000-8000-000000000101",
  "type": "fill_blank",
  "prompt": "She ___ to school every day.",
  "accepted_answers": ["walks", "goes"]
}
```

### Accepted (correct=true)

| # | user_answer (raw)  | Normalized       | Reason                        |
|---|--------------------|------------------|-------------------------------|
| 1 | `"walks"`          | `"walks"`        | Exact match, canonical answer |
| 2 | `"goes"`           | `"goes"`         | Alternate accepted answer     |
| 3 | `"  walks  "`      | `"walks"`        | Trim normalization            |
| 4 | `"Walks"`          | `"walks"`        | Lowercase normalization       |
| 5 | `"walks."`         | `"walks"`        | Trailing punctuation stripped |
| 6 | `"GOES"`           | `"goes"`         | Uppercase normalized          |

### Rejected (correct=false)

| # | user_answer (raw)  | Normalized       | Reason                              |
|---|--------------------|------------------|-------------------------------------|
| 1 | `"walk"`           | `"walk"`         | Not in accepted_answers             |
| 2 | `"walked"`         | `"walked"`       | Wrong tense, not listed             |
| 3 | `"run"`            | `"run"`          | Different word                      |
| 4 | `""`               | `""`             | Empty input                         |
| 5 | `"   "`            | `""`             | Whitespace-only input               |
| 6 | `"walks quickly"`  | `"walks quickly"`| Extra word, no match                |

---

## 2. multiple_choice

Exercise fixture:
```json
{
  "exercise_id": "00000000-0000-4000-8000-000000000201",
  "type": "multiple_choice",
  "prompt": "Which word means 'happy'?",
  "options": [
    { "id": "a", "text": "Sad" },
    { "id": "b", "text": "Joyful" },
    { "id": "c", "text": "Angry" },
    { "id": "d", "text": "Tired" }
  ],
  "correct_option_id": "b"
}
```

### Accepted (correct=true)

| # | user_answer (raw) | Normalized | Reason                 |
|---|-------------------|------------|------------------------|
| 1 | `"b"`             | `"b"`      | Exact match            |
| 2 | `"B"`             | `"b"`      | Lowercase normalization|
| 3 | `" b "`           | `"b"`      | Trim normalization     |

### Rejected (correct=false)

| # | user_answer (raw) | Normalized | Reason                        |
|---|-------------------|------------|-------------------------------|
| 1 | `"a"`             | `"a"`      | Wrong option                  |
| 2 | `"c"`             | `"c"`      | Wrong option                  |
| 3 | `"d"`             | `"d"`      | Wrong option                  |
| 4 | `"Joyful"`        | `"joyful"` | Text instead of option id     |
| 5 | `""`              | `""`       | Empty input                   |
| 6 | `"e"`             | `"e"`      | Non-existent option id        |

---

## 3. sentence_correction

Exercise fixture:
```json
{
  "exercise_id": "00000000-0000-4000-8000-000000000301",
  "type": "sentence_correction",
  "prompt": "She don't like coffee.",
  "accepted_corrections": [
    "She doesn't like coffee.",
    "She does not like coffee."
  ],
  "borderline_ai_fallback": true
}
```

### Accepted — deterministic (correct=true, evaluation_source=deterministic)

| # | user_answer (raw)                  | Normalized                         | Reason                         |
|---|------------------------------------|------------------------------------|--------------------------------|
| 1 | `"She doesn't like coffee."`       | `"she doesn't like coffee"`        | Exact match after normalization|
| 2 | `"She does not like coffee."`      | `"she does not like coffee"`       | Alternate accepted correction  |
| 3 | `"  She doesn't like coffee.  "`   | `"she doesn't like coffee"`        | Trim normalization             |
| 4 | `"SHE DOESN'T LIKE COFFEE"`        | `"she doesn't like coffee"`        | Lowercase + punct normalization|
| 5 | `"She doesn't like coffee"`        | `"she doesn't like coffee"`        | Missing trailing punct, match  |

### Rejected — deterministic, no AI fallback triggered

| # | user_answer (raw)            | Normalized                   | Reason                                        |
|---|------------------------------|------------------------------|-----------------------------------------------|
| 1 | `"She don't like coffee."`   | `"she don't like coffee"`    | Same as prompt, error uncorrected             |
| 2 | `""`                         | `""`                         | Empty input                                   |
| 3 | `"She doesn't like tea."`    | `"she doesn't like tea"`     | Changed meaning, not an accepted correction   |

---

## 4. Edge-Case Normalization Examples

| Input                              | Normalized                      | Rule applied                              |
|------------------------------------|---------------------------------|-------------------------------------------|
| `"café"`                           | `"café"`                        | NFC normalization preserves accents       |
| `"it\u2019s fine"`                 | `"it's fine"`                   | Smart apostrophe mapped to ASCII          |
| `"hello   world"`                  | `"hello world"`                 | Internal whitespace collapse              |
| `"...hello"`                       | `"...hello"`                    | Leading punct NOT stripped (boundary only)|
| `"hello..."`                       | `"hello"`                       | Trailing `.` stripped                     |
| `"don't"`                          | `"don't"`                       | Mid-word apostrophe preserved             |
| `"Hello, world!"`                  | `"hello, world"`                | Lowercase + trailing `!` stripped         |
| `"\twalks\n"`                      | `"walks"`                       | Tab/newline treated as whitespace, trimmed|

---

## 5. Borderline sentence_correction — AI Fallback Triggered

These cases fail deterministic check (no match in `accepted_corrections`) and satisfy the borderline trigger:
min Levenshtein distance ≤ 3 and length within 50%–200% of the shortest accepted correction.

Exercise fixture same as Section 3.

| # | user_answer                      | Why deterministic fails                       | Expected AI decision |
|---|----------------------------------|-----------------------------------------------|----------------------|
| 1 | `"She does not like coffe."`     | Minor spelling typo (`coffee`)                | AI: correct=true (meaning/grammar corrected; minor typo) |
| 2 | `"She doesn't likes coffee."`    | Verb form still wrong (`likes` after `doesn't`) | AI: correct=false (still ungrammatical) |
| 3 | `"She doesn't like coffeee."`    | Minor spelling typo (extra letter)            | AI: correct=true (meaning/grammar corrected; minor typo) |

---

## 6. AI Fallback Failure — Expected Outcomes

When AI call fails (timeout, HTTP 5xx, malformed response):

| Field               | Value            |
|---------------------|------------------|
| `correct`           | `false`          |
| `evaluation_source` | `deterministic`  |
| `feedback`          | `null`           |
| `canonical_answer`  | first entry from `accepted_corrections` |

### Golden case

Input: `user_answer = "She does not like coffe."` (borderline, deterministic miss)
AI call: timeout after 5s

Expected response:
```json
{
  "attempt_id": "<uuid>",
  "exercise_id": "00000000-0000-4000-8000-000000000301",
  "correct": false,
  "evaluation_source": "deterministic",
  "feedback": null,
  "canonical_answer": "She doesn't like coffee."
}
```

Note: user sees wrong marked as incorrect. Acceptable tradeoff per MVP constraints. Do not retry AI automatically.
