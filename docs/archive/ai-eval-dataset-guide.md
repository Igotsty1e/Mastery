# AI Eval Dataset Guide — v1

**Dataset:** `docs/ai-eval-dataset.v1.jsonl`  
**Status:** Synthetic evaluation fixture, safe to keep in-repo.  
**Last updated:** 2026-04-20

## Purpose

This guide explains how to use the expanded eval dataset for future AI sessions.

The dataset is synthetic. It was authored for evaluator calibration and
does not contain real learner submissions, personal data, or production
telemetry.

The dataset is intentionally richer than the earlier template:
- it captures current runtime expectations
- it captures desired human judgment
- it flags `content_gap` cases explicitly

This matters because not every wrong answer is a prompt problem. Some cases are valid English that current content will reject because they fall outside the teacher-defined accepted corrections. Under the MVP teacher-list policy, this is the intended behavior — not a defect.

## File Format

The dataset is JSONL: one JSON object per line.

Each row represents one learner answer for one `sentence_correction` exercise.

## Fields

- `id`: stable case id
- `lesson_id`: lesson fixture id
- `exercise_id`: sentence_correction exercise id
- `prompt`: original incorrect sentence shown to the learner
- `accepted_corrections`: current server-side accepted corrections
- `user_answer`: learner answer under evaluation
- `target_skill`: short label for the grammar concept
- `rubric_label`: one of the labels from `docs/ai-evaluation-rubric.md`
- `expected_current_correct`: expected result under the current product behavior
- `expected_current_evaluation_source`: expected current route, either `deterministic` or `ai_fallback`
- `desired_human_correct`: whether the answer is correct under the MVP teacher-list policy (accepted_corrections is authoritative; grammar validity alone does not override it)
- `notes`: why the row exists

## How To Read The Important Differences

### 1. Current behavior vs desired judgment

These two fields should often match:
- `expected_current_correct`
- `desired_human_correct`

When they do not match, the case is usually a `content_gap`.

Typical pattern under the MVP teacher-list policy:
- `expected_current_correct=false`
- `expected_current_evaluation_source=deterministic`
- `desired_human_correct=false`
- `rubric_label=content_gap`

That means:
- current backend correctly rejects it
- the answer is valid English but outside the teacher-defined accepted corrections scope
- this is expected behavior, not a prompt or model problem

### 2. `ai_fallback` rows

Rows with `expected_current_evaluation_source=ai_fallback` are the main live-eval set for future prompt/model work.

Use them to measure:
- false positives
- false negatives
- over-permissiveness
- over-strictness

### 3. `deterministic` rows

These rows protect the non-AI boundaries:
- exact accepted answers
- normalization-only variations
- clearly wrong answers that should never need AI

If these start changing after an AI-oriented session, something is drifting badly.

## Recommended Usage In The Next AI Session

1. Run deterministic rows first and confirm there is no unexpected drift.
2. Run `ai_fallback` rows next and compare actual model verdicts to `desired_human_correct`.
3. Separate failures into:
   - `prompt_issue`
   - `model_issue`
   - `threshold_issue`
   - `content_issue`
4. Treat `content_gap` rows as a content-authoring discussion, not as immediate prompt failures.

## What Not To Do

- do not use only exact-match rows to judge model quality
- do not treat every rejected valid sentence as an AI bug
- do not tune prompt and model at the same time
- do not collapse `content_gap` into `borderline_ai_accept`

## Dataset Scope

v1 covers only the three current `sentence_correction` fixtures in `b2-lesson-001`.

It does not yet include:
- real learner production data
- adversarial spam inputs
- rate-limit or timeout ops cases
- multilingual edge cases

## Repository Policy

This file may remain committed to the repository because it is a
synthetic fixture. If future eval material uses real learner answers or
operational traces, it must live outside the public repository surface.

## Suggested Next Dataset Expansions

1. Add 10-20 real learner-like wrong answers per sentence_correction item.
2. Add paired near-miss cases that differ by one token but must flip verdict.
3. Add more `content_gap` cases as content is expanded — policy is frozen (teacher-list authoritative), so new `content_gap` cases document structural rewrites that content authors should decide whether to include in `accepted_corrections`.
