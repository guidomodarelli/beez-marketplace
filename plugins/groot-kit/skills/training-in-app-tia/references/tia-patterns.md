# TIA Patterns (Kraken/Nordic)

## Scope

Use these snippets as known-good patterns for Training in App (TIA) integration.

## Global Layout Config

File:
- `/app/config/default.js`

Pattern:

```js
kraken_middlewares_config: {
  layout: {
    enableTrainingInApp: true,
    trainingInApp: {
      initiative: 'tia-users-shared-initiative',
    }
  },
}
```

## Per-Page Override in Legacy Controller

File:
- `/app/pages/.../controller.js`

Pattern:

```js
let tiaKrakenViewLayoutOptions = {
  initiative: 'tia-users-shared-initiative',
};

if (!loggedUserCanExecuteLeaderChangeProcess || req?.query?.tab === 'events') {
  tiaKrakenViewLayoutOptions = {
    ...tiaKrakenViewLayoutOptions,
    pathName: 'user-events-details',
  };
}

res.render(UserFormView, {
  krakenViewLayoutOptions: {
    trainingInApp: tiaKrakenViewLayoutOptions,
  },
});
```

## Conditional Enablement by Business Rule

File:
- `/app/pages/.../controller.js`

Pattern:

```js
const enabledTIA = users?.results?.some(user => user.ldap_user?.startsWith('ext_'));
const enableTrainingInApp = enabledTIA;
const trainingInApp = enabledTIA ? { initiative: 'tia-users-silos-initiative' } : null;

res.render(UsersSiloView, {
  krakenViewLayoutOptions: {
    enableTrainingInApp,
    trainingInApp,
  },
});
```

## SSR/Nordic Settings Pattern

File:
- `/app/nordic-pages/.../index.js`

Pattern:

```js
return {
  props: { ... },
  settings: {
    krakenViewLayoutOptions: {
      enableTrainingInApp: true,
      trainingInApp: {
        initiative: 'tia-role-general-config-initiative',
        manualControl: !tiaEnabledFromBeginning,
      },
    },
  },
};
```

## Manual Trigger (`tia:start`)

File:
- `/app/nordic-pages/.../ui-components/.../index.js`

Use this pattern when the component is mounted but hidden at first (for example, a modal hidden by CSS/state). Dispatch `tia:start` when the component becomes visible.

Pattern:

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

Render `<TiaVisibilityTrigger isModalOpen={isModalOpen} />` from the component that owns the modal state.

Alternative condition-based trigger:

```js
if (hasDistributedApproval) {
  dispatch('tia:start', { pathName: 'distributed-approval-path' });
}
```

`pathName` is the path name configured in TIA. Do not send it as `pathKey`: TIA matches `pathKey` against the generated path id (UUID), so the tour never starts. Without `detail`, TIA starts the first pending path of the initiative.

## Several Paths on One Page (Nordic, manual control)

Files:
- `/app/hooks/use-training-in-app-start.ts`
- `/app/nordic-pages/<page>/index.tsx`
- `/app/nordic-pages/<page>/ui-components/<Component>/index.tsx`

Enable TIA with manual control in the page settings, then start each path from the component that renders its anchor:

```ts
// index.tsx — getServerSideProps settings
krakenViewLayoutOptions: {
  enableTrainingInApp: true,
  trainingInApp: {
    initiative: 'tia-my-feature-initiative',
    pathName: 'my-feature-summary',
    manualControl: true,
  },
},
```

```tsx
// Component that owns the first anchor
useTrainingInAppStart(hasSummaryItems ? 'my-feature-summary' : null);

return <section id="my-feature-summary">…</section>;
```

```tsx
// Repeated item: only one instance receives the anchor id and starts the second path
useTrainingInAppStart(actionButtonId ? 'my-feature-item-action' : null);

return <Button id={actionButtonId}>…</Button>;
```

Each path in TIA points its step at the matching `#id`.

## Target Inside a Scroll Container

Coach marks measure the target once and follow window scroll, not the scroll of an inner container such as a modal body (`.andes-modal__scroll`) or a scrollable panel. Bring the target into view before the path starts:

```tsx
// Item the user just added; it also owns the anchor of its TIA path
const itemRef = useRef<HTMLLIElement>(null);

// Declared before the start hook: effects run in order, so TIA measures the target after the scroll.
useEffect(() => {
  if (isLatestAddition) {
    itemRef.current?.scrollIntoView?.({ block: 'center' });
  }
}, [isLatestAddition]);

useTrainingInAppStart(actionButtonId ? 'my-feature-item-action' : null);
```

- Use an instant scroll (default `behavior`), not `smooth`: a smooth scroll is still moving when TIA positions the spotlight.
- Center the target (`block: 'center'`) so the tooltip has room above or below it.
- jsdom does not implement `scrollIntoView`. The optional call keeps component tests that do not care about scrolling from crashing; tests that assert the scroll define it (see below).

## QA: Re-show an Already Seen Path

`tia:start` ignores paths the user already saw (`notPendingPaths`). Relaunch one from the browser console:

```js
document.dispatchEvent(
  new CustomEvent('module:training-in-app:tia:reset', { detail: { pathName: 'my-feature-summary' } })
);
```

## Test the Trigger Without Mocks

```tsx
test('starts the TIA path once its target is shown', () => {
  const handleTiaStart = jest.fn();

  document.addEventListener('module:training-in-app:tia:start', handleTiaStart);
  render(<ComponentWithAnchor />);

  expect(handleTiaStart.mock.calls[0][0].detail).toEqual({ pathName: 'my-feature-summary' });

  document.removeEventListener('module:training-in-app:tia:start', handleTiaStart);
});
```

To check the order against a scroll, record both in one array: define `HTMLElement.prototype.scrollIntoView` as a recording function in the test (jsdom does not implement it), listen to `tia:start`, and assert `['scroll', 'tia:<pathName>']`. Delete the property after the test.

## Runtime Debug Signals

Record every TIA event from the browser before reproducing the flow (Chrome DevTools init script or console):

```js
const originalDispatch = Document.prototype.dispatchEvent;
window.__tiaEvents = [];
Document.prototype.dispatchEvent = function (event) {
  if (String(event.type).startsWith('module:training-in-app')) {
    window.__tiaEvents.push({ type: event.type, detail: event.detail ?? null });
  }
  return originalDispatch.call(this, event);
};
```

- `module:training-in-app:tia:start` with the expected `detail` means the frontend did its part.
- `module:training-in-app:tia:onChangeState` with `render` and then `start` means TIA found the path and showed it. A `tia:start` without these means TIA had no matching pending path.
- `#tia-widget-container` is where the module renders; an empty container after `tia:start` confirms nothing was shown.
- The layout requests `POST <tia host>/api/tia/initiatives/<initiative>/paths?user=<grootId>`; its `pendingPaths` and `notPendingPaths` tell whether the path exists for that user and whether it was already seen.

## Direct Module Usage (`training-in-app`)

File:
- `/app/nordic-pages/.../ui-components/.../index.js`

Pattern:

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
    pathName: 'permission-collection-to-role-request-flow',
  }}
/>
```

## Discovery Commands

```bash
rg -n "enableTrainingInApp|trainingInApp" config app
rg -n "useModuleEvent\\('training-in-app'\\)|tia:start" app
rg -n "tia:start.*pathKey|pathKey:.*tia-|pathKey: '[a-z-]+'" app
rg -n "name=\"training-in-app\"|name='training-in-app'" app
```
