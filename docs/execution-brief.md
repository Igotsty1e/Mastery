# Execution Brief — Roundups AI Assistant MVP

## Build order

### Phase 1 — Content and contracts (no code)

1. ~~Resolve open questions from `docs/approved-spec.md` §10~~ — **resolved:**
   - Lesson content source: JSON fixtures in `backend/data/` (manifest + per-lesson files)
   - Session model: stateless per-visit; `attempt_id` is client-generated UUID per submission
   - LLM provider: OpenAI Responses API (`AI_PROVIDER=openai`); stub default for local dev
   - Empty input handling: treat as incorrect immediately — confirmed in backend implementation

2. Author at least one complete lesson fixture covering all 3 exercise types. Validate fixture against `docs/content-contract.md` schemas.

3. Finalize AI prompt template (see `docs/backend-contract.md`). Run 5+ manual test cases against it before integration.

### Phase 2 — Backend

1. Implement lesson content storage (hardcoded fixtures or DB seed).
2. Implement normalization function. Unit test against all cases in `docs/qa-golden-cases.md` §4.
3. Implement deterministic evaluation for all 3 types. Test against `docs/qa-golden-cases.md` §1–3.
4. Implement borderline detection for `sentence_correction`. Test against `docs/qa-golden-cases.md` §5.
5. Implement AI integration with 5s timeout and fallback. Test against `docs/qa-golden-cases.md` §6.
6. Wire all 3 API endpoints. Validate request/response schemas match `docs/backend-contract.md`.

### Phase 3 — Flutter client

1. Implement HTTP client layer (lesson fetch, answer submit, result fetch).
2. Implement LessonScreen (fetch + loading + error states).
3. Implement ExerciseScreen for each type (`fill_blank`, `multiple_choice`, `sentence_correction`).
4. Implement inline result display (correct/incorrect + feedback + canonical answer).
5. Implement LessonCompleteScreen (score display).
6. Wire navigation (linear, no back access after submit).

### Phase 4 — Integration and QA

1. Run all golden cases from `docs/qa-golden-cases.md` end-to-end against real backend.
2. Verify AI fallback path manually (borderline cases §5).
3. Verify AI timeout fallback (§6).
4. Test on Flutter web (`flutter run -d chrome`). iOS/Android require native toolchain — blocked until confirmed available.

---

## Acceptance gates (from `docs/approved-spec.md` §9)

### Gate 1 — Data contract
- [ ] Exercise schemas defined for all 3 types
- [ ] `accepted_answers[]` / `accepted_corrections[]` format specified
- [ ] AI request/response schema finalized
- [ ] All 3 API endpoint schemas finalized

### Gate 2 — Deterministic logic
- [ ] Normalization function specified and unit tested
- [ ] Levenshtein threshold confirmed (≤ 3)
- [ ] Borderline trigger conditions confirmed
- [ ] Timeout + fallback behavior confirmed (5s, default incorrect)

### Gate 3 — Flutter client scope
- [ ] Screen list confirmed: LessonScreen, ExerciseScreen, ResultScreen (inline), LessonCompleteScreen
- [ ] No local state beyond current session confirmed
- [ ] No client-side evaluation logic confirmed

### Gate 4 — Test cases
- [ ] All golden cases in `docs/qa-golden-cases.md` pass
- [ ] AI timeout/fallback golden case passes

### Gate 5 — AI prompt
- [ ] Prompt template written (see `docs/backend-contract.md`)
- [ ] Max token budget set (200 output tokens)
- [ ] 5+ manual test cases validated before integration

---

## What is locked (do not revisit without spec amendment)

- Exercise type count: exactly 3
- Evaluation authority: backend only
- AI scope: `sentence_correction` borderline only, server-side only
- Client framework: Flutter
- Lesson flow: linear, no branching
- Scope: no auth, no persistence, no gamification (full list in `docs/approved-spec.md` §8)
