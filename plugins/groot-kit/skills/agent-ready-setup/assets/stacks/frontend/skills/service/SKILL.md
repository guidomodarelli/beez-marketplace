---
description: Create a service layer for external API calls in Nordic. Use when adding a new service, API client, or data-fetching layer.
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
import { RestClient } from 'nordic/restclient';

const client = new RestClient({
  baseUrl: process.env.SERVICE_BASE_URL, // from Fury Secrets — never hardcode URLs with tokens
  timeout: 5000,
});
```

Rules:
- Never pass user-controlled input directly as the base URL or path — validate against a static allowlist.
- Never add or forward `scope` as a query parameter. If the client requires a scope, add it to the existing environment files under `config/` (typically `local.js`, `default.js`, `default-production.js`, and `sandbox.js`) and consume it through `nordic/config` or the client's configured-scope option. Do not create a new config file solely for scope or hardcode `sandbox`/`prod` in service code. See the `API Configuration` section in `../../rules/frontend-style.md`.
- Never log request/response bodies that may contain PII or tokens.
- Use environment variables injected via `node-melitk-secrets` for any credentials or base URLs.

---

## Step 3 — Implement the service functions

```ts
// Continue in the same index.ts file and reuse the client declared in Step 2.

export async function getResource(id: string): Promise<Resource> {
  // id must be validated by the caller before reaching here
  const response = await client.get<Resource>(`/resources/${id}`);
  return response.data;
}

export async function createResource(payload: CreateResourceInput): Promise<Resource> {
  const response = await client.post<Resource>('/resources', payload);
  return response.data;
}
```

Rules:
- Services do not validate inputs — that is the responsibility of the server hook or handler.
- Services let errors propagate — no try/catch here unless translating error types.
- Never expose internal error details — catch at the handler level.
- Never log inside a service — logging happens in the handler via `logError`/`logWarning` from `utils/logger.ts` (see skill `/logger`).
- Keep reusable helpers and domain/configuration constants out of service modules; place them in `utils/` and `constants/` respectively. See `../../rules/frontend-style.md`, section `Module placement`.
- Never use sequential or predictable identifiers when generating IDs — use `getRandomUUID()` from `websec-crypto-js`.
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

Usá fixtures de `nordic-dev/mocks` para escenarios de error, en lugar de mockear `nordic/restclient`. En la primera ejecución, el interceptor captura la respuesta y crea el fixture; commitealo para que CI pueda ejecutar el test sin red.

---

## Step 5 — Verify

```bash
tsc --noEmit
npm run lint
npm test
```
