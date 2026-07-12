# React Frontend Security Reference

The browser is a hostile, fully-inspectable environment. This pairs with the Release `react-security-guard` hook and the `security-auditor`. For the Django side, see [[django-expert]] `references/security.md`.

## Table of Contents

1. [Trust Boundaries](#trust-boundaries)
2. [XSS — The Dominant Threat](#xss--the-dominant-threat)
3. [Auth Token Handling](#auth-token-handling)
4. [CSRF with Cookie Auth](#csrf-with-cookie-auth)
5. [Content-Security-Policy](#content-security-policy)
6. [Clickjacking & Open Redirects](#clickjacking--open-redirects)
7. [Dependency & Supply-Chain](#dependency--supply-chain)
8. [Secrets & the Public Bundle](#secrets--the-public-bundle)
9. [Red-Flags Checklist](#red-flags-checklist)

---

## Trust Boundaries

The golden rule: **the frontend cannot enforce security — the Django API does.** Everything shipped to the browser is readable and modifiable by the user. Therefore:

- **Authorization is always enforced server-side.** Client-side route guards (`if (!user.isAdmin) redirect`) are *UX* — they hide UI the user can't use. They are not security. A user can call the API directly; the endpoint must reject them.
- **Never trust client-sent flags** for authz (`?isAdmin=true`, a hidden form field, a JWT claim the client could forge if unsigned).
- The frontend's security job is narrower: don't *introduce* vulnerabilities (XSS), handle credentials safely, and don't leak secrets.

---

## XSS — The Dominant Threat

Cross-site scripting = attacker-controlled data executes as script in your origin, with access to the DOM, cookies (non-httpOnly), and any token in JS. React escapes text by default — `{userInput}` renders as text, not HTML. XSS enters where you leave that protection:

**1. `dangerouslySetInnerHTML`** — the #1 vector. Only ever with sanitized or provably-safe HTML:

```tsx
import DOMPurify from "dompurify";

function RichText({ html }: { html: string }) {
  const clean = useMemo(() => DOMPurify.sanitize(html, { USE_PROFILES: { html: true } }), [html]);
  return <div dangerouslySetInnerHTML={{ __html: clean }} />;
}
```

**2. URLs from user input** — `javascript:` URIs execute on click:

```tsx
// ❌ href={user.website} → "javascript:alert(document.cookie)" runs
function isSafeHref(url: string) {
  try { const u = new URL(url, window.location.origin); return u.protocol === "http:" || u.protocol === "https:"; }
  catch { return false; }
}
<a href={isSafeHref(user.website) ? user.website : "#"} rel="noopener noreferrer">site</a>
```

The same applies to `<img src>`, `<iframe src>`, and anything assigned to `window.location`.

**3. Injecting into non-React DOM** — `ref.current.innerHTML = data`, or passing unsanitized data to a third-party charting/map lib that renders HTML. Bypasses React's escaping entirely.

**4. SVG and `<use>`** — inline SVG with user content, and `dangerouslySetInnerHTML` with `<svg>` containing `<script>` or event handlers. Sanitize SVG too.

**5. `eval` / `new Function` / template rendering** on user input — never.

---

## Auth Token Handling

Where the access token lives determines your XSS blast radius. Ranked:

| Storage | XSS-readable? | Survives reload? | CSRF-exposed? | Verdict |
|---------|---------------|------------------|---------------|---------|
| `localStorage` / `sessionStorage` | **Yes** — any XSS steals it | Yes | No | ❌ Red flag |
| JS memory (a store variable) | Yes, but only live-page XSS | No | No | ✅ for access token |
| httpOnly + Secure + SameSite cookie | **No** — JS can't read it | Yes | Yes → need CSRF | ✅ for refresh token |

**Recommended pattern with DRF:** the refresh token in an **httpOnly, Secure, SameSite=Strict/Lax cookie** set by Django (JS never touches it); a **short-lived access token held in memory** (a Zustand store, see `references/state.md`), lost on reload and re-obtained by calling `/token/refresh/` which reads the cookie. On `401`, the HTTP client refreshes once and retries.

```tsx
// In memory only — gone on refresh, re-fetched via the httpOnly refresh cookie
const token = useAuthStore.getState().accessToken;
apiClient.interceptors.request.use((c) => {
  if (token) c.headers.Authorization = `Bearer ${token}`;
  return c;
});
```

**`localStorage` for tokens is a red flag** in review: a single XSS anywhere on the origin exfiltrates every user's session. The convenience (surviving reload without a refresh call) is not worth it.

---

## CSRF with Cookie Auth

The moment you authenticate with cookies, you need CSRF protection — a malicious site can make the browser send your cookie on a forged request. Two layers:

1. **`SameSite=Lax` (or `Strict`)** on the auth cookie — the browser won't send it on cross-site POSTs. This alone stops most CSRF.
2. **Django's CSRF token** — read the `csrftoken` cookie and echo it in the `X-CSRFToken` header on unsafe methods:

```tsx
function getCookie(name: string) {
  return document.cookie.split("; ").find((r) => r.startsWith(name + "="))?.split("=")[1];
}
apiClient.interceptors.request.use((config) => {
  if (["post", "put", "patch", "delete"].includes(config.method ?? "")) {
    const csrf = getCookie("csrftoken");
    if (csrf) config.headers["X-CSRFToken"] = decodeURIComponent(csrf);
  }
  return config;
});
```

Pure `Authorization: Bearer` header auth (token not in a cookie) is not CSRF-exposed — the browser doesn't auto-attach headers — but then the token lives in JS (XSS-exposed). Pick your tradeoff deliberately; the httpOnly-refresh + in-memory-access pattern balances both.

---

## Content-Security-Policy

A CSP is defense-in-depth against XSS: even if an injection lands, the browser refuses to run disallowed scripts. Served as a response header (configure in Django/your CDN):

```
Content-Security-Policy:
  default-src 'self';
  script-src 'self';                 /* no inline scripts, no eval */
  style-src 'self' 'unsafe-inline';  /* relax only if a lib requires it */
  img-src 'self' data: https:;
  connect-src 'self' https://api.yourdomain.com;
  frame-ancestors 'none';
```

- Avoid `'unsafe-inline'`/`'unsafe-eval'` in `script-src` — they defeat the point. Use a per-response `nonce` or hashes if you need an inline script.
- Add `report-uri`/`report-to` to collect violations before enforcing.

---

## Clickjacking & Open Redirects

- **Clickjacking** — your app framed by an attacker to trick clicks. Block framing with `frame-ancestors 'none'` (CSP) or `X-Frame-Options: DENY`.
- **Open redirects** — a `?next=` / `returnTo` param used verbatim in navigation lets attackers bounce users to a phishing site under your domain's trust. Allowlist redirect targets to same-origin, relative paths:

```tsx
function safeRedirect(next: string | null) {
  // only allow same-origin relative paths, never absolute URLs
  return next && next.startsWith("/") && !next.startsWith("//") ? next : "/";
}
```

---

## Dependency & Supply-Chain

Your bundle ships every transitive dependency to users — a compromised package runs in your origin.

- **`npm audit`** in CI; fail on high/critical. Automate updates with Dependabot/Renovate.
- **Commit the lockfile** (`package-lock.json`/`pnpm-lock.yaml`) and install with `npm ci` for reproducible, tamper-evident builds.
- **Minimize dependencies** — every `dependency` is attack surface. Prefer a 10-line util over a package.
- **Pin and review** major updates of anything that touches auth, network, or rendering of user content.

---

## Secrets & the Public Bundle

Everything in the frontend build is public — `view-source` and DevTools reveal it all.

- **No secrets in the bundle.** No API secret keys, no service credentials, no signing keys. If the browser needs to do something privileged, it goes through your Django API which holds the secret.
- **`VITE_*` env vars are public by design** — Vite inlines them into client code. `VITE_API_URL` is fine; `VITE_STRIPE_SECRET` is a breach. Server-only secrets never get the `VITE_` prefix.
- **No security-by-obscurity** — a "hidden" admin route or an undocumented endpoint is not protection; authz enforces it.

---

## Red-Flags Checklist

| Red flag | Why it's dangerous |
|----------|-------------------|
| Auth token in `localStorage`/`sessionStorage` | Any XSS exfiltrates every session |
| `dangerouslySetInnerHTML` without DOMPurify | Direct XSS |
| `href`/`src`/`location` from user input, unchecked | `javascript:` URI XSS / open redirect |
| Client-side `isAdmin` check with no server enforcement | Authz bypass via direct API call |
| Secret with `VITE_` prefix | Secret shipped to browser |
| No lockfile / no `npm audit` in CI | Supply-chain compromise |
| `?next=`/`returnTo` used without allowlist | Open redirect / phishing |
| Missing CSP / `frame-ancestors` | No XSS defense-in-depth, clickjacking |
