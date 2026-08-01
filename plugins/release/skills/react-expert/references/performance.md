# React Performance Reference

Deep dive on render cost and load performance. For where state lives see `references/state.md`; for component structure, `references/patterns.md`.

## Table of Contents

1. [The Re-render Model](#the-re-render-model)
2. [Measure First](#measure-first)
3. [memo / useMemo / useCallback](#memo--usememo--usecallback)
4. [The React 19 Compiler](#the-react-19-compiler)
5. [useTransition and useDeferredValue](#usetransition-and-usedeferredvalue)
6. [List Virtualization](#list-virtualization)
7. [Code Splitting](#code-splitting)
8. [Bundle Optimization](#bundle-optimization)
9. [Context Performance Pitfalls](#context-performance-pitfalls)

---

## The Re-render Model

A component re-renders when **one of three** things happens:

1. Its own state changes (`setState`).
2. Its parent re-renders.
3. A context value it consumes changes.

Note #2: **a parent re-render re-renders all its children**, regardless of whether their props changed — unless a child is wrapped in `React.memo`. This debunks the most common myth ("my props didn't change so my component won't re-render"). It will, if its parent did.

Re-rendering is not inherently bad — React is fast, and a render that produces the same output is cheap. Performance problems appear when a **frequent** re-render drives an **expensive** subtree (a big list, a heavy chart, thousands of DOM nodes). Fix those specifically; don't memoize prophylactically.

---

## Measure First

Optimize with evidence, never by superstition.

- **React DevTools Profiler** — record an interaction, read the flamegraph. It shows which components rendered, how long each took, and *why* it rendered ("props changed", "hook changed", "parent rendered").
- **"Highlight updates when components render"** (DevTools setting) — visually flashes what re-renders as you interact. A component flashing on every keystroke that shouldn't is your target.
- **`react-scan`** (or the older `why-did-you-render`) — surfaces wasted renders (re-rendered with equal props) automatically in dev.

Find the actual hot path first. Most "perf" PRs that sprinkle `useMemo` everywhere add complexity and measure nothing.

---

## memo / useMemo / useCallback

These three prevent work, but each has a cost (comparison, cache) and is *useless* when its dependencies change every render. Use them where they pay off:

| Tool | Prevents | Worth it when |
|------|----------|---------------|
| `React.memo(Component)` | Re-render when props are shallow-equal | Component re-renders often from a parent, with the *same* props, and its render is non-trivial |
| `useMemo(fn, deps)` | Recomputing a value | The computation is genuinely expensive, OR the value is a dependency of `memo`/`useEffect`/another hook |
| `useCallback(fn, deps)` | New function identity each render | The function is passed to a `memo`'d child or used as a hook/effect dependency |

The trap: `React.memo` only helps if the props are *stable*. Passing an inline object/array/function (`style={{}}`, `onClick={() => …}`) to a memoized child breaks memoization — the prop is a new reference every render. That's exactly where `useMemo`/`useCallback` restore stability. Wrapping a leaf component that re-renders cheaply, or a callback passed to a plain (non-memo) child, is pure noise.

```tsx
const Row = React.memo(function Row({ order, onSelect }: RowProps) { /* … */ });

function List({ orders }: { orders: Order[] }) {
  const onSelect = useCallback((id: number) => { /* … */ }, []); // stable → Row's memo works
  return orders.map((o) => <Row key={o.id} order={o} onSelect={onSelect} />);
}
```

---

## The React 19 Compiler

The React Compiler (React 19) automatically memoizes components and values at build time — it inserts the equivalent of `memo`/`useMemo`/`useCallback` where they're provably safe. When it's enabled:

- **Hand-written memoization becomes largely redundant.** Don't add `useMemo`/`useCallback` for referential stability the compiler already guarantees; keep them only for genuinely expensive computations it can't reason about.
- **Write idiomatic, rule-following code.** The compiler relies on the Rules of React (pure render, no mutation of props/state). Code that breaks the rules is skipped (it bails out for that component) — the `eslint-plugin-react-hooks` compiler rules flag these.
- **Know your regime.** On React 18, or React 19 without the compiler, manual memoization still matters. Check whether `babel-plugin-react-compiler` is in the build before deciding to remove memoization.

Don't fight it: no premature `useMemo` "just in case," and don't disable the compiler to hand-tune unless profiling proves a specific need.

---

## useTransition and useDeferredValue

Concurrent features keep the UI responsive when a state update triggers expensive rendering. Classic case: a search box that filters a large list — you want the input to stay snappy while the list catches up.

```tsx
function ProductSearch({ all }: { all: Product[] }) {
  const [query, setQuery] = useState("");
  const deferredQuery = useDeferredValue(query); // lags behind during heavy renders
  const results = useMemo(
    () => all.filter((p) => p.name.includes(deferredQuery)),
    [all, deferredQuery]
  );
  return (
    <>
      <input value={query} onChange={(e) => setQuery(e.target.value)} /> {/* stays responsive */}
      <ResultList items={results} />
    </>
  );
}
```

`useDeferredValue` defers a *value*; `useTransition` marks an *update* as non-urgent (`startTransition(() => setState(...))`) and gives you `isPending` for a subtle loading indicator. Use them for expensive-but-interruptible updates (search, tab switches over heavy content), not for network loading (that's TanStack Query's job).

---

## List Virtualization

The single biggest DOM-side win for long lists. Rendering 5,000 rows means 5,000+ DOM nodes — that, not React, is the bottleneck. Virtualization renders only the visible window.

```tsx
import { useVirtualizer } from "@tanstack/react-virtual";

function OrderList({ orders }: { orders: Order[] }) {
  const parentRef = useRef<HTMLDivElement>(null);
  const virtualizer = useVirtualizer({
    count: orders.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 64, // row height
    overscan: 8,
  });
  return (
    <div ref={parentRef} style={{ height: 600, overflow: "auto" }}>
      <div style={{ height: virtualizer.getTotalSize(), position: "relative" }}>
        {virtualizer.getVirtualItems().map((v) => (
          <div key={v.key} style={{ position: "absolute", top: 0, transform: `translateY(${v.start}px)`, width: "100%" }}>
            <OrderRow order={orders[v.index]} />
          </div>
        ))}
      </div>
    </div>
  );
}
```

Virtualize anything past a few hundred rows, or any list with heavy per-row rendering.

---

## Code Splitting

Don't ship the entire app to render the login screen. Split at route boundaries with `React.lazy` + `Suspense` — the highest-leverage load-time win:

```tsx
const OrdersRoute = lazy(() => import("./features/orders/OrdersRoute"));

<Suspense fallback={<RouteSkeleton />}>
  <OrdersRoute />
</Suspense>
```

Split further for heavy, rarely-used chunks (a rich text editor, a charting lib, a PDF viewer) via dynamic `import()` on interaction. **Preload on intent** — kick off the import on hover/focus of the link so the chunk is ready by click:

```tsx
const prefetch = () => import("./features/orders/OrdersRoute");
<Link to="/orders" onMouseEnter={prefetch} onFocus={prefetch}>Orders</Link>
```

---

## Bundle Optimization

- **Analyze it.** `rollup-plugin-visualizer` (Vite) produces a treemap of what's in your bundle. The biggest single win is usually one fat dependency.
- **Avoid full imports** of large libs: `import debounce from "lodash/debounce"` not `import { debounce } from "lodash"`; drop `moment` for `date-fns`/`dayjs` or the native `Intl` API.
- **Watch barrel files.** A `shared/index.ts` re-exporting everything can defeat tree-shaking and pull unrelated code into a chunk. Import from the specific module when it matters.
- **Tree-shaking** needs ESM and no side effects — check a dep ships `"sideEffects": false` and ES modules.
- Defer polyfills and heavy vendor code out of the initial chunk.

---

## Context Performance Pitfalls

A single context value change re-renders **every** consumer — even ones reading a field that didn't change, because Context has no selector. Symptoms: typing in one field re-renders the whole form tree.

Fixes, in order of preference:
1. **Move the fast-changing state out of Context into Zustand** (selector subscriptions — see `references/state.md`).
2. **Split contexts** so unrelated consumers don't share a provider value.
3. **Memoize the provider value** (necessary but not sufficient — it stops *new-object* re-renders, not real value changes).

Rule of thumb: Context for config that changes rarely; a store for state that changes often.
