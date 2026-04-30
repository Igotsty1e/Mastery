# PR Notes

## Summary

Prepare the repository for public-readiness review without publishing
it. The branch removes accidental local-secret exposure, adds public
documentation, and makes deployment expectations explicit.

## Main Changes

- remove the embedded GitHub token from the local remote setup
- rewrite the public-facing `README.md`
- add `SECURITY.md`
- add `docs/public/` architecture, roadmap, and AI workflow notes
- add `docs/github-readiness/` audit and final report
- harden Render web builds so missing `API_BASE_URL` fails fast
- align CORS tests and backend docs with the real env precedence

## Validation

- `npm test -- backend-hardening.test.ts`
- fail-fast smoke check for `REQUIRE_API_BASE_URL=true` without
  `API_BASE_URL`

## Remaining Manual Follow-Up

- rotate the GitHub token that previously existed in local remote
  configuration
- confirm Render dashboard env values are set before deployment
