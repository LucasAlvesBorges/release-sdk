# React Patterns Reference

Deep dive on component & hook design patterns. For where state lives, see `references/state.md`; for render cost, `references/performance.md`.

## Table of Contents

1. [Composition Over Configuration](#composition-over-configuration)
2. [Compound Components](#compound-components)
3. [Custom Hook Design](#custom-hook-design)
4. [Provider Pattern](#provider-pattern)
5. [Render Props vs Hooks](#render-props-vs-hooks)
6. [Polymorphic Components](#polymorphic-components)
7. [Error Boundaries](#error-boundaries)
8. [Container/Presentational Is Dated](#containerpresentational-is-dated)
9. [TypeScript Component Patterns](#typescript-component-patterns)

---

## Composition Over Configuration

The most common design smell in React is the **boolean-prop explosion**: a component that grows `isLoading`, `hasError`, `showHeader`, `withIcon`, `variant`, `size`… Each new requirement adds a prop and a branch, until the component is an unreadable configuration matrix.

The fix is composition — pass *content* as `children`, not *flags*:

```tsx
// ❌ Configuration — every variation is a new prop + branch
<Dialog title="Delete?" body="This is permanent" confirmLabel="Delete" danger withClose />

// ✅ Composition — the consumer assembles the parts
<Dialog>
  <Dialog.Header onClose={close}>Delete?</Dialog.Header>
  <Dialog.Body>This is permanent</Dialog.Body>
  <Dialog.Footer>
    <Button variant="danger" onClick={confirm}>Delete</Button>
  </Dialog.Footer>
</Dialog>
```

Composition scales because new use cases don't touch `Dialog` — they rearrange its parts. Reach for a config prop only for genuinely closed sets (a `variant` union of 3 fixed styles is fine; a `showX` boolean per slot is not).

**Slots** generalize this — accept named regions as props when children ordering is fixed:

```tsx
type PageProps = { header: React.ReactNode; sidebar?: React.ReactNode; children: React.ReactNode };
export function Page({ header, sidebar, children }: PageProps) {
  return (
    <div className="page">
      <header>{header}</header>
      {sidebar && <aside>{sidebar}</aside>}
      <main>{children}</main>
    </div>
  );
}
```

---

## Compound Components

When several subcomponents must share implicit state (which tab is active, whether the accordion is open), a **compound component** exposes them as properties of the parent and wires state through Context — so the consumer writes declarative markup without threading props.

```tsx
import { createContext, useContext, useId, useState } from "react";

type TabsContextValue = { active: string; setActive: (id: string) => void };
const TabsContext = createContext<TabsContextValue | null>(null);

function useTabs() {
  const ctx = useContext(TabsContext);
  if (!ctx) throw new Error("Tabs.* must be used inside <Tabs>");
  return ctx;
}

export function Tabs({ defaultTab, children }: { defaultTab: string; children: React.ReactNode }) {
  const [active, setActive] = useState(defaultTab);
  return <TabsContext.Provider value={{ active, setActive }}>{children}</TabsContext.Provider>;
}

function TabList({ children }: { children: React.ReactNode }) {
  return <div role="tablist">{children}</div>;
}

function Tab({ id, children }: { id: string; children: React.ReactNode }) {
  const { active, setActive } = useTabs();
  return (
    <button role="tab" aria-selected={active === id} onClick={() => setActive(id)}>
      {children}
    </button>
  );
}

function TabPanel({ id, children }: { id: string; children: React.ReactNode }) {
  const { active } = useTabs();
  return active === id ? <div role="tabpanel">{children}</div> : null;
}

Tabs.List = TabList;
Tabs.Tab = Tab;
Tabs.Panel = TabPanel;
```

```tsx
<Tabs defaultTab="profile">
  <Tabs.List>
    <Tabs.Tab id="profile">Profile</Tabs.Tab>
    <Tabs.Tab id="billing">Billing</Tabs.Tab>
  </Tabs.List>
  <Tabs.Panel id="profile"><ProfileForm /></Tabs.Panel>
  <Tabs.Panel id="billing"><BillingForm /></Tabs.Panel>
</Tabs>
```

The `useTabs` guard turns "used outside provider" into a loud, immediate error instead of a confusing `null` crash later. Note the Context here holds *low-frequency* UI state — fine. High-frequency values (see [Provider Pattern](#provider-pattern)) need care.

---

## Custom Hook Design

A custom hook extracts a **cohesive** piece of behavior with a clear contract — it is not a place to dump lines to shrink a component. Guidelines:

- Name it `useX` for what it *does* (`useDisclosure`, not `useModalStuff`).
- Return a **stable, minimal** API. Prefer an object for 3+ values (named), a tuple for 2 (like `useState`).
- Memoize returned callbacks/objects if consumers put them in dependency arrays.
- Compose small hooks into bigger ones — don't build one 200-line mega-hook.

```tsx
// A focused, reusable hook with a tuple-like object return
export function useDisclosure(initial = false) {
  const [isOpen, setIsOpen] = useState(initial);
  const open = useCallback(() => setIsOpen(true), []);
  const close = useCallback(() => setIsOpen(false), []);
  const toggle = useCallback(() => setIsOpen((v) => !v), []);
  return { isOpen, open, close, toggle } as const;
}
```

```tsx
// Syncs a value to localStorage — encapsulates the serialization + effect
export function useLocalStorage<T>(key: string, initial: T) {
  const [value, setValue] = useState<T>(() => {
    const raw = localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as T) : initial;
  });
  useEffect(() => {
    localStorage.setItem(key, JSON.stringify(value));
  }, [key, value]);
  return [value, setValue] as const;
}
```

**Hook vs plain function:** if the logic uses React state/effects/context, it's a hook. If it's a pure transformation (formatting, math), it's a plain function in `shared/lib/` — don't wrap pure logic in a hook. (Note: `useLocalStorage` above does not sync across tabs; add a `storage` event listener if you need that.)

---

## Provider Pattern

Context is the right tool for **low-frequency, widely-read** values: theme, locale, the authenticated user object, a feature-flag map. It is the *wrong* tool for values that change on every keystroke — every consumer re-renders when the context value changes.

Two disciplines make providers safe:

**1. Memoize the value** so you don't hand consumers a new object each render:

```tsx
const value = useMemo(() => ({ user, permissions }), [user, permissions]);
return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
```

**2. Split state and dispatch** when updates are frequent — components that only dispatch never re-render on state change:

```tsx
const StateContext = createContext<State | null>(null);
const DispatchContext = createContext<React.Dispatch<Action> | null>(null);

export function CounterProvider({ children }: { children: React.ReactNode }) {
  const [state, dispatch] = useReducer(reducer, initialState);
  return (
    <StateContext.Provider value={state}>
      <DispatchContext.Provider value={dispatch}>{children}</DispatchContext.Provider>
    </StateContext.Provider>
  );
}
```

If you find yourself fighting Context re-renders, that state probably wants a store (Zustand) with selector subscriptions instead — see `references/state.md` and the Context-perf section of `references/performance.md`.

| Need | Use |
|------|-----|
| Rarely-changing config read everywhere | Context |
| Frequently-changing global state | Zustand (selector subscriptions) |
| Server/cached data | TanStack Query |
| State for one subtree | Lift to nearest common parent |

---

## Render Props vs Hooks

Before hooks, logic reuse meant render props and HOCs. Hooks replaced ~95% of those cases: they compose without nesting ("wrapper hell") and without obscuring the component tree.

```tsx
// Old: render prop
<Mouse>{({ x, y }) => <Cursor x={x} y={y} />}</Mouse>
// New: hook — flatter, composable, typed
const { x, y } = useMousePosition();
```

Render props / children-as-function still earn their place when the reused thing must **render into the tree at a location the consumer controls** — e.g. a headless list that yields each item for custom rendering, or virtualization libraries. If no rendering is delegated, use a hook.

---

## Polymorphic Components

A polymorphic component renders as different elements via an `as` prop — common for design-system primitives (`<Text as="h1">`). Type it so the extra props match the chosen element:

```tsx
import type { ElementType, ComponentPropsWithoutRef } from "react";

type TextProps<T extends ElementType> = {
  as?: T;
  variant?: "body" | "heading";
} & Omit<ComponentPropsWithoutRef<T>, "as">;

export function Text<T extends ElementType = "span">({ as, variant = "body", ...rest }: TextProps<T>) {
  const Component = as ?? "span";
  return <Component data-variant={variant} {...rest} />;
}

// <Text as="a" href="/x">link</Text>  → href is type-checked
// <Text as="label" htmlFor="y">…</Text>
```

Polymorphism adds real type complexity. If you only need two or three fixed elements, separate components (`<Heading>`, `<Body>`) are simpler and just as reusable.

---

## Error Boundaries

An uncaught render error unmounts the **whole** React tree — a white screen. Error boundaries contain the blast radius to a subtree with a fallback. Only class components can be boundaries, so in practice use the `react-error-boundary` library:

```tsx
import { ErrorBoundary } from "react-error-boundary";

function RouteError({ error, resetErrorBoundary }: { error: Error; resetErrorBoundary: () => void }) {
  return (
    <div role="alert">
      <p>Something went wrong: {error.message}</p>
      <button onClick={resetErrorBoundary}>Try again</button>
    </div>
  );
}

<ErrorBoundary FallbackComponent={RouteError} onError={(e) => Sentry.captureException(e)} resetKeys={[routeId]}>
  <Suspense fallback={<RouteSkeleton />}>
    <OrdersRoute />
  </Suspense>
</ErrorBoundary>
```

Place boundaries **per route or per major feature**, not one at the app root only — a widget crash shouldn't take down navigation. `resetKeys` clears the error when the route changes so users aren't stuck. Note: boundaries catch render/lifecycle errors, **not** async event-handler or fetch errors — handle those with TanStack Query's `error` state (see `references/state.md`).

---

## Container/Presentational Is Dated

The old split — a "container" that fetches and a "presentational" component that only renders props — was a workaround for class components mixing concerns. Hooks made it largely obsolete: colocate data access in a **custom hook** and let the component use it.

```tsx
function OrderList() {
  const { data, isPending, error } = useOrders(filters); // data access colocated
  if (isPending) return <ListSkeleton />;
  if (error) return <ErrorState error={error} />;
  return <>{data.results.map((o) => <OrderRow key={o.id} order={o} />)}</>;
}
```

A presentational split still helps for **pure, reusable UI** (a design-system `<Table>` that knows nothing about orders) and for **Storybook/visual testing** where you want a component with zero data dependencies. Split for reuse, not dogma.

---

## TypeScript Component Patterns

**Discriminated-union props** make illegal states unrepresentable — the compiler enforces which props go together:

```tsx
type AlertProps =
  | { severity: "error"; error: Error }           // error variant REQUIRES error
  | { severity: "info"; message: string };        // info variant REQUIRES message

function Alert(props: AlertProps) {
  if (props.severity === "error") return <div role="alert">{props.error.message}</div>;
  return <div>{props.message}</div>;
}
```

**Generic components** keep item/handler types linked:

```tsx
type ListProps<T> = { items: T[]; getKey: (item: T) => string | number; renderItem: (item: T) => React.ReactNode };
export function List<T>({ items, getKey, renderItem }: ListProps<T>) {
  return <ul>{items.map((item) => <li key={getKey(item)}>{renderItem(item)}</li>)}</ul>;
}
// renderItem's arg is inferred as T — no casts
```

**Reuse a component's props** with `ComponentProps<typeof X>` instead of re-declaring them. **Refs:** in React 19, `ref` is a normal prop (`{ ref }: { ref?: Ref<HTMLInputElement> }`) — no `forwardRef` needed; in React 18 you still wrap with `forwardRef`. Prefer inline prop types or a `type` alias over `React.FC` (it forces implicit `children` and complicates generics).
