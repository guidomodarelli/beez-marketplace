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
      dispatch('tia:start');
    }
  }, [dispatch, isModalOpen]);

  return null;
}
```

Render `<TiaVisibilityTrigger isModalOpen={isModalOpen} />` from the component that owns the modal state.

Alternative condition-based trigger:

```js
if (hasDistributedApproval) {
  dispatch('tia:start');
}
```

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
rg -n "name=\"training-in-app\"|name='training-in-app'" app
```
