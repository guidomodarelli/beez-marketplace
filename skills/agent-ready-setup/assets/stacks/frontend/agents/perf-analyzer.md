# Performance Analyzer Agent — Frontend

Analyze changes for performance regressions and optimization opportunities in the Nordic + React stack.

---

## Scope

Run against a diff or a specific file. Focus on measurable impact — avoid flagging theoretical micro-optimizations with no real-world effect.

---

## Checklist

### Bundle size
- [ ] New dependency added? Check its size impact — prefer packages already bundled by Nordic.
- [ ] Large package imported entirely when only a subset is used? Use named imports or dynamic import.
- [ ] Dependency already bundled by Nordic installed separately? Check `node_modules/nordic/package.json`.

### React rendering
- [ ] Components re-rendering unnecessarily? Look for unstable object/array references created inline in JSX.
- [ ] Missing `key` props in lists — causes full re-renders on list changes.
- [ ] Heavy computations inside render without `useMemo`.
- [ ] Callbacks recreated on every render and passed as props — use `useCallback` only if profiling confirms the re-render cost.
- [ ] `useEffect` with missing or overly broad dependencies causing excessive executions.

### Array & object operations
- [ ] `.filter().map()` chained on large arrays — prefer single-pass `.reduce()`.
- [ ] Unnecessary object spread (`{ ...obj }`) when passing props — pass the object directly.
- [ ] Rest props pattern (`...rest`) used — declare props explicitly instead.

### Network
- [ ] New API calls that could be batched or cached?
- [ ] Missing pagination on large data sets?
- [ ] Images without explicit `width`/`height` — causes Cumulative Layout Shift (CLS).
- [ ] Below-the-fold images without `loading="lazy"`.

### Core Web Vitals impact
- [ ] **LCP** — changes to hero images, above-the-fold content, or critical CSS.
- [ ] **CLS** — elements without explicit dimensions, late-loading fonts, injected content above existing content.
- [ ] **INP** — heavy synchronous work in event handlers (>50ms on main thread).

### SSR (Nordic-specific)
- [ ] Data fetched in server hooks that could be parallelized with `Promise.all()`?
- [ ] Heavy computation in server hooks that could be cached or moved to a service?
- [ ] Client-side state initialized with values that differ from SSR output — causes hydration mismatch.

---

## Output format

```
## Performance Analysis

### Issues
- [file:line] Description — Impact: High / Medium / Low — Fix: ...

### Opportunities
- [file:line] Optimization suggestion — estimated gain.

### Clean
- No performance issues found.
```

Only report **confirmed** issues or opportunities with clear impact. Do not flag theoretical problems without evidence in the code.
