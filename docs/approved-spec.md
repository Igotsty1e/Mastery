# Roundups AI Assistant — Approved MVP Spec

**Status:** Approved. Implementation-ready.  
**Date:** 2026-04-17  
**Version:** 1.0  
**Successor:** `LEARNING_ENGINE.md` + `docs/plans/learning-engine-mvp-2.md` for post-MVP engine evolution. This doc froze the original
MVP scope and remains authoritative for what the **launch product** committed to. Where the shipped engine has moved past the
original frozen scope, the relevant section below carries an explicit "**Post-MVP update**" pointer to the
`learning-engine-mvp-2.md` wave that landed the change. Cross-canon conflicts resolve per `CLAUDE.md §Content Source Of Truth`:
runtime contracts (`backend-contract.md`, `mobile-architecture.md`, `content-contract.md`) win for what the code does **today**;
`LEARNING_ENGINE.md` wins for where the product is **going**.

---

## 1. Product Definition

Roundups AI Assistant is a Flutter mobile app for English language practice. Users complete structured lessons composed of deterministic exercises. AI is used narrowly: evaluating borderline sentence corrections server-side. Learner-facing feedback remains curated lesson content. The server is the single source of truth for all lesson content and correctness decisions.

**One-sentence pitch:** A fixed-flow English practice app where each lesson teaches one rule, the backend decides correctness, and AI is used only to judge borderline sentence corrections.

---

## 2. System Boundaries

| Layer | Technology | Responsibility |
|---|---|---|
| Client | Flutter (Dart) | Render exercises, collect input, display results |
| Backend | REST API (deterministic) | Serve lessons, evaluate answers, enforce authority |
| AI Layer | LLM (server-side only) | (1) Evaluate borderline `sentence_correction`; return internal structured verdict only. (2) Generate the post-lesson **debrief** on `GET /result` from aggregated attempt facts (canonical answer + curated explanation), grounded by deterministic bucket. Never sees student free-text answers. **Post-MVP update:** AI now also evaluates `sentence_rewrite` (Wave 14.2 — same evaluator as sentence_correction) and `short_free_sentence` (Wave 14.4 — new `evaluateFreeSentence` method judging rule conformance instead of match-against-accepted). The "never sees student free-text" guarantee remains for the debrief; per-attempt evaluators do see the student answer for the open-answer family. |

**Hard rules:**
- AI never runs on the client.
- Client never makes its own correctness decisions.
- AI is never called for `fill_blank`, `multiple_choice`, or `listening_discrimination` — those are fully deterministic.
- AI output is always validated server-side before being returned to client.
- Debrief AI is **never** called on a perfect score (zero-error short-circuit). Failure modes (timeout, malformed JSON, refusal) fall back to deterministic copy keyed off the score bucket. The score-bucket → `debrief_type` mapping is deterministic; AI generates copy only.

---

## 3. Exercise Types (4 Shipped)

Every exercise has a required `instruction` field shown to the learner in a prominent band at the top of the exercise card before the prompt. It must be a short, action-oriented sentence (e.g. "Fill in the blank with the correct verb form.").

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

### 3.4 `listening_discrimination`
User listens to a pre-generated audio clip and selects the sentence they heard from 2–4 options.  
Evaluation: deterministic — `correct_option_id` comparison.  
No AI.  
Audio: pre-generated TTS served at `/audio/{lesson_id}/{exercise_id}.mp3`. Transcript required; hidden behind `Show transcript` toggle.  
Schema: see `docs/content-contract.md §2.4`.  
UI: see `DESIGN.md §14`.

No other exercise types will be added beyond these four without a spec revision.

---

## 4. Lesson Flow

Fixed linear sequence. No branching. No skipping. No adaptive reordering.

```
HomeScreen
  → First launch: 2-step onboarding (`Promise` → `Assembly`)
      → Dashboard (the single Home: level selector, progress card, "Start Lesson" CTA)
          → Lesson Intro / loading
              → Exercise 1
                  → Submit answer
                  → Receive result (correct / incorrect + canonical answer + explanation)
                  → Next
              → Exercise 2
                  ...
              → Exercise N
                  → Submit answer
                  → Receive result
              → SummaryScreen
                  → Show score (X / N correct)
                  → Show coach's-note **debrief** (AI-generated when present;
                    deterministic fallback otherwise; hides the legacy one-line
                    conclusion when the debrief is shown)
                  → Show mistake review cards (incorrect answers only)
                  → Done button → back to Dashboard
  → Returning launch: Dashboard (same as above)
```

**Rules:**
- User cannot go back to previous exercises.
- User cannot skip an exercise.
- First launch uses a 2-step onboarding that ends in the dashboard. The dashboard is the single Home — it is also the destination of `Done` from SummaryScreen.
- Returning users land on the dashboard directly.
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
- AI feedback is internal. User-facing explanations come from the exercise's curated `feedback.explanation` field.
- On invalid response or timeout (5s): treat as incorrect.

### evaluation_source Type Definition

The `evaluation_source` field in response payloads may be one of:

| Value | Meaning |
|---|---|
| `deterministic` | Answer evaluated by exact or normalized string match; AI not called |
| `ai_fallback` | Borderline submission was sent to AI and AI successfully evaluated it |
| `ai_timeout` | AI call exceeded 5-second timeout; submission marked incorrect as fallback |
| `ai_error` | AI call failed (invalid response schema, network error); submission marked incorrect as fallback |

**Post-MVP update (Wave 5).** The evaluation response shape has been
extended additively per `LEARNING_ENGINE.md §8.7` and
`docs/plans/learning-engine-mvp-2.md` Wave 5. The `correct: bool` field
is preserved for backwards compat; the wire response also carries
`result: "correct"|"partial"|"wrong"`, `response_units: []` (populated
only by Wave 6 multi-unit families), and `evaluation_version: 1`. Full
contract: `docs/backend-contract.md`.

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
- ~~Modifies exercise order.~~ **Post-MVP update (Wave 3):** the Flutter
  `DecisionEngine` (`app/lib/learner/decision_engine.dart`) re-orders the
  remaining-exercise queue per `LEARNING_ENGINE.md §9.1` after a learner
  mistake. The lesson fixture and the per-attempt evaluation verdict
  remain server-authored; only the **order** in which the learner sees
  the next un-attempted item is now a client decision, driven by stored
  metadata (`skill_id`) shipped from the server. Reorder fires only on a
  same-skill replacement candidate; with a single-skill bank the linear
  default is preserved. Audit trail: `docs/plans/learning-engine-mvp-2.md`
  Wave 3.
- Decides when to call AI.
- Interprets AI output directly.

Server responses are final. Client displays them without modification.

**API surface (MVP):**

```
GET  /lessons/{lesson_id}                          → lesson definition (ordered exercise list)
POST /lessons/{lesson_id}/answers                  → transitional anonymous answer submission (Wave 1)
GET  /lessons/{lesson_id}/result?session_id={uuid} → transitional anonymous result (Wave 1)

# Wave 2 — server-owned sessions (auth required)
POST /lessons/{lesson_id}/sessions/start           → create or resume the user's in-progress session
GET  /lessons/{lesson_id}/sessions/current         → return the active in-progress session (or 404)
POST /lesson-sessions/{session_id}/answers         → submit one answer (immutable history)
POST /lesson-sessions/{session_id}/complete        → mark completed + persist debrief snapshot
GET  /lesson-sessions/{session_id}/result          → result payload (live or persisted snapshot)
GET  /dashboard                                    → per-user lessons + recommended-next + last report
```

The legacy anonymous routes will be removed once the Flutter client has
cut over to the auth-protected lesson-session surface.

---

## 8. Non-Goals (Explicitly Out of Scope)

The following will NOT be built in this MVP. Any request to add them is a scope change requiring spec revision.

- ~~User authentication or accounts~~ **Post-MVP (Wave 7):** auth + server-owned learner state migration per `docs/plans/auth-server-state-wave7.md`. Backend foundation (Apple stub auth, refresh tokens, server-owned `lesson_sessions`, `/me`, audit log) is staged in this PR; Flutter wiring is Wave 7.4. The shipped MVP remains anonymous + in-memory until the auth surface is wired into the client.
- ~~Server-side progress persistence~~ **Post-MVP (Wave 7):** Drizzle + Postgres backs `lesson_sessions`, `exercise_attempts`, `lesson_progress` tables and the `/lessons/:id/sessions/*` + `/lesson-sessions/:id/*` + `/dashboard` endpoints. Legacy in-memory `src/store/memory.ts` stays alongside until the Flutter client cuts over. Local `SharedPreferences` (`LocalProgressStore`, `LearnerSkillStore`, `ReviewScheduler`) keeps working as device-scoped fallback during the migration window.
- ~~Resume / save state~~ **Post-MVP (Wave 7):** server-owned sessions support cross-device resume (one active in-progress session per user+lesson, enforced by a partial unique index). The Flutter client wiring lands in Wave 7.4.
- ~~Adaptive learning or difficulty adjustment~~ **Post-MVP (Waves 2–3):**
  per-learner per-skill mastery state + the §9.1 in-session 1/2/3 loop
  + the §9.3 review cadence shipped via the `LEARNING_ENGINE.md`
  migration path. Status surfaces are still planned (Wave 4 Transparency
  Layer). Original-MVP scope is unchanged: launch shipped a fixed linear
  flow; the engine evolution is a deliberate, audited extension.
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
- More than 4 exercise types (the 4 shipped types are `fill_blank`, `multiple_choice`, `sentence_correction`, `listening_discrimination`)
  - **Post-MVP update:** Wave 14.2 added `sentence_rewrite` and Wave 14.4 added `short_free_sentence`. The runtime gate (`backend/src/data/exerciseBank.ts#RUNTIME_SUPPORTED_EXERCISE_TYPES`) is the live source of truth. See `docs/plans/learning-engine-v1.md` Wave 14.2 + 14.4 entries.
- Hints or practical tips shown after an incorrect answer

---

## 9. Acceptance Gates (Before Coding Starts)

All gates must pass before implementation begins on each component.

### Gate 1 — Data Contract
- [ ] Exercise schema defined and reviewed for all 4 types
- [ ] `accepted_answers[]` / `accepted_corrections[]` formats specified (string arrays, normalized at write time)
- [ ] AI request/response schema finalized and documented
- [ ] API endpoint schemas finalized (request + response for all 3 endpoints)

### Gate 2 — Deterministic Logic
- [ ] Normalization function specified (see `docs/content-contract.md` §4)
- [ ] Levenshtein threshold confirmed (≤ 3)
- [ ] Borderline trigger conditions confirmed (Section 6)
- [ ] Timeout and fallback behavior confirmed (5s, default incorrect)

### Gate 3 — Flutter Client Scope
- [x] Screen list finalized: HomeScreen (onboarding + dashboard), LessonIntroScreen, ExerciseScreen (inline result), SummaryScreen
- [x] Session state is in-memory only; `LocalProgressStore` (SharedPreferences) persists completed-exercise count per lesson for the dashboard progress card
- [x] No client-side evaluation logic confirmed

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
