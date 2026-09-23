# Mocking Strategy — Frontend Tests vs Service Tests

Tests are split into two contexts with different mocking strategies. Apply the rules for the context you are in.

---

## Context 1: Frontend / Component Tests

Tests for React components, pages, and UI logic.

**Strategy: mock internal services; use Nordic provider defaults; never mock the component libraries or platform packages listed in `testing.md`.**

### Mock the services the component depends on

Components call services to fetch data. Those services must be mocked so the test controls what the component receives:

```js
// app/ui-components/user-card/__tests__/user-card.spec.jsx
import { render, screen } from '@testing-library/react';
import { NordicTestProviders } from 'nordic-dev/testing-tools';

import { UserCard } from '../index';
import * as userService from '../../../../src/services/user';

jest.spyOn(userService, 'getUser').mockResolvedValue({ id: 1, name: 'Ada' });

test('shows user name', async () => {
  render(
    <NordicTestProviders>
      <UserCard userId="1" />
    </NordicTestProviders>,
  );

  expect(await screen.findByText('Ada')).toBeInTheDocument();
});
```

---

## Context 2: Service Tests

Tests for service functions that call external APIs via `nordic/restclient`.

**Strategy: no mocks — let the service make real HTTP calls intercepted by `nordic-dev/mocks`.**

### How it works

`nordic-dev/mocks` intercepts Node's `http.request`/`https.request` at the transport level. On the first run it proxies to the real API and saves the response as a JSON fixture. Subsequent runs replay the fixture — no network needed, no mocking required.

This means service tests exercise the real service code (URL building, response parsing, error handling) against realistic API responses.

### Setup — directly in the test file

Register interceptors inside the test file using `beforeAll`/`afterAll`. No global config or server-side wiring needed:

```js
// services/__tests__/user.spec.js
import { config } from 'nordic/config';
import { Mock } from 'nordic-dev/mocks';
import { getUser } from '../user';

const baseUrl = config.get('restclient.baseUrl'); // e.g. 'https://internal-api.mercadolibre.com'

let mock;

beforeAll(() => {
  mock = Mock();
  mock.intercept(baseUrl, ['/users/*'], {
    ignoreParams: ['access_token', 'caller.id', 'scope'],
  });
});

afterAll(() => {
  mock.restore(baseUrl);
});

test('returns user data', async () => {
  const user = await getUser('1');

  expect(user.id).toBe(1);
  expect(user.name).toBeDefined();
});
```

Fixture files are auto-created at `mocks/{NODE_ENV}/{method}/{proto}/{host}/{path}.json` on the first run. Commit them to the repo so CI runs without network access.

### When service mocks are acceptable

Only mock a service dependency when:

- The dependency is **another internal service** (not an HTTP call) with side effects that would break test isolation (e.g., a service that writes to a queue or triggers a notification).
- The test needs to assert behavior under a **specific error condition** that cannot be represented as a fixture file (for example, a transport failure without an HTTP response). HTTP error statuses such as 500 or 404 are always covered with a fixture file.

### Creating error scenario fixtures manually

Instead of mocking, create the fixture JSON for the error case:

```json
// mocks/test/get/https/internal-api.mercadolibre.com/users/not-found.json
{
  "status": 404,
  "statusText": "Not Found",
  "headers": { "content-type": "application/json" },
  "data": { "message": "User not found", "error": "not_found" }
}
```

---

## Quick Reference

| Test type | Mock services? | Mock Nordic contexts? | Mock HTTP? |
|-----------|----------------|----------------------|------------|
| Component / UI | Yes — `jest.spyOn` on services | No | Never directly |
| Service | No | No | Never — use `nordic-dev/mocks` fixtures |

---

## References

- `nordic-dev/mocks` — HTTP interceptor for service tests
- `references/nordic/v9/pages/03-mocks.md` (via frontender-web-mcp)
