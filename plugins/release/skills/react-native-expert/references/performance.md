# React Native Performance Reference

Mobile performance is dropped frames and cold-start seconds — measured on a real mid-range Android, not the simulator. For component structure see `references/patterns.md`.

## Table of Contents

1. [Lists — the #1 Topic](#lists--the-1-topic)
2. [FlashList](#flashlist)
3. [FlatList Tuning](#flatlist-tuning)
4. [Animation on the UI Thread](#animation-on-the-ui-thread)
5. [Hermes](#hermes)
6. [Memory Leaks](#memory-leaks)
7. [Image Optimization](#image-optimization)
8. [Cold-Start Reduction](#cold-start-reduction)
9. [Profiling](#profiling)

---

## Lists — the #1 Topic

The most common RN performance disaster is rendering a long list with `.map()` inside a `ScrollView`. A `ScrollView` mounts **every** child immediately — 500 rows = 500 mounted components and their subtrees, blowing memory and freezing the first render.

Anything beyond a handful of items must be a **virtualized list** (`FlatList`/`SectionList`), and large or complex lists should be **`@shopify/flash-list`**. Never nest a virtualized list inside a same-direction `ScrollView` — it disables virtualization (RN warns you), reintroducing the original problem.

---

## FlashList

`@shopify/flash-list` recycles views (like native `RecyclerView`/`UICollectionView`) instead of mounting one component per row, dramatically cutting memory and blank cells during fast scroll.

```tsx
import { FlashList } from "@shopify/flash-list";

const renderItem = ({ item }: { item: Order }) => <OrderRow order={item} />; // hoisted, not inline

function OrderList({ orders }: { orders: Order[] }) {
  return (
    <FlashList
      data={orders}
      renderItem={renderItem}
      keyExtractor={(o) => String(o.id)}
      estimatedItemSize={72}          // required — measure a typical row
      getItemType={(o) => o.kind}     // return a type per row for heterogeneous lists → better recycling
    />
  );
}
```

Rules for smooth lists (apply to `FlatList` too):

- **Hoist `renderItem`** and wrap the row in `React.memo` — inline `renderItem`/styles allocate on every scroll frame.
- **Stable `keyExtractor`** — never index; corrupts recycled row state.
- **`estimatedItemSize`** close to reality — bad estimates cause layout thrash.
- Keep row components light; defer expensive per-row work.

---

## FlatList Tuning

When you use core `FlatList`, these props control the memory/blank-cell tradeoff:

```tsx
<FlatList
  data={orders}
  renderItem={renderItem}
  keyExtractor={(o) => String(o.id)}
  getItemLayout={(_, i) => ({ length: 72, offset: 72 * i, index: i })} // fixed-height → skips async layout
  initialNumToRender={10}
  maxToRenderPerBatch={10}
  windowSize={7}              // viewports of content to keep mounted (default 21)
  removeClippedSubviews       // unmount off-screen rows (Android esp.)
/>
```

`getItemLayout` (only for fixed-height rows) is the biggest single `FlatList` win — it enables instant `scrollToIndex` and skips measurement. For anything heterogeneous or heavy, prefer FlashList.

---

## Animation on the UI Thread

The JS thread runs your logic; if it's busy, JS-thread animations stutter. **`react-native-reanimated` 3** runs animations and gesture logic in **worklets on the UI thread**, so they stay at 60fps even under JS load. The core `Animated` API (non-native-driver) runs on JS and drops frames — avoid it for anything interactive.

```tsx
import Animated, { useSharedValue, useAnimatedStyle, withTiming, runOnJS } from "react-native-reanimated";

const opacity = useSharedValue(0);
const style = useAnimatedStyle(() => ({ opacity: opacity.value })); // reads shared value in a worklet
opacity.value = withTiming(1, { duration: 250 });                    // animates on the UI thread
// To call JS from a worklet (e.g. after an animation): runOnJS(callback)()
```

Key rules:
- **Never read `sharedValue.value` during React render** (JSX) — it's a UI-thread value; read it inside `useAnimatedStyle`/worklets.
- Use `runOnJS` to hop back to the JS thread; use `runOnUI` to push work to the UI thread.
- Prefer `Layout` animations and `entering`/`exiting` for list/mount transitions.

---

## Hermes

Hermes is the default JS engine in modern RN/Expo. It compiles JS to bytecode ahead of time, giving **faster startup**, **lower memory**, and smaller heap than JSC. Keep it on. Verify with `global.HermesInternal != null`. Ship source maps (`compilerSourcemap`) so production stack traces (Sentry) symbolicate.

---

## Memory Leaks

Mobile apps are long-lived — leaks accumulate and crash on low-memory devices. The usual culprits, all fixed by cleaning up in `useEffect`'s return:

```tsx
useEffect(() => {
  const sub = AppState.addEventListener("change", onChange);
  const kb = Keyboard.addListener("keyboardDidShow", onShow);
  const timer = setInterval(poll, 5000);
  return () => { sub.remove(); kb.remove(); clearInterval(timer); }; // ← without this, they leak & fire after unmount
}, []);
```

Also leak-prone: geolocation `watchPosition`, `NetInfo` subscriptions, event emitters from native modules, and effects that should be **screen-scoped** — use `useFocusEffect` (see `references/navigation.md`) so polling/camera pause when the screen loses focus instead of running forever in the background.

---

## Image Optimization

Images are the biggest memory consumer in most apps.

- **`expo-image`** with `cachePolicy="memory-disk"` — caches decoded images, avoids re-decoding on scroll.
- **Always set explicit `width`/`height`** — prevents layout shift and lets the list compute layout.
- Request **appropriately-sized** images from the backend (thumbnails for lists, full-res only on detail) — don't download a 4000px photo for a 96px avatar.
- `Image.prefetch(url)` to warm the cache before a screen that needs it.

---

## Cold-Start Reduction

Time-to-interactive on launch is a product metric.

- **Keep the initial bundle lean** — defer heavy screens via navigation lazy-loading; don't import a charting/video lib at the module top level of the root.
- **`InteractionManager.runAfterInteractions`** to defer non-critical work (analytics, prefetch) until after the first screen's animations settle.
- **Inline requires / RAM bundles** and Hermes keep parse/eval cheap.
- Show a native splash (`expo-splash-screen`) and hide it only when the first screen's data is ready — perceived performance.

---

## Profiling

Measure on a real low-to-mid-range Android (the simulator hides jank):

- **On-device performance monitor** (dev menu) — JS and UI thread FPS; watch for UI-thread dips (native/layout) vs JS-thread dips (your logic).
- **React DevTools Profiler** — component render cost, same as web.
- **Flipper** / **Hermes sampling profiler** — CPU profiles, native traces.
- **EAS Build** production profiling and Sentry performance for real-user metrics (cold start, slow frames).

Golden rule: a smooth scroll and a sub-2s cold start on a cheap Android means it's smooth everywhere.
