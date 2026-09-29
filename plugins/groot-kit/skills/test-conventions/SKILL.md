---
name: test-conventions
description: Enforces test naming, structure, coverage expectations, mock placement, reporting blocks (Commentary/Validation/Error), ErrorUX/CustomErrorUXSnackbar contracts, stale-error cleanup, and mandatory test execution before completing any change. Use whenever creating, updating, or reviewing automated tests, including Jest/RTL tests for retries, loading, empty states, partial responses, Failure Studio context, or async modal flows.
metadata:
  tags: "context-optimized-v1.17.2"
---

## Quick start

- Confirm the project's test framework and local patterns; default to Jest if unspecified.
- Place tests adjacent to implementation with `.spec` filenames, "should do X when Y" titles, and AAA/GWT structure.
- Cover happy paths, error cases, and significant edge conditions; mock external dependencies via `__mocks__`.
- Do not test source files by reading exact text, styles, SQL strings, SQL fragments, or ORM/query-builder call parameters; assert observable behavior or public contracts instead.
- Provide runnable test code, then include the required Commentary and Validation blocks (and Error when needed).

## Mandatory execution rules

- Before marking any change as done, run the relevant tests and verify they pass.
- When adding, modifying, or removing functionality, add or update the corresponding tests in the same change.
- If tests cannot be executed in the current environment, explicitly state what could not be validated and why.

## ErrorUX and CustomErrorUXSnackbar contracts

When a flow uses ErrorUX/Failure Studio or `CustomErrorUXSnackbar`, test the complete observable contract rather than only the visible copy:

- An actionable or unexpected failure with a real `ErrorUxContext` renders `CustomErrorUXSnackbar` and preserves the safe public message.
- Loading, expected domain states, empty results, validation feedback, and successful outcomes do not render `CustomErrorUXSnackbar`.
- Missing ErrorUX context uses a safe fallback message and never fabricates context.
- Changing the selected resource, closing/reopening a modal, starting a new attempt, or retrying clears stale `errorMessage` and `ErrorUxContext` before the next request.
- A degraded `202` response with `EXTERNAL_REQUIREMENT_PENDING` and no explainable requirements preserves the public status and carries safe ErrorUX context when the product contract requires support tracking.
- ErrorUX detail assertions must verify allowlisted diagnostic fields and absence of raw conditions, upstream payloads, request/response objects, headers, cookies, tokens, secrets, and full PII.
- Retry assertions must verify that the callback is safe and does not create duplicate mutations.

Prefer route/service contract tests for response `error_context` and component tests for rendering, cleanup, retry, and fallback behavior. Do not assert implementation-only logger calls unless logging is the explicit contract; assert the sanitized public/diagnostic projection instead.

## Resources

- See [rule.md](references/rule.md) for full conventions and output requirements.
