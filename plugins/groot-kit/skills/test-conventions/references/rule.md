## Mandatory Execution

- Run the relevant tests before marking any change as done; verify they pass.
- When functionality is added, modified, or removed, add or update the corresponding tests in the same change.
- If tests cannot be executed in the current environment, add an Error section stating what could not be validated and why.

# Test Conventions Rules

## Structure and Naming

- Use `describe` with `it` or `test` blocks, and include short explanatory comments for each scenario grouping.
- Name each test as: "should do X when Y".
- Follow Arrange-Act-Assert (AAA) or Given-When-Then (GWT); separate steps with comments like `// Arrange` or `// Given`.

## Coverage Expectations

- Include at least one happy path and significant edge cases for each key behavior.
- Cover error cases and atypical scenarios defensively.
- Assert both outputs and side effects that matter to the behavior.
- Do not use `fs`, filesystem helpers, snapshots, or raw source reads to assert exact file contents.
- Do not test implementation text in source, style files, SQL strings, ORM/query-builder call parameters, or SQL fragments such as `SELECT`, `JOIN`, `WHERE`, aliases, ordering clauses, or whitespace.
- For SQL or query behavior, validate user-facing filters, returned data, repository/service contracts, persisted effects, or integration behavior through the real query boundary when feasible.
- For styles, validate user-visible state, accessibility, class application only when it is the public styling contract, visual regression tooling, or the real build/lint command.

## Placement and Framework

- Place tests adjacent to the implementation file (for example, `example.spec.ts` next to `example.ts`, or `example.spec.js` next to `example.js`).
- Use `.spec` in the test filename.
- Prefer the project's existing testing framework and utilities; default to Jest if unspecified.

## Mocks and Isolation

- Organize manual mocks in a `__mocks__` sibling folder to the file being mocked.
- Mock all external dependencies (APIs, databases, network calls, timers) with mocks/spies.
- Keep tests independent, reset shared state in `beforeEach`/`afterEach`, and avoid relying on execution order.

## Output Requirements

- Deliver runnable test code with complete imports, setup, and teardown.
- After the code, add a brief Commentary block explaining coverage and suggesting enhancements.
- End with a Validation paragraph confirming coverage, correctness, and any gaps or manual steps.
- If any part cannot be tested automatically, add an Error section describing the limitation and a manual workaround.
