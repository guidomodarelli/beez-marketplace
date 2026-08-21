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

## TypeScript

- Always type props explicitly — no `any`.
- Use `interface` for object shapes; `type` for unions and aliases.
- Never use `enum` — use `const` objects with `as const` or string union types.
- Never use parameter properties in classes.
- Run `tsc --noEmit` after every file change and fix errors immediately.

## Naming

| Entity | Convention | Example |
|--------|-----------|---------|
| Components | PascalCase | `UserProfile` |
| Hooks | camelCase with `use` prefix | `useUserProfile` |
| Files & directories | kebab-case | `user-profile.tsx` |
| Constants | UPPER_SNAKE_CASE | `MAX_RETRIES` |
| Functions & variables | camelCase | `getUserProfile` |

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

## Comments

- Comment the WHY, not the WHAT. Well-named identifiers explain themselves.
- Only comment non-obvious constraints, workarounds, or invariants.
- No multi-line comment blocks or docstrings.
