---
description: Create a Nordic API endpoint — either a server hook (getServerSideProps) or a REST endpoint in the /api folder using Ragnar.router(). Use when adding a new endpoint, server hook, or API route.
---

# API Endpoint Creation — Nordic

> **Prerequisite**: run `/logger` first to generate `api/logger.ts` — the logging helpers used in the examples below depend on it.

Nordic exposes two ways to handle server-side logic:

| Type | Location | Use when |
|---|---|---|
| **Server hook** | `app/nordic-pages/<route>/index.hooks.server.ts` | Fetching data to render a page (SSR) |
| **REST endpoint** | `api/<resource>/index.ts` → mounted via `Ragnar.router()` | Client-side calls, middle-end JSON APIs |

> **Never call `/api` routes from `getServerSideProps`** — call services directly (no HTTP roundtrip needed).

---

## Option A — Server Hook (`getServerSideProps`)

Consult `frontender-web-mcp` (`nordic-modules` tool, `pages`) for the current hooks API before implementing.

### File placement

Hooks file name must **exactly match** the page file name. Wrong name = hooks silently don't run.

```
app/nordic-pages/<route>/
├── index.tsx                    ← page component
└── index.hooks.server.ts        ← server-side data + API logic
```

### Validate inputs

Use `schema.validate()` for object schemas — returns a boolean and logs errors automatically.

```ts
import * as iv from '@meli/input-validation';

const paramsSchema = iv.object({
  id: iv.string().uuid(),
});

export async function getServerSideProps(req) {
  if (!paramsSchema.validate(req.params, { traceRequestId: req.traceRequestId })) {
    return { props: { error: true } };
  }
  // ...
}
```

Rules:
- Validate **all** external inputs: body, query params, path params, headers.
- Use allowlist — define only what is permitted, reject everything else.
- Never trust user-provided identifiers — retrieve user identity from session/JWT claims.
- Never accept PII or tokens via query parameters — use body.

### Implement the handler

```ts
import { logError } from '../../../api/logger';
import { getProduct } from '../../../src/services/product';

export async function getServerSideProps(req) {
  if (!paramsSchema.validate(req.params, { traceRequestId: req.traceRequestId })) {
    return { props: { error: true } };
  }

  try {
    const product = await getProduct(req.params.id);
    return { props: { product } };
  } catch (err) {
    logError(`[PRODUCT-GET-SERVER-SIDE-PROPS] - error: ${err.message}`, { productId: req.params.id });
    return { props: { error: true } };
  }
}
```

Rules:
- Never inline business logic — delegate to a service.
- Never expose stack traces or internal error details.
- Use `new Logger('name')` — never `console.log`.
- Use `nordic/restclient` for outbound HTTP calls inside the hook.
- Use GET only for read operations.

---

## Option B — REST Endpoint (`/api` folder)

Nordic mounts the `apiRouter` at `/api` via Ragnar. Use `iv.createValidationMiddleware` as middleware — it handles validation, error responses (422), and trace logging automatically.

### File placement

```
api/
├── index.ts              ← mounts all resource routers
└── product/
    └── index.ts          ← product router
```

### 1. Create the resource router

> Para implementar `getProduct`, `createProduct` y cualquier servicio que el handler consuma, seguí el skill `/service`.

```ts
// api/product/index.ts
import * as iv from '@meli/input-validation';
import Ragnar from 'nordic/ragnar';
import { logError } from '../logger';
import { getProduct, createProduct } from '../../src/services/product';

const router = Ragnar.router();

const getSchema = {
  params: iv.object({
    id: iv.string().uuid(),
  }),
};

const postSchema = {
  body: iv.object({
    name: iv.string().secure().min(1).max(100),
    price: iv.number().positive().max(99999.99),
  }),
};

router.get('/product/:id', iv.createValidationMiddleware({ schema: getSchema }), async (req, res) => {
  try {
    const product = await getProduct(req.params.id);
    res.json(product);
  } catch (err) {
    logError(`[PRODUCT-GET] - error: ${err.message}`, { productId: req.params.id });
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/product', iv.createValidationMiddleware({ schema: postSchema }), async (req, res) => {
  try {
    const product = await createProduct(req.body);
    res.status(201).json(product);
  } catch (err) {
    logError(`[PRODUCT-CREATE] - error: ${err.message}`);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
```

### 2. Mount in `api/index.ts`

```ts
import Ragnar from 'nordic/ragnar';
import productRouter from './product';

const apiRouter = Ragnar.router();

apiRouter.use(productRouter);

export default apiRouter;
```

Rules:
- Use `iv.createValidationMiddleware({ schema })` before every handler — never access `req.body/params/query` without prior validation.
- For path/query params (always strings), use `iv.coerce` for non-string types: `iv.coerce.number()`, `iv.coerce.boolean()`.
- Use allowlist strategy — declare only what is permitted in the schema.
- Never retrieve user identity from user-provided input — use `req.session`.
- Never log request/response bodies containing PII or tokens.
- Never expose internal error details or stack traces in responses.
- Never inline business logic — delegate to a service.
- Never disable CSRF without WebSec validation.

---

## Verify

```bash
tsc --noEmit
npm run lint
```
