# Security Rules — Frontend (Nordic + React + TypeScript)

Baseline security rules for Nordic applications. These rules are always active and condition all code generation. The `security-scanner` agent uses this file as supplementary context alongside `meli_appsec_codeguard` MCP findings.

---

## Secrets & PII

- Never hardcode secrets, tokens, or API keys — use `node-melitk-secrets` for Fury Secrets Service.
- Never log PII (emails, IDs, addresses) or credentials — use `nordic/logger` with `node-data-privacy-toolkit` to truncate/obfuscate if logging is needed.
- Never receive PII or tokens via query parameters — use request body.
- Never expose sensitive data in React state, Redux, or Context — keep it server-side only.

## Input Validation

- Validate all external inputs (body, query params, path params, headers) at the controller/handler level using `@meli/input-validation`.
- Use allowlist strategy — define what is permitted, reject everything else.
- Never trust user-provided identifiers directly — retrieve user identity from session or JWT claims.

## XSS Prevention

- Never use `dangerouslySetInnerHTML` with untrusted content — use `DOMPurify` if HTML rendering is required.
- Never inject raw JSON or JS objects into HTML responses — use `@nordic/utils/serialize`.
- Never weaken or bypass Content Security Policy (CSP).

## HTTP & Outbound Calls

- Use `nordic/restclient` for all external HTTP calls.
- Never pass user-controlled input directly to `fetch`, `axios`, or `http.request` — validate destinations against a static allowlist.
- Never use GET for state-modifying operations.
- Never configure CORS without formal security review — never use wildcards (`*`).

## Secure Coding

- Never use `Math.random()` — use `crypto.randomBytes()` or `crypto.randomInt()` from `node:crypto`.
- Never use sequential or predictable identifiers (auto-increment, UUID v1/v6/v7, timestamp-based) — use `getRandomUUID()` from `websec-crypto-js`.
- Never use string concatenation for SQL queries — use parameterized queries or ORM.
- Never use `eval()`, `Function()`, or `setTimeout`/`setInterval` with strings.
- Never use deprecated crypto (MD5, SHA1, DES, RC4) — use AES-256, SHA-256, RSA-2048+.
- Never use regexes with exponential complexity on user input — validate for ReDoS resistance.

## Error Handling

- Never expose stack traces or internal error details to users — return generic messages.
- Never log sensitive data in error handlers.

## Authorization

- Use `@platsec-security/authz` + `@platsec-security/identity` for all new auth/authz implementations.
- Always validate that user actions follow valid business workflows server-side.
- Never enforce critical business logic validations from user-controlled input.
