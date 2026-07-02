# API Endpoint Creation — Nordic (Server Hooks)

Guide for creating a Nordic server-side endpoint using `index.hooks.server.ts`. Consult `frontender-web-mcp` (`nordic-modules` tool) for the current API of server hooks before implementing.

---

## Step 1 — Decide where the endpoint lives

Nordic server hooks live alongside the page they serve:

```
app/nordic-pages/<route>/
├── index.tsx                    ← page component
└── index.hooks.server.ts        ← server-side data + API logic
```

If the endpoint is a standalone API (no page), place it under an API-only route directory and confirm the routing exclusion pattern with `frontender-web-mcp`.

---

## Step 2 — Validate all inputs first

Never use request data before validating. Use `@meli/input-validation` at the top of the handler:

```ts
import { iv } from '@meli/input-validation';

const schema = iv.object({
  // Define every field explicitly — allowlist strategy
  id: iv.string().uuid(),
  // ...
});

const result = schema.safeParse(req.body); // or req.query, req.params
if (!result.success) {
  return res.status(400).json({ error: 'Invalid input' });
}
```

Rules:
- Validate **all** external inputs: body, query params, path params, headers.
- Use allowlist — define what is permitted, reject everything else.
- Never trust user-provided identifiers directly — retrieve the user from session/JWT claims.
- Never accept PII or tokens via query parameters — use body.

---

## Step 3 — Implement the handler

```ts
import { logger } from 'nordic/logger';

export async function getServerSideProps(context) {
  try {
    // 1. Validate input (see Step 2)
    // 2. Get user identity from session — never from user-provided input
    // 3. Call service layer (never inline business logic here)
    // 4. Return data to the page component
    return { props: { ... } };
  } catch (error) {
    logger.error('Handler error', { error: error.message }); // never log sensitive data
    return { props: { error: true } }; // never expose stack traces to the client
  }
}
```

Rules:
- Never inline business logic in the hook — delegate to a service.
- Never expose stack traces or internal error details in the response.
- Never log sensitive data (tokens, PII) — use `nordic/logger`.
- Use `nordic/restclient` for any outbound HTTP calls inside the hook.
- Use GET only for read operations — never for state-modifying operations.

---

## Step 4 — Write the test

```ts
import { getServerSideProps } from '../index.hooks.server';
import * as myService from '../../services/my-service';

jest.mock('../../services/my-service');

describe('getServerSideProps', () => {
  it('returns props when input is valid', async () => {
    (myService.fetchData as jest.Mock).mockResolvedValue({ id: '1', name: 'test' });

    const result = await getServerSideProps({ params: { id: '1' } } as any);

    expect(result).toEqual({ props: { ... } });
  });

  it('returns error prop when the service throws', async () => {
    (myService.fetchData as jest.Mock).mockRejectedValue(new Error('API error'));

    const result = await getServerSideProps({ params: { id: '1' } } as any);

    expect(result).toEqual({ props: { error: true } });
  });
});
```

---

## Step 5 — Verify

```bash
tsc --noEmit
npm run lint
npm test
```
