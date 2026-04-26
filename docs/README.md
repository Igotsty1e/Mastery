# Mastery — Documentation Map

Primary index for the Mastery documentation system. Project root carries a short orientation in `/README.md` that points back here.

The doc system follows one rule:

| Layer | Where | What lives there |
|---|---|---|
| **Canon** | repo root | Slow-changing source-of-truth. Read into context almost every session: `CLAUDE.md`, `DESIGN.md`, `GRAM_STRATEGY.md`, `exercise_structure.md`. |
| **Contracts** | `docs/*.md` (flat) | Source of truth for current shipped behaviour. Updated in lockstep with each shipped feature. |
| **Plans** | `docs/plans/` | Approved next-wave specs and roadmaps. Promoted out (deleted or archived) once shipped. |
| **Authoring** | `docs/content/` | Per-unit lesson blueprints and authoring artifacts. |
| **References** | `docs/design-mockups/` | Visual composition reference for shipped layouts. |
| **History** | `docs/archive/` | Superseded specs, one-shot reviews, planning artifacts kept for the audit trail only. Never used to decide current behaviour. |

When adding a new doc, ask: *which of those buckets is this?* If it doesn't fit, you probably don't need a new doc — extend an existing one.

---

## Active doc map

### Contracts (`docs/`)

| Document | Purpose |
|---|---|
| [`approved-spec.md`](approved-spec.md) | Canonical product spec — system boundaries, exercise types, lesson flow, evaluation policy, non-goals |
| [`backend-contract.md`](backend-contract.md) | API endpoints, evaluation logic, AI integration, debrief generation, CORS, error codes |
| [`mobile-architecture.md`](mobile-architecture.md) | Flutter app structure, screens, state, data classes |
| [`content-contract.md`](content-contract.md) | Lesson + exercise JSON schemas, normalization rules, accepted-answers policy |
| [`qa-golden-cases.md`](qa-golden-cases.md) | Acceptance test cases across all exercise types |

### Plans (`docs/plans/`)

| Document | Purpose |
|---|---|
| [`plans/roadmap.md`](plans/roadmap.md) | Next-step roadmap for audio, exercise expansion, screens, and tooling |
| [`plans/arrival-ritual.md`](plans/arrival-ritual.md) | Onboarding direction: 3-step shipped 2026-04-26 then replaced same day by 2-step + dashboard-as-home (locked, implementation pending design-shotgun output). First-exercise V2 + motion polish + QA still pending. |

### Content authoring (`docs/content/`)

| Document | Purpose |
|---|---|
| [`content/unit-u01-blueprint.md`](content/unit-u01-blueprint.md) | Active unit-level authoring plan for the next shippable grammar unit. New per-unit blueprints land here. |

### Visual references (`docs/design-mockups/`)

Eight 390×844 mobile mockups showing canonical screen composition for shipped layouts. Open via `cd docs/design-mockups && python3 -m http.server 8765`. Built directly against the `DESIGN.md` token system with real lesson content.

In-flight visual exploration:
- [`design-mockups/onboarding-2step/`](design-mockups/onboarding-2step/index.html) — three direction takes (Editorial Notebook / Atelier / Clinical Calm) on the locked 2-step onboarding + dashboard-as-home + quieter first exercise. Awaiting a pick before implementation.

### Project root (canon)

| Document | Purpose |
|---|---|
| [`/CLAUDE.md`](../CLAUDE.md) | Agent operating rules, deploy config, doc-maintenance rule |
| [`/README.md`](../README.md) | Project orientation + pointer here |
| [`/DESIGN.md`](../DESIGN.md) | Visual canon: colors, typography, spacing, components, motion |
| [`/GRAM_STRATEGY.md`](../GRAM_STRATEGY.md) | Top-level pedagogy: how Mastery teaches grammar and usage |
| [`/exercise_structure.md`](../exercise_structure.md) | Canonical exercise authoring rules, sequencing, runtime mapping |

### Archive (`docs/archive/`)

Historical artifacts only. See [`archive/README.md`](archive/README.md) for the inventory and reasons.

---

## How to use this map

- **Reading a feature spec** → check `docs/plans/` first.
- **Implementing or reviewing a shipped feature** → consult contracts in `docs/*.md`, cross-check against canon in repo root.
- **Authoring a new lesson** → start with `GRAM_STRATEGY.md` + `exercise_structure.md`, then `docs/content/`.
- **Looking for past decisions** → `docs/archive/`.
- **Adding a doc** → pick the right bucket above. If you can't, ask whether you actually need a new doc.
