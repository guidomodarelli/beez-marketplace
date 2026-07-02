# Component Creation — Frontend (Nordic + React + Andes)

Step-by-step guide for creating a React component following team conventions. Always consult `frontender-web-mcp` (`andes-components` tool) before selecting an Andes component.

---

## Step 1 — Define scope

Before writing code, answer:
- What does this component display or do?
- Does it need server-side data? → If yes, the data comes from a server hook, not fetched inside the component.
- Does Andes already have a component for this? → Consult `frontender-web-mcp` first.

---

## Step 2 — Create the directory

```
src/components/<ComponentName>/
├── index.tsx
├── <ComponentName>.module.css      ← only if custom styles are needed
└── __tests__/
    └── <ComponentName>.spec.tsx
```

Use PascalCase for the directory and component name. Use kebab-case for files.

---

## Step 3 — Write the component (`index.tsx`)

```tsx
type Props = {
  // Declare all props explicitly — no rest props (...rest)
};

export function <ComponentName>({ }: Props) {
  return (
    // Use Andes components for all UI elements
    // Never use dangerouslySetInnerHTML with untrusted content
    // Keep sensitive data out of component state — pass only what is needed for display
  );
}
```

Rules to follow while writing:
- Use Andes props (`variant`, `size`, `hierarchy`) before adding any custom CSS.
- Never override internal Andes component styles.
- Never store sensitive data (tokens, PII) in component state.
- Never render user-provided content as raw HTML — sanitize with `DOMPurify` if unavoidable.

---

## Step 4 — Add styles (`<ComponentName>.module.css`)

Only create this file if Andes props are not sufficient. Keep custom CSS minimal.

---

## Step 5 — Write the test (`__tests__/<ComponentName>.spec.tsx`)

```tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { <ComponentName> } from '../index';

describe('<ComponentName>', () => {
  it('renders <expected output>', () => {
    // Arrange
    render(<<ComponentName> />);

    // Assert
    expect(screen.getByRole('...')).toBeInTheDocument();
  });

  it('handles <user interaction>', async () => {
    // Arrange
    const user = userEvent.setup();
    render(<<ComponentName> />);

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
- [ ] All external dependencies mocked.

---

## Step 6 — Export (if a barrel file exists)

Add the component to `src/components/index.ts`:

```ts
export { <ComponentName> } from './<ComponentName>';
```

---

## Step 7 — Verify

```bash
tsc --noEmit    # no TypeScript errors
npm run lint    # no lint errors (project config only)
npm test        # all tests pass
```
