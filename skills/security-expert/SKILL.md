---
name: security-expert
description: Explicit, authorized interactive offensive review for a bounded web, backend, or mobile surface. Not an automatic substitute for release:security or routine code review.
---

# Security expert

Use only when the user explicitly requests an offensive/security-specialist investigation. For normal pipeline security use `release:security`; for post-implementation evidence use `release:secure-phase`. Never auto-activate solely from framework detection.

## Safety and scope

Confirm the target is code or infrastructure the user placed in scope. Prefer static evidence and safe local tests. Do not attack third parties, exfiltrate secrets, create persistence, or run destructive/availability-impacting payloads. Redact credentials and personal data.

## Method

1. Define the exposed surface, trust boundaries, attacker capability, and assets.
2. Read the smallest relevant reference:
   - web/backend/API: `references/web-backend.md`
   - React Native/Expo/device threats: `references/mobile.md`
3. Trace attacker-controlled input to authorization decisions, interpreters, storage, outbound requests, files, or privileged effects.
4. Validate plausible findings with the least invasive reproducible check. Do not manufacture PoCs when evidence is insufficient.
5. Report only actionable findings: severity, exploit preconditions, exact `file:line`, impact, evidence, and minimal remediation. Separate confirmed issues from hypotheses.

Avoid generic checklist dumps and duplicated pipeline reports. If no exploitable issue is supported, say so and name the material surfaces inspected.
