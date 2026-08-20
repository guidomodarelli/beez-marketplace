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
- Never log inside a service — logging happens in the handler via `logError`/`logWarning` from `api/logger.ts` (see skill `/logger`).
- Never use sequential or predictable identifiers when generating IDs — use `getRandomUUID()` from `websec-crypto-js`.
- Parallelize independent calls with `Promise.all()`.

---

## Step 4 — Write the test

```ts
import { RestClient } from 'nordic/restclient';
import { getResource } from '../index';

jest.mock('nordic/restclient');

describe('getResource', () => {
  it('returns the resource when the API responds successfully', async () => {
    const mockGet = jest.fn().mockResolvedValue({ data: { id: '1', name: 'test' } });
    (RestClient as jest.Mock).mockImplementation(() => ({ get: mockGet }));

    const result = await getResource('1');

    expect(result).toEqual({ id: '1', name: 'test' });
    expect(mockGet).toHaveBeenCalledWith('/resources/1');
  });

  it('propagates errors from the API', async () => {
    const mockGet = jest.fn().mockRejectedValue(new Error('Network error'));
    (RestClient as jest.Mock).mockImplementation(() => ({ get: mockGet }));

    await expect(getResource('1')).rejects.toThrow('Network error');
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
