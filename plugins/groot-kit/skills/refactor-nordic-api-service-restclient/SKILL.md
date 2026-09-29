---
name: refactor-nordic-api-service-restclient
description: Implements or updates API-only service flows in nordic kraken-* repos, from services/ to api/ routes to app/hooks restclient hooks (the client calls the hook, not the service). Use whenever adding or changing BFF service methods, /api/ routes, server hooks, restclient calls, request/response DTOs, upstream error mapping, or the client hook that calls a Nordic API.
metadata:
  tags: "context-optimized-v1.17.2"
---

# API Service Restclient Hook

## Quick start
Follow the repo pattern where server-only services are exposed through `api/` routes and consumed by client-side hooks in `app/hooks`.

## Workflow
1. Confirm the pattern applies.
   - `rg "@services/<name>"` should show only `api/` and server files (no `app/` client components).
   - Match the `api/index.js` mount path to the hook `baseURL`.
2. Implement or update the service.
   - Add or update `services/<name>.js` and call a restclient from `services/restclients/`.
   - Accept `req` and pass headers via `headersFromReq(req)` (or an equivalent utility).
   - Normalize shared params (arrays, paging, filters) in the service.
   - Return `response.data`.
3. Implement or update the API route.
   - Add the route in `api/<feature>.js` with `nordic/ragnar`.
   - Apply authorization and schema validation middlewares before the handler.
   - Parse `req.params`/`req.query`, apply defaults from `api/constants.js`, then call the service.
   - Respond with `res.send`/`res.json`.
   - On failure, log with `nordic/logger` including endpoint + method, then forward safe `err.response.status` and `err.response.data`.
   - Register any new router in `api/index.js`.
4. Implement or update the client hook.
   - Add the method to the correct hook file in `app/hooks/` (or create a new hook if the `baseURL` differs).
   - Use `nordic/restclient` for standard pages; use `frontend-remote-modules` `useRestClient` for FRM features.
   - Ensure `baseURL` matches the router prefix and include `X-Requested-With: XMLHttpRequest` plus timeout.
   - Return `data` from the restclient response; normalize params to match API expectations (arrays to comma strings, 1-based to 0-based page).
   - Export the hook from `app/hooks/index.js` when it is shared.
5. Consume from the client.
   - Use the hook in React code; do not import services in client components.

## Guardrails
- Keep services server-only; they depend on `req` and server auth headers.
- Keep hooks thin; add validation/logging only when needed.
- Add or update tests when hook logic goes beyond direct restclient calls.

## References
- See [repo-pattern.md](references/repo-pattern.md) for file mappings and examples.
