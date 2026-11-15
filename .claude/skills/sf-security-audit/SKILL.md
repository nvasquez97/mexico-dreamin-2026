---
name: sf-security-audit
description: "Full Salesforce security audit of this project (and optionally a connected org): runs the heuristic sf-security-scan and Salesforce Code Analyzer, fans out to the sf-security-code-reviewer, sf-security-access-reviewer and sf-security-exposure-reviewer subagents in parallel, then consolidates a severity-ranked report against the project security policy (guest user exposure, credential storage, OWD, FLS, View/Modify All, MAD/VAD, admin count, SOQL injection, unauthenticated APIs, system-mode Apex, sharing keywords, XSS, CSRF, OAuth apps and more). TRIGGER when the user asks to audit, pentest-review, security-review or 'find every vulnerability' in the Salesforce project or org, before a release, or for an AppExchange-style review. DO NOT TRIGGER for a quick review of one file or a small diff (delegate to the sf-security-auditor subagent instead) or for fixing a single known issue."
argument-hint: "[--org <alias>] [--diff <base-ref>] [paths...]"
---

# Salesforce security audit (orchestrator)

You coordinate the audit. The specialist subagents do the deep review; you prepare inputs, launch them in
parallel, merge their findings and write the report. **Audit only — do not modify source or the org.** Offer
fixes at the end.

Reference files (read them now, they define what "secure" means here):
- [references/security-policy.md](references/security-policy.md) — rules P1–P11 and X1–X15
- [references/severity-and-report.md](references/severity-and-report.md) — severity, finding format, report template
- [references/scanner-rules.md](references/scanner-rules.md) — heuristic scanner rule catalog
- [references/org-audit-queries.md](references/org-audit-queries.md) — read-only org queries

## 1. Scope

Parse `$ARGUMENTS`:
- `paths...` → audit those. Otherwise every `packageDirectories[].path` in `sfdx-project.json`.
- `--diff <base>` → only files from `git diff --name-only <base>...HEAD` plus uncommitted changes
  (`git diff --name-only HEAD`, `git ls-files --others --exclude-standard`). Still pass the **full**
  package directories to reviewers as context: a changed class is only safe if its callers and permissions are.
- `--org <alias>` → also audit live org configuration. Before touching the org, show the user
  `sf org display --target-org <alias> --json` (username, instance, isSandbox/production) and confirm it is the
  intended org. Everything you run against it is read-only (retrieve into a temp dir, `SELECT` queries).

If there is no source to review and no org, say so and stop (suggest `--org`).

## 2. Prepare the run directory

```bash
RUN=".security-reports/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$RUN"
```
`.security-reports/` is git-ignored — reports describe vulnerabilities and must not be committed or shared
publicly. Never write secret **values** into reports; cite file:line and redact (`sk_live_****`).

## 3. Automated passes (run in parallel where possible)

1. Heuristic scan (seconds, no dependencies):
   ```bash
   node .claude/skills/sf-security-audit/scripts/sf-security-scan.mjs --format json --out "$RUN/scan.json" <paths>
   node .claude/skills/sf-security-audit/scripts/sf-security-scan.mjs --format md   --out "$RUN/scan.md"   <paths>
   ```
   Also scan the repo root for committed secrets/keys: `... --format md --out "$RUN/repo-secrets.md" .`
   and check history briefly: `git log -p --all -S 'BEGIN PRIVATE KEY' --oneline | head`, same for `force://`.
2. Salesforce Code Analyzer (installed as `sf code-analyzer`):
   ```bash
   sf code-analyzer run --rule-selector Security --rule-selector AppExchange \
     --workspace . --target <paths> --output-file "$RUN/code-analyzer.json"
   ```
   If Java 11+ is available (`java -version`), also run Graph Engine for path-based CRUD/FLS:
   `--rule-selector sfge --output-file "$RUN/code-analyzer-sfge.json"`. If a run fails, record it under
   "Not covered" and consult the `dx-code-analyzer-configure` skill — don't block the audit. Violations with
   rule `UnexpectedEngineError` mean that engine did not analyze those files: list them under "Not covered".
3. With `--org`: retrieve org metadata into an isolated dir and scan it:
   ```bash
   bash .claude/skills/sf-security-audit/scripts/retrieve-security-metadata.sh <alias> "$RUN/org"
   ```
   Produces `$RUN/org/metadata/`, `$RUN/org/org-scan.json|md`.

## 4. Launch the specialist reviewers — in ONE message, in parallel

Use the Agent tool three times in the same response. Give each the same context block:

```
Run directory: <RUN>
Source paths: <paths>   Changed files (diff mode): <list or "n/a">
Heuristic scan: <RUN>/scan.json   Code Analyzer: <RUN>/code-analyzer.json (+ sfge if present)
Org alias: <alias or "none">   Retrieved org metadata: <RUN>/org/metadata or "none"
Policy: .claude/skills/sf-security-audit/references/security-policy.md
Return findings in the format of .claude/skills/sf-security-audit/references/severity-and-report.md.
Read-only: do not edit files, deploy, or run anything but SELECT queries against the org.
```

| subagent_type | Covers |
|---|---|
| `sf-security-code-reviewer` | P8, P10, P11, P9 code side, X1–X8, X13 — Apex, triggers, VF, Aura, LWC, flows |
| `sf-security-access-reviewer` | P3, P4, P5, P6, P7, X11 — profiles, permission sets/groups, OWD, sharing rules, admin count |
| `sf-security-exposure-reviewer` | P1, P2, P9 config side, X9, X10, X12, X14 — guest/sites, credentials, OAuth apps, endpoints, session |

Ask each to also return a short **cross-reference list** (e.g. "classes granted to guest: A, B";
"`without sharing` entry points: C") so you can chain findings.

## 5. Consolidate

1. Collect findings; drop duplicates (same root cause + location — keep the most complete write-up).
2. Apply cross-reviewer **escalation chains** from severity-and-report.md (guest-accessible class ×
   injection/without sharing/system mode → Critical; external OWD public × guest access → Critical).
3. Every scanner/Code Analyzer hit at High+ must be either a finding or explicitly dismissed by a reviewer with
   a reason. If a reviewer silently skipped some, verify them yourself.
4. Re-number as `SEC-001…` ordered Critical → Info.
5. Fill the policy compliance table: Pass / Fail / Not verifiable from source (say what would verify it).

## 6. Report

Write `$RUN/security-audit.md` using the template. Then reply to the user with: counts by severity, the top
findings (≤ 5, one line each with file:line), what was not covered, and the report path. Offer to fix the
Critical/High items — remediation should follow the vendored Salesforce skills (`platform-apex-generate`,
`platform-permission-set-generate`, `platform-sharing-owd-configure`, `integration-connectivity-generate`,
`integration-connectivity-connected-app-configure`, `experience-lwc-security-validate`).
