# Testing Rules — Frontend (React + TypeScript)

Standards for writing and reviewing tests. The `test-reviewer` agent uses this file as the reference for what a good test looks like in this stack.

---

## Framework

- Use **Jest + React Testing Library (RTL)** for unit and integration tests.
- Use the exact test runner configured in `package.json` — do not assume Jest if Vitest is configured.

## Coverage

- Minimum line coverage: **80%**.
- Every new or modified public component and function must have at least one test.
- API handlers and server hooks require integration tests.

## What to test

- **Happy path** — expected inputs produce expected outputs.
- **Error cases** — API failures, missing required fields, boundary values.
- **User interactions** — clicks, form submissions, keyboard navigation.
- Do not test implementation details — test what the user sees and does.

## Selectors (in order of preference)

1. `getByRole` — semantic and accessible.
2. `getByLabelText` — form fields.
3. `getByText` — visible content.
4. `getByTestId` — last resort, only when no semantic alternative exists.

Avoid snapshot tests as the primary assertion strategy — they detect change, not correctness.

## Mocking

- Mock all external dependencies: APIs, `nordic/restclient`, third-party SDKs, `nordic/logger`.
- Place `jest.mock()` / `vi.mock()` after imports.
- Reset mocks between tests using `beforeEach` / `afterEach`.
- No real HTTP calls in unit tests.

## Async

- Await all async interactions: `await userEvent.click(...)`, use `findBy*` queries for elements that appear after async operations.
- Never use arbitrary `setTimeout` delays to fix flakiness — find and fix the root cause.

## Structure

- Test file location: colocated in `__tests__/` next to the file under test, or `*.spec.tsx` alongside it.
- Description format: start with a verb describing behavior — `"shows the error banner when the API returns 500"`.
- Follow AAA: Arrange → Act → Assert. No logic (conditionals, loops) inside test bodies.
