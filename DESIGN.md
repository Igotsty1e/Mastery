# Design System — Mastery

## Visual Reference

- Hand-built HTML mockups for all eight core screens live in `docs/design-mockups/`. Open `docs/design-mockups/index.html` (or run `cd docs/design-mockups && python3 -m http.server 8765` and visit `http://127.0.0.1:8765/`) for the comparison gallery.
- Coverage: home onboarding, home dashboard, lesson intro, exercise (multiple choice — active and result revealed), exercise (fill-the-blank with keyboard up), exercise (sentence correction with keyboard up), summary.
- Mockups use the lesson content from `backend/data/lessons/b2-lesson-001.json` and the tokens from this document. They are the canonical composition reference.
- Relationship: this document = tokens (the specification). `docs/design-mockups/` = composition (the reference). When the two disagree, this document wins. Update both when visual decisions change.

## Product Context
- **What this is:** `Mastery` is a structured English grammar practice app with a fixed lesson flow. Each lesson teaches one rule, gives a short explanation, then moves the learner through focused exercises with immediate evaluation and a clean summary.
- **Who it's for:** adult and late-teen learners who want serious, calm, high-trust English practice without cartoonish gamification, clutter, or chat-based noise.
- **Space/industry:** mobile-first EdTech, specifically English learning and grammar training.
- **Project type:** Flutter mobile app with four core screens: onboarding/home, lesson intro, exercise, summary.
- **Product constraints that shape the design:** no streaks, no badges, no points, no social feed, no chat UI, no adaptive branching, no tiny text, no visual noise. The product must feel premium, warm, and disciplined.

## Document Map
- `DESIGN.md` owns visual language, interaction tone, layout, motion, and component behavior.
- `docs/design-mockups/` owns screen-level composition reference.
- `docs/plans/arrival-ritual.md` owns the selected V2 onboarding and first-exercise contract derived from the approved design exploration.
- `GRAM_STRATEGY.md` owns the top-level pedagogy for how Mastery teaches language.
- `exercise_structure.md` owns the exercise system and authoring rules derived from that pedagogy.
- `exercise_structure.md §2.9 Visual Context Layer` decides whether a given exercise should remain text-only or may use an image.
- `docs/content/unit-u01-blueprint.md` owns the current lesson-authoring plan.
- All instructional content for Mastery must be created or explicitly reviewed using the `english-grammar-methodologist` skill; `DESIGN.md` does not replace that content-authoring workflow.

## Market Reference Audit

Method note: this list uses public Android install bands from Google Play as the comparable market proxy. Google Play exposes install ranges, not exact totals, so ties are grouped.

| App | Public install band | Why it matters | Borrow | Avoid |
|---|---:|---|---|---|
| Duolingo | 500M+ | category leader in clarity and retention | instant feedback, large-status moments, clear one-next-step UX | childish over-gamification, streak theatrics, cluttered reward loops |
| Cake | 100M+ | strong mobile-native content packaging | snackable cards, media-led learning surfaces, approachable onboarding | content sprawl, thumbnail overload |
| Babbel | 50M+ | adult premium benchmark | calm hierarchy, practical grammar framing, editorial trust | overly corporate flatness |
| Busuu | 50M+ | strongest balance of structure + warmth | disciplined lesson structure, progress visibility, real-life tone | too many adjacent options on home |
| ABA English | 10M+ | English-specific, academy-like trust | serious learning cues, level framing, teacher-like guidance | landing-page heaviness inside product |
| ELSA Speak | 10M+ | modern AI-coach language learning | confidence-first copy, conversational cards, polished assessments | too much “AI glow” or futuristic blue tech styling |
| EWA | 10M+ | entertainment-driven engagement | rich media modules, soft premium surfaces, motivating variety | excessive shelf UI or streaming-app mimicry |
| Falou | 10M+ | real-life scenario teaching | scenario-first practice framing, strong CTA discipline | too many premium upsell interruptions |
| Memrise | 10M+ | adult, human-centered speaking practice | real-people feel, authentic examples, breathable layouts | generic video-grid layouts |
| Mondly | 10M+ | polished gamified microlearning | compact lesson packaging, clear category scannability, energetic transitions | gradients and gamification taking over the product |

## Competitive Takeaways

### Patterns worth keeping
- A single dominant CTA per screen.
- Large progress signals that are readable in under one second.
- One primary learning object on screen at a time.
- Rounded cards, layered surfaces, and clearly separated states.
- Human, confidence-building copy instead of academic jargon.
- Immediate feedback with strong color and icon shifts.
- Motion that teaches hierarchy: enter, focus, confirm, continue.

### Patterns we should reject
- Any streak, leaderboard, badge, heart, coin, or “daily mission” mechanic.
- Tiny metadata labels and dense dashboards.
- Loud mascot-led branding.
- Neon gradients, hyper-saturated greens, or generic AI purple.
- Carousel-heavy home screens.
- More than one competing primary action in the exercise flow.

## Aesthetic Direction
- **Direction:** Quiet Premium Coach
- **Decoration level:** intentional
- **Mood:** `Mastery` should feel like a high-end private tutor who is warm, composed, and exacting. The emotional mix is soft confidence, adult calm, and academic polish rather than playful chaos.
- **Reference blend:** take the clarity of Duolingo and Busuu, the adult seriousness of Babbel and ABA, and the premium softness of ELSA/EWA, then remove gamification and visual sugar.
- **Visual thesis:** “A rose-tinted grammar studio.” Warm ivory surfaces, dusty-rose anchors, deep espresso text, subtle paper-like depth, and elegant typography that makes rule-based learning feel desirable.

## Brand Principles
- **Warm authority:** the UI should feel helpful and expert, never childish.
- **One thing at a time:** each screen has one obvious focus and one obvious next action.
- **Confidence over excitement:** use calm reward, not dopamine gimmicks.
- **Readable luxury:** large typography, careful spacing, tactile cards, restrained color.
- **Learning is the hero:** visuals support the lesson, they never compete with it.

## Typography
- **Display/Hero:** `Fraunces` — used for hero moments, lesson titles, and score moments. Adds editorial sophistication without feeling old-fashioned.
- **Body:** `Manrope` — highly readable, modern, and excellent on mobile for explanatory text and long labels.
- **UI/Labels:** `Manrope` SemiBold / Bold — all chips, buttons, field labels, tabs, and inline metadata.
- **Data/Tables:** `IBM Plex Mono` — optional, only for score fractions, progress percentages, and diagnostic microdata where tabular numerals help.
- **Code:** `IBM Plex Mono`
- **Loading strategy:** self-host all font files in Flutter assets. Do not rely on platform defaults or Google Fonts runtime fetches.

### Type Scale
- `display-xl`: 56/60, `Fraunces`, 600
- `display-lg`: 48/52, `Fraunces`, 600
- `display-md`: 40/46, `Fraunces`, 600
- `headline-lg`: 32/38, `Fraunces`, 550
- `headline-md`: 28/34, `Manrope`, 700
- `title-lg`: 24/30, `Manrope`, 700
- `title-md`: 20/26, `Manrope`, 700
- `title-sm`: 18/24, `Manrope`, 700
- `body-lg`: 18/30, `Manrope`, 500
- `body-md`: 16/26, `Manrope`, 500
- `body-sm`: 15/24, `Manrope`, 500
- `label-lg`: 16/20, `Manrope`, 700
- `label-md`: 14/18, `Manrope`, 700
- `label-sm`: 13/16, `Manrope`, 700

### Non-negotiable type rules
- Default body copy is `16px` minimum.
- Primary button text is `16px` minimum.
- No tappable text below `16px`.
- Use `Fraunces` only for short, high-impact text. Never for dense paragraphs or input-heavy screens.
- Avoid pure bold everywhere; use size and spacing first, weight second.

## Color
- **Approach:** balanced, warm, rose-led
- **Primary:** `#B07A84` — dusty rose; core brand color for primary actions, progress highlights, active chips, and hero accents.
- **Primary strong:** `#8F5C68` — pressed states, active emphasis, stronger text on pale rose surfaces.
- **Primary soft:** `#E7D2D6` — selected backgrounds, onboarding panels, quiet highlights.
- **Secondary:** `#C8A59A` — warm clay-taupe for secondary accents and illustration support.
- **Accent gold:** `#C89A52` — sparingly for progress achievement, score glow, and premium cues.
- **Neutrals:** `#FCF8F6`, `#F6EFEC`, `#E9DDDA`, `#D7C8C4`, `#AD9A97`, `#6A5A5E`, `#2B2326`
- **Semantic:** success `#4E7C68`, warning `#B68242`, error `#B14C64`, info `#5C7595`
- **Dark mode strategy:** use cocoa-charcoal surfaces instead of black; reduce rose saturation by about 12%; keep text warm, never stark blue-white.

### Color Roles
- `bg.app`: `#FCF8F6`
- `bg.surface`: `#FFFDFC`
- `bg.surface-alt`: `#F6EFEC`
- `bg.raised`: `#FFFFFF`
- `bg.primary-soft`: `#F3E6E9`
- `text.primary`: `#2B2326`
- `text.secondary`: `#6A5A5E`
- `text.tertiary`: `#8E7E82`
- `border.soft`: `#E4D7D4`
- `border.strong`: `#D2C0BD`
- `action.primary`: `#B07A84`
- `action.primary-hover`: `#A06B76`
- `action.primary-pressed`: `#8F5C68`

### Color Usage Rules
- Dusty rose is the anchor, not wallpaper. Avoid filling whole screens with solid pink.
- Main reading surfaces should stay ivory or warm off-white.
- Use success/error colors in muted premium tones, not system-bright defaults.
- Gold appears only for “completion” moments or premium separators, never as a second primary color.

## Spacing
- **Base unit:** 8px
- **Density:** comfortable
- **Scale:** `2xs 4`, `xs 8`, `sm 12`, `md 16`, `lg 24`, `xl 32`, `2xl 40`, `3xl 56`, `4xl 72`

### Spacing Rules
- Card padding default: `20-24px`
- Screen horizontal padding: `24px` mobile, `32px` tablet
- Vertical rhythm should alternate `16 / 24 / 32`, not random gaps
- Never stack more than two “small” gaps in a row; combine them into one larger rhythm

## Layout
- **Approach:** hybrid
- **Grid:** 4-column mobile, 8-column tablet, 12-column desktop/web
- **Max content width:** `560px` on mobile-centered learning flow, `720px` on tablet/web lesson views
- **Border radius scale:** `sm 10`, `md 16`, `lg 22`, `xl 28`, `pill 999`
- **Elevation style:** subtle. Prefer border + slight shadow over heavy drop shadows.

### Layout Rules by Screen
- Home/onboarding: vertical story stack with one hero statement, one proof block, one CTA zone.
- Lesson intro: editorial top section, then rule cards, then examples, then CTA.
- Exercise: one dominant exercise card, optional result panel below, sticky progress at top.
- Summary: centered score hero, then mistake cards as a quiet review column.

## Motion
- **Approach:** intentional
- **Easing:** `enter: cubic-bezier(0.22, 1, 0.36, 1)`, `exit: cubic-bezier(0.55, 0, 1, 0.45)`, `move: cubic-bezier(0.4, 0, 0.2, 1)`
- **Duration:** micro `90ms`, short `180ms`, medium `280ms`, long `420ms`

### Motion Principles
- Every transition must reinforce progress, not distract from it.
- Prefer fade + slide or fade + scale. Avoid bounce and overshoot.
- Buttons should feel cushioned and tactile via opacity + scale microfeedback.
- Result reveal should feel decisive: card tint, icon pop, short content fade-in.

### Required Motion Patterns
- Screen-to-screen transitions: fade-through or shared-axis horizontal.
- Onboarding to dashboard: content crossfade plus hero card slide-up.
- Lesson intro sections: staggered reveal of rule cards `40ms` apart.
- Exercise submission: input locks, button morphs to loading, overlay fades in.
- Result panel: slide-up `12px` + fade in.
- Progress bar: animated width, never instant jump.
- Summary score: count-up or gentle numeric fade, no casino-style spin.

## Illustration and Imagery
- **Image direction:** editorial learning imagery, soft line illustrations, photographed hands/notebooks, or muted 3D study objects.
- **Use images where appropriate:** onboarding hero, empty/error states, summary completion, and occasional lesson intro art.
- **Do not use images:** inside the main exercise interaction zone unless they directly support the task.
- **Human representation:** adults or older teens, modern, international, calm, competent.
- **Art palette:** dusty rose, oat, muted clay, parchment, sage accents.
- **Decision authority:** whether an exercise is allowed to use imagery is governed by `exercise_structure.md §2.9 Visual Context Layer`. `DESIGN.md` governs only style, surface treatment, and placement once that gate is passed.

### Image Rules
- No childish mascots.
- No stock-photo smiles on pure white backgrounds.
- No techy holograms, robots, or glowing AI brains.
- When using illustrations, keep line weights soft and rounded, not corporate-outline icon packs.
- If an exercise image risks revealing the answer directly, do not render it at all.

## Component System

### 1. App Shell
- Warm ivory background with a slightly darker rose-cream top layer behind hero sections.
- Top bars should be light, quiet, and almost blend into the page unless used as a progress anchor.

### 2. Primary Button
- Filled dusty-rose background, dark text or ivory text depending on contrast.
- Height `56px`, horizontal padding `20-24px`, radius `18px`.
- Shadow is minimal; rely on color confidence and shape.
- States: default, hover, pressed, loading, disabled.

### 3. Secondary Button
- Tinted ivory or outline on warm surface.
- Border `1px` with `border.strong`.
- Never visually equal to the primary button.

### 4. Level Chips
- Pill shapes with strong internal padding.
- Active state: dusty rose fill.
- Locked/inactive state: warm stone background with subtle icon.
- Minimum chip height `40px`.

### 5. Progress Card
- Large, calm, premium.
- Use a title row, progress sentence, and thick progress track.
- Progress bar height `10-12px`, rounded ends, soft background trough.
- Include one supporting micro-metric only. No analytics overload.

### 6. Rule Card
- Core teaching surface.
- Background `bg.raised`, radius `22px`, padding `24px`.
- Optional eyebrow label like `Rule`, `Pattern`, `Watch for`.
- Headline large enough to scan from arm’s length.
- When a rule contains a contrast pair, the layout must surface the changing slot first and the prose explanation second.
- Shared grammar material stays visually quiet; only the variable slot gets the strong accent.
- Contrasted formulas should stack vertically with aligned changing parts, never drift apart into decorative left/right scatter.
- Use one accent treatment per contrasted form and reuse it in the matching examples below.

### 7. Example Block
- Slightly tinted `primary-soft` background.
- Bullet markers use rose or gold dots, never default black bullets.
- Example sentences should breathe; target `16/26`.
- Do not present examples as one undifferentiated list when the lesson is teaching a contrast.
- Group examples under the form they illustrate.
- Highlight only the same grammar slot that was highlighted in the FORM block; never highlight the whole sentence.

### 8. Exercise Card
- The main interaction object.
- Radius `24px`, padding `24px`, quiet border, optional top instruction band.
- The instruction band may use a pale rose tint with a compact icon.
- Keep one exercise per card. Never split attention with side widgets.

### 9. Input Fields
- Height `56px` single-line, `120px+` multi-line.
- Radius `16px`.
- Strong placeholder contrast; placeholders should still be readable.
- Focus state uses border emphasis plus a faint rose glow, not default blue.

### 10. Multiple Choice Rows
- Full-width rows with generous padding.
- Selected state should feel soft-premium, not quiz-app bright.
- Support immediate correctness styling after submit.

### 11. Result Panel
- Distinct from the exercise card but visually related.
- Correct: pale sage surface with deep green icon.
- Incorrect: pale rose-cream surface with wine-red accent.
- Canonical answer should read like a correction from a tutor, not a punishment box.

### 12. Mistake Review Card
- Cleaner and quieter than the main exercise card.
- Prompt in secondary text, answer in primary rose, explanation in readable body text.
- Avoid tiny annotations or dense grammar jargon blocks.

### 13. Empty / Error States
- Use warm illustration or icon container.
- Tone is calm and competent: “We couldn’t load this lesson. Try again.”
- Never use scary system-red full-screen alarms.

### 14. Audio Player (Listening Exercises)
- Used inside the exercise card when the exercise is `listening_discrimination`.
- Replaces the prompt text — the audio is the prompt.
- Anchor control: a single circular Play button, **64px**, dusty-rose fill, ivory play glyph. Centered above the options list.
- After first playback the same control morphs to a Replay state: same fill, circular-arrow glyph, identical size and position. No layout shift.
- Active playback state: a soft 4px halo at `bg.primary-soft` opacity ~0.3 pulses around the button at `d-long` cadence. Stops on completion.
- Below the Play control: a quiet `Show transcript` text button.
  - Default style: tertiary text, `label-md`, `text.secondary`, no border.
  - On tap, reveals a `bg.primary-soft` card with `r-md` radius, **16px** padding, `body-md` text containing the transcript verbatim. Once revealed, stays visible for the rest of the exercise.
  - Reveal animation: `d-short` slide-up `8px` plus fade-in. No collapse-back affordance.
- No volume control, no playback speed, no waveform, no scrubber. Listening is a one-decision interaction, not a media player.
- No autoplay. The first play is always learner-initiated (also a hard requirement for iOS Safari).
- Replays are unlimited and do not affect scoring.
- Disabled state (audio failed to load): button shows muted glyph, tertiary color, with one-line tertiary text below: `Audio unavailable. Try again.`

### 15. Exercise Image
- Used inside the exercise card on any exercise type that carries the optional `image` block (Visual Context Layer per `exercise_structure.md §2.9`).
- Sits at the **top** of the exercise card content, above the prompt / audio player / option list. Renders full card width inside the card's normal padding.
- Aspect ratio: **4:3** (matches the upstream pipeline output). Fit `cover`, never letter-boxed.
- Border radius: `r-lg` (22px). No outer shadow — the card already provides elevation.
- Loading state: warm `bg.primary-soft` fill with a small dusty-rose spinner centered. No text label, no skeleton shimmer (would compete with the calm tone).
- Failure state (image fetch fails): replace the image area with a quiet `bg.surface-alt` block displaying the `alt` text in `body-sm`, italic, `text.tertiary`. The exercise stays usable — image support is never a hard requirement.
- The image must obey the role from the schema (`scene_setting | context_support | disambiguation | listening_support`); roles do not change the visual rendering, only the authoring permission.
- The on-wire `alt` field is the accessibility label and the failure-state caption. Authors must always write a meaningful `alt` even when the image is decorative-feeling, because screen readers will speak it.
- Generated images are pre-rendered offline by the kie.ai-driven pipeline (see `docs/plans/roadmap.md` Workstream I) and served from the backend at `/images/{lesson_id}/{exercise_id}.png` with a one-year immutable cache header.

## Screen-Level Direction

### Home / Onboarding
- First screen should sell the learning philosophy, not features.
- Large hero wordmark or title, one elegant supporting sentence, 3 proof points max.
- Use a subtle illustration or study still-life near the top or side.
- The dashboard state should show level, lesson progress, and one main CTA.
- **Chosen V2 direction:** `Arrival Ritual` (currently in revision — see `docs/plans/arrival-ritual.md` for the locked 2-step + dashboard-as-home contract).
- On first launch, onboarding should run as a **2-step ritual**:
  1. `Promise`
  2. `Assembly`
- The final onboarding CTA lands on the **dashboard**. The dashboard is the single Home — it is also where `Done` from SummaryScreen brings the learner back. There is no separate "post-lesson home" surface.
- Each onboarding step must be individually addressable in implementation so copy, art, and motion can be tuned step-by-step.
- Motion should make the product feel like it is calmly preparing the workspace: soft float, staged rise, clean handoff into the dashboard.
- *History:* 2026-04-26 morning shipped a transitional 3-step direction (Promise → Assembly → Handoff, ending directly in the lesson intro, `cea886f..bd0f021`). Same-day reversal to 2-step + dashboard-as-home; final visual locked as Direction A · Editorial Notebook. Reference mockup: `docs/design-mockups/onboarding-2step/direction-a-editorial.html`.

### Lesson Intro
- Treat this like opening a premium lesson notebook.
- Lesson title is big and editorial.
- Level badge is compact and elegant.
- Rule sections must feel teachable, not like API text dumps.
- Examples live in a tinted support block beneath the rule content.
- For contrast-based lessons, the intro should read like a guided diff:
  common part first, changing slot emphasized, examples paired directly under each form.
- IMPORTANT copy should compress the contrast into a short paired reminder rather than carry the teaching load alone.
- Visual emphasis must support noticing: color + weight/underline/chip is acceptable; broad paragraph tinting without slot-level emphasis is not sufficient.

### Exercise Screen
- Put the learner in a tunnel: progress up top, task in center, result below.
- No side quests, no floating secondary widgets.
- The exercise surface should occupy emotional focus.
- Submission and "Next" controls should stay visually consistent to reduce friction.
- Required state coverage:
  - `idle`
  - `focused`
  - `answer selected / input entered`
  - `correct result revealed`
  - `incorrect result revealed`
- Result reveal should feel teacher-like and decisive, never game-like or punitive.

> Note: an earlier "first-exercise V2" direction (Brief B in `docs/plans/arrival-ritual.md`) proposed quieter chrome, no instruction band, and a Fraunces serif hero prompt. That brief was declined 2026-04-26 by the product owner. The current shipped chrome — rose-tinted `InstructionBand`, `MasteryCard` wrapper, single thin progress bar, body-text prompt — is the long-term contract.

#### Listening exercise variant (`listening_discrimination`)
- The exercise card shows the instruction band, then the Audio Player (component §14) where the prompt would normally sit.
- No prompt text. The audio is the prompt.
- The `Show transcript` toggle stays under the Play control. Hidden by default; revealing it never displaces the options below — the transcript card pushes content down softly, never scrolls the options off-screen on a 390-wide viewport.
- Options render as the standard Multiple Choice Rows (component §10) directly below the audio block.
- The single primary CTA at the bottom remains `Check answer`, identical to other exercise types. After submit, the audio block stays visible (so the learner can replay while reading the result panel).
- Result panel includes the canonical text in the `Answer:` line so the learner sees what they were supposed to hear.

### Summary Screen
- This is a reflection screen, not a reward casino.
- Score hero should be large and proud.
- If the learner made mistakes, the review stack should feel useful and non-shaming.
- A completion illustration is appropriate here if it does not push the review below the fold on small phones.

## Accessibility and Readability
- Minimum contrast target: WCAG AA everywhere, AAA for body text where feasible.
- Minimum touch target: `48x48`.
- Never communicate status by color alone; pair with icon and label.
- Keep line length in reading cards around `40-70` characters on mobile.
- Provide motion-reduced fallbacks for all animated sequences.

## Flutter Implementation Guidance
- Use Material 3 foundations only as infrastructure, not as the final visual language.
- Override the default `ThemeData` color scheme, shape scheme, and text theme completely.
- Add a `ThemeExtension` for custom tokens: surfaces, semantic colors, progress fills, and illustration backgrounds.
- Create reusable widgets for `MasteryButton`, `MasteryCard`, `MasteryChip`, `ResultPanel`, `SectionEyebrow`, `MasteryAudioPlayer` (single-clip, replay-only, transcript-on-demand — see Component System §14), and `MasteryExerciseImage` (4:3 aspect, soft loading skeleton, quiet failure state — see Component System §15).
- Use `AnimatedSwitcher`, `AnimatedOpacity`, `AnimatedSlide`, and `TweenAnimationBuilder` for most motion.
- Avoid default `FilledButton` and `OutlinedButton` styling without token overrides.
- Do not ship with `colorSchemeSeed` defaults; they are too generic for this product.

## Anti-Patterns
- No purple tech gradients.
- No flat system-blue primary theme.
- No tiny gray helper text under everything.
- No 12px all-caps UI as a dominant pattern.
- No mascot-centered onboarding.
- No streak widgets, coins, flames, confetti bursts, or reward shops.
- No more than one primary CTA per viewport.
- No dense settings-style home dashboard.

## Secondary Aesthetic Reference
- `Promova` is not in the top 10 by public Android install band (`5M+`), but it is a useful secondary visual reference for contemporary soft-premium EdTech surfaces and wellness-adjacent warmth. Use it as an aesthetic calibration point, not as the structural model.

## Source Links
- Duolingo Google Play: https://play.google.com/store/apps/details/Duolingo_aprende_idiomas?hl=en-US&id=com.duolingo
- Duolingo product page: https://en.duolingo.com/nojs/splash
- Duolingo design notes: https://blog.duolingo.com/core-tabs-redesign/
- Babbel Google Play: https://play.google.com/store/apps/details?hl=en_US&id=com.babbel.mobile.android.en
- Babbel mobile page: https://www.babbel.com/mobile?slc=c281s001
- Babbel product overview: https://www.babbel.com/about-us
- Busuu Google Play: https://play.google.com/store/apps/details?hl=en_US&id=com.busuu.android.enc
- Busuu product page: https://www.busuu.com/en
- Cake Google Play: https://play.google.com/store/apps/details?hl=en_US&id=me.mycake
- Cake company page: https://www.cakecorp.com/en/index.html
- ELSA Google Play: https://play.google.com/store/apps/details?hl=en_US&id=us.nobarriers.elsa
- ELSA product page: https://us.elsaspeak.com/
- ABA English Google Play: https://play.google.com/store/apps/details?hl=en-GB&id=com.abaenglish.videoclass
- ABA English product page: https://www.abaenglish.com/
- EWA Google Play: https://play.google.com/store/apps/details?amp=&hl=en&id=com.ewa.ewaapp
- Falou Google Play: https://play.google.com/store/apps/details/Falou_Fast_language_learning?hl=en_NZ&id=com.moymer.falou
- Falou app page: https://app.falou.com/
- Memrise Google Play: https://play.google.com/store/apps/details/?hl=en&id=com.memrise.android.memrisecompanion
- Memrise product page: https://www.memrise.com/
- Mondly Google Play: https://play.google.com/store/apps/details?id=com.atistudios.mondly.languages&xcust=169065532940178lb&xs=1
- Mondly product page: https://www.mondly.com/app/
- Promova Google Play: https://play.google.com/store/apps/details?hl=en_US&id=com.appsci.tenwords

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-04-25 | Initial design system created | Based on Mastery product docs, current Flutter screen structure, and competitive review of leading English-learning apps by public install band |
| 2026-04-25 | Chosen direction: Quiet Premium Coach | Fits the product’s non-gamified, adult, structured learning model better than playful or hyper-tech aesthetics |
| 2026-04-25 | Chosen core color: dusty rose | Matches user instruction while keeping the product warm, premium, and distinct from blue/purple EdTech defaults |
| 2026-04-25 | Chosen font pairing: Fraunces + Manrope | Gives editorial trust and premium character without sacrificing mobile readability |
| 2026-04-26 | Chosen onboarding direction: Arrival Ritual | Best balance of premium calm, emotional handoff, and immediate lesson readiness |
| 2026-04-26 | First-launch path should land directly in the lesson intro | Removes dead time after onboarding and makes the app feel useful immediately |
| 2026-04-26 | First exercise should use a quieter, prompt-led hierarchy | The learner should feel the lesson has arrived, not that they are still inside setup chrome |
