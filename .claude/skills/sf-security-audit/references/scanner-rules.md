# sf-security-scan rule catalog

`scripts/sf-security-scan.mjs` is a dependency-free heuristic scanner. It is tuned for **recall**: every hit
is a candidate the reviewer must confirm by reading the code. Absence of hits is not proof of safety —
reviewers still read every entry point and permission file.

```bash
node .claude/skills/sf-security-audit/scripts/sf-security-scan.mjs [--format md|json] [--out FILE] [--fail-on SEV] [paths...]
```
Default path `.`; skips `node_modules`, `.git`, `.sf`, `.sfdx`, `.claude`, `.security-reports`.
`--fail-on high` exits 1 when any High/Critical exists (CI use).

| Rule | Policy | Default severity | Detects |
|---|---|---|---|
| SEC-PRIVATE-KEY, SEC-SFDX-AUTH-URL, SEC-AWS-KEY | P2/X14 | Critical | Key material, `force://` auth URLs, AWS keys |
| SEC-TOKEN, SEC-JWT, SEC-BEARER, SEC-SESSION-ID, SEC-HARDCODED-SECRET | P2 | High | Tokens / secret literals in any text file |
| SEC-KEY-FILE | X14 | High | `.env`, `*.pem`, `*.key`, `*.p12` in workspace |
| APEX-ENTRY-POINT | P9 | Info / Medium (REST, webservice, email) | `@AuraEnabled`, `@RestResource`, `@Http*`, `@RemoteAction`, `@InvocableMethod`, `webservice`, `global` methods |
| APEX-WITHOUT-SHARING | P11 | High | `without sharing` classes |
| APEX-NO-SHARING-KEYWORD | P11 | Low (API ≥ 67) / Medium–High (< 67) | Top-level class with no sharing keyword |
| APEX-SOQL-INJECTION | P8 | High (concatenation) / Medium | Dynamic `Database.query*` / `Search.query` |
| APEX-TYPE-FORNAME, APEX-DESCRIBE-INPUT | P8 | Medium / Low | Class/object resolved from variables |
| APEX-EXPLICIT-SYSTEM-MODE | P10 | Medium | `WITH SYSTEM_MODE`, `AccessLevel.SYSTEM_MODE`, `as system` |
| APEX-SOQL-SYSTEM-MODE, APEX-DML-SYSTEM-MODE | P10 | Medium (Low if manual checks) | API < 67 queries/DML without user mode (aggregated per file) |
| APEX-SECURITY-ENFORCED | P10 | Info | `WITH SECURITY_ENFORCED` on API ≥ 67 |
| APEX-CREDENTIAL-FIELD-READ, APEX-AUTH-HEADER, APEX-ENDPOINT-NO-NC | P2 | High / High / Medium | Secrets read from fields, auth headers in code, non-`callout:` endpoints |
| APEX-SESSION-ID, APEX-DEBUG-SENSITIVE | X7 | Medium | Session id use, secrets/PII in debug logs |
| APEX-WEAK-CRYPTO, APEX-INSECURE-RANDOM, APEX-STATIC-IV | X8 | Medium / Low / Low | MD5/SHA1, `Math.random`, explicit IVs |
| APEX-OPEN-REDIRECT | X4 | Medium | `new PageReference(variable)` |
| APEX-MASS-ASSIGNMENT | X6 | Medium | `JSON.deserialize` into SObject types |
| APEX-INSECURE-HTTP | X9 | Medium | `http://` literals |
| APEX-SEEALLDATA, TRIGGER-SYSTEM-CONTEXT | X14 / P10 | Low / Info | Test hygiene, trigger context |
| JS-XSS-SINK, JS-OPEN-REDIRECT, JS-STORAGE-SECRET | X2/X4/X7 | High / Medium / Medium | `innerHTML`, `eval`, computed `location`, tokens in storage |
| LWC-DOM-MANUAL, LWC-INNER-HTML, LWC-COMMUNITY-TARGET | X2 / P1 | Medium / High / Info | Raw DOM, Experience Cloud exposure |
| AURA-UNESCAPED-HTML, AURA-GUEST-ACCESS, AURA-GLOBAL-ACCESS | X2 / P1 | High / Medium / Low | |
| VF-ESCAPE-FALSE, VF-UNENCODED-PARAM, VF-CSRF-ACTION, VF-INSECURE-SCRIPT | X1/X3 | High / High / Medium / Medium | |
| PERM-MAD-VAD | P6 | Critical (Info on admin profile) | ModifyAllData / ViewAllData |
| PERM-HIGH-RISK | P6 | High / Medium / Low | Other admin-level system permissions |
| PERM-VIEW-MODIFY-ALL, PERM-VIEW-ALL-FIELDS | P5 / P4 | High / Medium | Object View All / Modify All / View All Fields |
| PERM-PROFILE-FLS, PERM-SENSITIVE-FLS | P4 | Low | FLS in profiles, sensitive-looking fields |
| GUEST-USER-PERMISSION, GUEST-OBJECT-ACCESS, GUEST-FIELD-ACCESS | P1 | Critical–Medium | Guest profile permissions |
| GUEST-APEX-CLASS, GUEST-VF-PAGE, GUEST-FLOW | P1/P9 | High / Medium / Medium | Classes/pages/flows granted to guest |
| OWD-INTERNAL-PUBLIC, OWD-EXTERNAL-PUBLIC | P3 | Medium / High | Non-private OWD |
| SHR-GUEST-RULE, SHR-BROAD-RULE | P1 / P3 | High / Low–High | Guest sharing rules, rules to all internal/external users |
| CRED-STORAGE-FIELD, CRED-CMDT-VALUE | P2 | High / Critical | Credential-like fields, populated CMDT secret values |
| NC-PASSWORD, NC-MERGE-FIELDS, NC-HTTP, NC-LEGACY | P2 / X9 | Critical / Medium / High / Low | Named Credential metadata |
| RSS-NO-TLS, RSS-HTTP, RSS-PRESENT, CSP-TRUSTED-SITE, CORS-ALLOWLIST | X9 / P2 | High–Info | Remote sites, CSP, CORS |
| APP-CONSUMER-SECRET, APP-CALLBACK, APP-FULL-SCOPE, APP-REFRESH-INFINITE, APP-IP-BYPASS, APP-SELF-AUTHORIZE, APP-CONNECTED-APP | P2 / P9 | Critical–Info | Connected App / ECA OAuth config |
| FLOW-SYSTEM-NO-SHARING, FLOW-SYSTEM-MODE | P10 / X13 | High / Medium | Flow `runInMode` |
| SITE-GUEST-SETTING, SITE-SELF-REGISTRATION, SITE-GUEST-PROFILE | P1 / X11 | Medium / Low / Info | CustomSite / Network settings |

Known blind spots (cover manually): data-flow from `@AuraEnabled` params to sinks across classes, IDOR,
sharing of inner classes, Experience Builder (`ExperienceBundle`) page visibility, static resource contents,
org-only settings (Health Check, session, MFA, site guest toggles), permission set **assignments**.
