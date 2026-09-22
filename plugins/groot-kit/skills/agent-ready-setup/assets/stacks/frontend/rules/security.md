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
- Prefer a safe fallback before structural narrowing when absence, `null`, `undefined`, or an intentionally empty value can use an adapter-approved default. Use `??` for nullish fallback and `||` only when every falsy value is intentionally equivalent to absence; never use a fallback that fabricates authorization, eligibility, ownership, success, or provider facts.
- Use structural narrowing only when it changes control flow or enables safe access and no safe fallback exists. Valid examples are HTTP status or transport metadata, `null` versus `array` versus `object`, or a minimum discriminator such as `PROCESSING` or `FINISHED`. This narrowing is not upstream contract verification and must not become a complete field allowlist, type guard, or error-shape parser.
- Never add a `normalize*Response`/`parse*Response` helper, response-shape guard, field-by-field response validator, or client-error throw solely because an upstream or backend response differs from an expected shape. Apply approved defaults first; narrow only to choose a flow or avoid unsafe access.
- If an upstream response cannot be consumed after safe fallback and the minimum flow discriminator is unavailable, continue with the adapter's safe empty/default projection when the contract permits it; otherwise map a controlled integration failure without forwarding the raw payload or introducing full contract validation.
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

Treat the middleend/BFF as an error-origin boundary: preserve statuses received from upstream, and translate only failures owned by the BFF into its public HTTP contract.

- Preserve the HTTP status received from upstream, including upstream 4xx and 5xx. The BFF may sanitize or adapt the public error body, but must not replace an upstream status with a BFF-owned status merely because the payload is being translated.
- For failures owned by the BFF and attributable to the request or domain state, return the corresponding 4xx: `400` for malformed requests, `401` for missing or invalid authentication, `403` for insufficient permissions, `404` for missing resources, `409` for state conflicts, or `422` for semantically invalid or unprocessable input.
- For failures owned by the BFF that are genuinely unexpected or internal, return an appropriate 5xx. Use `502`/`504` for integration failures such as an upstream transport failure, timeout, or response without a usable HTTP status; choose the status according to the failure cause.
- Do not use a generic 5xx fallback for a known BFF client/domain error, and do not convert an upstream 4xx into a BFF 5xx. Preserve a safe public message and log the diagnostic cause server-side without exposing internals.
- Do not classify hydration or partial-attribute failures by symptom alone. First identify the origin: when client-controlled input or domain state caused incomplete attributes, map the cause to its applicable BFF-owned 4xx; when upstream transport/status metadata or adapter classification identifies a dependency failure, preserve the upstream status or map a no-status integration failure to the appropriate 5xx. Do not validate the full upstream success or error payload to make that classification.
- If the adapter cannot consume an upstream response, map a controlled integration failure at that boundary without forwarding the raw payload or introducing full upstream contract validation.
- Keep upstream status reporting truthful in every diagnostic artifact (ErrorUX details, structured logs, metrics): report only the real HTTP status returned by the upstream dependency, and report `unknown` when the dependency returned no status. A BFF-synthesized `503`/`504` chosen as the public response status is never the upstream status and must not be labeled as one; when the BFF owns a status mapping, keep it separate from the reported upstream status so diagnostics never invent upstream facts.
- Never expose stack traces or internal error details to users — return generic messages.
- Never log sensitive data in error handlers.

## Authorization

- Use `@platsec-security/authz` + `@platsec-security/identity` for all new auth/authz implementations.
- Always validate that user actions follow valid business workflows server-side.
- Never enforce critical business logic validations from user-controlled input.
