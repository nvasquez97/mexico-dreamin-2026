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
