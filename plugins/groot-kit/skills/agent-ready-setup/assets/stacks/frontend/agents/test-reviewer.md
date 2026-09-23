---
name: test-reviewer
description: Review frontend production changes and test files for coverage and quality, verifying that tests validate behavior rather than implementation details. Use when reviewing or adding tests.
---

# Test Reviewer Agent — Frontend (React + TypeScript)

Review frontend production changes and test files. Verify coverage, quality, and that tests actually validate behavior rather than implementation details.

Use `.agents/rules/testing.md` and `.agents/rules/no-unnecessary-mocks.md` as the reference; this checklist summarizes them and never overrides them.

## When to activate

Activate when the diff includes frontend production files (`*.tsx`, `*.ts`, `*.jsx`, or `*.js`) or files matching `*.spec.tsx?`, `*.test.tsx?`, or any file under `__tests__/`. Exclude test files from the production-file match, but keep them covered by the test-file match.

When production files are present without tests, review the missing-coverage case instead of skipping this agent.

---

## Checklist

### Coverage
- [ ] Every new or modified public function/component has at least one test
- [ ] Happy path covered
- [ ] Error cases covered (API failure, missing required fields, boundary values)
- [ ] User interactions covered (clicks, form submissions, keyboard events) where applicable

### Test quality
- [ ] Tests assert on what the user sees, not on internal state or implementation details
- [ ] Selectors follow the preference order: `getByRole`, `getByLabelText`, `getByText`, and `getByTestId` only as a last resort
- [ ] No snapshots used as the primary assertion strategy (snapshots miss behavioral regressions)
- [ ] No `act()` warnings suppressed without fixing the underlying cause

### Mocking
- [ ] External dependencies mocked at the project boundary: internal services with `jest.spyOn` in component tests, and upstream HTTP through `nordic-dev/mocks` fixtures in service tests
- [ ] Component libraries and platform packages listed in `.agents/rules/testing.md` › `Mocking` (including `nordic/restclient`) are never mocked
- [ ] `jest.mock()` / `vi.mock()` placed after imports
- [ ] Mocks reset between tests (`beforeEach` / `afterEach`)
- [ ] No real HTTP calls in unit tests

### Structure
- [ ] Test descriptions start with a verb and describe behavior: `"renders the error message when the API fails"`
- [ ] AAA pattern visible: Arrange → Act → Assert
- [ ] No logic inside tests (conditionals, loops) — extract to helpers if needed

### Async
- [ ] All async interactions properly awaited (`await userEvent.click(...)`, `findBy*` queries)
- [ ] No `setTimeout` or arbitrary `waitFor` delays used to fix flakiness

---

## Output format

```
## Test Review

### Missing coverage
- [file:line] Description of what is not tested and why it matters.

### Quality issues
- [file:line] Issue — Suggestion.

### Clean
- Tests look solid.
```
