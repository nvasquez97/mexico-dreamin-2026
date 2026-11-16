# Project memory

## 2026-11-15 18:58 — Scratch org rutacargo-b-opus is the deploy target
- Type: decision
- What: All deploys, tests and org work for this project go to the scratch org alias `rutacargo-b-opus` (expires 2026-12-15). Do not deploy to `rutacargo` or any other org.
- Why / evidence: User request. Already set as project default in .sf/config.json (target-org=rutacargo-b-opus, target-dev-hub=JhonyMexD); that file is gitignored, so this entry is the durable record. Built from config/project-scratch-def.json.
- Next: Before each deploy, confirm target-org is still rutacargo-b-opus; recreate from the scratch def via JhonyMexD before 2026-12-15 expiry if still needed.

## 2026-11-15 19:40 — Feature document created; T1 next
- Type: status
- What: Large feature tracked in odd/tasks/rutacargo-shipping-tracking.md (S1–S47, T1–T14) on branch feature/rutacargo-shipping-tracking. ODD runs through CLAUDE.md rules only (no ODD skill), confirmed with the user via ~/Documents/ODD-workflow-explained.md.
- Why / evidence: CLAUDE.md step 5; user asked about the missing ODD skill/folder.
- Next: T1 data model.

## 2026-11-15 19:40 — Assumptions recorded at kickoff
- Type: assumption
- What: "org ALIAS" = rutacargo-b-opus; EntregaYa key never copied (Named Credential, manual entry); Coffee Blazers logos used; Montserrat Black for headlines; see feature doc Log L2–L11.
- Why / evidence: odd/tasks/rutacargo-shipping-tracking.md Log.
- Next: none.

## 2026-11-15 19:40 — Org state observed before any deploy
- Type: environment
- What: rutacargo-b-opus has no Network/site yet; admin user has no role (portal account owners need one); Customer Community license 5 seats, Salesforce Integration license 1 seat.
- Why / evidence: SOQL on UserLicense, Network, User.
- Next: T1/T13 create a role and assign it to the admin before creating portal users.

## 2026-11-15 19:55 — T1 done, T2 next
- Type: status
- What: Data model deployed (deploy 0AfEc00000pyRBFKA2); commit 6f09a51. External OWD Private on Account, Contact, Shipment__c.
- Why / evidence: feature doc L12.
- Next: T2 pricing + business calendar (test-first).

## 2026-11-15 20:10 — T2 done, T3 next
- Type: status
- What: Pricing + business calendar, commit cfa6b13, 21/21 tests pass.
- Why / evidence: feature doc L13.
- Next: T3 public tracking (guest, system mode with explicit public field list).

## 2026-11-15 20:10 — Environment: skills-first hook
- Type: environment
- What: A PreToolUse hook blocks raw sf data query / apex run test until the owning skill (platform-soql-query, platform-apex-test-run, platform-metadata-deploy) is dispatched; a blocked compound command runs nothing, so re-run every step.
- Why / evidence: BusinessCalendar sed skipped when the hook blocked the command.
- Next: none.

## 2026-11-15 20:35 — T3 implemented, base site created; T4 next
- Type: status
- What: Site RutaCargo exists (guest profile "RutaCargo Profile"), commit b8f5205. Public tracking commit fcb5ebb, 16/16 tests as guest. T3 is "security review pending" (batched item-2 review after T11, feature doc L18).
- Why / evidence: feature doc L15–L18.
- Next: T4 delivery details with postal-code verification and throttle.

## 2026-11-15 20:35 — API 67 user mode in tests
- Type: environment
- What: Test DML/SOQL in API 67 runs in user mode; admin lacks FLS on new fields, so factory/setup uses AccessLevel.SYSTEM_MODE. AuraHandledException needs setMessage for tests to read the message (AuraErrors.of).
- Why / evidence: 707Ec00002j36Rq failed with "fields being inaccessible on Sobject Account".
- Next: none.

## 2026-11-15 20:55 — T4 implemented; T5 next
- Type: status
- What: Delivery details + throttle, commit dedae45, 12/12 as guest; security review pending (batched, L18).
- Why / evidence: feature doc L19.
- Next: T5 proof of delivery via Named Credential EntregaYa.

## 2026-11-15 21:15 — T5 implemented; T6 next
- Type: status
- What: Proof of delivery via Named Credential EntregaYa, commit 1a7c12a; key and URL must be set manually in Setup.
- Why / evidence: feature doc L20.
- Next: T6 reschedule.
