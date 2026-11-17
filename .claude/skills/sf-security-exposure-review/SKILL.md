---
name: sf-security-exposure-review
description: "Review of what a Salesforce solution exposes to the outside world: guest user / Experience Cloud / Sites access (guest profile permissions, guest sharing rules, guest-accessible Apex, flows, LWC and Aura, the /s/sfsites/aura and LWR APIs), unauthenticated and public APIs (Apex REST on sites, webservice, global), credential storage (Named Credentials, External Credentials, External Client Apps vs secrets in custom settings, custom metadata, objects, code or repo files), Connected App / ECA OAuth policies, Remote Site Settings, CSP trusted sites, CORS, session/MFA/Health Check settings, and Agentforce agent users. TRIGGER when reviewing sites, communities, guest profiles, .namedCredential, .externalCredential, .connectedApp, .eca*, .remoteSite, .cspTrustedSite, .corsWhitelistOrigin, .site or .network metadata, or when asked whether anything is reachable without login or where secrets are stored. DO NOT TRIGGER for internal least-privilege review (sf-security-access-review) or Apex code-level bugs (sf-security-code-review)."
---

# Salesforce external-exposure and credentials review

Policy: `.claude/skills/sf-security-audit/references/security-policy.md` — this skill owns **P1, P2, P9
(configuration side), X9, X10, X12, X14**.
Finding format & severity: `.claude/skills/sf-security-audit/references/severity-and-report.md`.
Org queries: `.claude/skills/sf-security-audit/references/org-audit-queries.md`.

## P1 — Guest user exposure (highest priority)

Threat model: anyone on the internet gets a guest session on a public site and calls the Aura endpoint
(`/s/sfsites/aura`) or LWR `/webruntime/api` directly — no UI needed. Automated tools (e.g. modified
AuraInspector) enumerate objects the guest can read and every `@AuraEnabled` method the guest can invoke.
Treat **everything the guest profile can reach as published**.

1. Find guest profiles: `grep -l 'Guest User License' force-app/**/profiles/*` and `<guestProfile>` in
   `sites/*.site-meta.xml`; with an org, the P1 queries. One guest profile per site — check each.
2. Object/field access: no Create/Edit/Delete unless it is a deliberate public form (then: Create only, no
   Read on the same object); no View All/Modify All ever; Read only for public-by-design objects. List every
   readable field.
3. Record access: guest sharing rules (`sharingGuestRules`) and External OWD. Guest sees records only via
   guest sharing rules when "Secure guest user record access" is on — every rule's criteria must match only
   public records.
4. Guest-callable code: each class in the guest profile's `classAccesses` → hand the list to the code
   reviewer (or review yourself) — every `@AuraEnabled` / `@RemoteAction` method must be safe anonymous:
   `with sharing`, user mode, no record-Id IDOR, validated inputs, no data beyond what the page shows.
   Also LWC with `lightningCommunity__*` targets / Aura with `ltng:allowGuestAccess` on public pages, flows in
   `flowAccesses`, VF pages in `pageAccesses`, Apex REST under the site's URL.
   For every guest action that reads or changes a specific record, ask what proves the caller is entitled
   to it: a postal code, email or tracking number alone is weak verification (X16).
5. Settings (org or retrieved `Sharing`/`Communities`/`CustomSite`/`Network` metadata): guest API access off,
   `ApiEnabled` off on guest profile, "Let guest users see other members" off, hide first/last name in SOAP API
   for site users, `ViewAllUsers` off, guest file/Chatter access off unless required. Not verifiable from source
   → list under "Needs org verification" with the setting path.

## P2 — Credentials
Accepted: Named Credential + External Credential (outbound), External Client App (inbound OAuth),
Certificate and Key Management (keys). Everything else is a finding:
- Credential-like fields on custom settings / `__mdt` / objects (EncryptedText included) → High; populated
  CMDT record values or committed secret values → Critical (also tell the user to **rotate** the secret —
  removal from HEAD does not remove it from git history).
- Custom Labels, Static Resources, Apex/JS literals, `.env`, `*.key`, `force://` SFDX auth URLs.
- Named Credentials: `<password>` in metadata, legacy (`principalType`) → migrate to External Credential;
  `allowMergeFieldsInHeader/Body` only with platform merge fields, never with user-controlled values;
  HTTPS endpoints only.
- Repo: `git ls-files | grep -E '\.(env|key|pem|p12|jks)$'`, `git log -p --all -S '<pattern>'` for leaked
  history; `.forceignore` / `.gitignore` coverage.

## P9 — Public APIs and OAuth apps
- Connected Apps: new integrations should be **External Client Apps**. For each app/ECA: callback URLs HTTPS
  and exact (no wildcards); scopes minimal (no `Full`; `RefreshToken` only if needed; JWT flows need neither);
  admin-approved users only (permission set assignment); refresh token expiry; IP relaxation `ENFORCE` for
  server-to-server; no consumer secret in source; certificate-based JWT for integrations. Use the vendored
  `integration-connectivity-connected-app-configure` checklist
  (`.claude/skills/integration-connectivity-connected-app-configure/references/security-checklist.md`).
- Integration users: dedicated, API-only, scoped permission sets, not System Administrator (feed to P7).
- Apex REST / SOAP exposed via Sites = anonymous; otherwise any authenticated user with class access.

## X9 — Transport and browser
Remote Site Settings with `disableProtocolSecurity` or `http://`; each remote site means code handles the
endpoint (and maybe credentials) → prefer Named Credentials. CSP Trusted Sites and CORS allowlist: no
wildcards, HTTPS only, each entry owned and justified.

## X10 — Session and identity (org)
Retrieved `Security.settings-meta.xml` / Health Check: MFA for all UI logins, session timeout, lock sessions
to IP/domain, HttpOnly, clickjack protection for Setup/non-Setup/VF, CSRF on GET/POST, password policies,
login IP ranges on admin and integration profiles, `PasswordNeverExpires` holders. Health Check HIGH_RISK
items are findings.

## X12 — Agentforce / AI
Agent actions (flows, `@InvocableMethod`, prompt templates) run as the agent's user: review that user's
permission sets like any integration user. Agents on public sites are guest-reachable. Record data fed into
prompts is untrusted (prompt injection) — actions that write or send data need confirmation steps.

## Output
Findings with IDs `EXP-###`, plus an **external attack-surface inventory**:

| Surface | Reachable by | Backing code / data | Notes |
|---|---|---|---|
| Site "Customer" (guest profile X) | Anonymous | Classes A, B; objects C (Read); flows D | |
| Apex REST /services/apexrest/... | Authenticated / Anonymous via site | Class E | |
| ECA "ERP Integration" | Server, JWT | Integration user U | |

## Remediation guidance
Named/External Credentials and callout refactors: `integration-connectivity-generate`. OAuth apps and ECA
migration: `integration-connectivity-connected-app-configure`. Encrypting regulated fields at rest:
`platform-encryption-configure`. Guest hardening is configuration in Setup per site — give exact steps.
