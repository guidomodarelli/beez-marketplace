# Security Scanner Agent — Frontend (Nordic + React + TypeScript)

Scan the current changes for security vulnerabilities specific to the Nordic + React + TypeScript stack.

## Scope

Run this agent when reviewing a diff, a PR, or a specific file. Focus only on vulnerabilities — not style, not performance.

---

## Checklist

### XSS
- [ ] `dangerouslySetInnerHTML` used with untrusted content → must use `DOMPurify`
- [ ] Raw JSON or JS objects injected into HTML responses → must use `@nordic/utils/serialize`
- [ ] Any code that weakens or bypasses CSP

### Input Validation
- [ ] External inputs (body, query params, path params, headers) validated with `@meli/input-validation`
- [ ] Allowlist strategy used (not denylist)
- [ ] User-provided identifiers trusted directly without server-side verification

### Secrets & PII
- [ ] Secrets, tokens, or API keys hardcoded in code or config → must use `node-melitk-secrets`
- [ ] Sensitive data logged → must sanitize with `nordic/logger` or `node-data-privacy-toolkit`
- [ ] PII or tokens received via query parameters → must use request body
- [ ] Sensitive data exposed in React state, Redux, or Context (client-side) → must stay server-side

### HTTP & Outbound Calls
- [ ] External HTTP calls not using `nordic/restclient`
- [ ] User-controlled input passed directly to `fetch`, `axios`, or `http.request` → validate against static allowlist
- [ ] GET used for state-modifying operations
- [ ] Custom security headers defined at app level (CSP, HSTS, X-Frame-Options) → must use centrally managed headers
- [ ] CORS configured without formal security review → never use wildcards

### Secure Coding
- [ ] `Math.random()` used anywhere → must use `crypto.randomBytes()` or `crypto.randomInt()`
- [ ] Sequential or predictable identifiers (auto-increment, UUID v1/v6/v7, timestamp-based) → must use `getRandomUUID()` from `websec-crypto-js`
- [ ] SQL string concatenation → must use parameterized queries or ORM
- [ ] `eval()`, `Function()`, `setTimeout`/`setInterval` with strings → remove or sandbox
- [ ] Deprecated crypto (MD5, SHA1, DES, RC4) → must use AES-256, SHA-256, RSA-2048+
- [ ] Regex with exponential complexity on user input → validate for ReDoS resistance

### Error Handling
- [ ] Stack traces or internal error details exposed to users → must return generic messages
- [ ] Sensitive data logged in error handlers

### Authorization
- [ ] New auth/authz not using `@platsec-security/authz` + `@platsec-security/identity`
- [ ] User identity retrieved from user-controlled input instead of session/JWT claims
- [ ] Business logic validations enforced client-side only → must be server-side

---

## Output format

```
## Security Scan

### Critical
- [file:line] Vulnerability — CWE — Fix: ...

### High
- [file:line] Issue — Fix: ...

### Informational
- [file:line] Note — no immediate action required.

### Clean
- No issues found.
```

Severity scale: **Critical** = exploitable with direct impact (XSS, secrets exposed, auth bypass). **High** = likely exploitable under certain conditions. **Informational** = patterns to watch, no confirmed exploit path.
