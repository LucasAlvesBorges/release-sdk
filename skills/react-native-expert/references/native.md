# React Native Native Modules, Permissions & Delivery Reference

Bridging to platform capabilities the Expo way, doing permissions right, and shipping with EAS. Prefer Expo/community modules before writing native code.

## Table of Contents

1. [Managed vs Bare/Prebuild](#managed-vs-bareprebuild)
2. [Dynamic Config](#dynamic-config)
3. [Config Plugins](#config-plugins)
4. [Permissions Done Right](#permissions-done-right)
5. [Common Expo Modules](#common-expo-modules)
6. [Writing Native Modules](#writing-native-modules)
7. [EAS Build](#eas-build)
8. [EAS Update — OTA](#eas-update--ota)

---

## Managed vs Bare/Prebuild

- **Managed workflow** — you write only JS/TS; Expo owns the native projects. Native capabilities come from Expo modules and **config plugins**. Simplest, fastest upgrades.
- **Prebuild** — Expo *generates* the `ios/`/`android/` projects from your config (`npx expo prebuild`); you can add custom native code but regenerate carefully.
- **Bare** — you own the native projects fully. Maximum control, maximum maintenance.

Default to managed + config plugins. Reach for prebuild/bare only when a capability truly has no module. Every line of native code is build complexity, upgrade risk, and platform-specific bugs.

---

## Dynamic Config

Use `app.config.ts` (TypeScript, dynamic) over static `app.json` so config can read env and stay typed:

```ts
// app.config.ts
import type { ExpoConfig } from "expo/config";

export default (): ExpoConfig => ({
  name: "ReleaseApp",
  slug: "release-app",
  scheme: "releaseapp",                 // deep-link scheme
  ios: { supportsTablet: true, bundleIdentifier: "com.release.app" },
  android: { package: "com.release.app" },
  plugins: [
    "expo-router",
    ["expo-location", { locationWhenInUsePermission: "Show nearby orders." }],
  ],
  extra: { apiUrl: process.env.API_URL },  // read via expo-constants at runtime
  experiments: { typedRoutes: true },
});
```

Never bake secrets into `extra` — it ships in the bundle. Use EAS secrets for build-time values and your API for runtime secrets (see `references/security.md`).

---

## Config Plugins

Config plugins inject native configuration (permissions, Info.plist keys, Gradle tweaks, native deps) **without ejecting** — they run during prebuild. Most Expo modules ship one; you can write a small one for custom native config:

```ts
// plugins/withCustomScheme.ts — trivial example: add an Info.plist key
import { withInfoPlist, type ConfigPlugin } from "expo/config-plugins";

const withCustom: ConfigPlugin = (config) =>
  withInfoPlist(config, (cfg) => {
    cfg.modResults.ITSAppUsesNonExemptEncryption = false; // skip the export-compliance prompt
    return cfg;
  });

export default withCustom;
```

Add it to `plugins` in `app.config.ts`. Plugins are how you stay in the managed workflow while still customizing native.

---

## Permissions Done Right

Three rules keep you shipping and out of App Store rejection:

1. **Request in context** — ask when the user takes the action that needs it, with a rationale first, not on app launch.
2. **Declare purpose strings** — iOS requires `NS*UsageDescription` (via the module's plugin option); Android needs the manifest permission. Missing/empty purpose strings = **guaranteed App Store rejection**.
3. **Handle denial gracefully** — never crash or loop; explain and offer a deep-link to Settings.

```tsx
import * as Location from "expo-location";
import { Linking } from "react-native";

async function ensureLocation(): Promise<boolean> {
  const { status, canAskAgain } = await Location.requestForegroundPermissionsAsync();
  if (status === "granted") return true;
  if (!canAskAgain) Linking.openSettings(); // user permanently denied → send to Settings
  return false;
}
```

Most Expo modules also expose a hook (`Location.useForegroundPermissions()`) for reactive permission state.

---

## Common Expo Modules

| Need | Module | Notes |
|------|--------|-------|
| Secure storage | `expo-secure-store` | Keychain/Keystore — tokens/PII |
| Push notifications | `expo-notifications` | Get Expo push token; Android needs channels; handle foreground vs tapped |
| Biometrics | `expo-local-authentication` | Face ID / fingerprint gate; check `hasHardwareAsync` + `isEnrolledAsync` |
| Camera | `expo-camera` | Permission + purpose string |
| Location | `expo-location` | Foreground/background are separate permissions |
| Files | `expo-file-system` | Download, cache, read/write app sandbox |
| Splash | `expo-splash-screen` | `preventAutoHideAsync` → hide when first screen ready |
| Constants/env | `expo-constants` | Read `extra` from config |

Push example (register + handle):

```tsx
import * as Notifications from "expo-notifications";
const { status } = await Notifications.requestPermissionsAsync();
if (status === "granted") {
  const token = (await Notifications.getExpoPushTokenAsync()).data; // send to Django, associate with user
}
```

---

## Writing Native Modules

When no module exists, the modern path is the **Expo Modules API** (Swift/Kotlin, clean TS interface) or RN's **TurboModules/JSI** for high-performance synchronous bridging. Whichever you use:

- **Isolate it behind a plain TS interface** so the rest of the app doesn't know it's native.
- Handle the platform that *doesn't* implement it (feature-detect, graceful fallback).
- Keep the bridge surface small; batch calls (crossing the JS↔native boundary has cost).

Only do this when the capability is real and unserved — it's the highest-maintenance code in the app.

---

## EAS Build

EAS Build produces store-ready binaries in the cloud with managed credentials. Profiles in `eas.json`:

```json
{
  "build": {
    "development": { "developmentClient": true, "distribution": "internal" },
    "preview": { "distribution": "internal", "channel": "preview" },
    "production": { "channel": "production", "autoIncrement": true }
  }
}
```

- **development** — a dev client with debugging, for daily work.
- **preview** — internal distribution (TestFlight / internal track) for QA.
- **production** — store submission; `autoIncrement` bumps build numbers.

EAS manages signing certs/keystores so you don't hand-juggle credentials.

---

## EAS Update — OTA

EAS Update ships JS/asset changes over-the-air without a store review — for bug fixes and small features (not native changes, which need a new build).

- **`runtimeVersion`** gates compatibility: an update only reaches builds with a matching runtime version. Bump it whenever native code/SDK changes, or you'll push JS that references missing native modules → crash loop.
- **Channels** map builds to update streams (`preview`, `production`); roll out to preview first.
- **Roll out carefully and keep rollback ready** — a bad OTA update can crash-loop *every installed app*. Test the update on the preview channel before promoting.
- **Sign updates** and gate by runtime version — treat OTA integrity as a security concern (see `references/security.md`).
