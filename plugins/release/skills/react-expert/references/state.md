# React State Management Reference

Deep dive on putting state in the right place. For provider/context mechanics see `references/patterns.md`; for re-render cost see `references/performance.md`.

## Table of Contents

1. [The State Taxonomy](#the-state-taxonomy)
2. [useState vs useReducer](#usestate-vs-usereducer)
3. [Zustand — Global Client State](#zustand--global-client-state)
4. [Context — Use Sparingly](#context--use-sparingly)
5. [TanStack Query — Server State](#tanstack-query--server-state)
6. [URL State](#url-state)
7. [Decision Table](#decision-table)

---

## The State Taxonomy

Most React state bugs come from one mistake: **putting a piece of state in the wrong category.** Classify every value before you decide where it lives.

| Category | Definition | Lives in | Examples |
|----------|-----------|----------|----------|
| **Server state** | A cached copy of data owned by the backend | TanStack Query | orders, current user, catalog |
| **URL state** | State that should be shareable/bookmarkable/back-able | Router search params | filters, page, active tab, sort |
| **Local UI state** | Ephemeral, used by one component/subtree | `useState`/`useReducer` | input value, dropdown open, hover |
| **Global client state** | Cross-cutting, not from the server | Zustand | auth token (in memory), theme, toasts |

The cardinal rule: **server state is not client state.** Data from your Django API is a *cache*, with all a cache's concerns — staleness, revalidation, deduplication, invalidation. `useState` + `useEffect(fetch)` reinvents all of that, badly, and produces the classic bugs: double fetches, race conditions, stale data after mutations, no loading/error states. Use TanStack Query and delete the effect.

---

## useState vs useReducer

Use `useState` for independent values. Reach for `useReducer` when **multiple values change together** or transitions form a small state machine — it centralizes the logic and makes invalid transitions impossible.

```tsx
type FetchState<T> =
  | { status: "idle" }
  | { status: "loading" }
  | { status: "success"; data: T }
  | { status: "error"; error: string };

type Action<T> =
  | { type: "start" }
  | { type: "resolve"; data: T }
  | { type: "reject"; error: string };

function reducer<T>(state: FetchState<T>, action: Action<T>): FetchState<T> {
  switch (action.type) {
    case "start": return { status: "loading" };
    case "resolve": return { status: "success", data: action.data };
    case "reject": return { status: "error", error: action.error };
  }
}
```

A discriminated union as the state type means you can never render `data` while `status === "loading"` — the compiler forbids it. (For actual data fetching, prefer TanStack Query, which is this machine, done right and cached.)

---

## Zustand — Global Client State

Zustand is the recommended store for global *client* state. It's minimal, hook-based, and — critically — supports **selector subscriptions** so a component re-renders only when the slice it reads changes.

```tsx
import { create } from "zustand";

type ThemeState = {
  theme: "light" | "dark";
  toggle: () => void;
};

export const useThemeStore = create<ThemeState>((set) => ({
  theme: "light",
  toggle: () => set((s) => ({ theme: s.theme === "light" ? "dark" : "light" })),
}));
```

**Select narrowly** — this is the single most important Zustand habit:

```tsx
const theme = useThemeStore((s) => s.theme);   // ✅ re-renders only when theme changes
const toggle = useThemeStore((s) => s.toggle); // ✅ stable action ref
const store = useThemeStore();                 // ❌ re-renders on ANY state change
```

When selecting multiple fields, return primitives separately, or use `useShallow` to avoid a new-object-every-render re-render:

```tsx
import { useShallow } from "zustand/react/shallow";
const { user, permissions } = useAuthStore(useShallow((s) => ({ user: s.user, permissions: s.permissions })));
```

**Slices pattern** keeps a large store modular:

```tsx
const createAuthSlice = (set) => ({ token: null, setToken: (token) => set({ token }) });
const createUiSlice = (set) => ({ sidebarOpen: false, toggleSidebar: () => set((s) => ({ sidebarOpen: !s.sidebarOpen })) });
export const useStore = create((...a) => ({ ...createAuthSlice(...a), ...createUiSlice(...a) }));
```

**Middleware:** `persist` (localStorage/sessionStorage — but *not* for auth tokens, see `references/security.md`), `immer` (mutable-style updates for nested state), `devtools` (Redux DevTools).

**Access outside React** — the store is usable anywhere, which is perfect for an axios interceptor reading the token:

```tsx
apiClient.interceptors.request.use((config) => {
  const token = useAuthStore.getState().token; // no hook needed
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});
```

**Testing:** reset state between tests with `useStore.setState(initialState, true)`.

---

## Context — Use Sparingly

Context is for dependency injection of low-frequency values, not for state management of frequently-changing data. Every consumer re-renders whenever the provider's value changes (referential inequality), and Context has no selector mechanism. See `references/patterns.md` for memoizing the value and splitting state/dispatch. If you're passing high-frequency state through Context and fighting re-renders, migrate it to Zustand.

---

## TanStack Query — Server State

All server communication goes through Query hooks in a feature's `api/` folder. Components never call the network directly.

### Query Key Factories

A structured key factory makes caching and invalidation precise and typo-proof:

```tsx
export const orderKeys = {
  all: ["orders"] as const,
  lists: () => [...orderKeys.all, "list"] as const,
  list: (filters: OrderFilters) => [...orderKeys.lists(), filters] as const,
  details: () => [...orderKeys.all, "detail"] as const,
  detail: (id: number) => [...orderKeys.details(), id] as const,
};
```

### staleTime vs gcTime

- **`staleTime`** — how long data is considered fresh (no background refetch on mount/focus). Default `0` = refetch aggressively. Set it deliberately (e.g. `30_000`) to stop refetch storms.
- **`gcTime`** (formerly `cacheTime`) — how long *unused* data stays in cache before garbage collection. Default 5 min.

### Mutations + Precise Invalidation

```tsx
export function useCreateOrder() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (dto: CreateOrderDto) => apiClient.post<Order>("/orders/", dto),
    onSuccess: () => qc.invalidateQueries({ queryKey: orderKeys.lists() }),
  });
}
```

### Optimistic Updates with Rollback

```tsx
export function useToggleFavorite() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ id, fav }: { id: number; fav: boolean }) =>
      apiClient.patch(`/orders/${id}/`, { favorite: fav }),
    onMutate: async ({ id, fav }) => {
      await qc.cancelQueries({ queryKey: orderKeys.detail(id) });
      const previous = qc.getQueryData<Order>(orderKeys.detail(id));
      qc.setQueryData<Order>(orderKeys.detail(id), (o) => o && { ...o, favorite: fav });
      return { previous, id }; // context for rollback
    },
    onError: (_e, _vars, ctx) => {
      if (ctx?.previous) qc.setQueryData(orderKeys.detail(ctx.id), ctx.previous); // roll back
    },
    onSettled: (_d, _e, { id }) => qc.invalidateQueries({ queryKey: orderKeys.detail(id) }), // reconcile
  });
}
```

### Pagination & Infinite

Map DRF's pagination shape explicitly and keep the previous page visible while fetching the next:

```tsx
type Paginated<T> = { count: number; next: string | null; previous: string | null; results: T[] };

export function useOrders(page: number) {
  return useQuery({
    queryKey: orderKeys.list({ page }),
    queryFn: () => apiClient.get<Paginated<Order>>("/orders/", { params: { page } }),
    placeholderData: (prev) => prev, // keepPreviousData — no list flash between pages
  });
}
```

For infinite scroll use `useInfiniteQuery` with `getNextPageParam: (last) => last.next ? extractPage(last.next) : undefined`.

### Dependent Queries, `select`, Prefetch

```tsx
const { data: user } = useCurrentUser();
const { data: orders } = useQuery({
  queryKey: orderKeys.list({ userId: user?.id }),
  queryFn: () => apiClient.get(`/orders/?user=${user!.id}`),
  enabled: !!user?.id,                        // wait for the dependency
  select: (page) => page.results,            // narrow/derive without extra renders
});
// Prefetch on hover: qc.prefetchQuery({ queryKey: orderKeys.detail(id), queryFn: ... })
```

### Global Error Handling & 401 → Refresh

Configure one `QueryClient` with sane defaults and centralize auth-refresh in the HTTP client's response interceptor (on `401`, refresh the token via the httpOnly cookie, retry once, else log out). Map DRF field errors `{ "email": ["Already registered"] }` back onto forms in the mutation's `onError` (see `references/testing.md` for asserting this).

---

## URL State

Filters, pagination, sort, and the active tab belong in the URL — they're shareable, survive refresh, and make the back button work. Don't mirror them into `useState`.

```tsx
import { useSearchParams } from "react-router";

function useOrderFilters() {
  const [params, setParams] = useSearchParams();
  const status = params.get("status") ?? "all";
  const page = Number(params.get("page") ?? "1");
  const setStatus = (s: string) => setParams((p) => { p.set("status", s); p.set("page", "1"); return p; });
  return { status, page, setStatus };
}
```

Feed this URL state straight into the query key (`orderKeys.list({ status, page })`) — now the URL, the cache, and the UI are one consistent source of truth.

---

## Decision Table

| You have… | Put it in | Not in |
|-----------|-----------|--------|
| Data fetched from Django | TanStack Query | Zustand / useState+useEffect |
| Filters, page, sort, tab | URL search params | useState |
| Auth token | in-memory Zustand (+ httpOnly cookie for refresh) | localStorage |
| Theme, locale | Zustand or Context | prop drilling |
| One input's value | `useState` | global store |
| Coupled multi-field transitions | `useReducer` | many `useState` |
