---
name: training-in-app-tia
description: Implement and maintain Training in App (TIA) integration in Nordic/Kraken frontends. Use when enabling TIA globally in layout config, overriding TIA behavior per page, embedding the training-in-app remote module, or triggering guided flows with `dispatch('tia:start')`.
---

# Training In App TIA

## Overview

Implement TIA with existing Kraken/Nordic patterns instead of inventing a new integration style. Reuse the same layout keys, remote module wiring, and trigger events already used by other Kraken apps.

## Workflow

1. Detect the existing integration mode in the repo.
   - Run: `rg -n "enableTrainingInApp|trainingInApp|training-in-app|tia:start|useModuleEvent" app config`.
2. Choose the target pattern.
   - Use global layout config for app-wide defaults.
   - Use page override for per-view behavior.
   - Use remote module mount for feature-level onboarding surfaces.
   - Use `dispatch('tia:start')` for explicit start control.
3. Implement with the same key names.
   - Keep `enableTrainingInApp`, `trainingInApp`, `initiative`, `pathName`, and `manualControl` unchanged.
4. Verify behavior.
   - Confirm TIA module renders (if mounted directly).
   - Confirm guided flow starts only under the intended condition.
   - Confirm no regressions in layout/page settings.

## Core Patterns

### Global Layout Defaults

Set defaults in `config/default.js` under `kraken_middlewares_config.layout`:

```js
kraken_middlewares_config: {
  layout: {
    enableTrainingInApp: true,
    trainingInApp: {
      initiative: 'tia-users-shared-initiative',
    },
  },
}
```

Use this when most pages share one initiative or baseline behavior.

### Page-Level Override

Override TIA per route/controller with `krakenViewLayoutOptions`.

Use this for conditional behavior by permission, tab, or user type.

Examples:
- Legacy controller `res.render(..., { krakenViewLayoutOptions: { ... } })`.
- Nordic page `getServerSideProps` returning `settings.krakenViewLayoutOptions`.

### Manual Trigger (`tia:start`)

Use explicit start when training must begin only after a user action or a UI visibility change.

Typical case:
- The modal/component is already mounted in the DOM, but initially hidden by CSS (`display: none`, `visibility: hidden`, hidden state, etc.).
- In that scenario, dispatch `tia:start` when it becomes visible, not when it mounts.

```js
import { useEffect } from 'react';
import { useModuleEvent } from 'frontend-remote-modules';

function TiaVisibilityTrigger({ isModalOpen }) {
  const { dispatch } = useModuleEvent('training-in-app');

  useEffect(() => {
    if (isModalOpen) {
      dispatch('tia:start');
    }
  }, [dispatch, isModalOpen]);

  return null;
}
```

Render `<TiaVisibilityTrigger isModalOpen={isModalOpen} />` from the component that owns the modal state. Combine with `trainingInApp.manualControl: true` to avoid auto-start before the modal is visible.

### Direct Remote Module Mount

Mount the module explicitly for local/feature-level control:

```jsx
<Module
  name="training-in-app"
  host={tiaProps.tiaFrmHost}
  i18n={tiaProps.userLocale}
  user={tiaProps.grootId}
  loadingComponent={() => <></>}
  errorComponent={() => <></>}
  device={tiaProps.device}
  config={{
    initiative: 'tia-permission-collection-initiative',
    pathName: 'permission-collection-to-role-request-button',
  }}
/>
```

Use this pattern when the onboarding belongs to one specific view/component.

## TIA Config Keys

- `enableTrainingInApp`: Enable/disable TIA in layout.
- `trainingInApp.initiative`: Initiative identifier to load.
- `trainingInApp.pathName`: Optional path/step override inside the initiative.
- `trainingInApp.manualControl`: Prevent automatic start and wait for `tia:start`.

## Validation Checklist

1. Search for duplicated/conflicting config in the same render path.
2. Ensure `initiative` value exists for the target flow.
3. If `manualControl` is true, ensure at least one code path dispatches `tia:start`.
4. Ensure TIA host comes from config (`tia_frm_host`) when mounting `<Module />`.
5. Validate page still renders correctly without TIA side effects.

## References

- See [references/tia-patterns.md](references/tia-patterns.md) for concrete snippets and file locations.
