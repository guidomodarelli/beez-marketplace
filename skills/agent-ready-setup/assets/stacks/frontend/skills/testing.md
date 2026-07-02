# Testing — Frontend (Nordic + React + TypeScript)

How to write tests for each type of unit in this stack. Reference `rules/testing.md` for team standards (coverage, selectors, naming).

---

## Testing a React component

Use React Testing Library. Test what the user sees — not internal state or implementation details.

```tsx
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MyComponent } from '../index';

// Mock all external dependencies
jest.mock('../../../services/my-service');

describe('MyComponent', () => {
  it('renders the submit button', () => {
    render(<MyComponent label="Save" />);
    expect(screen.getByRole('button', { name: /save/i })).toBeInTheDocument();
  });

  it('calls onSubmit when the button is clicked', async () => {
    const onSubmit = jest.fn();
    const user = userEvent.setup();

    render(<MyComponent onSubmit={onSubmit} />);
    await user.click(screen.getByRole('button', { name: /save/i }));

    expect(onSubmit).toHaveBeenCalledTimes(1);
  });

  it('shows an error message when the API fails', async () => {
    // mock the service to reject
    (myService.save as jest.Mock).mockRejectedValue(new Error('API error'));
    const user = userEvent.setup();

    render(<MyComponent />);
    await user.click(screen.getByRole('button', { name: /save/i }));

    expect(screen.getByText(/something went wrong/i)).toBeInTheDocument();
  });
});
```

---

## Testing a server hook (`index.hooks.server.ts`)

Mock the service layer. Test what the hook returns — not how it calls the service internally.

```ts
import { getServerSideProps } from '../index.hooks.server';
import * as myService from '../../../services/my-service';

jest.mock('../../../services/my-service');

describe('getServerSideProps', () => {
  it('returns props with data on success', async () => {
    (myService.getResource as jest.Mock).mockResolvedValue({ id: '1', name: 'test' });

    const result = await getServerSideProps({ params: { id: '1' } } as any);

    expect(result).toEqual({ props: { resource: { id: '1', name: 'test' } } });
  });

  it('returns error prop when the service throws', async () => {
    (myService.getResource as jest.Mock).mockRejectedValue(new Error('fail'));

    const result = await getServerSideProps({ params: { id: '1' } } as any);

    expect(result).toEqual({ props: { error: true } });
  });

  it('returns 400 when input is invalid', async () => {
    const result = await getServerSideProps({ params: { id: '' } } as any);
    // assert based on your validation error shape
    expect(result).toEqual(expect.objectContaining({ props: { error: true } }));
  });
});
```

---

## Testing a service

Mock `nordic/restclient`. Test that the service calls the right endpoints and propagates errors.

```ts
import { RestClient } from 'nordic/restclient';
import { getResource, createResource } from '../index';

jest.mock('nordic/restclient');

const mockGet  = jest.fn();
const mockPost = jest.fn();

beforeEach(() => {
  (RestClient as jest.Mock).mockImplementation(() => ({
    get:  mockGet,
    post: mockPost,
  }));
});

afterEach(() => jest.resetAllMocks());

describe('getResource', () => {
  it('calls the correct endpoint and returns data', async () => {
    mockGet.mockResolvedValue({ data: { id: '1' } });

    const result = await getResource('1');

    expect(mockGet).toHaveBeenCalledWith('/resources/1');
    expect(result).toEqual({ id: '1' });
  });

  it('propagates API errors', async () => {
    mockGet.mockRejectedValue(new Error('Network error'));
    await expect(getResource('1')).rejects.toThrow('Network error');
  });
});
```

---

## Testing a custom hook

Use `renderHook` from RTL. Mock external dependencies.

```ts
import { renderHook, act } from '@testing-library/react';
import { useMyHook } from '../useMyHook';
import * as myService from '../../../services/my-service';

jest.mock('../../../services/my-service');

describe('useMyHook', () => {
  it('returns data after loading', async () => {
    (myService.getResource as jest.Mock).mockResolvedValue({ id: '1' });

    const { result } = renderHook(() => useMyHook('1'));

    expect(result.current.loading).toBe(true);
    await act(async () => {}); // flush promises
    expect(result.current.loading).toBe(false);
    expect(result.current.data).toEqual({ id: '1' });
  });
});
```

---

## Run tests

```bash
npm test                          # all tests
npm test -- --testPathPattern=MyComponent   # single file
npm test -- --coverage            # with coverage report
```
