# Vendored skills

Skills in this folder come from two sources.

## Project security skills (owned here — edit freely)

| Skill | Purpose |
|---|---|
| `sf-security-audit` | `/sf-security-audit` orchestrator, project security policy, scanner, org queries, report format |
| `sf-security-code-review` | Apex / VF / Aura / LWC / Flow security review method |
| `sf-security-access-review` | OWD, sharing, profiles, permission sets, FLS, admin access |
| `sf-security-exposure-review` | Guest/sites, credentials, OAuth apps, endpoints, session settings |

Subagents using them live in `.claude/agents/sf-security-*.md`.

## Salesforce skills (vendored from forcedotcom/sf-skills — do not edit, re-sync instead)

- **Source:** https://github.com/forcedotcom/sf-skills (Apache-2.0, see `SF-SKILLS-LICENSE.txt`)
- **Commit:** `788b83fb9f5effb4f1548e3090df415704d3ec64` (ref `main`, synced 2026-11-15)
- **Update:** `scripts/sync-sf-skills.sh [ref]`, then review the diff.

Curated for security work (the upstream library has 260+ skills; only these are loaded to keep triggering precise):

| Skill | Used for |
|---|---|
| `dx-code-analyzer-run` / `-configure` / `-custom-rule-create` | Salesforce Code Analyzer scans (PMD, ESLint, RetireJS, Flow, SFGE), setup/CI, custom policy rules |
| `experience-lwc-security-validate` | Lightning Web Security (LWS) validation of LWC bundles |
| `platform-apex-generate` | Secure Apex remediation patterns (sharing, user mode) |
| `platform-soql-query` | Safe SOQL shape |
| `platform-permission-set-generate` | Least-privilege permission set remediation |
| `platform-sharing-owd-configure` / `platform-sharing-rules-generate` | OWD and sharing remediation |
| `integration-connectivity-generate` | Named / External Credentials, callouts |
| `integration-connectivity-connected-app-configure` | Connected Apps / External Client Apps OAuth security |
| `platform-encryption-configure` | Shield Platform Encryption |
| `platform-metadata-retrieve`, `dx-org-analyze` | Pulling and inventorying org metadata for audits |

Alternative to vendoring: install the full Salesforce plugin marketplace per developer with
`/plugin marketplace add forcedotcom/sf-skills` (Claude Code) or `npx skills add forcedotcom/sf-skills`.
