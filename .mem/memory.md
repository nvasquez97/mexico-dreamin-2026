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

## 2026-11-15 21:30 — T6 implemented; T7 next
- Type: status
- What: Reschedule, commit f6e55ea; AC-003.5 (field history) still to verify in the org after seeding.
- Why / evidence: feature doc L21.
- Next: T7 EntregaYa status REST endpoint.

## 2026-11-15 21:50 — T7 implemented; T8 next
- Type: status
- What: EntregaYa status endpoint + EntregaYa_Integration permission set, commit 08da7ab. Test users: integration tests use Minimum Access - Salesforce (Salesforce license has 1 free seat); keep the Salesforce Integration license for the real integration user.
- Why / evidence: feature doc L22.
- Next: T8 sign-up, login, logout, forgot password.

## 2026-11-15 22:15 — T8 implemented; T9 next
- Type: status
- What: Sign-up/login/forgot password, commit b7faada; custom profile RutaCargo Customer; customer permission set assigned by Queueable.
- Why / evidence: feature doc L23-L24.
- Next: T9 request shipment.

## 2026-11-15 22:40 — T9 implemented; T10 next
- Type: status
- What: Shipment request, commit 98b26a8.
- Why / evidence: feature doc L25.
- Next: T10 my shipments (list + detail, sharing set).

## 2026-11-15 22:40 — runAs and describe
- Type: environment
- What: System.runAs does not apply object permissions to Schema describe; use USER_MODE DML/SOQL to prove access in tests.
- Why / evidence: ShipmentRequestControllerTest first run, 707Ec00002j2fUy.
- Next: none.

## 2026-11-15 23:00 — T10 implemented; T11 next
- Type: status
- What: My shipments, commit 9fba4fb; sharing set RutaCargo Customers.
- Why / evidence: feature doc L26.
- Next: T11 guest + support agent permission sets, OAuth app for EntregaYa, then batched security review.

## 2026-11-15 23:25 — T11 implemented; T13 then T12 next
- Type: status
- What: Guest/agent perm sets, ECA, layout with history, network self-registration, commit 83065bb. Batched item-2 review moved to after T12+T13 (L28).
- Why / evidence: feature doc L27-L28.
- Next: T13 seed script (role, setting, users, 120 shipments, perm set assignments), then T12 UI.

## 2026-11-15 23:50 — T13 done; T12 (UI) next
- Type: status
- What: Seed script scripts/seed/seed.sh, commit 4665bc7; data verified. Seeded site-user password is not in the repo (re-run seed.sh with PASSWORD_FILE to reset it).
- Why / evidence: feature doc L29.
- Next: T12 LWR pages, theme layout and LWC with the brand.

## 2026-11-16 01:20 — T12 implemented, live smoke tests pass; reviews running
- Type: status
- What: Site published and Live; guest flows verified over HTTP; AC-003.5 history verified; 151/151 tests, 93% coverage. security-reviewer and access-auditor running on S1-S43.
- Why / evidence: feature doc L30-L34.
- Next: fix Critical/High findings, then test-reviewer, brand-reviewer, architecture-review; close T14.
