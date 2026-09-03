---
description: Create a shared logger utility in /api that instantiates nordic/logger with the project name from package.json and exposes logError and logWarning helpers. Use when setting up logging in a Nordic /api folder or when standardizing logger usage across API handlers.
---

# Logger Setup — Nordic `/api`

Creates `api/logger.ts` — a single shared logger instance named after the project, with typed helpers for error and warning logs.

---

## Step 1 — Check prerequisites

```bash
# Verify package.json exists and has a name field
node -e "const p = require('./package.json'); if (!p.name) throw new Error('Missing name in package.json');"
```

If the command fails, ask the user to add a `name` field to `package.json` before continuing.

---

## Step 2 — Check if logger already exists

```bash
test -f api/logger.ts && echo "EXISTS" || echo "MISSING"
```

If the file exists, report it and stop:
> "`api/logger.ts` already exists — skipped."

---

## Step 3 — Create `api/logger.ts`

```bash
mkdir -p api
```

Create the file with this exact content:

```ts
import { Logger } from 'nordic/logger';
import { name } from '../package.json';

type Tags = Record<string, string | number | boolean | undefined | null>;

const logger = new Logger(name);

export const logError = (message: string, tags?: Tags): void => {
  logger.error(message, tags);
};

export const logWarning = (message: string, tags?: Tags): void => {
  logger.warn(message, tags);
};
```

---

## Step 4 — Verify

```bash
tsc --noEmit
npm run lint
```

Fix any errors before reporting success.

---

## Step 5 — Report

Show the created file path and a usage example:

```ts
import { logError, logWarning } from '../logger';

try {
  const product = await getProduct(req.params.id);
  res.json(product);
} catch (error) {
  logError(`[PRODUCT-GET] - error: ${error instanceof Error ? error.message : String(error)}`, { productId: req.params.id });
  const publicError = mapKnownErrorToHttpResponse(error);
  res.status(publicError.statusCode).json({ error: publicError.message });
}
```

`mapKnownErrorToHttpResponse` is a project-level typed error mapper: known client/domain causes must become the corresponding 4xx response, while unexpected failures follow the error policy in `../../rules/security.md` and must not be disguised as a known client error.

Convention for the `message` string: `[FEATURE-DASH-SEPARATED] - error: description`.
