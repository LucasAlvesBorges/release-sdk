# React Native Security Reference

Mobile security differs from web: the attacker may **own the device** — root it, attach a debugger, read storage, extract the binary. Aligns with OWASP MASVS. Pairs with the Release `react-security-retro` and `advanced-threat-auditor`.

## Table of Contents

1. [Mobile Threat Model](#mobile-threat-model)
2. [Secure Storage](#secure-storage)
3. [Transport Security & Pinning](#transport-security--pinning)
4. [Deep-Link Validation](#deep-link-validation)
5. [Data at Rest & on Screen](#data-at-rest--on-screen)
6. [Reverse Engineering & the Bundle](#reverse-engineering--the-bundle)
7. [WebView Hardening](#webview-hardening)
8. [OTA Update Integrity](#ota-update-integrity)
9. [Checklist](#checklist)

---

## Mobile Threat Model

Assume: the device may be rooted/jailbroken; storage and the app binary are readable; traffic may be intercepted (MITM proxy); deep links and clipboard are attacker-reachable; and the app is backgrounded into a screenshot. As on web, **the Django API is the security boundary** — the client cannot enforce authorization, and any client-side check is bypassable by someone who owns the device.

---

## Secure Storage

**Tokens, refresh tokens, and PII go in `expo-secure-store`** (iOS Keychain, Android Keystore — hardware-backed, encrypted). **Never** `AsyncStorage` or plain `MMKV`: both are plaintext, recoverable from device backups (`iTunes`/`adb backup`) and trivially read on a rooted device.

```tsx
import * as SecureStore from "expo-secure-store";

export const secureStorage = {
  setToken: (t: string) =>
    SecureStore.setItemAsync("access_token", t, {
      keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY, // not synced/backed up
    }),
  getToken: () => SecureStore.getItemAsync("access_token"),
  clear: () => SecureStore.deleteItemAsync("access_token"),
};
```

Gate especially sensitive values behind biometrics (`requireAuthentication: true`, or an `expo-local-authentication` check before read). Keep the access token short-lived; store only the refresh token long-term.

---

## Transport Security & Pinning

- **HTTPS everywhere.** iOS App Transport Security blocks cleartext by default — don't add exceptions. On Android set `android:usesCleartextTraffic="false"` (network security config).
- **Certificate/SSL pinning** for high-value apps defeats MITM proxies even with a user-installed root CA. Pin to a public-key hash, not a leaf cert, and **ship a backup pin + rotation plan** — a pinned cert that expires with no fallback bricks the app. Libraries: `react-native-ssl-pinning` or a native config. Weigh the operational cost against the threat.

---

## Deep-Link Validation

Deep/universal-link params are **untrusted, attacker-controllable input** — a malicious app or webpage can fire `releaseapp://…` at your app. Never:

- Auto-authenticate or elevate a session from a link (`releaseapp://magic?token=…`) without server-side validation of the token.
- Navigate/redirect to an arbitrary target from a link param (`releaseapp://open?url=…`) — allowlist internal routes only.
- Perform a state-changing action (pay, delete) directly from a link without confirmation + auth.

```tsx
function resolveDeepLink(path: string): string {
  const allowed = ["/orders", "/profile", "/home"]; // allowlist
  return allowed.some((p) => path.startsWith(p)) ? path : "/home";
}
```

Validate the token *on the Django side*; treat the link only as a hint of intent. See `references/navigation.md`.

---

## Data at Rest & on Screen

- **Block screenshots / app-switcher previews** on sensitive screens: Android `FLAG_SECURE` (via `expo-screen-capture`'s `preventScreenCaptureAsync`), and blur/hide content when the app backgrounds (`AppState` → overlay) so the OS snapshot doesn't leak data.
- **Clipboard** — don't auto-copy secrets; clear sensitive values you do copy.
- **Logs** — never `console.log` tokens/PII; they land in device logs and crash reports. Scrub before sending to Sentry.

```tsx
import { AppState } from "react-native";
// Show an opaque overlay while inactive so the OS app-switcher snapshot hides sensitive UI
AppState.addEventListener("change", (s) => setBlurred(s !== "active"));
```

---

## Reverse Engineering & the Bundle

The JS bundle and assets are extractable from the installed app (`.ipa`/`.apk`).

- **No secrets in the bundle** — no API secret keys, no private endpoints as "security". Privileged operations go through the Django API which holds the secret.
- **Obfuscation raises the bar, not the ceiling** — Hermes bytecode and minification slow analysis but don't protect secrets. Don't rely on it.
- **Root/jailbreak detection** (e.g. `jail-monkey`) has limited value — a determined attacker bypasses it — but can gate high-risk features. Fail safe, don't hard-crash legitimate users (custom ROMs trip false positives).

---

## WebView Hardening

A `WebView` loading untrusted content is a serious risk — it can bridge to native and run arbitrary JS in your app.

- **Disable JavaScript** unless required (`javaScriptEnabled={false}`).
- **Allowlist origins** (`originWhitelist`) — never load arbitrary user-supplied URLs.
- **Never bridge native capabilities** (`injectedJavaScript`/`onMessage`) to untrusted pages — a compromised page then drives your native code.
- Prefer an in-app browser (`expo-web-browser`) for external links over an embedded WebView.

---

## OTA Update Integrity

EAS Update ships code over-the-air — treat that channel as security-sensitive:

- **Sign updates** (EAS code signing) so a compromised update server can't push malicious JS.
- **Gate by `runtimeVersion`** so JS never lands on an incompatible native build.
- Roll out via the preview channel first; keep rollback ready. A bad or malicious update reaches every installed app instantly. See `references/native.md`.

---

## Checklist

| Red flag | Risk |
|----------|------|
| Token in `AsyncStorage` / plain MMKV | Recoverable from backup / rooted device |
| Cleartext HTTP / ATS exception | MITM interception |
| Auth/redirect driven by deep-link param | Session hijack / open redirect |
| Secret baked into bundle or `extra` | Extracted from the binary |
| Sensitive screen without `FLAG_SECURE` / background blur | Data leaks via screenshots / app switcher |
| WebView with JS enabled loading untrusted URLs | Native bridge compromise |
| Token/PII in `console.log` | Leaks to device logs / crash reports |
| Unsigned OTA updates | Malicious code push to all users |
