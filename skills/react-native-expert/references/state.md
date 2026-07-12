# React Native State & Data Reference

State management on mobile, where the network is unreliable — so server state must be cached and persistable. Shares the web taxonomy ([[react-expert]] `references/state.md`) with mobile-specific storage and offline concerns.

## Table of Contents

1. [State Taxonomy on Mobile](#state-taxonomy-on-mobile)
2. [Storage Layers](#storage-layers)
3. [Zustand + Secure Hydration](#zustand--secure-hydration)
4. [MMKV](#mmkv)
5. [TanStack Query Offline](#tanstack-query-offline)
6. [Offline Mutations](#offline-mutations)
7. [DRF Mapping & Auth Refresh](#drf-mapping--auth-refresh)

---

## State Taxonomy on Mobile

Same four categories as web (server / navigation-param / local UI / global client), with an offline-first mindset: **the app must open to useful content with no network** and tolerate requests failing mid-flight.

| Category | Lives in | Mobile note |
|----------|----------|-------------|
| Server state | TanStack Query (+ persisted cache) | Launch shows cached data instantly, offline |
| Global client state | Zustand | Session store hydrated from secure-store at boot |
| Navigation params | Router params | Pass IDs, not objects (see `references/navigation.md`) |
| Local UI state | `useState`/`useReducer` | Same as web |
| Persisted prefs | MMKV | theme, onboarding-seen, feature flags |

---

## Storage Layers

Three distinct stores — never mix their purposes:

| Store | Backing | Use for | Never for |
|-------|---------|---------|-----------|
| `expo-secure-store` | iOS Keychain / Android Keystore (encrypted) | tokens, refresh tokens, PII | large data (it's slow, small-value) |
| `react-native-mmkv` | fast native key-value (unencrypted by default) | cache, prefs, non-sensitive flags | secrets/tokens |
| TanStack Query cache | in-memory + MMKV persister | server data | client-only state |

Putting a token in MMKV or `AsyncStorage` is a security bug — both are recoverable from device backups and on rooted devices. See `references/security.md`.

---

## Zustand + Secure Hydration

The session store holds the in-memory token; it's **hydrated from secure-store at boot** (async), so the app restores the session without keeping the token in JS-readable storage.

```tsx
// features/auth/stores/session.store.ts
import { create } from "zustand";
import { secureStorage } from "@/shared/storage/secure";

type SessionState = {
  token: string | null;
  hydrated: boolean;
  hydrate: () => Promise<void>;
  signIn: (token: string) => Promise<void>;
  signOut: () => Promise<void>;
};

export const useSession = create<SessionState>((set) => ({
  token: null,
  hydrated: false,
  hydrate: async () => set({ token: await secureStorage.getToken(), hydrated: true }),
  signIn: async (token) => { await secureStorage.setToken(token); set({ token }); },
  signOut: async () => { await secureStorage.clear(); set({ token: null }); },
}));
```

```tsx
// Call hydrate() once at app root; keep the splash until hydrated === true
useEffect(() => { useSession.getState().hydrate(); }, []);
```

Select narrowly (`useSession((s) => s.token)`) — same discipline as web Zustand. The store is also readable outside React in the HTTP client (`useSession.getState().token`).

---

## MMKV

Synchronous, fast, native. Wrap it typed:

```tsx
// shared/storage/kv.ts
import { MMKV } from "react-native-mmkv";
const mmkv = new MMKV();

export const kv = {
  getBool: (k: string) => mmkv.getBoolean(k),
  setBool: (k: string, v: boolean) => mmkv.set(k, v),
  getString: (k: string) => mmkv.getString(k),
  setString: (k: string, v: string) => mmkv.set(k, v),
  delete: (k: string) => mmkv.delete(k),
};
```

MMKV is synchronous — good for a fast boot (read `onboardingSeen` without awaiting). It can be encrypted (`new MMKV({ encryptionKey })`) but the key management still points you to secure-store for real secrets.

---

## TanStack Query Offline

Persist the Query cache to MMKV so the app opens to cached content instantly and survives offline, and bind Query's online state to real connectivity:

```tsx
import { QueryClient, onlineManager } from "@tanstack/react-query";
import { persistQueryClient } from "@tanstack/react-query-persist-client";
import { createSyncStoragePersister } from "@tanstack/query-sync-storage-persister";
import NetInfo from "@react-native-community/netinfo";
import { MMKV } from "react-native-mmkv";

// Query now knows the device's real connectivity → pauses/resumes correctly
onlineManager.setEventListener((setOnline) =>
  NetInfo.addEventListener((state) => setOnline(!!state.isConnected))
);

const storage = new MMKV();
export const queryClient = new QueryClient({
  defaultOptions: { queries: { staleTime: 60_000, gcTime: 1000 * 60 * 60 * 24, retry: 2 } },
});

persistQueryClient({
  queryClient,
  maxAge: 1000 * 60 * 60 * 24,
  persister: createSyncStoragePersister({
    storage: {
      getItem: (k) => storage.getString(k) ?? null,
      setItem: (k, v) => storage.set(k, v),
      removeItem: (k) => storage.delete(k),
    },
  }),
});
```

A long `gcTime` keeps data around for offline launches; `staleTime` avoids refetch storms on resume.

---

## Offline Mutations

Writes made offline should queue and replay when connectivity returns. TanStack Query pauses mutations when `onlineManager` reports offline and resumes them on reconnect — pair with optimistic updates so the UI reflects the change immediately:

```tsx
useMutation({
  mutationKey: ["orders", "create"],
  mutationFn: (dto: CreateOrderDto) => apiClient.post("/orders/", dto),
  networkMode: "offlineFirst",   // run if online, else queue until reconnect
  onMutate: async (dto) => { /* optimistic cache update + rollback context */ },
});
```

For durability across app restarts, persist the mutation cache too (`persistQueryClient` includes mutations) and set default mutation functions so paused mutations can resume after a cold start. Keep offline writes idempotent (server-side dedup key) — the replay may double-send on flaky networks.

---

## DRF Mapping & Auth Refresh

Same DRF shapes as web — mirror them in types and centralize handling in the HTTP client:

```tsx
type Paginated<T> = { count: number; next: string | null; previous: string | null; results: T[] };
type FieldErrors = Record<string, string[]>; // { email: ["Already registered"] }
```

The request interceptor attaches the token from the session store; the response interceptor handles `401` by refreshing once (using the refresh token from secure-store) and retrying, else signing out. Map `400` field errors back onto forms (react-hook-form `setError`), shared discipline with [[react-expert]]. And remember: a value arriving from a **deep link is untrusted** — validate it before it touches state (see `references/navigation.md` and `references/security.md`).
