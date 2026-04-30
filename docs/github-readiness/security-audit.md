# Security Audit

## Summary

- Risk level: Medium
- Safe for public: No
- Critical issues:
  - local git remote previously contained an embedded GitHub personal access token
  - tracked documentation exposed internal deployment detail and local absolute paths

## Findings

| Severity | File | Issue | Risk | Fix |
|---|---|---|---|---|
| Critical | local `.git/config` | `origin` URL contained an embedded GitHub PAT | local secret exposure, potential account or repo access misuse | cleaned local remote URL, rotate the PAT in GitHub |
| High | `CLAUDE.md` | concrete production endpoints, service names, and deploy workflow were committed | unnecessary exposure of internal deployment topology | sanitize committed deploy notes, keep operational specifics private |
| Low | `docs/archive/ai-eval-dataset.v1.jsonl` | synthetic evaluation dataset is committed | low risk because the file is author-created and contains no learner data; main risk is future accidental mixing with real submissions | keep it synthetic, document the boundary clearly |
| Medium | `CLAUDE.md`, `docs/content/unit-u01-blueprint.md` | absolute local file paths were committed | workstation disclosure and unpolished public docs | replace with relative paths |
| Low | `backend/src/auth/tokens.ts` | dev fallback secret constant exists in code | public security smell, future misuse risk if guards regress | keep production guard, consider removing the dev fallback in a later hardening pass |

## Required fixes

- rotate the GitHub PAT that was previously embedded in the local remote URL
- verify no additional operational details remain in tracked docs intended for public readers

## Recommended fixes

- keep generated logs and temp files ignored by git
- prefer relative repository paths in committed documentation
- gradually move internal-only guidance out of public-facing root docs
- keep synthetic eval fixtures clearly separated from any real learner data
