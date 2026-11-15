# Severity rubric, finding format and report template

## Severity

| Severity | Meaning | Typical examples |
|---|---|---|
| **Critical** | Exploitable by **unauthenticated** users, or exposes credentials / all data | Guest can read private records or call a `without sharing` `@AuraEnabled` method; committed secret/token; MAD/VAD on a non-admin permission set; SOQL injection reachable by guest |
| **High** | An **authenticated low-privilege** user can read/modify data beyond their rights, or an attacker gains a strong foothold | SOQL injection in `@AuraEnabled`; `without sharing` entry point; View/Modify All on objects; public external OWD; stored XSS; credentials in Custom Settings/CMDT; HTTP/wildcard OAuth callback |
| **Medium** | Real weakness that needs extra conditions, or missing defense-in-depth | System-mode SOQL/DML on internal-only code; public internal OWD; guest read of a "public" object; open redirect; weak crypto |
| **Low** | Hardening / hygiene | Missing explicit sharing keyword on API ≥ 67; FLS in profiles; legacy Named Credential |
| **Info** | Attack-surface inventory, justified exceptions | List of entry points, community-exposed components, admin profile MAD |

**Escalate** when findings combine (record the chain in the finding):
- Guest-accessible class (`classAccesses` on guest profile, or used by a guest-exposed LWC/Aura) + `without sharing` / system mode / injection → **Critical**.
- `@AuraEnabled` + record Id parameter + system mode/without sharing → IDOR, **High**.
- Public external OWD + guest sharing rule or guest Read on the object → **Critical**.

**De-escalate** only with evidence: input proven constant/allowlisted, object proven public-by-design, code
proven unreachable (no callers, no class access). Justified exceptions (see policy) → **Info**.

## Confidence
- **Confirmed** — read the code/metadata and traced the path.
- **Likely** — pattern matches and nothing mitigates it, but reachability not fully traced.
- **Needs org verification** — depends on org config not in source (assignments, site settings, Health Check).

## Finding format (every reviewer uses this)

```markdown
### [SEV] <ID> — <short title>
- **Policy:** P8 (SOQL injection)
- **Location:** force-app/main/default/classes/AccountCtrl.cls:42
- **Confidence:** Confirmed | Likely | Needs org verification
- **Evidence:** <the exact code/metadata lines, ≤ 10 lines>
- **Attack scenario:** <who (guest / portal user / internal user) does what, and what they get>
- **Remediation:** <concrete change, with a code/XML snippet>
```

IDs: `CODE-###` (code reviewer), `ACC-###` (access reviewer), `EXP-###` (exposure reviewer). The orchestrator
re-numbers to `SEC-###` in the final report.

## Final report template (`.security-reports/<YYYY-MM-DD>-security-audit.md`)

```markdown
# Salesforce Security Audit — <project> — <YYYY-MM-DD>

**Scope:** <source paths> | **Org:** <alias or "source only"> | **API version:** <sourceApiVersion>
**Tools:** sf-security-scan (heuristic), Salesforce Code Analyzer <version> (rule selectors), manual review by
sf-security-code-reviewer / sf-security-access-reviewer / sf-security-exposure-reviewer

## Executive summary
<3–6 sentences: overall posture, the worst risk in plain language, what to fix first>

| Critical | High | Medium | Low | Info |
|---|---|---|---|---|

## Policy compliance
| Rule | Status (Pass / Fail / Not verifiable from source) | Findings |
|---|---|---|
| P1 Guest user | | |
| … P11, X-rules with findings | | |

## Findings
<Critical → Info, finding format above>

## Attack-surface inventory
<entry points, guest-reachable components/classes/flows, integrations>

## Not covered / needs org verification
<what could not be checked and the exact query/setting to check it>

## Remediation plan
<ordered list: fix now (Critical/High), next sprint, hardening backlog>
```
