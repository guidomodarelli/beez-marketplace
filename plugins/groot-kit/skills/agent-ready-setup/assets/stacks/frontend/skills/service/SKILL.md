---
name: service
description: Create a service layer for external API calls in Nordic. Use when adding a new service, API client, or data-fetching layer.
metadata:
  tags: "context-optimized-v1.18.2"
---

# Service Creation — Frontend (Nordic)

Guide for creating a service — the layer that encapsulates all external API calls and business logic. Server hooks and components delegate to services; they never call APIs directly.

---

## Step 1 — Decide where the service lives

```
src/services/<domain>/
├── index.ts                     ← public API of the service
└── __tests__/
    └── <domain>.spec.ts
```

Group by domain (`user`, `shipping`, `payment`) — not by technical type (`api`, `fetch`).

---

## Step 2 — Set up the restclient

Always use `nordic/restclient` for external HTTP calls. Never use `fetch`, `axios`, or `http.request` directly.

```ts
import { config } from 'nordic/config';
import { RestClient } from 'nordic/restclient';
import { RESOURCE_REQUEST_TIMEOUT_MS } from '../../constants/resource';

const client = new RestClient({
  baseUrl: config.get('restclient.baseUrl'),
  timeout: RESOURCE_REQUEST_TIMEOUT_MS,
});
```

Rules:
- Read base URLs and scopes from the environment files under `config/` through `nordic/config`, as required by `../../rules/api-configuration.md`. Only credentials come from `node-melitk-secrets`.
- Never pass user-controlled input directly as the base URL or path — validate against a static allowlist.

---

## Step 3 — Implement the service functions

```ts
// Continue in the same index.ts file and reuse the client declared in Step 2.

export async function getResource(id: string): Promise<Resource> {
  // id must be validated by the caller before reaching here
  const response = await client.get<Resource>(`/resources/${id}`);
  return response.data;
}

interface CreateResourceUpstreamRequest {
  resource_name: string;
  unit_price: number;
}

// Owns the upstream field names so client input shapes never leak upstream.
function buildCreateResourceUpstreamRequest(input: CreateResourceInput): CreateResourceUpstreamRequest {
  return {
    resource_name: input.name,
    unit_price: input.price,
  };
}

export async function createResource(input: CreateResourceInput): Promise<Resource> {
  const response = await client.post<Resource>('/resources', buildCreateResourceUpstreamRequest(input));
  return response.data;
}
```

Rules:
- Services do not validate inputs — that is the responsibility of the server hook or handler.
- Build every upstream request body with a named builder per operation (`build<Operation>UpstreamRequest`); never send the handler input as-is. See `../../rules/upstream-contracts.md`.
- Services let errors propagate — no try/catch here unless translating error types.
- Never expose internal error details — catch at the handler level.
- Never log inside a service — logging happens in the handler via `logError`/`logWarning` from `utils/logger.ts` (see skill `/logger`).
- Keep reusable helpers and domain/configuration constants out of service modules; place them in `utils/` and `constants/` respectively. See `../../rules/frontend-style.md`, section `Module placement`.
- Parallelize independent calls with `Promise.all()`.

---

## Step 4 — Write the test

```ts
import { config } from 'nordic/config';
import { Mock } from 'nordic-dev/mocks';
import { getResource } from '../index';

const baseUrl = config.get('restclient.baseUrl');
let mock;

beforeAll(() => {
  mock = Mock();
  mock.intercept(baseUrl, ['/resources/*'], {
    ignoreParams: ['access_token', 'caller.id', 'scope'],
  });
});

afterAll(() => {
  mock.restore(baseUrl);
});

describe('getResource', () => {
  it('returns the resource when the API responds successfully', async () => {
    const result = await getResource('1');

    expect(result.id).toBe('1');
    expect(result.name).toBeDefined();
  });
});
```

Usá fixtures de `nordic-dev/mocks` para escenarios de error, en lugar de mockear `nordic/restclient`. Para `createResource`, cubrí el mapeo de `buildCreateResourceUpstreamRequest` verificando el request enviado con el mecanismo de intercepción HTTP del proyecto que permita inspeccionarlo (ver `../../rules/upstream-contracts.md`, sección `Tests`). En la primera ejecución, el interceptor captura la respuesta y crea el fixture; commitealo para que CI pueda ejecutar el test sin red.

---

## Step 5 — Verify

```bash
tsc --noEmit
npm run lint
npm test
```
