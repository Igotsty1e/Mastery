# Implementation Scope — Next Learning System Expansion

## Purpose

This document captures the major workstreams required to move Mastery from the current
controlled-practice MVP toward the stronger teaching system defined in:
- `GRAM_STRATEGY.md`
- `exercise_structure.md`
- `LEARNING_ENGINE.md`

It is a planning document, not an approved MVP spec replacement.

This roadmap addresses **product-surface** workstreams (content hardening,
audio, imagery, frontend screens, backend/API). The **engine-side**
migration that introduces skill metadata, mastery state, decision-engine
routing, the in-session 1/2/3 loop, the cross-session 1d / 3d / 7d / 21d
review cadence, and the new exercise families (`multi_blank`,
`multi_select`, `multi_error_correction`, `sentence_rewrite`,
`short_free_sentence`) is sequenced separately in
`docs/plans/learning-engine-mvp-2.md`. The two plans are parallel tracks
and must update each other in lockstep when their scopes overlap.

---

## 1. Scope Summary

Major expansion areas:
1. content system hardening
2. audio output (listening only)
3. new exercise families
4. evaluation and scoring upgrades
5. authoring and QA tooling
6. frontend screen expansion
7. backend/API expansion
8. visual context layer (imagery)

Speaking / microphone input is **not** in scope. See `GRAM_STRATEGY.md §15.1`
and `exercise_structure.md §5.10`.

---

## 2. Workstream A — Content System Hardening

### Goal

Make the new pedagogy executable across all future lessons, not just documented.

### Tasks

- align unit blueprints, lesson fixtures, and QA docs with the new methodology and exercise framework
- update unit blueprints to reference lesson intent, target contrast, and recommended exercise sequencing
- define lesson archetypes:
  - rule introduction
  - contrast lesson
  - consolidation lesson
  - mixed review
- add content author checklists for:
  - meaning/use/form/contrast coverage
  - acceptable answer coverage
  - distractor quality
  - explanation quality
- review shipped fixtures against the new framework and mark gaps

### Deliverables

- updated content system docs
- updated blueprints
- revised lesson QA checklist

---

## 3. Workstream B — Audio Output

### Status

**Engineering shipped.** All tasks below landed before V1 MVP. The
schema (`backend/src/data/lessonSchema.ts §ExerciseAudio`), the offline
TTS pipeline (`backend/scripts/gen-audio.ts` + `npm run gen:audio`,
hash-based skip + sidecar `.meta.json`), the Express static mount
(`backend/public/audio/` with the immutable cache headers), the Flutter
`MasteryAudioPlayer` widget (`app/lib/widgets/mastery_audio_player.dart`,
277 LOC, transcript-on-demand toggle, soft-error fallback), and the
`ListeningDiscriminationWidget` are live. Wave 14.8 (2026-04-28) added
14 widget tests covering the player's transcript toggle / disabled
state and the listening exercise's option ordering / selection /
after-submit lock. Schema validates `audio.transcript` matches the
correct option text.

**What remains is content, not engineering.** The bank ships exactly
one `listening_discrimination` item today (`b2-lesson-002.json`). The
authoring sprint to widen listening coverage across the five shipped
B2 skills is methodologist-owned and has not started — it is not
blocked by any engineering work. When that sprint runs:
`OPENAI_API_KEY=… npm run gen:audio` regenerates only the items whose
`voice + transcript` hash changed.

### Goal

Add deliberate listening support — only on items explicitly designed for it —
without turning the app into a generic TTS wrapper.

### Scope decisions (locked)

- Audio appears **only** on `listening_discrimination` items. Not on intro
  examples, not on regular exercise prompts, not on result-panel canonical
  answers.
- Two voices, both US English: `nova` (warm female, default) and `onyx`
  (low calm male). One accent. No UK / multi-accent rotation.
- Generation: pre-generated TTS, stored as static `.mp3` files, served by
  the backend at `/audio/{lesson_id}/{exercise_id}.mp3`. No runtime TTS.
  Hybrid path open for future: human-recorded audio may replace selected
  high-impact clips with no schema change.
- Transcripts are required on every clip but hidden in the UI behind a
  `Show transcript` toggle (per `DESIGN.md §14`). They are visible to
  accessibility tooling and QA tooling at all times.
- No autoplay. Replays unlimited and do not affect scoring.

Authoritative references:
- pedagogy: `GRAM_STRATEGY.md §15` (listening planned, speaking out)
- exercise authoring: `exercise_structure.md §5.9`
- schema: `docs/content-contract.md §2.4 listening_discrimination`
- UI: `DESIGN.md §14 Audio Player` and `Exercise Screen → Listening exercise variant`

### Tasks

- add `audio` field to lesson content schema and validators
  (`backend/data/schema/*` + Flutter model classes)
- write the offline TTS pipeline:
  - script reads lesson JSON, finds every `listening_discrimination` item
  - calls OpenAI TTS (`tts-1` with voice `nova` or `onyx` per item)
  - hashes the `transcript` text + voice; skips regeneration when hash
    matches the existing file's metadata
  - writes `backend/public/audio/{lesson_id}/{exercise_id}.mp3`
  - writes a sidecar `.json` with hash + voice + duration for diff review
- expose `backend/public/audio/` as Express static with long cache headers
  (`Cache-Control: public, max-age=31536000, immutable`); files are
  content-addressed so re-authoring busts the URL only when intended
- add the `MasteryAudioPlayer` widget (Flutter) per `DESIGN.md §14`
- wire `listening_discrimination` exercise into the existing screen-level
  CTA flow: same `Check answer` / `Next` button, same result panel
- add a "loading / unavailable" state for cases where the audio file fails
  to fetch (treat as soft error, learner can still see transcript)
- add `npm run gen:audio` script in `backend/` package.json
- document in `README.md` under Stack: how to run gen:audio locally and
  how authors verify generated clips before commit

### Cost note

OpenAI TTS `tts-1` is roughly $15 per 1M input characters. A 12-lesson B2
sequence with 1-2 listening items per lesson averaging 60 chars per
transcript costs cents, not dollars. Budget is not the blocker.

### Voice usage rules

- Default voice for any listening item is `nova`.
- `onyx` is only chosen when content fits a masculine first-person speaker
  or when an item explicitly contrasts two speakers in a future two-clip
  layout (out of current widget scope).
- Voice does not vary mid-clip. One clip = one voice.
- Voice consistency across items in a single lesson is preferred; mixing
  `nova` and `onyx` items in the same 10-item arc is allowed only if it
  serves a teaching contrast.

---

## 4. Workstream C — Audio Input — Out Of Scope

Spoken production and microphone capture are **not planned** for Mastery.
The learner is never asked to speak.

Authoritative scope statement: `GRAM_STRATEGY.md §15.1`.
Operational rule: `exercise_structure.md §5.10`.

This workstream is left in the document only as a forwarding pointer so
future planners do not silently re-introduce speaking. To revive it, both
canonical pedagogy documents above must be revised first.

---

## 5. Workstream D — New Exercise Families

### Goal

Expand beyond the current four runtime types to better express the teaching model.

`listening_discrimination` is already shipped. The candidates below are future additions only.

### Candidate additions

The engine target-state names nine families (`LEARNING_ENGINE.md §8.4`).
Five of them are planned new families with engine-side safeguards
declared in `LEARNING_ENGINE.md §8.4.1` and authoring contracts in
`exercise_structure.md §§5.1, 5.5, 5.6, 5.7, 5.8`. They are sequenced —
lowest scoring risk first — in `docs/plans/learning-engine-mvp-2.md
Wave 6`:

1. `multi_blank` — multi-blank controlled completion
   (`exercise_structure.md §5.7`); safeguard: no interdependent blanks.
2. `sentence_rewrite` — transformation
   (`exercise_structure.md §5.1`); safeguard: bounded answer-space,
   `accepted_rewrites` cap of 3.
3. `multi_error_correction` — multi-error guided correction
   (`exercise_structure.md §5.8`); safeguard: same primary skill /
   target error rollup, no-error decoy rule.
4. `multi_select` — plural recognition with anti-gaming guard
   (`exercise_structure.md §5.6`).
5. `short_free_sentence` — constrained short production, written only
   (`exercise_structure.md §5.5`); safeguard: deterministic-first
   scoring with bounded AI fallback (`LEARNING_ENGINE.md §12.4`).

Other pedagogical families called out in `exercise_structure.md §3.1`
that are **not** yet sequenced into a wave:

- ordering / sentence building
- matching / sorting
- dialogue completion

These remain on the roadmap as longer-horizon additions; they need their
widget, schema, and scoring contracts scoped before they enter a wave in
`docs/plans/learning-engine-mvp-2.md`.

Speaking production is excluded. See `GRAM_STRATEGY.md §15.1`.

### Tasks

- define widget behavior for each new type
- define scoring contract
- define acceptable answer policy
- define explanation policy
- define QA golden cases
- map each type to lesson stages and lesson archetypes
- enforce each family's `LEARNING_ENGINE.md §8.4.1` safeguard at the
  runtime, not just in docs

---

## 6. Workstream E — Evaluation And Scoring

### Goal

Make scoring fair enough for richer tasks without losing trust.

### Tasks

- revisit `sentence_correction` policy and decide whether it remains:
  - narrow teacher-approved rewrites only
  - or broader meaning-preserving acceptance
- expand accepted correction coverage for current lessons
- define scoring policy per future type:
  - exact match
  - set membership
  - structured parser
  - AI review with guardrails
- separate evaluation sources in reporting:
  - deterministic
  - AI-assisted
- add more eval datasets built from realistic learner answers

### Risk

Exercise expansion without scoring reform will create false negatives and erode trust.

---

## 7. Workstream F — Authoring And QA Tooling

### Goal

Make lesson creation scalable without dropping below the new quality bar.

### Tasks

- create author templates for each exercise family
- create fixture linting rules:
  - missing contrast
  - duplicate distractor logic
  - overly wide answer space
  - explanation too generic
- create content review worksheet per lesson
- create a lesson sequencing validator
- create regression QA packs for:
  - current runtime only
  - future audio (listening) items

---

## 8. Workstream G — Frontend Screens And UX

### Goal

Support richer pedagogy in UI without losing the calm, linear experience.

### Current screen set

- home
- lesson intro
- exercise
- summary

### Likely screen / component expansions

- richer `HomeScreen` / dashboard as a true study desk:
  - compact level dropdown
  - stronger next-lesson hero
  - persistent last-lesson report
  - badge-based current-unit rows
- audio player control inside exercise card (only on
  `listening_discrimination` items — see Workstream B scope decisions)
- listening exercise variant of the existing exercise screen
- review screen filters:
  - mistakes
  - pattern recap
  - replay audio (for listening items only)

### Tasks

- define next dashboard states and data needs:
  - first launch after onboarding
  - returning in-progress
  - post-lesson return with persistent report
- define how the summary's debrief compresses into a home-screen report module
- define status badge system for `done / current / locked`
- design variants for new exercise families
- define responsive behavior with keyboard + audio controls
- maintain one-primary-action discipline
- define accessibility behavior for captions and transcripts

---

## 9. Workstream H — Backend And API

### Goal

Support richer content and scoring while keeping backend authority.

### Tasks

- extend lesson schema safely for audio metadata
- add endpoint support for richer exercise payloads if new widgets are approved
- version lesson fixtures if schema changes become non-backward-compatible
- add server-side validators for new exercise types
- add richer result payloads if needed:
  - transcript (for listening items)
  - structured error codes
- **Persistent Last Lesson Report** — backend portion shipped 2026-04-26 in Wave 2: the `/dashboard` endpoint returns `last_lesson_report` from the most recent completed `lesson_session` (with the persisted debrief snapshot). The Flutter client is **not yet rewired** against `/dashboard`; until the client cutover, the in-memory `LastLessonStore` singleton (`app/lib/session/last_lesson_store.dart`) is still authoritative on-device and the block disappears after app restart.

---

## 10. Suggested Delivery Order

### Phase 1

- lock pedagogy docs
- align existing content docs
- expand lesson QA standards
- improve current `sentence_correction` acceptance coverage

### Phase 2

- audio output for intro examples and canonical answers
- no scoring changes yet
- no audio input yet

### Phase 3

- first new exercise family:
  - transformation or ordering
- schema updates
- scoring contract updates
- frontend widget implementation

### Phase 4

- audio-first UI polish for `listening_discrimination` (engineering
  shipped — pipeline + widget + tests live; the open work is
  methodologist-owned content expansion across the five shipped B2
  skills)
- imagery roll-out for items where the author has signed off on a
  scene-setting / context-support brief (engineering shipped — same
  state as audio; bottleneck is methodologist authoring time, not
  engineering)

(There is no Phase 5. Speaking capture is excluded — see
`GRAM_STRATEGY.md §15.1`.)

---

## 11.5 Workstream I — Visual Context Layer (Imagery)

### Status

**Engineering shipped.** All tasks below landed before V1 MVP. The
schema (`ExerciseImageSchema` in `backend/src/data/lessonSchema.ts`,
mirrored on every exercise variant), the projection layer that strips
the authoring-only `brief` / `dont_show` / `risk` fields before the
wire response, the kie.ai Flux Kontext generator
(`backend/scripts/gen-image.ts` + `npm run gen:image`, hash-based skip
on `role + brief + dont_show`, sidecar `.meta.json`, retry-tolerant),
the Express static mount (`backend/public/images/` with immutable
cache headers), the Flutter `ExerciseImage` model
(`role` × `policy` enums) and the `MasteryExerciseImage` widget
(`app/lib/widgets/mastery_exercise_image.dart`, with
`cached_network_image` for canvaskit-friendly cross-origin PNGs and a
quiet alt-text fallback) are live. Wave 14.8 (2026-04-28) added 5
widget tests covering URL resolution, aspect-ratio defaults +
overrides, and every role × policy combination.

**What remains is content, not engineering.** Items in the bank
opting into imagery (`image_policy != optional` with a non-empty
`brief`) are sparse today. The authoring sprint to add scene-setting
or context-support imagery to selected B2 items is methodologist-owned
and has not started — it is not blocked by any engineering work.

### Goal

Add deliberate scene-setting / context-supporting imagery — only on items
whose author explicitly opts in via `image_policy != none` — without turning
the app into a generic image-bank product.

### Scope decisions (locked)

- Imagery is allowed on every exercise type (`fill_blank`,
  `multiple_choice`, `sentence_correction`, `listening_discrimination`).
- Default policy is `none`; the burden of proof is on adding an image.
- An image must never reveal the correct answer (per
  `exercise_structure.md §2.9`).
- For `listening_discrimination` items the bar is even higher — see
  `exercise_structure.md §6.6.1` for the image+audio edge case rule.
- Generation provider: **kie.ai Flux Kontext** (`flux-kontext-pro`).
  Flux is open-weights with a permissive `safetyTolerance`, which avoids
  the false-positive content-moderation flags that gpt4o-image was
  triggering on calm editorial scenes.
- Aspect ratio: **4:3** for every clip — single ratio simplifies layout
  and matches the chosen Flux Kontext aspect.
- Output format: **png**.
- Storage: `backend/public/images/{lesson_id}/{exercise_id}.png`, served
  by Express with `Cache-Control: public, max-age=31536000, immutable`.
- Style consistency: short brand-anchored prefix (DESIGN.md art palette),
  no negation chains in the upstream prompt — `dont_show` lives in the
  lesson JSON for human QA only.
- Pipeline failure mode: the fixture is allowed to ship without an image
  if generation fails repeatedly; the runtime renders a quiet caption
  fallback (DESIGN.md §15) so the exercise still works.

Authoritative references:
- pedagogy: `GRAM_STRATEGY.md §4.9` (visual context serves meaning)
- authoring: `exercise_structure.md §2.9` (per-item image fields,
  acceptance rules) and `§6.6.1` (image+audio edge case)
- schema: `docs/content-contract.md §2.5 ExerciseImage`
- UI: `DESIGN.md §15 Exercise Image`

### Tasks

- add `ExerciseImageSchema` to `backend/src/data/lessonSchema.ts` and
  TypeScript mirror in `backend/src/data/lessons.ts`
- strip authoring-only fields (`brief`, `dont_show`, `risk`) before the
  lesson endpoint responds
- expose `backend/public/images/` as Express static with the standard
  immutable-asset cache headers
- write `backend/scripts/gen-image.ts` (kie.ai Flux Kontext, hash-based
  skip on `role + brief + dont_show`, sidecar metadata, retry-tolerant)
- add `npm run gen:image` and an `npm run gen:assets` aggregator that
  runs audio + image together
- add `MasteryExerciseImage` Flutter widget per `DESIGN.md §15`,
  rendered above the type-specific exercise body inside `MasteryCard`
- extend the Flutter `Exercise` model with the optional `image` field
  and the role / policy enums

### Cost note

`flux-kontext-pro` on kie.ai sits in the same low-single-cents-per-clip
range as the audio TTS. A full B2 unit (`~5 lessons × ~3 imaged items`)
runs at well under one US dollar, so cost is not the bottleneck —
authorial discipline is.

---

## 11.6 Workstream J — Multilingual UI + Content Localization

### Goal

Let the learner pick the **L1** the app speaks to them in — UI chrome,
exercise instructions, rule explanations, feedback copy — without
translating the **target English** they are practising. The app teaches
English; the scaffolding around it can be in the learner's first
language.

### Scope decisions (locked)

- **Supported L1s:** English (`en`, default), Russian (`ru`),
  Vietnamese (`vi`). Three languages, no auto-detection of more.
- **What is localized:**
  - app chrome — buttons, screen titles, dashboard labels, status
    badges, error messages, navigation, onboarding copy, feedback
    prompt sheets, diagnostic completion copy
  - per-exercise `instruction` field (e.g. *"Choose the correct
    option"*, *"Rewrite the sentence using the past perfect."*)
  - rule materials served by `GET /skills` — `intro_rule`,
    per-example explanation strings, skill `description`
  - per-attempt curated `feedback.explanation` (the 3-part block
    after a wrong answer)
  - AI debrief prompt + AI feedback for `short_free_sentence`
    evaluator (the model is told to respond in the learner's L1)
- **What stays English (always):**
  - the **target sentence** of every exercise (the prompt body, the
    blank context, the `original` field of `sentence_correction` /
    `sentence_rewrite`)
  - the **answer options** / distractors of `multiple_choice` /
    `multi_select`
  - the **canonical answers** / `accepted_answers` / `accepted_rewrites`
  - audio transcripts for `listening_discrimination`
  - skill identifiers (`skill_id` is a code string; not translated)
- **Authoring contract:** lesson JSON gains `i18n` blocks alongside
  the localizable string fields. Authoring rule: an exercise is
  schema-valid only if **all three** L1 strings are present —
  partial localization is rejected at boot. (Avoids silent fallback
  to English making the feature feel half-baked for a Vietnamese
  learner.)
- **Storage:** per-user preference on `user_profiles` (new column
  `ui_language`). On first sign-in we seed it from
  `Accept-Language` if it matches one of the supported L1s, else
  `en`. Learner can change it in an Account/Settings screen.
- **Wire:** the lesson / session / skills endpoints honour either
  the `ui_language` from the authenticated profile or an
  `Accept-Language` header for unauthenticated screens; the
  response carries only the chosen L1's strings (no client-side
  language switch table — keeps payload small and avoids leaking
  in-progress translations).
- **Out of scope for Workstream J:** translating learner-typed
  free-text answers; right-to-left layouts; per-exercise mixed-L1
  display; multi-L1 audio (only English clips ship).

Authoritative references:
- pedagogy: `GRAM_STRATEGY.md` (target language is English; L1
  scaffolding is allowed)
- authoring: `exercise_structure.md` — gains an `§i18n` section
  when this workstream enters a wave
- schema: `docs/content-contract.md` — gains the `i18n` field
  shapes and the all-three-or-reject validation rule
- UI: `DESIGN.md` — adds typography fallback for Vietnamese
  diacritics and Cyrillic; verifies the calm-pace tokens still
  read on longer Russian strings

### Tasks

- extend `LessonSchema` (`backend/src/data/lessonSchema.ts`) with
  `i18n` blocks on `instruction`, the per-skill rule fields, and
  the per-attempt explanation fields; reject partial localization
  at boot
- extend `backend/data/skills.json` with `i18n` blocks on
  `title` / `description` / `intro_rule` / per-example
  explanation strings
- add `ui_language` column to `user_profiles` (migration); seed
  from `Accept-Language` on first login
- new endpoint shape: lesson / session / skills responses honour
  `ui_language` from the profile (auth) or `Accept-Language`
  (unauth pre-login screens); responses carry only the chosen
  L1's strings
- AI surfaces (debrief prompt builder, `short_free_sentence`
  evaluator prompt) take `ui_language` as input and instruct the
  model to respond in that language; deterministic-first scoring
  is unchanged
- Flutter: install `flutter_localizations` + `intl`; add
  `MasteryStrings` ARB pipeline; route every UI string through it
- Flutter: new `LanguagePicker` widget on a slim Account/Settings
  screen reachable from the dashboard (calm, one-screen, three
  options, immediate apply)
- typography pass on Vietnamese (Inter / Noto stack — verify
  diacritic stacking) and Russian (longer strings — verify the
  Study Desk dashboard hierarchy still holds)
- authoring sprint via `english-grammar-methodologist` to author
  ru + vi for every shipped string; **all three** L1s ship in the
  same wave or the wave does not ship (no half-launch)

### Cost note

The per-string localization is mostly authoring time, not API
spend. AI debrief / `short_free_sentence` prompts in ru / vi are
pennies per session at current pricing. The bottleneck is the
methodologist + native-speaker review pass on the rule
materials and feedback explanations.

### Sequencing

This is a multi-wave workstream. Suggested split when it enters
the active backlog:

1. **J.1** — schema additions + `ui_language` column + endpoint
   plumbing + Flutter `MasteryStrings` scaffold. No UI surface;
   defaults to `en` for everyone. Pure foundation.
2. **J.2** — authoring sprint for Russian; ship the
   `LanguagePicker` with **two** options (en, ru); Vietnamese row
   greyed out as "coming soon." Validates the pipeline on the L1
   the founder + tester team speaks.
3. **J.3** — Vietnamese authoring sprint + open the third option
   in the picker.

Each sub-wave updates `docs/content-contract.md`,
`docs/backend-contract.md`, `docs/mobile-architecture.md` in
lockstep per the Documentation Maintenance Rule.

### Risk

- silent partial translation — mitigated by the all-three-or-reject
  schema rule
- typography regressions on longer Russian / accented Vietnamese
  strings — mitigated by the J.2 / J.3 design pass before each
  authoring sprint lands
- AI surfaces drifting in tone across L1s — mitigated by curated
  prompt templates per language, not free-form translation

---

## 11. What Requires Spec Revision

These are outside the current 4-type shipped set and must not be implemented silently:
- more than 4 exercise types (shipped: `fill_blank`, `multiple_choice`, `sentence_correction`, `listening_discrimination`)
- new scoring models beyond current contracts
- broader AI role in learner-facing evaluation
- new screen states that alter lesson flow materially

Speaking tasks are not on the spec-revision list at all because they are
permanently out of scope — see `GRAM_STRATEGY.md §15.1`.

---

## 12. Immediate Next Steps

1. Treat `GRAM_STRATEGY.md` as top pedagogical authority.
2. Treat `exercise_structure.md` as the exercise-generation authority.
3. Update current content docs and references to match that hierarchy.
4. Review shipped lessons against the new framework before authoring additional units.
