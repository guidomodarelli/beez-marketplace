# API Configuration Rules — Nordic

How Nordic API endpoints and services receive upstream configuration such as scopes.

- Never add or forward `scope` as a query parameter (`?scope=...`, `params: { scope: ... }`, or equivalent URL construction). API scope belongs to client configuration, not request URLs.
- When an upstream client requires a scope, add a service-specific key to the existing environment files under `config/` (typically `config/local.js`, `config/default.js`, `config/default-production.js`, and `config/sandbox.js`) and consume it through `nordic/config` or the client option designed for configured scopes (for example, `scopeConfig`). Do not create a new config file solely for scope. Never hardcode environment values such as `sandbox` or `prod` in service code.
- Keep scope values in those existing `config/` files; do not duplicate them in services or handlers.
