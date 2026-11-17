# Salesforce Security Policy (project standard)

Single source of truth for every `sf-security-*` skill and agent. Each finding must cite one rule ID below.
Rules **P1–P11** are the team's non-negotiables. **X-rules** extend them with the other places Salesforce
vulnerabilities hide.

> Platform context (API 67.0 / Summer '26, this project's `sourceApiVersion`): Apex classes on API ≥ 67
> run database operations in **user mode** by default, classes without a sharing keyword run **with sharing**,
> and `WITH SECURITY_ENFORCED` is no longer allowed. Classes on API < 67 keep the old **system-mode**
> defaults. Always read each class's `-meta.xml` `apiVersion` before judging P10/P11.

## Justified exceptions

An exception is accepted only when the code/metadata carries a justification next to it:

```apex
// SECURITY-JUSTIFICATION: <why elevated access is required, scope, compensating control> (<approver>, <YYYY-MM-DD>)
```

Justified items are still reported (severity **Info**), and the reviewer must check the justification is
plausible and the elevated scope is as small as possible. A justification never excuses P1 guest exposure of
private data, P2 stored credentials or P6 MAD/VAD on non-admins.

---

## P1 — Guest user exposure
Guest (unauthenticated) users of Sites/Experience Cloud reach data through the Aura/LWR endpoints
(`/s/sfsites/aura`, `/webruntime/api`) with only a guest session — attackers mass-scan these with tools like
AuraInspector. Anything the guest profile can reach is public.

Check:
- Guest profile (`<userLicense>Guest User License</userLicense>`) object permissions: no Edit/Delete/View All/Modify All; Read only for genuinely public objects without private fields.
- Guest FLS: no sensitive fields readable; nothing editable unless it is a deliberate public form.
- Guest `classAccesses`: every `@AuraEnabled` method in those classes is callable anonymously → each must be safe for unauthenticated callers (no `without sharing`, no system-mode reads of private data, no IDOR by record Id, input validated).
- Guest `ApiEnabled` = false; `ViewAllUsers` = false; RunFlow only if needed.
- Guest sharing rules (`sharingGuestRules`) only for public records; External OWD Private.
- Flows reachable by guests must not run `SystemModeWithoutSharing`.
- LWC targets `lightningCommunity__*` and Aura `ltng:allowGuestAccess` / `forceCommunity:*` mark the public UI surface.
- Org settings (verify in org): "Secure guest user record access" on, "Let guest users see other members" off, guest access to public APIs off, "Hide first and last name fields in SOAP API for site users" on, per site.

## P2 — Credentials storage
Only **Named Credentials + External Credentials** (callouts) and **External Client Apps** (inbound OAuth)
may hold secrets. Never in Custom Settings, Custom Metadata, custom object fields (EncryptedText included),
Custom Labels, Static Resources, Apex/JS literals, or committed files (`.env`, `*.key`, SFDX auth URLs).

Check: credential-like field names on `__mdt` / custom settings / objects; populated CMDT record values;
Apex reading `*Secret__c`/`*Token__c`/`*Password__c`; `setHeader('Authorization', ...)` built in code;
`setEndpoint` not using `callout:`; `<password>`/`<consumerSecret>` in metadata; legacy Named Credentials
(migrate to External Credentials); `allowMergeFieldsInHeader/Body` with user input.

## P3 — Organization-wide defaults
Every object is **Private** (internal and external) unless *every* user must see it *and* it holds no private
data. `ControlledByParent` is fine. External OWD must be Private for anything with customer data. Broad
sharing rules to "All Internal Users" / "All Partner Users" are equivalent to a public OWD and need the
same justification. Turning off "Grant Access Using Hierarchies" on custom objects should be deliberate.

## P4 — Field-level security
Only users who need a field get it, through **permission sets** (not profiles). Sensitive fields
(PII, financial, health, credentials) need an explicit owner-approved access list. No "View All Fields"
on objects. Apex must not bypass FLS (see P10).

## P5 — Object access: View All / Modify All
No `viewAllRecords` / `modifyAllRecords` (or `viewAllFields`) on any object in non-admin profiles or
permission sets. Use sharing rules, teams, or Apex managed sharing instead.

## P6 — Modify All Data / View All Data
`ModifyAllData` and `ViewAllData` only on the System Administrator profile. Never in custom profiles or
permission sets / permission set groups. Same treatment for org-level equivalents: `ModifyMetadata`,
`CustomizeApplication`, `AuthorApex`, `ManageUsers`, `AssignPermissionSets`, `ManageProfilesPermissionsets`,
`ManageSharing`, `ViewEncryptedData`, `ManageEncryptionKeys`, `BypassMFAForUiLogins`, `QueryAllFiles`.

## P7 — Minimum number of admins
Count active users holding admin-equivalent access (profile **or** permission set with MAD/VAD/ModifyMetadata/
ManageUsers). Expect a small, named group (rule of thumb: ≤ 3–5 or < 2% of users). Integration users must use
the Minimum Access – API Only profile plus scoped permission sets, never System Administrator. Flag dormant
admins (no login 90 days), shared admin accounts, and admins without MFA.

## P8 — SOQL / SOSL injection
No user-controlled string concatenated into `Database.query`, `Database.countQuery`, `Database.getQueryLocator`
or `Search.query`. Use static SOQL with binds, or `Database.queryWithBinds`. Identifiers (field/object names,
ORDER BY, direction, LIMIT) must be validated against a describe-based allowlist; `String.escapeSingleQuotes`
only protects quoted literals. Also: `Type.forName(input)`, `Schema.getGlobalDescribe().get(input)`.

## P9 — Unauthenticated / exposed APIs
Inventory every entry point: `@RestResource`, `webservice`, `global` methods, `@AuraEnabled`, `@RemoteAction`,
`@InvocableMethod` (flows/Agentforce), `Messaging.InboundEmailHandler`, Sites/Experience pages, public
Visualforce. For each: who can call it (guest? portal? any internal user?), authN context, sharing, CRUD/FLS,
input validation, rate/abuse. Apex REST classes on a Site are public. Connected Apps / ECAs: no wildcard or
HTTP callbacks, minimal scopes (no `Full`), admin-approved users, refresh-token expiry, IP enforcement.

## P10 — System-mode Apex (CRUD/FLS)
SOQL and DML must run in **user mode** unless elevated access is necessary and justified:
`WITH USER_MODE`, `AccessLevel.USER_MODE`, `insert as user`, `Security.stripInaccessible`. Flag
`WITH SYSTEM_MODE`, `AccessLevel.SYSTEM_MODE`, `as system`; on API < 67 also flag every query/DML without
user mode. Flows: `runInMode` `SystemModeWithSharing` / `SystemModeWithoutSharing` need justification.
Triggers run in system context → delegate to handlers that enforce user mode where data comes from users.

## P11 — Sharing keywords
Every class declares a sharing keyword. Default `with sharing`; `inherited sharing` for reusable
selectors/services; `without sharing` only in small, isolated helpers with a justification and ideally a
Custom Permission check — never on an entry-point class (`@AuraEnabled`, REST, `global`). Inner classes do not
inherit the outer class's sharing.

---

## Extended rules (other places to look)

| ID | Area | What to look for |
|---|---|---|
| X1 | XSS (Visualforce) | `escape="false"`, `{!$CurrentPage.parameters.x}` without `JSENCODE`/`HTMLENCODE`/`URLENCODE`, merge fields inside `<script>`, `apex:includeScript` over HTTP |
| X2 | XSS (Aura/LWC) | `aura:unescapedHtml`, `innerHTML`/`outerHTML`/`insertAdjacentHTML`, `lwc:dom="manual"`, `lwc:inner-html`, `eval`/`new Function`, third-party libs in static resources (RetireJS), LWS disabled |
| X3 | CSRF | VF `<apex:page action="{!...}">` doing DML on GET; state changes via GET params |
| X4 | Open redirect | `new PageReference(userInput)`, `retURL`/`startURL` passthrough, `window.location = computed` |
| X5 | IDOR | Methods taking a record Id and querying/updating it in system mode or without sharing |
| X6 | Mass assignment | `JSON.deserialize(clientJson, SObjectType)` then DML — attacker sets OwnerId/flags |
| X7 | Sensitive data leakage | `System.debug` of PII/secrets, `UserInfo.getSessionId()` sent to client/third parties, detailed exceptions returned to UI |
| X8 | Crypto | MD5/SHA1, static IVs, `Math.random()` for tokens, home-grown crypto |
| X9 | Transport & browser | HTTP endpoints, Remote Site `disableProtocolSecurity`, wildcard CORS/CSP trusted sites, clickjack protection off |
| X10 | Session & identity (org) | MFA enforcement, session timeout, lock sessions to IP/domain, login IP ranges on admin/integration profiles, password policies, `PasswordNeverExpires` |
| X11 | Experience Cloud users | Portal/partner profiles: same P3–P6 checks, sharing sets, self-registration default profile, "View All Users" |
| X12 | Agentforce / AI | Agent actions (`@InvocableMethod`, flows) run as the agent user — check its permissions; prompt-injection via record data; agents on public sites behave like guest users |
| X13 | Automation | Flows in system mode, scheduled/batch jobs `without sharing` over user-supplied criteria, platform-event subscribers |
| X14 | Repo hygiene | `.env`, keys, SFDX auth URLs, `sfdx-config` with tokens, `SeeAllData=true` tests, secrets in history (`git log -p`) |
| X15 | Packages & encryption | Managed packages with broad access, Shield Platform Encryption for regulated fields (see `platform-encryption-configure`) |
| X16 | Weak verification | Guest or external actions authorized only by guessable, public or printed facts (postal code, email, phone, record or tracking number, birth date); no second factor or one-time token; enumeration through different messages or timings for "not found" vs "wrong value"; no attempt limit or lockout. A guest-reachable write authorized this way → **High**, **Critical** if it exposes or changes personal data |
