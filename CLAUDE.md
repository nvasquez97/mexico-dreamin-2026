# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Salesforce DX (source-driven) project generated from the standard `sf project generate` template. Single package directory `force-app` (`force-app/main/default/`), source API version 67.0, no namespace. No application code has been written yet; the metadata folders are scaffolding.

## Commands

JS tooling (LWC/Aura only; run `npm install` first):

- `npm run lint` — ESLint on `**/{aura,lwc}/**/*.js`
- `npm test` — LWC Jest unit tests (`sfdx-lwc-jest`)
- Single test: `npx sfdx-lwc-jest -- <path/to/file.test.js>` (add `-t "<test name>"` to filter by name)
- `npm run test:unit:watch` / `test:unit:debug` / `test:unit:coverage`
- `npm run prettier` / `npm run prettier:verify` — format/check Apex, LWC, XML, etc.

Salesforce CLI (`sf`):

- `sf org login web` — authorize an org; `sf org create scratch -f config/project-scratch-def.json` — scratch org (needs Dev Hub)
- `sf project deploy start` / `sf project retrieve start` — push/pull source
- `sf apex run -f scripts/apex/hello.apex` — run anonymous Apex; `sf data query -f scripts/soql/account.soql` — run SOQL
- `sf apex run test` — run Apex tests in an org (Jest only covers LWC)

## Notes

- Husky pre-commit runs `lint-staged`: Prettier on all staged supported files, ESLint on staged Aura/LWC JS, and related Jest tests for staged `lwc/` files. Commits can be rewritten/blocked by these.
- `.forceignore` controls what is excluded from deploy/retrieve.

## Security

The project security policy (rules P1–P11, X1–X15) lives in `.claude/skills/sf-security-audit/references/security-policy.md`. All new code and metadata must comply with it: explicit sharing keyword on every class, user-mode SOQL/DML, no dynamic SOQL with unvalidated input, Private OWDs, permission sets over profiles with least privilege, no MAD/VAD or View/Modify All outside System Administrator, nothing private reachable by guest users, credentials only in Named/External Credentials or External Client Apps.

- Elevated access (`without sharing`, `SYSTEM_MODE`, flows in system mode) needs a `// SECURITY-JUSTIFICATION: <reason> (<approver>, <date>)` comment next to it.
- `/sf-security-audit [--org <alias>] [--diff <base>] [paths]` — full audit (scanner + Code Analyzer + three parallel specialist subagents), report in git-ignored `.security-reports/` as Markdown + HTML (`node .claude/skills/sf-security-audit/scripts/render-report-html.mjs <report.md>` re-renders the HTML).
- `sf-security-auditor` subagent — focused review of a file, feature or the current diff; use it after changing Apex, LWC/Aura/VF, flows, permissions, sharing, sites or integrations.
- `node .claude/skills/sf-security-audit/scripts/sf-security-scan.mjs [--fail-on high] [paths]` — fast heuristic scan (CI-friendly).
- Salesforce skills under `.claude/skills/` listed in `.claude/skills/VENDORED.md` are vendored from forcedotcom/sf-skills — don't edit them; re-sync with `scripts/sync-sf-skills.sh`.
