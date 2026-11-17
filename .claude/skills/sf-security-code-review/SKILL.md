---
name: sf-security-code-review
description: "Security review method for Salesforce code: Apex classes and triggers, Visualforce, Aura, LWC and Flows. Covers SOQL/SOSL injection, sharing keywords (with/without/inherited sharing), system vs user mode (CRUD/FLS, WITH USER_MODE, AccessLevel, stripInaccessible, API 67 defaults), exposed entry points (@AuraEnabled, @RestResource, global, webservice, @InvocableMethod), IDOR, mass assignment, XSS, CSRF, open redirect, secrets and crypto in code. TRIGGER when reviewing or writing Apex/VF/Aura/LWC/Flow for security, triaging Code Analyzer security violations, or when asked if code is safe for guest/community users. DO NOT TRIGGER for profile/permission-set/OWD review (sf-security-access-review) or site/credential/OAuth configuration (sf-security-exposure-review)."
---

# Salesforce code security review

Policy: `.claude/skills/sf-security-audit/references/security-policy.md` (cite P/X rule IDs).
Finding format & severity: `.claude/skills/sf-security-audit/references/severity-and-report.md`.
Vulnerable → fixed patterns: [references/secure-patterns.md](references/secure-patterns.md).

## Method: entry point → data flow → sink

Pattern matching finds candidates; **tracing** finds vulnerabilities. For every finding, answer: who can
reach this code, with what input, and what do they get?

### 1. Inventory entry points (P9)
```bash
grep -rnE '@AuraEnabled|@RestResource|@Http(Get|Post|Put|Patch|Delete)|@RemoteAction|@InvocableMethod|\bwebservice\b|InboundEmailHandler|implements\s+(Schedulable|Database\.Batchable|Queueable)' --include=*.cls force-app
grep -rnE '^\s*global\s' --include=*.cls force-app
```
For each, note: class sharing keyword, `apiVersion` (from `*.cls-meta.xml`), parameters, and who can call it
— internal users with class access, portal users, **guest** (class in a guest profile's `classAccesses`, or
used by a guest-exposed LWC/Aura component — check `*.js-meta.xml` `lightningCommunity__*` targets and
`ltng:allowGuestAccess`). REST resources on a Site are anonymous.

### 2. Sharing (P11)
- `without sharing` on an entry-point class → High (Critical if guest-reachable). Accept only small helpers
  with `// SECURITY-JUSTIFICATION:` and ideally `FeatureManagement.checkPermission(...)`.
- No keyword: API ≥ 67 defaults to `with sharing` (Low, declare it); API < 67 → runs in caller's mode, and as
  `without sharing` when it is the entry point for many contexts (Medium/High).
- Inner classes do **not** inherit the outer class's keyword — check each.
- `inherited sharing` is right for selectors/services; wrong as the only declaration on an entry point that
  must enforce sharing.

### 3. Data access mode — CRUD/FLS (P10)
- API ≥ 67: user mode is default. Flag explicit `WITH SYSTEM_MODE`, `AccessLevel.SYSTEM_MODE`, `as system`.
  `WITH SECURITY_ENFORCED` will not compile — use `WITH USER_MODE`.
- API < 67: every SOQL/SOSL/DML is system mode unless `WITH USER_MODE`, `AccessLevel.USER_MODE`, `as user`,
  `Security.stripInaccessible`, or explicit describe checks. Recommend upgrading the class API version
  **with tests under realistic permission sets** (user mode may return fewer rows or throw).
- Triggers always start in system context; the handler decides.
- Flows: `<runInMode>SystemModeWithoutSharing|SystemModeWithSharing</runInMode>` need justification —
  Critical when the flow is reachable by guests (screen flow on a site, `flowAccesses` on guest profile).

### 4. Injection (P8)
- Sinks: `Database.query`, `Database.countQuery`, `Database.getQueryLocator`, `Search.query`,
  `Database.queryWithBinds` (only the string part), `Type.forName`, `Schema.getGlobalDescribe().get`.
- Trace the query string back to its parts. Any `@AuraEnabled`/REST/VF parameter, URL parameter, record field
  written by users, or platform event payload is **tainted**.
- Safe: static SOQL with `:binds`; `queryWithBinds` with identifiers from an allowlist / describe check.
  `String.escapeSingleQuotes` is only sufficient for values inside quotes — not for field names, ORDER BY,
  ASC/DESC, LIMIT/OFFSET, or `IN (...)` lists built by joining.

### 5. Authorization logic (X5, X6, X16)
- **IDOR**: method takes a record Id and reads/updates it without sharing or in system mode → any user can
  act on any record. Fix: `with sharing` + user mode, or explicit `UserRecordAccess` check.
- **Mass assignment**: `JSON.deserialize(input, SObject.class)` / untyped maps copied into SObjects, then DML.
  Fix: DTO with allowed fields, set fields explicitly, `stripInaccessible`.
- Custom permission checks (`FeatureManagement.checkPermission`) must be server-side, not only in LWC.
- **Weak verification (X16)**: a guest/external action (view, edit, cancel, reschedule) authorized only by
  facts that are guessable, public or printed on documents — postal code, email, phone, record or tracking
  number, birth date. Also flag enumeration (different message/timing for "not found" vs "wrong value") and no
  attempt limit/lockout. Fix: one-time token or link sent to a verified channel, or an authenticated session;
  identical error responses; attempt limits.

### 6. Client side (X1–X4)
- Visualforce: `escape="false"`, unencoded `{!$CurrentPage.parameters.*}`, merge fields in `<script>` or
  `style` without `JSENCODE`/`HTMLENCODE`, `<apex:page action=...>` doing DML (CSRF), `PageReference` from
  input (open redirect).
- Aura: `aura:unescapedHtml`, `$A.util` DOM writes, `access="global"`.
- LWC: `innerHTML`/`outerHTML`/`insertAdjacentHTML`, `lwc:dom="manual"`, `lwc:inner-html`, `eval`,
  computed `window.location`, tokens in `localStorage`. For full LWS analysis use the
  `experience-lwc:experience-lwc-security-validate` skill on each component bundle.
- Static resources: outdated JS libraries (Code Analyzer `retire-js` engine).

### 7. Secrets, logging, crypto, callouts (P2, X7, X8, X9)
- Literal secrets, `setHeader('Authorization', ...)` built in Apex, `setEndpoint` not using `callout:`,
  reading `*Secret__c`/`*Token__c`/`*Password__c` from custom settings/metadata → P2.
- `System.debug` of tokens/PII, returning raw exception messages/stack traces to the UI, `UserInfo.getSessionId()`.
- MD5/SHA1, `Math.random()` tokens, static IVs (prefer `Crypto.encryptWithManagedIV`).

## Using the tool outputs
- Heuristic scan (`scan.json`) rule IDs: see `.claude/skills/sf-security-audit/references/scanner-rules.md`.
- Code Analyzer security rules worth mapping: `ApexSOQLInjection`→P8, `ApexSharingViolations`/
  `DatabaseOperationsMustUseWithSharing`→P11, `ApexCRUDViolation`/`ApexFlsViolation` (SFGE)→P10,
  `ApexXSSFromURLParam`/`ApexXSSFromEscapeFalse`/`VfUnescapeEl`/`VfHtmlStyleTagXss`/`AvoidUnescapedHtmlInAura`/
  `@lwc/lwc/no-inner-html`→X1/X2, `ApexCSRF`/`VfCsrf`→X3, `ApexOpenRedirect`→X4, `ApexBadCrypto`→X8,
  `ApexInsecureEndpoint`→X9, `ApexSuggestUsingNamedCred`/`AvoidHardcodedCredentialsInFieldDecls`→P2,
  `ApexDangerousMethods`→X7. To explain a rule: `sf code-analyzer rules --rule-selector <Rule> --view detail`.
- Confirm or dismiss every High+ hit with a reason; add what the tools missed (cross-class data flow, IDOR).

## Remediation guidance
Write fixes the way `salesforce-development:platform-apex-generate` prescribes (explicit sharing keyword on every class, user mode
by default, isolated justified elevation). For SOQL shape use `salesforce-development:platform-soql-query`. Show the minimal diff.
