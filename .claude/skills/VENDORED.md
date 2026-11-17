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

Only the skills that are **not** in the Salesforce plugins enabled for this project
(`.claude/settings.json`: salesforce-development, salesforce-code-quality, experience-lwc, integration) are
vendored. Everything else comes from the plugins and is called by its full name, for example
`salesforce-development:platform-apex-generate`. Vendoring a skill the plugins already provide shadows the plugin
copy when it is called by its bare name, so do not add those back.

| Skill | Used for |
|---|---|
| `platform-encryption-configure` | Shield Platform Encryption |
| `dx-org-analyze` | Inventorying and comparing org metadata for audits |

## Project workflow skills (owned here — edit freely)

| Skill | Purpose |
|---|---|
| `odd` | The ODD workflow (Organic Driven Development) |
| `project-memory` | Project memory in `.mem/`, with rotation at 50 KB |

The plugins come from the marketplace: `/plugin marketplace add forcedotcom/sf-skills`, then install
salesforce-development, salesforce-code-quality, experience-lwc and integration from `@salesforce`.
