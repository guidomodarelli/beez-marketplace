# Lodash Rules — Nordic + React + TypeScript

Use lodash only where it removes code the language cannot express as briefly; never as a wrapper around native features.

## When lodash is available

Resolve availability in this order before importing, so `import/no-extraneous-dependencies` stays clean without duplicating what Nordic already ships:

1. **Re-exported by `nordic/`** → import from the `nordic/` path (see `Imports` in `frontend-style.md`).
2. **Declared** in `dependencies` of `package.json` (`lodash` or `lodash-es`) → import it directly.
3. **Bundled by Nordic but not declared** (listed in `node_modules/nordic/package.json`) → do not add it to `package.json`. Register every subpath you import (for example `lodash/debounce`) in `settings['import/core-modules']` of the existing ESLint config, extending the current list instead of replacing it. Never silence the rule with `eslint-disable`.
4. **Not available** → ask before adding it instead of hand-rolling a mandatory case; never add it for a case listed as forbidden.

In TypeScript, neither package ships its own declarations: `lodash` needs `@types/lodash` and `lodash-es` needs `@types/lodash-es`. If the types are missing, apply the same order above to the `@types` package instead of typing the import as `any`.

## Mandatory cases

For these cases, never hand-roll an implementation:

| Need | Use |
| --- | --- |
| Debounce or throttle a handler | `lodash/debounce`, `lodash/throttle` |
| Deep equality of objects or arrays | `lodash/isEqual` |
| Default options, flat or nested | `lodash/defaults({}, options, defaultOptions)`, `lodash/defaultsDeep` |
| Deep merge without mutating inputs | `lodash/merge({}, base, override)` |
| Unique values of a list | `lodash/uniq` |
| Unique items by a key | `lodash/uniqBy` |
| Sort by several keys or directions | `lodash/orderBy` |
| Index a list by a key | `lodash/keyBy` |
| Group a list by a key | `lodash/groupBy`, only when the target runtime lacks `Object.groupBy` |
| Split a list into fixed-size batches | `lodash/chunk` |
| Check for `null` or `undefined` | `lodash/isNil` (use `??` when you only need a fallback value) |
| Check for a plain object (`{}` or `Object.create(null)`) | `lodash/isPlainObject` |
| Type checks instead of `typeof`, `Array.isArray`, `=== undefined` or `=== null` | `lodash/isString`, `lodash/isNumber`, `lodash/isBoolean`, `lodash/isFunction`, `lodash/isSymbol`, `lodash/isObject`, `lodash/isArray`, `lodash/isUndefined`, `lodash/isNull` |

## Existing project utils

When a change adds, modifies, or calls a project util that reimplements a mandatory case (for example `isRecord`, `isNullish`, `unique`, `chunkArray`, `debounceFn`, `deepEqual`), replace it with the lodash method in the same change:

1. Compare semantics before swapping. `isPlainObject` rejects class instances, `Date` and `Map`; if the util accepts them, keep that behavior with `lodash/isObjectLike` plus the exclusions the util already had, and say so in the change.
2. Update every call site and delete the util, its export and its unit tests; the behavior stays covered by the tests of the call sites.
3. Call lodash directly: no wrapper util that only delegates to lodash, not even to keep a TypeScript type guard.

   ```ts
   // ❌ Hand-rolled check, or a wrapper that only delegates
   const isRecord = (value: unknown): value is Record<string, unknown> =>
     typeof value === 'object' && value !== null && !Array.isArray(value);

   // ✅ Import and call lodash at every call site
   import isPlainObject from 'lodash/isPlainObject';

   if (isPlainObject(payload)) {
     // ...
   }
   ```

## Forbidden cases

Use the native equivalent instead:

| Lodash | Native |
| --- | --- |
| `_.map` | `Array.from(source, callback)` (see `Performance` in `frontend-style.md`) |
| `_.each`, `_.forEach`, `_.filter`, `_.reduce`, `_.find`, `_.some`, `_.every`, `_.includes` | Array methods or `for...of` |
| `_.get`, `_.has` | Optional chaining (`?.`), `??`, `Object.hasOwn` |
| `_.cloneDeep` | `structuredClone` |
| `_.assign`, `_.keys`, `_.values`, `_.entries` | `Object.assign`, spread, `Object.keys/values/entries` |
| `_.omit`, `_.pick` | Destructuring on data objects (`const { password, ...safeUser } = user`; component props still follow the no-rest-props rule) or `Object.fromEntries` over filtered `Object.entries` |
| `_.groupBy` when `Object.groupBy` is available | `Object.groupBy` |
| `_.flatten`, `_.range` | `.flat()`, `Array.from({ length }, ...)` |

## Usage

- Import one method per module (`import debounce from 'lodash/debounce'`). With `lodash-es`, named imports are fine because they tree-shake (`import { debounce } from 'lodash-es'`). Never import the whole `lodash` package (`import _ from 'lodash'`, `import { debounce } from 'lodash'`), because it pulls the full library into the bundle.
- Never mutate inputs: pass a fresh target (`{}`) as the first argument to `defaults`, `defaultsDeep` and `merge`.
- In React components, create a debounced or throttled function once per component instance (`useMemo` or `useRef`) and call `.cancel()` in the effect cleanup on unmount. Otherwise it is recreated on every render, loses its pending state, and can fire after the component unmounted.
