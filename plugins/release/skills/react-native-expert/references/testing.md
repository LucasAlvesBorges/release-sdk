# React Native Testing Reference

A mobile test pyramid: many component tests (RNTL), targeted integration tests, and a thin E2E layer (Maestro/Detox) on the critical flows. Stack: jest-expo + React Native Testing Library + MSW.

## Table of Contents

1. [jest-expo + RNTL Setup](#jest-expo--rntl-setup)
2. [Mocking Native Modules](#mocking-native-modules)
3. [RNTL Principles](#rntl-principles)
4. [MSW on React Native](#msw-on-react-native)
5. [Testing Screens & Navigation](#testing-screens--navigation)
6. [Testing Query Hooks](#testing-query-hooks)
7. [E2E — Maestro](#e2e--maestro)
8. [E2E — Detox](#e2e--detox)
9. [What to E2E](#what-to-e2e)

---

## jest-expo + RNTL Setup

`jest-expo` provides the preset that transforms RN/Expo modules correctly.

```js
// jest.config.js
module.exports = {
  preset: "jest-expo",
  setupFilesAfterEnv: ["@testing-library/react-native/extend-expect", "./jest.setup.ts"],
  transformIgnorePatterns: [
    "node_modules/(?!((jest-)?react-native|@react-native(-community)?|expo(nent)?|@expo(nent)?/.*|@react-navigation/.*|@shopify/flash-list))",
  ],
};
```

```ts
// jest.setup.ts
import { server } from "./src/test/msw/server";
beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

---

## Mocking Native Modules

Native modules don't exist in the Jest (Node) environment — mock them, or tests crash on import.

```ts
// jest.setup.ts (continued)
import "react-native-reanimated/mock"; // official Reanimated mock

// MMKV — in-memory fake
jest.mock("react-native-mmkv", () => {
  const store = new Map<string, string>();
  return { MMKV: jest.fn(() => ({
    getString: (k: string) => store.get(k),
    set: (k: string, v: string) => store.set(k, v),
    delete: (k: string) => store.delete(k),
    getBoolean: (k: string) => store.get(k) === "true",
  })) };
});

// expo-secure-store — in-memory fake
jest.mock("expo-secure-store", () => {
  const m = new Map<string, string>();
  return {
    getItemAsync: async (k: string) => m.get(k) ?? null,
    setItemAsync: async (k: string, v: string) => { m.set(k, v); },
    deleteItemAsync: async (k: string) => { m.delete(k); },
  };
});
```

Mock permissions/`NetInfo` per test as needed (`jest.mock("expo-location", …)` returning `granted`).

---

## RNTL Principles

React Native Testing Library mirrors the web RTL philosophy — query by what the user/assistive tech perceives, interact via `userEvent`.

```tsx
import { render, screen, userEvent } from "@testing-library/react-native";
import { OrderCard } from "./OrderCard";

test("fires onPress with the order", async () => {
  const user = userEvent.setup();
  const onPress = jest.fn();
  render(<OrderCard order={{ id: 7, status: "pending" }} onPress={onPress} />);
  await user.press(screen.getByRole("button", { name: /order 7/i }));
  expect(onPress).toHaveBeenCalledTimes(1);
});
```

- Query by **accessibility**: `getByRole`, `getByLabelText`, `getByText`. If a control isn't queryable by role/label, it's likely missing `accessibilityRole`/`accessibilityLabel` — an a11y gap to fix, not a `testID` to add.
- `userEvent` (`press`, `type`) over `fireEvent` — it simulates the real event sequence.
- Assert what renders (`findByText`, `toBeOnTheScreen`), never internal state.

---

## MSW on React Native

MSW works in the RN/Jest environment (Node server) — mock the HTTP boundary, not modules or hooks, so the HTTP client and Query hooks run for real. Handlers mirror DRF (paginated lists, `201`, `400` field errors, `401`) — the same handler style as [[react-expert]] `references/testing.md`. Override per test with `server.use(...)` for error paths.

---

## Testing Screens & Navigation

Wrap screens in the providers they need (QueryClient, SafeArea, navigation). For components that read route params or call the router, mock the router:

```tsx
import { renderWithProviders, screen } from "@/test/utils"; // wraps QueryClientProvider + SafeAreaProvider
import { useLocalSearchParams } from "expo-router";
jest.mock("expo-router", () => ({
  ...jest.requireActual("expo-router"),
  useLocalSearchParams: jest.fn(),
  useRouter: () => ({ push: jest.fn(), replace: jest.fn(), back: jest.fn() }),
}));

test("order detail shows the fetched order", async () => {
  (useLocalSearchParams as jest.Mock).mockReturnValue({ id: "7" });
  renderWithProviders(<OrderDetail />);
  expect(await screen.findByText(/order #7/i)).toBeOnTheScreen();
});
```

For React Navigation, render inside a real `NavigationContainer` with a test navigator.

---

## Testing Query Hooks

Same pattern as web — `renderHook` with a QueryClient wrapper (retries off), `waitFor` on `isSuccess`. Because MSW backs the network, the hook exercises real fetch + cache logic. See [[react-expert]] `references/testing.md` for the wrapper.

---

## E2E — Maestro

**Maestro** runs black-box flows against a built app with simple YAML — low maintenance, resilient to minor UI changes. Great default for critical paths.

```yaml
# .maestro/login.yaml
appId: com.release.app
---
- launchApp
- tapOn: "Email"
- inputText: "user@example.com"
- tapOn: "Password"
- inputText: "password123"
- tapOn: "Sign in"
- assertVisible: "Home"
```

Run with `maestro test .maestro/login.yaml`. Elements are matched by visible text/`testID`/accessibility — so accessible labels double as test hooks.

---

## E2E — Detox

**Detox** is gray-box (it hooks into the app to sync with async work), giving faster, more deterministic runs for large suites — at a higher setup/maintenance cost.

```ts
// e2e/login.test.ts
describe("login", () => {
  beforeAll(async () => { await device.launchApp(); });
  it("signs in and lands on Home", async () => {
    await element(by.id("email")).typeText("user@example.com");
    await element(by.id("password")).typeText("password123");
    await element(by.text("Sign in")).tap();
    await expect(element(by.text("Home"))).toBeVisible();
  });
});
```

Detox needs `testID`s on elements and a dev/test build. Choose Maestro for simplicity and quick coverage; Detox when you need a large, fast, deterministic suite in CI.

---

## What to E2E

E2E is slow and inherently flakier than unit tests — **cover the flows that lose money or lock users out**, not everything:

- Authentication (login, logout, token refresh, biometric unlock).
- The core revenue/critical path (checkout, booking, submit).
- Payment and permission flows.

Everything else belongs in fast RNTL component/integration tests. A thin, reliable E2E layer beats a broad, flaky one that the team learns to ignore.
