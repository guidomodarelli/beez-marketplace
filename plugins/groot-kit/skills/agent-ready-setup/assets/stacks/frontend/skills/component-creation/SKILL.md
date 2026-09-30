---
name: component-creation
description: Create a React component following team conventions with Andes UI and Nordic. Use when asked to create a component, widget, or UI element.
metadata:
  tags: "context-optimized-v1.18.0"
---

# Component Creation — Frontend (Nordic + React + Andes)

Step-by-step guide for creating a React component following team conventions.

---

## Step 1 — Define scope

Before writing code, answer:
- What does this component display or do?
- Does it need server-side data? → If yes, the data comes from a server hook, not fetched inside the component.
- Does Andes already have a component for this? → Consult `frontender-web-mcp` (`andes-components` tool) first.
- Is it reusable across multiple pages? → `app/ui-components/<component-name>/`
- Is it specific to a single page? → `app/nordic-pages/<page>/<component-name>/`

---

## Step 2 — Create the directory

Use the location decided in Step 1:

```
# Reusable component
app/ui-components/<component-name>/
├── index.tsx
└── styles.scss   ← only if custom styles are needed

# Page-specific component
app/nordic-pages/<page>/<component-name>/
├── index.tsx
└── styles.scss   ← only if custom styles are needed
```

Use PascalCase for component names and kebab-case for directories and filenames. One component per file — `index.tsx` exports only `<ComponentName>`.

---

## Step 3 — Write the component (`index.tsx`)

```tsx
interface <ComponentName>Props {
  // Declare all props explicitly — no rest props (...rest)
}

export function <ComponentName>({ }: <ComponentName>Props) {
  return (
    // Use Andes components for all UI elements
    // Never use dangerouslySetInnerHTML with untrusted content
    // Keep sensitive data out of component state — pass only what is needed for display
  );
}
```

While writing, apply `../../rules/frontend-style.md` (sections `Components`, `Andes UI`, `User-facing copy`, `TypeScript`, and `Equality`) and `../../rules/security.md` (sections `Secrets & PII` and `XSS Prevention`).

---

## Step 4 — Add styles (`styles.scss`)

Only create this file if Andes props are not sufficient. Keep custom CSS minimal.

---

## Step 5 — Write the test (`__tests__/<component-name>.spec.tsx`)

```tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { NordicTestProviders } from 'nordic-dev/testing-tools';
import { <ComponentName> } from '../index';

describe('<ComponentName>', () => {
  it('renders <expected output>', () => {
    // Arrange
    render(
      <NordicTestProviders>
        <ComponentName />
      </NordicTestProviders>,
    );

    // Assert
    expect(screen.getByRole('...')).toBeInTheDocument();
  });

  it('handles <user interaction>', async () => {
    // Arrange
    const user = userEvent.setup();
    render(
      <NordicTestProviders>
        <ComponentName />
      </NordicTestProviders>,
    );

    // Act
    await user.click(screen.getByRole('button', { name: /label/i }));

    // Assert
    expect(screen.getByText('...')).toBeInTheDocument();
  });
});
```

Test checklist:
- [ ] Happy path renders correctly.
- [ ] Error states render the right feedback.
- [ ] User interactions produce the expected outcome.
- [ ] No snapshot tests as the primary assertion.
- [ ] External dependencies mocked at the project boundary: internal services with `jest.spyOn`.
- [ ] Component libraries and platform packages rendered for real, never mocked (`../../rules/testing.md`, section `Mocking`).

---

## Step 6 — Export (reusable components only)

If the component lives in `app/ui-components/`, add it to the barrel file `app/ui-components/index.ts`:

```ts
export { <ComponentName> } from './<component-name>';
```

Page-specific components are not exported from a barrel — they are imported directly by the page that uses them.

---

## Step 7 — Verify

```bash
tsc --noEmit    # no TypeScript errors
npm run lint    # no lint errors (project config only)
npm test        # all tests pass
```
