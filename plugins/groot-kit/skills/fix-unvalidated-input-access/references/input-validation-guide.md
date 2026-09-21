# @meli/input-validation — SDK Reference

> **Source of truth:** [Nordic Security — Input Validation](https://nordic.adminml.com/docs/input-validation) (last updated 2026-07-16).
>
> **Rule:** NUNCA usar AJV. NUNCA usar `schemaValidationMiddleware`. Usar este SDK directamente.

## Installation

```json
"@meli/input-validation": "1.4.8"
```

## Basic usage

```js
const inputValidation = require('@meli/input-validation');
```

## Schema types

### object

```js
const schema = inputValidation.object({
  field: inputValidation.string(),
});
```

### string

```js
inputValidation.string()          // required string
inputValidation.string().optional()
inputValidation.string().max(255)
inputValidation.string().min(1)
inputValidation.string().regex(/^[a-z]+$/)
inputValidation.string().secure() // adds MELI injection/XSS checks — prefer for user input
```

### coerce.number (for req.query — always strings)

```js
inputValidation.coerce.number()             // coerces '42' → 42
inputValidation.coerce.number().int()       // must be integer after coercion
inputValidation.coerce.number().min(0)
inputValidation.coerce.number().max(500)
inputValidation.coerce.number().optional()
```

### coerce.boolean — GOTCHA

`inputValidation.coerce.boolean()` accepts ANY truthy string (`'1'`, `'yes'`, `'on'`, etc.) → `true`.

**For strict `'true'`/`'false'` query params, use:**

```js
inputValidation.string().regex(/^(true|false)?$/).optional()
// The `?` makes an empty string valid (absent param). Remove if the field is required.
```

## Route validation (preferred)

The `input-validation-enforcer` proxy monitors access to `req.query`, `req.body`, and `req.params`.
Register `createValidationMiddleware` before any middleware or handler that reads those properties.

```js
const router = require('nordic/ragnar').router();
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

`createValidationMiddleware` returns `422` by default when validation fails. Configure its documented
custom error handler only when product behavior requires another response shape.

## Direct `.validate()` usage

Use manual validation only when route middleware is not appropriate. One call validates input and returns
a boolean; branch on that result before reading properties.

```js
const isValid = pageQuerySchema.validate(req.query);

if (!isValid) {
  return res.status(422).json({ error: 'Validation failed' });
}

const { page, size, active, search } = req.query;
```

Do not require a second `validate(input, { global: true })` call. Official Nordic guidance documents
`createValidationMiddleware` for routes and one `.validate()` call for manual validation.

## Resolving UNVALIDATED INPUT ACCESS warnings

1. Use warning path to identify exact request part and property.
2. Ensure schema declares property under matching key: `query`, `body`, or `params`.
3. Ensure `createValidationMiddleware` runs before first property access.
4. Bind request source and schema at route declaration; do not inspect unvalidated input to select a schema.
5. Keep every access after validation middleware in chain.

Warnings are emitted only in local development; protection applies in all environments.

## Testing route validation

Do not mock `@meli/input-validation` when test goal is validating SDK integration or warning removal. Mocking
SDK hides route-order and schema-coverage defects. Mock unrelated authorization/service boundaries instead.

```js
jest.mock('nordic/ragnar', () => ({ router: jest.fn(() => mockRouter) }));

jest.isolateModules(() => {
  require('@root/api/routes/products');
});

const routeMiddlewares = mockRouter.post.mock.calls[0];
const validationMiddleware = routeMiddlewares[1];
const handler = routeMiddlewares[2];
```

## schemaValidationMiddleware (DO NOT USE FOR NEW ROUTES)

`middlewares/schemaValidationMiddleware.js` is an **AJV-based** wrapper that happens to call
`markSchemaPropertiesAsValidated` from `@meli/input-validation` internally. It exists for legacy routes.
For any new route or refactor, use `@meli/input-validation` directly as shown above.
