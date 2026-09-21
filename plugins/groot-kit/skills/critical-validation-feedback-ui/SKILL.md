---
name: critical-validation-feedback-ui
description: Ensure critical UI interactions have pre-action validation and clear, visible feedback (errors or helper text), including stale-error cleanup and ErrorUX/CustomErrorUXSnackbar integration. Use when adding or updating forms, searches, navigations, edits, modals, selectors, or async actions to avoid silent failures, misleading previous errors, or incorrect Failure Studio feedback.
---

# Critical Validation and Feedback

## Quick start
Before executing any critical action, validate inputs and state, then show a clear error or helper message next to the triggering control or field. Make feedback visible and actionable.

## Core workflow
1. Identify critical interactions (submit, search, navigation, edit, delete, async load).
2. Define required inputs, allowed states, and blocking conditions.
3. Validate immediately before the action; avoid firing requests when validation fails.
4. Display error or helper feedback inline and near the field or control.
5. Ensure loading and empty states are explicit and not silent.
6. Reset feedback when the user corrects the issue.

## Async error and ErrorUX feedback

Keep validation, operation error, and ErrorUX context as separate state values. When the user changes the selected resource, facility, filter, or operation, clears a modal, starts a new attempt, or retries, clear the previous error message and `ErrorUxContext` before the new request begins. Never leave an error from resource A visible while resource B is loading or ready.

Use `CustomErrorUXSnackbar` only when a real `ErrorUxContext` exists and the failure is actionable or unexpected enough to require Failure Studio/support tracking. Use ordinary `Message`/`Snackbar` for loading, expected domain states, warnings, empty results, and validation feedback. If ErrorUX context is absent, use a safe fallback and do not fabricate context.

ErrorUX detail may contain rich, searchable, sanitized diagnostics and correlation IDs, but never raw conditions, upstream payloads, request/response objects, credentials, tokens, or full PII. Retry callbacks must be safe and must not duplicate a mutation.

Tests must cover: clearing stale errors after changing selection; replacing/clearing context on retry; actionable errors with ErrorUX; unexpected errors without retry; and expected states that never render `CustomErrorUXSnackbar`.

## Guidelines
- **Visibility**: Place feedback adjacent to the field or action; avoid only console logs or toasts for form errors.
- **Specificity**: Explain what failed and how to fix it; avoid vague messages.
- **Critical actions**: Always block the action when validation fails (disable button or prevent handler).
- **Asynchronous flows**: Show loading indicators and handle empty/error states with clear text.
- **Navigation/search**: Validate input (required, format) before routing or querying.
- **Edits**: Validate required fields, minimum lengths, and allowed ranges; show helper text while typing when possible.

## Patterns

### Pre-action validation
```
if (!isValid) {
  setError('Ingresa un termino de busqueda valido');
  return;
}
```

### Inline feedback near action
```
<Button ... />
{error && <Text ...>{error}</Text>}
```

### Loading feedback
```
{isLoading && <Spinner />}
```

## Quick checklist
- Critical actions validate inputs and state before executing.
- Validation failures block the action.
- Error/help text is visible and placed next to the field/action.
- Loading, empty, and error states are explicit.
- Feedback is cleared when the issue is fixed.
