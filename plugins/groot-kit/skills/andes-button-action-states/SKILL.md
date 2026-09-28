---
name: andes-button-action-states
description: Enforce Andes Button action states (disabled/loading) and contextual progress feedback in MELI/Nordic UIs. Use whenever implementing or reviewing submit, search, pagination, fetch, retry, modal confirmation, mutation, or critical async buttons, including flows with stale errors or ErrorUX feedback, so actions cannot duplicate and progress is visible.
metadata:
  tags: "context-optimized-v1.17.1"
---

# Andes Button Action States

## Quick start
For every critical action, disable the Andes Button when the action is invalid or running, and show contextual loading on the button instead of full-screen spinners. Make action availability and system status obvious.

## Core workflow
1. Identify action buttons (submit, search, paginate, fetch, edit, save, delete).
2. Define validation rules and an `isActionValid` state.
3. Track async status with `isLoading` or `requestState`.
4. Bind `disabled={!isActionValid || isLoading}`.
5. Use Andes Button `loading` with `loadingType` determined/indetermined.
6. Provide inline feedback for success or error near the action.

## Guidelines
- **Disabled state**: Always disable buttons while invalid or in-flight to prevent duplicate actions.
- **Contextual loading**: Prefer Andes Button loading over global spinners to keep the rest of the UI usable.
- **Loading type**: Use `loadingType="determinate"` when progress is known; use `loadingType="indeterminate"` for unknown durations.
- **Clarity**: Pair loading with helper or error text near the button or field.
- **Recovery**: Re-enable actions and clear errors once the user fixes the issue or the request completes.
- **Accessibility**: Ensure loading state is conveyed via button state and visible text, not color alone.

## Patterns

### Disabled + loading button
```
<Button
  disabled={!isActionValid || isLoading}
  loading={isLoading}
  loadingType="indeterminate"
>
  {i18n.gettext('Buscar')}
</Button>
```

### Determinate loading
```
<Button
  disabled={!isActionValid || isLoading}
  loading={isLoading}
  loadingType="determinate"
  progress={uploadProgress}
>
  {i18n.gettext('Cargar producto')}
</Button>
```

## Quick checklist
- Buttons are disabled when invalid or loading.
- Andes Button loading is used instead of full-screen spinners.
- `loadingType` matches whether progress is known.
- Users see clear status for errors, success, and loading.
