# Project memory

## 2026-11-15 — Build session (RutaCargo)
- Request: implement docs/functional-design.md in org "ALIAS" (placeholder) per brand manual. Used scratch org `rutacargobsonnet`.
- Feature doc: odd/tasks/rutacargo-shipping-tracking.md (specs S1..S36, tasks T1..T13, assumptions/decisions in Log L2..L17). README.md lists assumptions A1..A11 and manual steps.
- Done and committed on branch Sonnet-skills: data model, Apex services/REST/tests (73 passing, ~88% coverage), permission sets/profiles, legacy Named Credential EntregaYa, LWR site (Live), brand LWCs, ECA EntregaYa_Status, test data (120 shipments), setup scripts.
- Gotchas learned: API 67 plain SOQL/DML are user mode (tests use API 66; prod uses explicit SYSTEM_MODE); anonymous Apex cannot use SYSTEM_MODE; Profile has no externalCredentialPrincipalAccesses (guest cannot hold ext. credential access); custom LWR route ids need __c; BaseFont cannot contain commas; autonumber repeats between @TestSetup and test methods; use --ignore-conflicts for scratch-org deploys after retrieving site metadata.
- Reviewers all ran (security, access, test, brand, architecture); verdicts and fixes are in Log L18-L25. 90/90 tests, 91% coverage. Open High accepted with reason: postal-code spraying across shipments (README residual risks).
- Open manual items: Named Credential URL+key, ECA consumer key handoff, sender verification, rotate provider key in docs/functional-design.md, Daily Brew font, official logos.

## 2026-11-16 — Brand logo stand-ins
- Added docs/brand/*.png: six logo stand-ins cropped from page 5 of the brand manual (solid backgrounds, not official vectors); docs/brand/README.txt lists which background each must be used on. Official SVG/transparent logos remain an open manual item.
- Branch Sonnet-skills pushed to origin (no PR, per project rules).
