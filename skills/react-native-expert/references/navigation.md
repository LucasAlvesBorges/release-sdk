# React Native Navigation Reference

Navigation is the backbone of a mobile app and a common source of bugs (leaked listeners, wrong back behavior, unguarded routes). Covers Expo Router and React Navigation.

## Table of Contents

1. [Expo Router vs React Navigation](#expo-router-vs-react-navigation)
2. [Expo Router — File-Based](#expo-router--file-based)
3. [Typed Routes & Params](#typed-routes--params)
4. [Nested Navigators](#nested-navigators)
5. [Auth Flow Patterns](#auth-flow-patterns)
6. [Screen-Scoped Effects](#screen-scoped-effects)
7. [Deep & Universal Linking](#deep--universal-linking)
8. [React Navigation Variant](#react-navigation-variant)

---

## Expo Router vs React Navigation

| | Expo Router | React Navigation |
|---|-------------|------------------|
| Model | File-based (routes = files) | Imperative (JS config) |
| Deep linking | Automatic from file tree | Manual `linking` config |
| Typed routes | Generated | Manual param lists |
| Web support | First-class | Limited |
| Built on | React Navigation | — |
| Best for | New Expo apps | Max control, existing apps |

Expo Router *is* React Navigation underneath with a file-based router on top. **Recommend Expo Router for new Expo apps**; the concepts below (stacks, tabs, params) apply to both.

---

## Expo Router — File-Based

Routes live in `app/`. The file tree *is* the navigation tree.

```
app/
├── _layout.tsx        # Root navigator + providers
├── index.tsx          # "/"
├── orders/
│   ├── index.tsx      # "/orders"
│   └── [id].tsx       # "/orders/:id" (dynamic)
└── (tabs)/            # route GROUP — folder name in () is not part of the URL
    ├── _layout.tsx    # Tabs navigator
    ├── home.tsx       # "/home"
    └── profile.tsx    # "/profile"
```

- **`_layout.tsx`** defines the navigator (Stack/Tabs) for its directory and renders `<Slot />` or `<Stack />`.
- **`[id].tsx`** is a dynamic route; **`(group)`** organizes routes without adding a URL segment (great for separating auth vs app trees).
- Navigate with `<Link href="/orders/7">` or `useRouter().push("/orders/7")`.

```tsx
// app/_layout.tsx — providers + root Stack
import { Stack } from "expo-router";
import { QueryClientProvider } from "@tanstack/react-query";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { GestureHandlerRootView } from "react-native-gesture-handler";

export default function RootLayout() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <QueryClientProvider client={queryClient}>
          <Stack screenOptions={{ headerShown: false }} />
        </QueryClientProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
```

---

## Typed Routes & Params

Enable typed routes (`experiments.typedRoutes` in `app.config.ts`) so `href`s are checked. Read params with typed hooks:

```tsx
// app/orders/[id].tsx
import { useLocalSearchParams, useRouter } from "expo-router";

export default function OrderDetail() {
  const { id } = useLocalSearchParams<{ id: string }>(); // params are strings
  const router = useRouter();
  const { data: order } = useOrder(Number(id));          // read from Query, not passed-in objects
  return /* … */;
}
```

**Pass IDs, not objects.** Route params should be small serializable values (an `id`), and the screen re-reads the full entity from the TanStack Query cache. Passing large objects through navigation bloats state, goes stale, and breaks deep links. See `references/state.md`.

---

## Nested Navigators

Real apps nest a Stack inside each Tab (so each tab has its own push history):

```
app/
└── (tabs)/
    ├── _layout.tsx          # Tabs
    ├── (home)/
    │   ├── _layout.tsx      # Stack for the Home tab
    │   ├── index.tsx
    │   └── [id].tsx
    └── settings.tsx
```

```tsx
// app/(tabs)/_layout.tsx
import { Tabs } from "expo-router";
export default function TabsLayout() {
  return (
    <Tabs screenOptions={{ headerShown: true }}>
      <Tabs.Screen name="(home)" options={{ title: "Home" }} />
      <Tabs.Screen name="settings" options={{ title: "Settings" }} />
    </Tabs>
  );
}
```

Present modals with a `Stack.Screen` set to `presentation: "modal"` (Expo Router) — natural sheet behavior on iOS.

---

## Auth Flow Patterns

Split the pre-login and post-login trees into route groups and **guard at the group layout** — clean, and impossible to reach app screens unauthenticated:

```tsx
// app/(app)/_layout.tsx — protects the whole authenticated tree
import { Redirect, Stack } from "expo-router";
import { useSession } from "@/features/auth/api/useSession";

export default function AppLayout() {
  const { data: session, isLoading } = useSession(); // session hydrated from secure-store (see references/state.md)
  if (isLoading) return null;                          // keep splash up
  if (!session) return <Redirect href="/(auth)/login" />;
  return <Stack />;
}
```

On login, `router.replace("/(app)")` (replace, not push — the user shouldn't be able to swipe back to login). On logout, clear the session store + secure-store and `router.replace("/(auth)/login")`.

---

## Screen-Scoped Effects

`useEffect` runs while a screen is mounted — but a screen behind another in the stack is still *mounted*, just not focused. For work that must pause when the screen isn't visible (polling, camera, location, subscriptions), use **`useFocusEffect`**:

```tsx
import { useFocusEffect } from "expo-router"; // (or @react-navigation/native)
import { useCallback } from "react";

useFocusEffect(
  useCallback(() => {
    const sub = subscribeToLiveUpdates();
    return () => sub.remove(); // runs on blur AND unmount
  }, [])
);
```

Using plain `useEffect` here leaves the camera on / polling running on a backgrounded screen — battery drain and bugs.

---

## Deep & Universal Linking

Deep links (`myapp://orders/7`) and universal/app links (`https://app.example.com/orders/7`) route straight into a screen. Expo Router wires the *routing* automatically from the file tree; you still configure the scheme/domains and — critically — **validate the input**.

- **Scheme** in `app.config.ts` (`scheme: "myapp"`); **universal links** need iOS Associated Domains + an `apple-app-site-association` file, and Android `intent-filters` + `assetlinks.json` on your domain.
- **Deep-link params are untrusted, attacker-controllable input.** Never authenticate, authorize, pay, or navigate to an arbitrary internal target based on a link alone. Treat `myapp://reset?token=…` and `myapp://open?url=…` as hostile: validate the token server-side, allowlist navigation targets, never `open`-redirect to an arbitrary URL. See `references/security.md`.

---

## React Navigation Variant

Without Expo Router, wire navigators imperatively with typed param lists:

```tsx
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { NavigationContainer } from "@react-navigation/native";

type RootStackParamList = { Orders: undefined; OrderDetail: { id: number } };
const Stack = createNativeStackNavigator<RootStackParamList>();

export function Navigation() {
  return (
    <NavigationContainer>
      <Stack.Navigator>
        <Stack.Screen name="Orders" component={OrdersScreen} />
        <Stack.Screen name="OrderDetail" component={OrderDetailScreen} />
      </Stack.Navigator>
    </NavigationContainer>
  );
}
```

```tsx
// Typed navigation + route
import type { NativeStackScreenProps } from "@react-navigation/native-stack";
type Props = NativeStackScreenProps<RootStackParamList, "OrderDetail">;
function OrderDetailScreen({ route, navigation }: Props) {
  const { id } = route.params; // typed as number
}
```

Use `@react-navigation/native-stack` (native screens, better perf/gestures) over the JS `stack`. Handle the Android hardware back button with the `BackHandler` API where custom behavior is needed.
