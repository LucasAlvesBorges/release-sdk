# React Native Patterns Reference

Component architecture & styling for RN 0.7x + Expo SDK 50+. For lists/animation cost see `references/performance.md`; for screens/routing, `references/navigation.md`.

## Table of Contents

1. [Styling Architecture](#styling-architecture)
2. [The Screen Primitive](#the-screen-primitive)
3. [Reusable UI Primitives](#reusable-ui-primitives)
4. [Platform-Specific Code](#platform-specific-code)
5. [Keyboard Handling](#keyboard-handling)
6. [Gestures & Touch](#gestures--touch)
7. [Images](#images)
8. [Responsive & Adaptive](#responsive--adaptive)
9. [TypeScript Patterns for RN](#typescript-patterns-for-rn)

---

## Styling Architecture

`StyleSheet.create` is the baseline: it validates styles at creation, lets RN pass styles by reference (cheaper bridging), and — critically — you must **hoist it out of render** so styles aren't rebuilt every frame.

```tsx
// ✅ module scope — created once
const styles = StyleSheet.create({ card: { padding: 16, borderRadius: 12 } });
// ❌ inside the component — new objects every render, and worse inside a list row
```

Raw numbers scattered across files rot. Add a **theme/tokens layer** and a typed `useTheme`:

```tsx
// shared/theme/index.ts
export const theme = {
  spacing: { xs: 4, sm: 8, md: 16, lg: 24 },
  colors: { bg: "#fff", text: "#111", muted: "#666", primary: "#2563eb", danger: "#dc2626" },
  radius: { sm: 8, md: 12, lg: 20 },
  font: { body: 16, title: 20, caption: 13 },
} as const;
export type Theme = typeof theme;
```

For dynamic theming (light/dark), expose the theme via Context or a Zustand store and read it in components. Library options, with tradeoffs:

| Approach | Pros | Cons |
|----------|------|------|
| Vanilla `StyleSheet` + tokens | Zero deps, full control, fastest | More boilerplate, manual theming |
| `nativewind` (Tailwind) | Utility classes, fast iteration, familiar | Build setup, class-string typing |
| `tamagui` | Optimizing compiler, design system, RN+web | Steeper learning curve, heavier |
| `react-native-unistyles` | Themeable `StyleSheet` API, performant | Extra dep, newer |

Start with tokens + `StyleSheet`; adopt a library when the design system justifies it.

---

## The Screen Primitive

Every screen should apply safe-area insets, background, and status-bar config **once**, through a shared wrapper — so no screen hardcodes `paddingTop: 44` (which breaks on every other device).

```tsx
import { SafeAreaView, type Edge } from "react-native-safe-area-context";
import { StatusBar } from "expo-status-bar";
import { StyleSheet, View, type ViewProps } from "react-native";
import { theme } from "@/shared/theme";

type ScreenProps = ViewProps & { edges?: readonly Edge[]; padded?: boolean };

export function Screen({ children, edges = ["top", "bottom"], padded = true, style, ...rest }: ScreenProps) {
  return (
    <SafeAreaView style={styles.safe} edges={edges}>
      <StatusBar style="dark" />
      <View style={[styles.body, padded && styles.padded, style]} {...rest}>
        {children}
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: theme.colors.bg },
  body: { flex: 1 },
  padded: { padding: theme.spacing.md },
});
```

Use `useSafeAreaInsets()` directly only when you need the raw inset numbers (e.g. to pad a scroll view's content or a floating button).

---

## Reusable UI Primitives

Wrap RN primitives in themed components so screens stay declarative and accessible. Interactive elements always get `accessibilityRole`, `accessibilityLabel`, and a `hitSlop`.

```tsx
import { Pressable, Text, StyleSheet, type PressableProps } from "react-native";
import { theme } from "@/shared/theme";

type ButtonProps = PressableProps & { title: string; variant?: "primary" | "danger" };

export function Button({ title, variant = "primary", disabled, ...rest }: ButtonProps) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={title}
      accessibilityState={{ disabled: !!disabled }}
      hitSlop={8}
      disabled={disabled}
      style={({ pressed }) => [
        styles.base,
        { backgroundColor: variant === "danger" ? theme.colors.danger : theme.colors.primary },
        pressed && styles.pressed,
        disabled && styles.disabled,
      ]}
      {...rest}
    >
      <Text style={styles.label}>{title}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  base: { paddingVertical: 12, paddingHorizontal: 20, borderRadius: theme.radius.md, alignItems: "center" },
  pressed: { opacity: 0.7 },
  disabled: { opacity: 0.4 },
  label: { color: "#fff", fontSize: theme.font.body, fontWeight: "600" },
});
```

Remember: **all text must be inside `<Text>`** — a bare string in a `<View>` crashes at runtime.

---

## Platform-Specific Code

Small divergences → `Platform.select` / `Platform.OS`:

```tsx
import { Platform } from "react-native";
const cardShadow = Platform.select({
  ios: { shadowColor: "#000", shadowOpacity: 0.1, shadowRadius: 8, shadowOffset: { width: 0, height: 2 } },
  android: { elevation: 4 },        // iOS shadow props do nothing on Android; use elevation
  default: {},
});
```

Large divergences → **platform files**. `Button.ios.tsx` and `Button.android.tsx` (import `./Button`) — Metro resolves the right one automatically. Expect divergence in: shadows/elevation, the Android hardware back button, keyboard behavior, ripple vs opacity feedback, date/picker components, and permission dialogs.

---

## Keyboard Handling

The keyboard covering an input is a top complaint. `KeyboardAvoidingView` behavior differs by platform:

```tsx
import { KeyboardAvoidingView, Platform, ScrollView, Keyboard, TouchableWithoutFeedback } from "react-native";

<KeyboardAvoidingView behavior={Platform.OS === "ios" ? "padding" : "height"} style={{ flex: 1 }}>
  <TouchableWithoutFeedback onPress={Keyboard.dismiss} accessible={false}>
    <ScrollView keyboardShouldPersistTaps="handled">{/* form */}</ScrollView>
  </TouchableWithoutFeedback>
</KeyboardAvoidingView>
```

`keyboardShouldPersistTaps="handled"` lets a tap on a button work while the keyboard is up (otherwise the first tap only dismisses the keyboard). For complex forms (sticky footers, precise scroll-to-input), `react-native-keyboard-controller` gives far better control than the core component.

---

## Gestures & Touch

Prefer `Pressable` (flexible, gives `pressed` state, `hitSlop`) over the legacy `TouchableOpacity`/`TouchableWithoutFeedback`. For real gestures (swipe-to-delete, pan, pinch), use `react-native-gesture-handler` driving a `react-native-reanimated` worklet so the gesture runs on the UI thread:

```tsx
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated, { useAnimatedStyle, useSharedValue, withSpring } from "react-native-reanimated";

function Draggable() {
  const x = useSharedValue(0);
  const pan = Gesture.Pan()
    .onChange((e) => { x.value += e.changeX; })
    .onEnd(() => { x.value = withSpring(0); });
  const style = useAnimatedStyle(() => ({ transform: [{ translateX: x.value }] }));
  return <GestureDetector gesture={pan}><Animated.View style={style} /></GestureDetector>;
}
```

See `references/performance.md` for why UI-thread animation matters. Wrap the app root in `GestureHandlerRootView`.

---

## Images

Use **`expo-image`** over the core `<Image>` — it caches to disk/memory, decodes efficiently, and supports blurhash placeholders and transitions:

```tsx
import { Image } from "expo-image";

<Image
  source={{ uri: order.thumbnailUrl }}
  style={{ width: 96, height: 96, borderRadius: 12 }}   // ALWAYS size remote images
  contentFit="cover"
  placeholder={{ blurhash }}
  transition={200}
  cachePolicy="memory-disk"
/>
```

Unsized remote images cause layout shift as they load. For lists, sizing + caching is also a scroll-performance issue (see `references/performance.md`).

---

## Responsive & Adaptive

Use `useWindowDimensions()` (a hook that re-renders on rotation/resize) over the static `Dimensions.get()` (a snapshot that goes stale). Design with flex, not fixed pixels; respect a **44×44pt minimum tap target**; and account for tablets and foldables (wider layouts, split views).

```tsx
import { useWindowDimensions } from "react-native";
const { width } = useWindowDimensions();
const columns = width > 700 ? 2 : 1; // adapt layout to available width
```

---

## TypeScript Patterns for RN

- **Style prop types:** `StyleProp<ViewStyle>` / `StyleProp<TextStyle>` / `StyleProp<ImageStyle>` accept a style, an array, or falsy — matching how RN styles compose.
- **Extend native props:** `type Props = PressableProps & { title: string }` inherits `onPress`, `accessibilityRole`, etc.
- **Variant unions** (`variant?: "primary" | "danger"`) keep styling type-safe.
- **Refs:** type component refs (`useRef<TextInput>(null)`) so `.focus()` is checked.

```tsx
import type { StyleProp, ViewStyle } from "react-native";
type CardProps = { style?: StyleProp<ViewStyle>; children: React.ReactNode };
```
