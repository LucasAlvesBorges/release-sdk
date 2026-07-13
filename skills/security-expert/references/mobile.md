# Auditoria de Segurança Mobile — React Native / Expo (CAT-14)

Deep-dive da categoria mobile do [[security-expert]]. O modelo de ameaça **muda**: o atacante pode ser o **dono do dispositivo** — root/jailbreak, debugger anexado, binário extraído (`.ipa`/`.apk`), storage lido, tráfego interceptado por proxy MITM com CA instalada. Alinha com **OWASP MASVS**.

Par defensivo (como escrever certo, do lado do engenheiro): [[react-native-expert]] `references/security.md`. No pipeline `/release:security`, a cobertura profunda mobile mora em `release:advanced-threat-auditor` e `release:react-security-retro`.

**Diferença crucial vs. web:** no browser, o atacante ataca *outro* usuário (XSS rouba a sessão da vítima). No mobile, ele frequentemente ataca *o device que já controla* — então "esconder no cliente" nunca é proteção, storage local é território hostil, e a API Django continua sendo a única fronteira de segurança real.

---

## Recon mobile

```bash
# Storage de tokens — deve ser expo-secure-store, nunca AsyncStorage/MMKV plaintext
grep -rn "AsyncStorage\|new MMKV(\|from 'react-native-mmkv'" --include="*.ts" --include="*.tsx" src/ app/ 2>/dev/null \
  | grep -iE "token|jwt|refresh|secret|password|senha"

# Handlers de deep link (todo param é input hostil)
grep -rn "getInitialURL\|useURL\|Linking.addEventListener\|useLocalSearchParams\|useGlobalSearchParams" \
  --include="*.ts" --include="*.tsx" .

# WebView (bridge nativo + execução de JS não confiável)
grep -rn "WebView\|javaScriptEnabled\|injectedJavaScript\|onMessage" --include="*.tsx" .

# Transporte cleartext / exceções ATS
grep -rn "usesCleartextTraffic\|NSAllowsArbitraryLoads\|NSExceptionDomains\|http://" \
  app.config.* app.json 2>/dev/null

# Config de OTA (updates não assinados / sem gate de runtime)
grep -rn "runtimeVersion\|codeSigning\|EXPO_UPDATE" app.config.* app.json eas.json 2>/dev/null

# Segredos embutidos no config (vai pro bundle)
grep -rn "extra\s*:" app.config.* app.json 2>/dev/null
```

---

## 🔴 CAT-14.1: Secure Storage — tokens fora do Keychain/Keystore

**O que procurar:**
- Access/refresh token, PII ou segredo em `AsyncStorage` — **plaintext**, recuperável de backup (`adb backup`, backup do iTunes/iCloud) e trivial de ler em device com root.
- `react-native-mmkv` sem `encryptionKey` guardando token (MMKV é plaintext por padrão).
- `expo-secure-store` usado, mas sem `keychainAccessible` restrito (sincroniza pra iCloud Keychain / vai pro backup).
- Token de longa duração guardado direto em vez de só o refresh; access token deveria ser curto e em memória.

**PoC de ataque:**
```bash
# Android com allowBackup=true (padrão em muitos apps) — sem root:
adb backup -f app.ab com.release.app
# desempacota o .ab → tar → procura o storage do AsyncStorage (SQLite "RKStorage" ou arquivos)
strings apps/com.release.app/**/RKStorage | grep -iE "token|jwt|refresh"

# Device com root:
cat /data/data/com.release.app/databases/RKStorage      # AsyncStorage em claro
cat /data/data/com.release.app/files/mmkv/mmkv.default   # MMKV em claro
```

```tsx
// ❌ VULNERÁVEL — token em claro, recuperável de backup / root
await AsyncStorage.setItem("access_token", token);
new MMKV().set("refresh_token", refresh);

// ✅ SEGURO — Keychain (iOS) / Keystore (Android), hardware-backed, sem backup/sync
import * as SecureStore from "expo-secure-store";
await SecureStore.setItemAsync("refresh_token", refresh, {
  keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY, // não sincroniza, não vai pro backup
  requireAuthentication: true,                                    // opcional: gate biométrico na leitura
});
```

**Checklist:**
- [ ] Nenhum token/refresh/PII em `AsyncStorage` ou `MMKV` plaintext?
- [ ] Tokens em `expo-secure-store` com `WHEN_UNLOCKED_THIS_DEVICE_ONLY`?
- [ ] Access token curto + em memória; só o refresh persistido?
- [ ] `android:allowBackup="false"` para apps que guardam dados sensíveis?
- [ ] Valores de alto risco atrás de biometria (`requireAuthentication`)?

---

## 🔴 CAT-14.2: Deep / Universal Link como input hostil

**O que procurar:**
- Sessão concedida ou elevada a partir de um link (`releaseapp://magic?token=…`) sem validação server-side do token.
- Redirect/navegação para alvo arbitrário vindo de um param de link (`releaseapp://open?url=…`) — open redirect / phishing dentro do app.
- Ação de estado (pagar, deletar, transferir) disparada direto do link, sem confirmação + re-auth.
- Param de link fluindo pra `WebView`, `Linking.openURL`, ou pra uma query sem sanitização.

**PoC de ataque:**
```
# Página web ou app malicioso dispara o scheme do app da vítima:
<a href="releaseapp://reset?token=ATACANTE_CONTROLA">clique</a>

# Se o handler auto-autentica com o token do link → hijack de sessão
# Se navega pro ?url= → open redirect pra página de phishing com a marca do app
releaseapp://open?url=https://evil.com/login-falso
```

```tsx
// ✅ SEGURO — allowlist de rotas internas; token validado no backend, nunca no cliente
function resolveDeepLink(path: string): string {
  const allowed = ["/orders", "/profile", "/home"];
  return allowed.some((p) => path.startsWith(p)) ? path : "/home";
}
// magic-link: o link é só um HINT de intenção. O token vai pra API Django,
// que valida (single-use, expira <1h) e devolve a sessão. O app nunca confia no link sozinho.
```

**Checklist:**
- [ ] Params de deep/universal link tratados como não confiáveis?
- [ ] Nenhuma auto-autenticação/elevação de sessão só com base num link?
- [ ] Navegação restrita a allowlist de rotas internas (sem `open?url=` arbitrário)?
- [ ] Ação de estado exige confirmação + re-auth, nunca dispara direto do link?
- [ ] Token de magic-link validado **no Django** (single-use, curto), não no app?

---

## 🟠 CAT-14.3: Transporte — cleartext & SSL pinning

**O que procurar:**
- HTTP cleartext em produção; exceção de ATS no iOS (`NSAllowsArbitraryLoads`) ou `usesCleartextTraffic="true"` no Android.
- Ausência de certificate/SSL pinning em apps de alto valor (permite MITM com CA instalada pelo usuário/atacante).
- Pinning **sem backup pin nem plano de rotação** — cert que expira sem fallback **brica o app instalado**.

```tsx
// ✅ pin por hash de chave pública + backup pin (rotação sem brickar)
// react-native-ssl-pinning ou config nativa; nunca pinar só o leaf cert
```

**Checklist:**
- [ ] HTTPS em tudo; sem exceção ATS / `usesCleartextTraffic`?
- [ ] Pinning (quando aplicável) com **backup pin** + plano de rotação?
- [ ] Pin é de chave pública, não do certificado folha?

---

## 🟠 CAT-14.4: Dados em repouso e na tela

**O que procurar:**
- Tela sensível sem `FLAG_SECURE` (Android) → screenshot / snapshot do app-switcher vaza o conteúdo.
- App não borra/oculta conteúdo ao ir pra background → o snapshot do OS no multitarefa expõe dados.
- `console.log(token)` / PII → cai no log do device (`logcat`) e em crash reports/Sentry sem scrub.
- Segredo copiado pro clipboard e não limpo (outros apps leem o clipboard).

```tsx
import * as ScreenCapture from "expo-screen-capture";
ScreenCapture.preventScreenCaptureAsync();                 // FLAG_SECURE na tela sensível

import { AppState } from "react-native";
AppState.addEventListener("change", (s) => setBlurred(s !== "active")); // overlay opaco no background
```

**Checklist:**
- [ ] Telas sensíveis com `FLAG_SECURE` / `preventScreenCaptureAsync`?
- [ ] Blur/overlay ao ir pra background (snapshot do app-switcher)?
- [ ] Nenhum `console.log` de token/PII; Sentry com scrub de PII?
- [ ] Clipboard sensível limpo após uso?

---

## 🟡 CAT-14.5: Bundle extraível & segredos embutidos

**O que procurar:**
- Segredo em `extra` (`app.config.ts`), em constante JS, ou em qualquer coisa que vá pro bundle — o `.ipa`/`.apk` é extraível e o bundle Hermes é desmontável.
- "Endpoint escondido" ou autorização client-side tratados como segurança.
- Confiança em obfuscação — bytecode Hermes e minificação atrasam análise, não protegem segredo.

```ts
// ❌ VULNERÁVEL — vai pro bundle, extraível do binário
extra: { apiSecret: "sk-123456" }

// ✅ CORRETO — só valores públicos; segredo fica na API Django
extra: { apiUrl: process.env.API_URL }
```

**Checklist:**
- [ ] Nenhum segredo/chave privada em `extra`, constante ou bundle?
- [ ] Operação privilegiada passa pela API (que guarda o segredo), não pelo app?
- [ ] Autorização é enforçada no Django, não por condicional/rota escondida no app?

---

## 🟠 CAT-14.6: WebView insegura

**O que procurar:**
- `WebView` com `javaScriptEnabled` carregando conteúdo não confiável (pode rodar JS arbitrário no contexto do app).
- Sem `originWhitelist` → carrega URL arbitrária controlada pelo usuário.
- Bridge `injectedJavaScript` / `onMessage` expondo capacidade nativa a uma página potencialmente comprometida.

```tsx
// ✅ SEGURO — origens restritas, sem bridge pra conteúdo não confiável;
// prefira expo-web-browser (in-app browser) para links externos
<WebView originWhitelist={["https://app.release.com"]} javaScriptEnabled={false} />
```

**Checklist:**
- [ ] `WebView` só carrega origens allowlisted (`originWhitelist`)?
- [ ] JS desabilitado quando não é estritamente necessário?
- [ ] Nenhum bridge (`onMessage`/`injectedJavaScript`) exposto a página não confiável?
- [ ] Links externos via `expo-web-browser`, não WebView embutida?

---

## 🔴 CAT-14.7: Integridade de OTA (EAS Update)

**O que procurar:**
- Updates OTA **não assinados** — servidor de update comprometido injeta JS malicioso em **todos** os apps instalados, instantaneamente.
- Sem gate por `runtimeVersion` → JS novo cai em build nativo incompatível → crash-loop de todos os apps.
- Sem canal de preview / sem rollback pronto — um update ruim não tem como ser revertido rápido.

**Checklist:**
- [ ] EAS code signing habilitado (updates assinados)?
- [ ] `runtimeVersion` gateando compatibilidade com o build nativo?
- [ ] Rollout via canal `preview` antes de `production`; rollback pronto?

---

## Checklist consolidado

| Red flag | Risco | Sub-cat |
|----------|-------|---------|
| Token em `AsyncStorage` / MMKV plaintext | Recuperável de backup / device com root | 14.1 |
| Auth/redirect dirigido por param de deep link | Hijack de sessão / open redirect | 14.2 |
| HTTP cleartext / exceção ATS | Interceptação MITM | 14.3 |
| Pinning sem backup pin | App bricado na expiração do cert | 14.3 |
| Tela sensível sem `FLAG_SECURE` / blur | Vaza via screenshot / app-switcher | 14.4 |
| `console.log` de token/PII | Vaza pra logs do device / crash reports | 14.4 |
| Segredo em `extra` / bundle | Extraído do binário | 14.5 |
| WebView com JS carregando URL não confiável | Comprometimento do bridge nativo | 14.6 |
| Update OTA não assinado | Push de código malicioso a todos os usuários | 14.7 |

## Mapeamento OWASP MASVS

- **MASVS-STORAGE** → 14.1, 14.4 (secure storage, dados em repouso/tela)
- **MASVS-CRYPTO** → 14.1 (Keychain/Keystore hardware-backed)
- **MASVS-NETWORK** → 14.3 (TLS, pinning)
- **MASVS-PLATFORM** → 14.2, 14.6 (deep links, WebView, IPC)
- **MASVS-CODE** → 14.5, 14.7 (integridade do bundle e do canal OTA)
- **MASVS-RESILIENCE** → 14.5 (anti-tampering, root/jailbreak — barra, não teto)
