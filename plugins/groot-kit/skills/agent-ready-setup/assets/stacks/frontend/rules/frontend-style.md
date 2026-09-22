# Frontend Style Rules — Nordic + React + TypeScript

Coding conventions for this stack. Always consult `frontender-web-mcp` for Nordic and Andes-specific APIs before implementing — these rules cover conventions, not API details.

---

## Components

- Use function components with hooks — no class components.
- Keep components small and single-responsibility. Extract when a component has more than one reason to change.
- Extract complex logic into custom hooks (`use<Name>`).
- Avoid prop drilling beyond two levels — use context or a state manager.
- Never use rest props (`...rest`) — declare all props explicitly.
- **One component per file** — never export more than one component from a single file. A file named `user-card.tsx` exports only `UserCard`.
- **Component placement by scope**:
  - Reusable across pages → `app/ui-components/<component-name>/`
  - Used only within one page → colocated inside `app/nordic-pages/<page>/`
- **Atomic size** — keep components at the smallest meaningful unit. A component that mixes concerns (layout + data formatting + interaction) must be split.

## Andes UI

- Use Andes components for all UI elements: buttons, inputs, modals, selects, etc.
- Never build custom replacements for components Andes already provides.
- Use Andes props (`variant`, `size`, `hierarchy`, `color`) to control appearance before adding any custom CSS.
- Only add custom CSS when Andes has no prop or component that covers the need.
- Never override internal Andes component styles with custom CSS.
- Always consult `frontender-web-mcp` (`andes-components` tool) before selecting a component.

## User-facing copy

- Write labels, buttons, headings, helper text, empty states, confirmations, and progress messages for people who use the product, not for the team that built it.
- Avoid implementation terms in regular UI copy, including `preflight`, `bootstrap`, `provider`, `stack`, `upstream`, `lockfile`, `schema`, `sync`, and `retry` when they describe internal mechanics. Prefer the user-visible action or outcome, such as `Reintentar` instead of `Reintentar preflight`.
- Do not expose internal component names, service names, workflow names, file names, status codes, or infrastructure details in regular UI copy. Keep those details in logs or technical documentation, not in ordinary interface text.
- Keep error messages clear and actionable. Errors may include the minimum technical detail needed to diagnose or resolve the problem, but never expose secrets or unnecessary internal data.
- Review every new or changed user-facing string from the perspective of a non-technical user; if the message explains how the system works instead of what the user can do or expect, rewrite it.

## TypeScript

- Always type props explicitly — no `any`.
- Use `interface` for object shapes; `type` for unions and aliases.
- Never use `enum` — use `const` objects with `as const` or string union types.
- Never use parameter properties in classes.
- Run `tsc --noEmit` after every file change and fix errors immediately.

## Equality

- Prefer `Object.is(leftValue, rightValue)` over the strict equality operators `===` and `!==` when comparing values.
- Keep `===` or `!==` when `+0` and `-0` must be equivalent, when `NaN` must remain unequal, or when an existing contract explicitly requires strict-equality semantics; do not use `Object.is` for ordering or coercive comparisons.

## Naming

| Entity | Convention | Example |
|--------|-----------|---------|
| Components | PascalCase | `UserProfile` |
| Hooks | camelCase with `use` prefix | `useUserProfile` |
| Files & directories | kebab-case | `user-profile.tsx` |
| Constants | UPPER_SNAKE_CASE | `MAX_RETRIES` |
| Functions & variables | camelCase | `getUserProfile` |

## Module placement

- Keep subrouters and service modules focused on routing, validation, orchestration, and service calls. Do not add shared utilities or reusable constants inside `api/<resource>/`, `api/services/`, or `services/` modules.
- Place shared or reusable utility functions in `utils/` and domain/configuration constants in `constants/`. Keep only route-local declarations required to mount a router or define its schema inside a subrouter; extract anything reused or carrying domain meaning.

## Performance

- Never use anonymous functions in JSX event handlers on frequently rendered components.
- Use `Array.from()` with callback instead of `.map()` — avoids double iteration.
- Avoid unnecessary object cloning with spread — pass objects directly when no mutation is needed.
- Use `React.memo`, `useMemo`, and `useCallback` only when profiling confirms a render bottleneck — not preemptively.
- Lazy-load routes and heavy components.

## Imports

- Import from `nordic/` re-exports when available — never from the underlying package directly.
- Never install packages that Nordic already bundles (`react`, `react-dom`, `frontend-restclient`, etc.).
- Check `node_modules/nordic/package.json` before installing any new dependency.

## API Configuration

- Never add or forward `scope` as a query parameter (`?scope=...`, `params: { scope: ... }`, or equivalent URL construction). API scope belongs to client configuration, not request URLs.
- When an upstream client requires a scope, add a service-specific key to the existing environment files under `config/` (typically `config/local.js`, `config/default.js`, `config/default-production.js`, and `config/sandbox.js`) and consume it through `nordic/config` or the client option designed for configured scopes (for example, `scopeConfig`). Do not create a new config file solely for scope. Never hardcode environment values such as `sandbox` or `prod` in service code.
- Keep scope values in those existing `config/` files; do not duplicate them in services or handlers.

## Comments

- Comment the WHY, not the WHAT. Well-named identifiers explain themselves.
- Only comment non-obvious constraints, workarounds, or invariants.
- No multi-line comment blocks or docstrings.
