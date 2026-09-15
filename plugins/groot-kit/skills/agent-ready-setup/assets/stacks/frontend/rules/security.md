# Security Rules — Frontend (Nordic + React + TypeScript)

Baseline security rules for Nordic applications. These rules are always active and condition all code generation. The `security-scanner` agent uses this file as supplementary context alongside `meli_appsec_codeguard` MCP findings.

---

## Secrets & PII

- Never hardcode secrets, tokens, or API keys — use `node-melitk-secrets` for Fury Secrets Service.
- Never log PII (emails, IDs, addresses) or credentials — use `nordic/logger` with `node-data-privacy-toolkit` to truncate/obfuscate if logging is needed.
- Never receive PII or tokens via query parameters — use request body.
- Never expose sensitive data in React state, Redux, or Context — keep it server-side only.

## Input Validation

- Middleend endpoints must validate all untrusted client-controlled request inputs (body, query params, path params, headers) at the controller/handler boundary using `@meli/input-validation`.
- Never revalidate payloads received from backend/upstream services; they are response data, not client input. Consume them according to the adapter contract instead of adding a second validation step.
- Never validate the complete format or contract of a backend/upstream success payload or error payload at runtime. Do not add a schema, allowlist, field-by-field check, type guard, or error-shape parser for the provider response.
- Use only minimal structural narrowing when it changes control flow or enables safe access: HTTP status or transport metadata, `null` versus `array` versus `object`, or a minimum discriminator such as `PROCESSING` or `FINISHED`. This narrowing is not upstream contract verification and must not become a complete field allowlist.
- If an upstream response cannot be consumed, map a controlled failure at the adapter or service boundary without forwarding the raw payload or introducing full contract validation.
- Whenever code needs to validate a variable, function argument, method argument, or intermediate value that is not a backend/upstream response payload, prefer `@meli/input-validation` over native validation.
- If `@meli/input-validation` cannot express the complete requirement, keep it as the primary validation and add only the narrowly scoped native checks that are still necessary, such as `Number.isSafeInteger`.
- Use allowlist strategy for client-controlled inputs and public middleend DTOs — define what is permitted, reject everything else.
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

Treat the middleend as a translation boundary: convert known client- or domain-caused failures into the public HTTP contract instead of leaking upstream error statuses.

- Never return a 5xx from a middleend when the cause is known and attributable to the request or domain state. Return the corresponding 4xx: `400` for malformed requests, `401` for missing or invalid authentication, `403` for insufficient permissions, `404` for missing resources, `409` for state conflicts, or `422` for semantically invalid or unprocessable input.
- Do not use a generic `500`, `502`, or `503` fallback for a known client/domain error. Preserve a safe public message and log the diagnostic cause server-side without exposing internals.
- Do not classify hydration or partial-attribute failures by symptom alone. First identify the origin: when client-controlled input or domain state caused incomplete attributes, map the cause to its applicable 4xx at the middleend boundary; `422` is often appropriate when the request is semantically unprocessable. When transport/status metadata or the adapter identifies an upstream dependency failure, treat it as a dependency failure and map it to the appropriate 5xx (often `502`) instead of blaming the client; do not validate the full upstream success or error payload to make that classification.
- Reserve 5xx responses for genuinely unexpected middleend failures or dependency failures surfaced by transport/status metadata or adapter classification. If the adapter cannot consume an upstream response, map a controlled dependency failure at that boundary; never use 5xx as a shortcut for client/domain error mapping and never introduce full upstream contract validation.
- Never expose stack traces or internal error details to users — return generic messages.
- Never log sensitive data in error handlers.

## Authorization

- Use `@platsec-security/authz` + `@platsec-security/identity` for all new auth/authz implementations.
- Always validate that user actions follow valid business workflows server-side.
- Never enforce critical business logic validations from user-controlled input.
