---
name: fix-unvalidated-input-access
description: Validates req.query, req.body, and req.params in Nordic/Node.js routes using @meli/input-validation. Invoke proactively for InputValidationError, UNVALIDATED INPUT ACCESS, runtime failures at req.query/req.body/req.params, new BFF/API routes, or migrations from AJV/schemaValidationMiddleware. Limit implementation to the reported endpoint/property unless evidence requires wider scope.
---

# @meli/input-validation

## Rules

- **NEVER use AJV directly.** Never use `schemaValidationMiddleware` (it wraps AJV internally). Use `@meli/input-validation` directly.
- **Prefer `createValidationMiddleware({ schema })` for routes.** Register it before every middleware or handler that reads `req.query`, `req.body`, or `req.params`. It validates declared request parts and returns `422` by default when validation fails.
- **Use one `.validate()` call for manual validation.** Check its boolean result and reject invalid input before access. Do not require a second `.validate(input, { global: true })` call: official Nordic guidance does not document a two-call pattern.
- **Fix `UNVALIDATED INPUT ACCESS` at route ordering/schema coverage.** Confirm validation middleware runs before access and schema declares exact request part and property. Do not silence warning by adding redundant validation passes.
- **Treat stack traces as scope boundaries.** Locate the exact source line, identify the reported route and property, and fix that route/property first. Inspect adjacent routes only when the same stack trace, shared execution path, or explicit user request demonstrates they are part of the issue.
- **Do not expand validation without evidence.** Do not add schemas to unrelated endpoints merely because they live in the same module or also read request input; record broader hardening as a separate follow-up instead.
- **Place validation before authorization and other parameter-reading middleware when possible.** `createValidationMiddleware` should be the first route middleware; keep authorization after validation unless framework constraints require another order, then document and test the exception.
- **Preserve existing API contracts.** If legacy route behavior returns `400`, uses a custom error payload, or intentionally normalizes malformed values (for example, falls back to a default page size), provide a narrow `errorHandler` or schema boundary that preserves that observable behavior while still validating unsafe input.
- **Do not assume coercion mutates requests.** `coerce` validates converted values but the SDK keeps original `req` values unchanged; use string schemas when downstream code relies on raw query strings, or normalize explicitly only when behavior requires it.
- **`coerce.boolean()` is too permissive** — accepts `'1'`, `'yes'`, any truthy string. For strict `'true'`/`'false'` query params use `inputValidation.string().regex(/^(true|false)?$/).optional()`.
- **`coerce.number()`** coerces query string numbers (always strings on `req.query`) to numbers before validation.
- **`string().secure()`** adds MELI security checks on string fields (injection, etc.). Prefer over bare `.string()` for user-supplied strings.
- **`.optional()`** makes a field optional (absent = valid). Without it, the field is required.

## Preferred route pattern

```js
const inputValidation = require('@meli/input-validation');

const pageQuerySchema = inputValidation.object({
  page: inputValidation.coerce.number().int().min(0).max(500).optional(),
  size: inputValidation.coerce.number().int().min(1).max(500).optional(),
  active: inputValidation.string().regex(/^(true|false)?$/).optional(),
  search: inputValidation.string().secure().max(255).optional(),
});

router.get(
  '/',
  inputValidation.createValidationMiddleware({
    schema: { query: pageQuerySchema },
  }),
  (req, res) => {
    const { page, size, active, search } = req.query;

    return res.json({ page, size, active, search });
  },
);
```

## Manual validation pattern

Use only when route middleware is not appropriate:

```js
const isValid = pageQuerySchema.validate(req.query);

if (!isValid) {
  return res.status(422).json({ error: 'Validation failed' });
}

const { page, size, active, search } = req.query;
```

## Troubleshooting warnings

1. Identify exact accessed path (`query.id`, `body.name`, `params.userId`).
2. Confirm route schema declares that property under correct request part.
3. Confirm `createValidationMiddleware` appears before first access in middleware chain.
4. Avoid reading input while choosing which schema to apply; bind source/schema when route is declared.
5. Tests for warnings must use real `@meli/input-validation`; mocking SDK hides integration failures.

## See also

- [Official Nordic Input Validation documentation](https://nordic.adminml.com/docs/input-validation) — source of truth.
- [input-validation-guide.md](references/input-validation-guide.md) — SDK reference and coercion details.
