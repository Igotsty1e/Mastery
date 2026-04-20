# Roundups AI Assistant — Approved MVP Spec

**Status:** Approved. Implementation-ready.  
**Date:** 2026-04-17  
**Version:** 1.0

---

## 1. Product Definition

Roundups AI Assistant is a Flutter mobile app for English language practice. Users complete structured lessons composed of deterministic exercises. AI is used narrowly: evaluating free-text answers and generating short corrective feedback. The server is the single source of truth for all lesson content and correctness decisions.

**One-sentence pitch:** A fixed-flow English practice app where the backend decides correctness and AI only explains why.

---

## 2. System Boundaries

| Layer | Technology | Responsibility |
|---|---|---|
| Client | Flutter (Dart) | Render exercises, collect input, display results |
| Backend | REST API (deterministic) | Serve lessons, evaluate answers, enforce authority |
| AI Layer | LLM (server-side only) | Evaluate borderline `sentence_correction`; generate short feedback strings |

**Hard rules:**
- AI never runs on the client.
- Client never makes its own correctness decisions.
- AI is never called for `fill_blank` or `multiple_choice` — those are fully deterministic.
- AI output is always validated server-side before being returned to client.

---

## 3. Exercise Types (Exactly 3)

### 3.1 `fill_blank`
User types a word or short phrase into a blank.  
Evaluation: deterministic exact match + normalized match (lowercase, trim, collapse whitespace).  
Accepted answers list stored in exercise definition. No AI.

### 3.2 `multiple_choice`
User selects one option from 2–4 choices.  
Evaluation: deterministic index/ID comparison against `correct_option_id`.  
No AI.

### 3.3 `sentence_correction`
User rewrites a sentence that contains one or more errors.  
Evaluation: deterministic exact match against `accepted_corrections[]` first.  
AI fallback: triggered only when deterministic check fails AND the submission meets borderline criteria (see Section 6).  
AI output: `{ "correct": bool, "feedback": string (max 80 chars) }`.

No other exercise types will be added in this MVP.

---

## 4. Lesson Flow

Fixed linear sequence. No branching. No skipping. No adaptive reordering.

```
Lesson Start
  → Exercise 1
      → Submit answer
      → Receive result (correct / incorrect + feedback)
      → Next
  → Exercise 2
      ...
  → Exercise N
      → Submit answer
      → Receive result
Lesson Complete screen
  → Show score (X / N correct)
  → Done button → exit
```

**Rules:**
- User cannot go back to previous exercises.
- User cannot skip an exercise.
- Each exercise shows result immediately after submission.
- No timers. No streaks. No points. No badges.
- Lesson Complete screen shows raw score only.

---

## 5. Evaluation Policy

### Priority order (all types):

1. **Deterministic match** — always attempted first.
2. **AI fallback** — `sentence_correction` only, borderline cases only (see Section 6).
3. **Default to incorrect** — if AI is unavailable or times out.

### Deterministic matching rules:
- Normalize: see `docs/content-contract.md` §4.
- Compare against all entries in `accepted_answers[]` (fill_blank) or `accepted_corrections[]` (sentence_correction).
- Match = correct. No match = incorrect (or borderline check for `sentence_correction`).

### AI evaluation contract:
- Request payload: `{ "prompt_template": string, "user_answer": string, "exercise_context": object }`
- Response schema: `{ "correct": bool, "feedback": string }`
- Feedback max length: 80 characters.
- Server validates response schema before using it.
- On invalid response or timeout (5s): treat as incorrect, return generic feedback.

---

## 6. Borderline Definition (sentence_correction only)

AI fallback is triggered if ALL of the following are true:

1. Deterministic match failed (normalized answer not in `accepted_corrections[]`).
2. Edit distance between normalized submission and nearest accepted correction is ≤ 3 characters (Levenshtein).
3. Submission length is between 50% and 200% of the shortest accepted correction length.

If any condition fails → immediately mark incorrect, skip AI call.

This definition is fixed. Do not expand criteria without a spec revision.

---

## 7. Server Authority

The backend is the single source of truth. The client renders what the server sends. The client never:
- Stores lesson definitions locally beyond the current session render.
- Computes correctness.
- Modifies exercise order.
- Decides when to call AI.
- Interprets AI output directly.

Server responses are final. Client displays them without modification.

**API surface (MVP):**

```
GET  /lessons/{lesson_id}                          → lesson definition (ordered exercise list)
POST /lessons/{lesson_id}/answers                  → submit one answer, receive result
GET  /lessons/{lesson_id}/result?session_id={uuid} → final lesson score (requires session_id)
```

No other endpoints required for MVP.

---

## 8. Non-Goals (Explicitly Out of Scope)

The following will NOT be built in this MVP. Any request to add them is a scope change requiring spec revision.

- User authentication or accounts
- Progress persistence across sessions
- Resume / save state
- Adaptive learning or difficulty adjustment
- Branching lesson paths
- Chat UI or conversational interface
- Gamification (streaks, badges, points, leaderboards, levels)
- Lesson authoring tools
- Offline mode
- Push notifications
- Social features
- Hints or help system
- Multiple language support beyond English
- Analytics or telemetry
- AI-generated lesson content
- More than 3 exercise types

---

## 9. Acceptance Gates (Before Coding Starts)

All gates must pass before implementation begins on each component.

### Gate 1 — Data Contract
- [ ] Exercise schema defined and reviewed for all 3 types
- [ ] `accepted_answers[]` / `accepted_corrections[]` formats specified (string arrays, normalized at write time)
- [ ] AI request/response schema finalized and documented
- [ ] API endpoint schemas finalized (request + response for all 3 endpoints)

### Gate 2 — Deterministic Logic
- [ ] Normalization function specified (see `docs/content-contract.md` §4)
- [ ] Levenshtein threshold confirmed (≤ 3)
- [ ] Borderline trigger conditions confirmed (Section 6)
- [ ] Timeout and fallback behavior confirmed (5s, default incorrect)

### Gate 3 — Flutter Client Scope
- [ ] Screen list finalized: Lesson screen, Exercise screen, Result screen, Lesson Complete screen
- [ ] No local state beyond current exercise render confirmed
- [ ] No client-side evaluation logic confirmed

### Gate 4 — Test Cases
- [ ] At least 3 test cases per exercise type covering: exact match, normalized match, no match
- [ ] At least 2 borderline test cases for `sentence_correction`: one that triggers AI, one that does not
- [ ] Timeout/fallback scenario documented

### Gate 5 — AI Prompt
- [ ] AI prompt template written and reviewed
- [ ] Max token budget set
- [ ] Output validated with at least 5 manual test cases before integration

---

## 10. Resolved Decisions (formerly Open Questions)

1. **Lesson content source:** JSON fixtures in `backend/data/` (manifest + per-lesson files). No DB, no CMS.
2. **Session model:** Session-scoped in-memory store. Client generates a `session_id` UUID at lesson start and passes it with every answer submission. Results are keyed by `session_id:lesson_id` in the backend's in-memory store. No cross-session persistence; store is process-lifetime only.
3. **LLM provider:** OpenAI Responses API (`AI_PROVIDER=openai`). `StubAiProvider` is default for local dev (always returns incorrect).
4. **Empty input handling:** Treat as incorrect immediately — skip evaluation, return `correct=false, evaluation_source=deterministic`.

---

*This spec is approved. Deviations require written amendment to this document.*
