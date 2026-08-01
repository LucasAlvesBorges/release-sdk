# React Testing Reference

Test the behavior a user experiences, not implementation details. Stack: Vitest + React Testing Library + MSW, for a React 19 app talking to DRF.

## Table of Contents

1. [Vitest + Vite Setup](#vitest--vite-setup)
2. [renderWithProviders](#renderwithproviders)
3. [RTL Principles](#rtl-principles)
4. [MSW — Mock the Network Boundary](#msw--mock-the-network-boundary)
5. [Testing Components That Fetch](#testing-components-that-fetch)
6. [Testing Query Hooks](#testing-query-hooks)
7. [Testing Forms](#testing-forms)
8. [Async & act](#async--act)
9. [What Not to Test](#what-not-to-test)

---

## Vitest + Vite Setup

Vitest shares Vite's config and transform pipeline — same aliases, same plugins, no separate Babel/Jest config to drift. That's why it beats Jest for a Vite app.

```ts
// vitest.config.ts
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import tsconfigPaths from "vite-tsconfig-paths";

export default defineConfig({
  plugins: [react(), tsconfigPaths()],
  test: {
    environment: "jsdom",
    globals: true,             // describe/it/expect without imports
    setupFiles: ["./src/test/setup.ts"],
    css: false,
  },
});
```

```ts
// src/test/setup.ts
import "@testing-library/jest-dom/vitest";
import { cleanup } from "@testing-library/react";
import { afterEach, afterAll, beforeAll } from "vitest";
import { server } from "./msw/server";

beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => { cleanup(); server.resetHandlers(); });
afterAll(() => server.close());
```

`onUnhandledRequest: "error"` makes a forgotten mock fail loudly instead of hitting the real network.

---

## renderWithProviders

Never render a component bare when it needs providers — wrap it in the *real* ones so tests exercise real wiring. A fresh QueryClient per test (retries off) keeps tests isolated and fast.

```tsx
// src/test/utils.tsx
import { render, type RenderOptions } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router";
import type { ReactElement } from "react";

export function renderWithProviders(ui: ReactElement, { route = "/" } = {}) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[route]}>{ui}</MemoryRouter>
    </QueryClientProvider>
  );
}
export * from "@testing-library/react";
export { default as userEvent } from "@testing-library/user-event";
```

---

## RTL Principles

Query the DOM the way a user (or assistive tech) perceives it. Priority order:

| Priority | Query | Use for |
|----------|-------|---------|
| 1 | `getByRole` (with `name`) | Buttons, links, headings, inputs — the default |
| 2 | `getByLabelText` | Form fields |
| 3 | `getByPlaceholderText` / `getByText` | When no label/role fits |
| last | `getByTestId` | Escape hatch for non-semantic nodes |

If you *can't* query by role/label, that's usually an accessibility gap in the component — fix the component, don't reach for `testId`. Interact with `user-event` (simulates real event sequences: focus, keydown, input) over `fireEvent`.

---

## MSW — Mock the Network Boundary

Mock HTTP, not modules. MSW intercepts real `fetch`/XHR so your components, HTTP client, and Query hooks all run for real — only the server is fake. Handlers mirror the DRF API.

```ts
// src/test/msw/handlers.ts
import { http, HttpResponse } from "msw";

const paginated = <T>(results: T[]) => ({ count: results.length, next: null, previous: null, results });

export const handlers = [
  http.get("*/api/orders/", () =>
    HttpResponse.json(paginated([{ id: 1, status: "pending" }, { id: 2, status: "shipped" }]))
  ),
  http.post("*/api/orders/", async ({ request }) => {
    const body = (await request.json()) as { items: unknown[] };
    if (!body.items?.length) {
      return HttpResponse.json({ items: ["This field is required."] }, { status: 400 }); // DRF field error
    }
    return HttpResponse.json({ id: 3, status: "pending" }, { status: 201 });
  }),
];
```

```ts
// src/test/msw/server.ts
import { setupServer } from "msw/node";
import { handlers } from "./handlers";
export const server = setupServer(...handlers);
```

Override per-test for error paths with `server.use(...)`.

---

## Testing Components That Fetch

Assert the states a user sees — loading, success, error — driven entirely through MSW:

```tsx
import { renderWithProviders, screen } from "@/test/utils";
import { server } from "@/test/msw/server";
import { http, HttpResponse } from "msw";
import { OrderList } from "./OrderList";

test("renders orders from the API", async () => {
  renderWithProviders(<OrderList />);
  expect(screen.getByTestId("list-skeleton")).toBeInTheDocument();       // loading
  expect(await screen.findByText(/order #1/i)).toBeInTheDocument();      // success
});

test("shows an error state on 500", async () => {
  server.use(http.get("*/api/orders/", () => new HttpResponse(null, { status: 500 })));
  renderWithProviders(<OrderList />);
  expect(await screen.findByRole("alert")).toHaveTextContent(/something went wrong/i);
});
```

---

## Testing Query Hooks

For a hook in isolation, `renderHook` with a QueryClient wrapper:

```tsx
import { renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useOrders } from "./useOrders";

function wrapper({ children }: { children: React.ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
}

test("useOrders returns paginated data", async () => {
  const { result } = renderHook(() => useOrders({ page: 1 }), { wrapper });
  await waitFor(() => expect(result.current.isSuccess).toBe(true));
  expect(result.current.data?.results).toHaveLength(2);
});
```

---

## Testing Forms

Cover the three behaviors: validation blocks bad input, valid input submits, and server (DRF) errors surface on the field.

```tsx
import { renderWithProviders, screen, userEvent } from "@/test/utils";
import { LoginForm } from "./LoginForm";

test("blocks submit and shows error for invalid email", async () => {
  const user = userEvent.setup();
  renderWithProviders(<LoginForm />);
  await user.type(screen.getByLabelText(/email/i), "nope");
  await user.click(screen.getByRole("button", { name: /sign in/i }));
  expect(await screen.findByRole("alert")).toHaveTextContent(/valid email/i);
});

test("maps a DRF 400 field error onto the input", async () => {
  server.use(http.post("*/api/login/", () =>
    HttpResponse.json({ email: ["No account with this email."] }, { status: 400 })
  ));
  const user = userEvent.setup();
  renderWithProviders(<LoginForm />);
  await user.type(screen.getByLabelText(/email/i), "ghost@example.com");
  await user.type(screen.getByLabelText(/password/i), "password123");
  await user.click(screen.getByRole("button", { name: /sign in/i }));
  expect(await screen.findByText(/no account with this email/i)).toBeInTheDocument();
});
```

---

## Async & act

- Use `findBy*` (retries until present) and `waitFor` for anything that appears after an await — never a fixed `setTimeout`.
- `user-event` calls are async — always `await` them; that flushes React state updates and avoids `act(...)` warnings.
- If a warning persists, something updated state after the test finished — usually an unmocked request or a missing `await`. Fix the cause, don't wrap in `act` manually.
- Fake timers (`vi.useFakeTimers()`) only for debounce/throttle/interval logic; restore them in `afterEach`.

---

## What Not to Test

- **Implementation details** — internal `useState` values, whether a specific hook was called, CSS class names. They change on refactors that don't change behavior, producing brittle tests.
- **The library** — you don't test that TanStack Query caches or that React renders; test *your* behavior on top.

**Coverage strategy:** chase branches and behaviors, not a line-percentage target. A 100%-line test that asserts nothing meaningful is worse than a focused test of the permission logic and the error path. Prioritize: forms, auth/permission-dependent UI, data-error states, and anything that's broken before.

**Organization:** colocate `Component.test.tsx` next to `Component.tsx`; keep MSW handlers in `src/test/msw/`; share `renderWithProviders`.
