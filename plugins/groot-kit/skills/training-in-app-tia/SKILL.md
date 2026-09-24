---
name: training-in-app-tia
description: Implement and maintain Training in App (TIA) integration in Nordic/Kraken frontends. Use when enabling TIA globally in layout config, overriding TIA behavior per page, embedding the training-in-app remote module, triggering guided flows with `dispatch('tia:start')`, tagging an element as a coach mark target, or debugging a TIA tour that does not start, points at the wrong element, or shows a shifted highlight inside a modal or scroll container.
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
   - Use `dispatch('tia:start', { pathName })` for explicit start control.
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
- The target element only exists after a step or user action (second modal step, first item added to a list).
- In that scenario, dispatch `tia:start` when the target becomes visible, not when the page or modal mounts. A coach mark needs its target element in the DOM.

```js
import { useEffect } from 'react';
import { useModuleEvent } from 'frontend-remote-modules';

function TiaVisibilityTrigger({ isModalOpen }) {
  const { dispatch } = useModuleEvent('training-in-app');

  useEffect(() => {
    if (isModalOpen) {
      dispatch('tia:start', { pathName: 'my-feature-path' });
    }
  }, [dispatch, isModalOpen]);

  return null;
}
```

Render `<TiaVisibilityTrigger isModalOpen={isModalOpen} />` from the component that owns the modal state. Combine with `trainingInApp.manualControl: true` to avoid auto-start before the modal is visible.

#### Choose the path with `pathName`, never with the path name in `pathKey`

`tia:start` and `tia:reset` resolve the path from `event.detail`, checked in this order:

| Detail field | Matched against | Value to send |
| --- | --- | --- |
| `pathKey` | `path.key` | The UUID TIA generates for the path (for example `01a0d471-…`), not the name you typed in TIA |
| `pathName` | `path.name` | The path name configured in TIA (for example `my-feature-summary`) |
| `initiativeKey` | `path.initiativeKey` | Initiative key |
| `krakenApplication` | `path.applicationName` | Application name |

- Send `{ pathName: '<name configured in TIA>' }`. Sending the name as `pathKey` matches nothing, and the tour silently never starts.
- Without `detail`, TIA starts the first pending path of the initiative, which is only safe when the initiative has a single path for the page.
- When one page has several paths (one per element), dispatch one `tia:start` per path, each from the component that renders its target, with its own `pathName`.

#### Pending versus seen paths

- `tia:start` only searches the user's `pendingPaths`. Once the user finished or dismissed a path, TIA returns it in `notPendingPaths` (`"pending": false`) and `tia:start` no longer shows it. This is expected for real users.
- `tia:reset` searches `notPendingPaths`, so it re-shows an already seen path. Use it for manual QA from the browser console instead of adding a reset to product code:

```js
document.dispatchEvent(
  new CustomEvent('module:training-in-app:tia:reset', { detail: { pathName: 'my-feature-path' } })
);
```

### Tag the Target Element

TIA coach mark steps point at a CSS selector configured in TIA, so the frontend must expose a stable anchor:

- Add a stable `id` to the target element (for example `id="my-feature-summary"`); do not rely on generated classes, Andes internals, or text.
- Keep the `id` unique. When the element repeats (a button per list item), give the `id` to exactly one instance (for example the first actionable one) and move it when that instance stops being actionable.
- Start the path from the component that renders the anchor, so the event fires only when the anchor exists.
- Share the dispatch in a small hook when the repo has more than one trigger, and pass the path name or `null` instead of a boolean flag:

```js
export const useTrainingInAppStart = (pathName) => {
  const { dispatch } = useModuleEvent('training-in-app');

  useEffect(() => {
    if (pathName) {
      dispatch('tia:start', { pathName });
    }
  }, [dispatch, pathName]);
};

// In the component that renders the anchor:
useTrainingInAppStart(hasSummaryItems ? 'my-feature-summary' : null);
```

### Targets Inside a Scroll Container

Coach marks position the spotlight once and follow window scroll only. When the target lives inside a scrollable container (a modal body such as `.andes-modal__scroll`, a drawer, a scrollable panel) and may be off-screen, bring it into view before the path starts:

- Scroll the target with `scrollIntoView({ block: 'center' })` using the default instant behavior. A `smooth` scroll is still moving when TIA measures the target, so the highlight lands shifted.
- Run the scroll before the start: declare the scroll effect before the start hook in the same component, since React runs effects in declaration order.
- When the target appears because the user added an item, scroll to the newly added item, which is also where the user is looking.

See [references/tia-patterns.md](references/tia-patterns.md#target-inside-a-scroll-container) for the snippet.

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
- `trainingInApp.manualControl`: Prevent automatic start and wait for `tia:start`. With manual control, the path started is the one in the event detail, not the layout `pathName`.
- `trainingInApp.pathKey`: Optional path id (TIA-generated UUID). Do not confuse it with `pathName`.

## Validation Checklist

1. Search for duplicated/conflicting config in the same render path.
2. Ensure `initiative` value exists for the target flow.
3. If `manualControl` is true, ensure at least one code path dispatches `tia:start`, with `{ pathName }` when the initiative has more than one path.
4. Ensure every `pathName` sent in an event matches the path name configured in TIA, and that no path name is sent as `pathKey`.
5. Ensure each coach mark target has a stable, unique `id` and that the path starts only after that element is rendered.
6. Ensure TIA host comes from config (`tia_frm_host`) when mounting `<Module />`.
7. Validate page still renders correctly without TIA side effects.
8. Cover the trigger with a test that listens to the real `module:training-in-app:tia:start` event on `document` and asserts its `detail`, instead of mocking `frontend-remote-modules`.

## Debugging a Tour That Does Not Show

Check these in order before changing code:

1. **Event:** confirm `module:training-in-app:tia:start` fires with the expected `detail.pathName` when the target appears.
2. **Environment:** the layout loads TIA from the host of the current environment. Local development uses the sandbox TIA (`tiafrm-sandbox.adminml.com`), so the path must exist there, not only in production.
3. **Paths response:** inspect `POST <tia host>/api/tia/initiatives/<initiative>/paths?user=<grootId>`. An empty `pendingPaths` and `notPendingPaths` means the initiative exposes no path to that user: check that the path is published, belongs to that initiative, has a route pattern for the page, and has an audience that includes the user's attributes (sent in the request body).
4. **Seen path:** if the path is in `notPendingPaths`, the user already saw it; relaunch it with `tia:reset` for QA.
5. **Shown or not:** after `tia:start`, `module:training-in-app:tia:onChangeState` with `render` and `start` means TIA showed the path; no state change and an empty `#tia-widget-container` means it found no matching pending path.
6. **Misplaced highlight:** if the spotlight has the target's size but is shifted, the target is inside a scroll container (for example `.andes-modal__scroll`) whose scroll changed after the coach mark was positioned. Compare the offset with that container's `scrollTop`, and apply [Targets Inside a Scroll Container](#targets-inside-a-scroll-container).

See [references/tia-patterns.md](references/tia-patterns.md#runtime-debug-signals) for a script that records every TIA event.

## References

- See [references/tia-patterns.md](references/tia-patterns.md) for concrete snippets and file locations.
- Event resolution (`pathKey`, `pathName`, pending and seen paths) comes from `useTIAEvents` in the `quimera-tia-frm-provider` `training-in-app` remote module.
