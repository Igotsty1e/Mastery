# Mastery — Project Entry

> Cross-project principles, user profile, skill routing baseline, auto-memory
> protocol, model selection и token economy живут в `~/.claude/COMPANY.md`
> (loaded automatically per `~/.claude/CLAUDE.md` bootstrap). Этот файл —
> только Mastery-specific layer: sources of truth, doc layout, project skill
> routes, deploy config.

## Secret Files

- Never commit `.mcp.json`. It may contain MCP auth headers or API keys such as the Render token.

## Design Source Of Truth

- `DESIGN.md` is the canonical source of truth for all visual design decisions: color system, typography, spacing, component specs, motion, and screen-level direction.
- `docs/design-mockups/` is the canonical **visual reference** for screen-level composition. Eight mobile mockups (390×844) cover the shipped layouts: home onboarding/dashboard, lesson intro, three text-based exercise types (multiple choice, fill-the-blank, sentence correction), result, summary. Built directly against DESIGN.md tokens with real lesson content from `backend/data/lessons/b2-lesson-001.json`. The `listening_discrimination` exercise variant is specified in `DESIGN.md §14` (not in the mockup set). In-flight visual explorations live alongside the shipped set: `docs/design-mockups/onboarding-2step/` for the shipped onboarding wave audit trail, and `docs/design-mockups/dashboard-study-desk.html` for the next dashboard redesign study.
- `docs/plans/arrival-ritual.md` is the approved screen contract for the onboarding + first-exercise V2 wave. **Shipped 2026-04-26 (Direction A · Editorial Notebook):** 2-step onboarding (`Promise` → `Assembly`) ending in a dashboard that doubles as the single Home (also the destination of `Done` from SummaryScreen). Implementation: `app/lib/screens/onboarding_arrival_ritual_screen.dart`, dashboard in `app/lib/screens/home_screen.dart`, calm route transitions in `app/lib/widgets/mastery_route.dart`. Visual reference: `docs/design-mockups/onboarding-2step/direction-a-editorial.html`. **Brief B (first-exercise V2 chrome) was declined by the product owner — the current exercise chrome is the long-term contract; do not redesign it without an explicit reversal.** Use this doc together with `DESIGN.md` before changing those flows.
- `docs/plans/dashboard-study-desk.md` is the Dashboard V2 (Study Desk) contract. **Shipped 2026-04-26.** Implementation: `app/lib/screens/home_screen.dart` plus `app/lib/session/last_lesson_store.dart` and the reusable `StatusBadge` widget in `app/lib/widgets/mastery_widgets.dart`. Visual reference: `docs/design-mockups/dashboard-study-desk.html`. The Wave 2 backend (`GET /dashboard`, 2026-04-26) is the persistent source of truth for the Last lesson report, but the Flutter client is **not yet rewired** against it — see `docs/plans/auth-foundation.md §Wave 3 — remaining`.
- Open the gallery: `cd docs/design-mockups && python3 -m http.server 8765` then `http://127.0.0.1:8765/`.
- Use both together: DESIGN.md = tokens (color, typography, spacing, motion); design-mockups/ = composition (layout, hierarchy, copy). When implementing or reviewing UI, cross-reference both.
- Use these as the primary reference whenever evaluating, implementing, or reviewing any UI or design work.
- Do not introduce visual styles, color values, font choices, or component patterns that contradict DESIGN.md without explicit user instruction. When the mockups and DESIGN.md disagree, DESIGN.md wins (tokens are spec, mockups are reference).
- Update both DESIGN.md and the mockups when changing visual decisions.

## Content Source Of Truth

- `GRAM_STRATEGY.md`, `exercise_structure.md`, and `LEARNING_ENGINE.md` are the three **sibling** top-level canonical docs, each authoritative in its own domain — pedagogy / authoring rules / engine design — per `GRAM_STRATEGY.md §Authority chain`. None is subordinate to another; cross-canon conflicts are resolved by domain (pedagogy → `GRAM_STRATEGY.md`, authoring → `exercise_structure.md`, engine invariants → `LEARNING_ENGINE.md`).
- `GRAM_STRATEGY.md` is the canonical source of truth for how Mastery teaches English grammar and usage (pedagogy: what we teach and why).
- `exercise_structure.md` is the canonical source of truth for exercise types, sequencing, authoring standards, runtime mapping, and examples (authoring: how individual items are written).
- `docs/content/unit-u01-blueprint.md` is the active unit-level authoring plan that turns that pedagogy into the next shippable lesson sequence.
- Use it as the primary reference whenever generating, revising, reviewing, or expanding educational content for the app.
- Treat it as authoritative for the **content layer**, not for unsupported runtime features.
- If content guidance conflicts with the shipped app architecture or current MVP constraints, keep the content intent but adapt it to the technical source of truth in:
- `docs/approved-spec.md`
- `docs/backend-contract.md`
- `docs/mobile-architecture.md`
- Do not let the content documents silently introduce unsupported runtime features such as persistence, unlock logic, adaptive difficulty, or new exercise widgets unless those are explicitly added to the technical specs first.
- Grammar rules, examples, and canonical explanations should be based on open educational/textbook sources and then curated into the app's JSON-compatible lesson schema.
- AI may assist offline authoring, but shipped lesson content must remain curated, source-backed, and schema-valid.
- For any new lesson authoring or exercise creation task, always invoke the local `english-grammar-methodologist` skill first.
- This applies to grammar rules, intro examples, exercises, distractors, accepted answers, accepted corrections, and rule-specific explanations.
- Invoke `english-grammar-methodologist` only when the task actually requires English-language content authoring or content review.
- Do not load or invoke it for app engineering, UI implementation, deployment, infra, or documentation tasks unless those tasks explicitly require creating or checking English-learning content.
- If `english-grammar-methodologist` is unavailable in the current session, treat that as a blocker for new content authoring unless the user explicitly overrides it.

## Learning Engine Source Of Truth

- `LEARNING_ENGINE.md` is the canonical source of truth for the **target-state** Mastery learning engine: skill graph, error model, evidence model, mastery model, decision engine, transparency layer, content strategy.
- It defines **where the product is going**, not what the runtime ships today. Anything currently in production is documented in the contract layer (`docs/approved-spec.md`, `docs/backend-contract.md`, `docs/mobile-architecture.md`, `docs/content-contract.md`).
- When the engine spec is in tension with those runtime contracts, the runtime contracts win for what the code can do **today**, and `LEARNING_ENGINE.md` wins for where the product is **going**.
- The migration plan from current shipped runtime to the target engine is `docs/plans/learning-engine-mvp-2.md`. Read that before starting any wave that adds engine metadata, mastery state, decision-engine routing, or new exercise families.
- `LEARNING_ENGINE.md` is paired with — not a replacement for — `GRAM_STRATEGY.md` (pedagogy) and `exercise_structure.md` (authoring rules). Pedagogy decides what to teach; engine decides how the system uses that pedagogy to make per-learner decisions.

## Documentation Maintenance — Mastery doc layout

The general rule "every shipped change updates every doc it touches in the same
commit" is in `~/.claude/COMPANY.md`. Mastery has a specific doc taxonomy on top:

| Layer | Where | What goes there |
|---|---|---|
| **Canon** | repo root (`/`) | Slow-changing source-of-truth: `CLAUDE.md`, `DESIGN.md`, `GRAM_STRATEGY.md`, `exercise_structure.md`, `LEARNING_ENGINE.md`. Almost always read into context. |
| **Contracts** | `docs/*.md` (flat) | Source of truth for current shipped behaviour. Updated in lockstep with each shipped feature. `approved-spec.md`, `backend-contract.md`, `mobile-architecture.md`, `content-contract.md`, `qa-golden-cases.md`. |
| **Plans** | `docs/plans/` | Approved next-wave specs and roadmaps. Promoted out (deleted or archived) once shipped. |
| **Authoring** | `docs/content/` | Per-unit lesson blueprints and authoring artifacts. |
| **References** | `docs/design-mockups/` | Visual composition reference for shipped layouts. |
| **History** | `docs/archive/` | Superseded specs, one-shot reviews, planning artifacts kept for the audit trail only. **Never** used to decide current behaviour. See `docs/archive/README.md` before consulting any file there. |

If the new doc doesn't fit any of these, you probably don't need a new doc — extend an existing one. The full live map is `docs/README.md`; update it whenever a doc is added, renamed, or archived.

### Files almost always relevant (start here, then sweep)

- `docs/approved-spec.md` — system boundaries, AI usage, exercise types, navigation, non-goals.
- `docs/backend-contract.md` — API surface, request/response shape, errors, headers, evaluator routing.
- `docs/mobile-architecture.md` — client model, screen list, state, navigation, data classes (**field lists must be exact**).
- `docs/content-contract.md` — lesson schema, authoring rules, normalization, accepted-answers policy.
- `CLAUDE.md` — this file (project entry pointers).
- `README.md` — top-level doc map and quick orientation.
- `DESIGN.md` and `docs/design-mockups/` — when shipped visuals change.
- `LEARNING_ENGINE.md` — when target-state engine behaviour changes (skill graph, error model, evidence/mastery model, decision engine, transparency layer); update `docs/plans/learning-engine-mvp-2.md` in lockstep.

### Past incident (drift sweep skipped)

AI debrief feature shipped 2026-04-25 updated `backend-contract.md`, `approved-spec.md`, and `mobile-architecture.md`, but missed the `evaluationSource` field reference in `mobile-architecture.md` after the field was deleted from the Flutter model in a follow-up cleanup. Fixed 2026-04-26. Caused by working from a memorised list instead of `grep`.

## Skill routing — Mastery additions

Baseline routes (e.g. `/review`, `/ship`, `/investigate`, `/plan-eng-review`) are
in `~/.claude/COMPANY.md`. Mastery adds:

- **Lesson authoring**, exercise creation, distractor writing, answer-key
  creation, explanation writing, curriculum expansion → invoke
  `english-grammar-methodologist` first, then validate against the canonical
  content docs (`GRAM_STRATEGY.md`, `exercise_structure.md`, `LEARNING_ENGINE.md`).

## Deploy Configuration

Concrete deployment endpoints, service names, and operational dashboard links are intentionally kept out of the repository.

Public deploy contract:

- Platform: Render-compatible web deployment
- Backend health check path: `/health`
- Frontend build expects `API_BASE_URL` as a build-time variable
- Backend production env requires `AUTH_SECRET` and any persistence / AI env vars relevant to the selected runtime mode

Operational runbooks belong in private deployment notes, not in committed docs.
