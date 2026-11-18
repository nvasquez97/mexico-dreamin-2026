# hardening-1 — Close the Critical and High findings of Hardening audit 1
Tier: 2 · Reason: SEC-001 (P2, X14 secret in history), SEC-002 (X16 guest lockout oracle, RecipientAccess.cls:121-141), SEC-003 (X10 MFA), CA-001, CA-002 (X14 SeeAllData) of .security-reports/20261118-035506-hardening-1/security-audit.md
Mode: auto
Branch: ODD-Opus-Cargo-Test-1
Org: cargo-opus-t1
Approved: standing choice of the owner (unattended run), 2026-11-18
Base: 2230597
Plan review: 

## Findings
- Audit 1 (run .security-reports/20261118-035506-hardening-1, report security-audit.md, git-ignored): Critical 1, High 2, Medium 7, Low 7, Info 6; CA High 2; 134 CA GlobalVariable hits dismissed (false positive: PMD's JavaScript parser reads LWC class fields such as `force-app/main/default/lwc/rcHeader/rcHeader.js:47 isGuest = IS_GUEST;` as globals).
- SEC-001 (Critical): the EntregaYa API key is in the history of four pushed remote branches (docs/functional-design.md:182 at b85773a and others; scripts/setup-entregaya-key.sh:4 on another branch); HEAD is clean (18a2aa5). Rotation and any history purge belong to the owner (force-push and the external service are outside an agent's remit); the repository has no secret scan on commit (`.git/hooks` holds only samples; `core.hooksPath` unset).
- SEC-002 (High): `RecipientAccess.verifyBeforeCallout` checks the lock before the code (`force-app/main/default/classes/RecipientAccess.cls:124`) and counts a failure only when the postal code matches (`:138-140`); `countFailure` keys the guard on the shipment Id (`:296-312`, `Shipment_Key__c`), and the fifth counted failure locks the shipment for 15 minutes. So LOCKED appears only for the right postal code (oracle) and anyone who learns it can keep the recipient locked out. Tracking numbers are sequential (Shipment__c AutoNumber) and PublicTrackingController returns the destination city.
- SEC-011 (Low, same code): `findGuard` reads without `FOR UPDATE` (`RecipientAccess.cls:123`), so a parallel burst gets more than 5 guesses per window.
- SEC-003 (High): Health Check "Require MFA for all direct UI logins: Not enforced"; retrieved Security settings `enableMFADirectUILoginOptIn=false`; force-app has no Security settings file (`force-app/main/default/settings/` holds only Apex.settings-meta.xml).
- CA-001 (High, sev 2): `force-app/main/default/lwc/rcHeader/__tests__/rcHeader.accessibility.test.js:40` and `rcHeader.test.js:104` — `new Promise((resolve) => setTimeout(resolve, 0))` (eslint no-promise-executor-return).
- CA-002 (High, sev 2, X14): `force-app/main/default/classes/CustomerShipmentAccessTest.cls:252` `@IsTest(SeeAllData=true)` (G9 history test; it also forced DEPLOY-ORDER.md step 5c).

## Problems
- P1: A leaked credential stays usable until rotated, and nothing stops the next secret from being committed (evidence: SEC-001).
- P2: A guest can learn every recipient's postal code and deny any recipient access to their delivery (evidence: SEC-002, SEC-011).
- P3: Either administrator's stolen password gives full control of the org (evidence: SEC-003).
- P4: Two analyzer High violations remain in the code base; one test depends on org data (evidence: CA-001, CA-002).

## Solutions
- S1 → P2: key the failure guard on the pair (shipment, typed postal code) — `Shipment_Key__c` = shipment Id + ":" + a hash of the normalized typed postal code (widen the field if needed) — and count every failure for an existing shipment under that key, whatever the postal code; check the lock of that same pair. Every postal code then locks the same way after 5 failures (no oracle), an attacker who does not know the recipient's postal code cannot lock the recipient's pair, and the 5-attempt limit per pair stays. Read the guard `FOR UPDATE` before comparing when the pair is counted (SEC-011). Discarded: counting by tracking number only (removes the oracle but lets anyone lock any recipient knowing only the public number); removing the lockout (X16 requires an attempt limit); CAPTCHA (no third-party script host allowed on the site); a site rate limit (infrastructure, owner).
- S2 → P3: version `force-app/main/default/settings/Security.settings-meta.xml` with only `sessionSettings.enableMFADirectUILoginOptIn = true`, deploy it, and add `scripts/checks/org-security-check.sh` that fails unless the source file and the org (retrieved Security settings, and the Health Check row) both show MFA required. Discarded: leaving it to production auto-enforcement (policy X10); setting every Health Check item now (Medium items stay in the report).
- S3 → P1, P4: a repository secret scan — `scripts/checks/secret-scan.sh` (patterns: the EntregaYa key shape, PEM private-key headers, SFDX auth URLs `force://`, generic `consumerSecret`/password assignments with a value) that prints file:line and rule, never the value, and exits non-zero; `.githooks/pre-commit` runs it on staged files; `scripts/setup/` enables it with `git config core.hooksPath .githooks` (documented in README); pattern-definition files are allow-listed by path. CA-001: block-bodied promise executors. CA-002: replace the SeeAllData test with a test that needs no org data (as Ana: Delivery_Instructions__c is not accessible by describe and a user-mode read of it fails), relying on the platform rule that field history follows FLS; drop DEPLOY-ORDER.md step 5c. Discarded: rewriting history (force-push, owner); deleting the history test without a replacement.

## Acceptance
- AC-H1.1 (SEC-002, X16) — Given a guest who knows a shipment's tracking number and its destination city, When they send 5 requests with a wrong access code using the recipient's postal code and 5 with a wrong access code using another postal code, Then both series return the same outcomes and messages (NOT_MATCHED four times, then LOCKED), so the right postal code cannot be told apart; and the guard writes are the same kind on both paths.
  *Mutation:* count failures only when the postal code matches (the old rule) — observed: <filled at tick>
- AC-H1.2 (SEC-002) — Given a guest made 5 or more failed attempts on a tracking number with postal codes that are not the recipient's, When the recipient then sends the right postal code and the right access code, Then access is granted (details returned, reschedule and proof still work) and the recipient's pair has no failure recorded.
  *Mutation:* key the guard on the shipment only — observed: <filled at tick>
- AC-H1.3 (attempt limit kept, SEC-011) — Given 5 failed attempts with the right postal code and wrong codes, When a sixth request brings the right code within 15 minutes, Then LOCKED; after the lock expires (test seam for the clock) the right code works and resets the pair; a parallel request cannot evaluate a guess on a pair that another request is locking (guard read FOR UPDATE before the comparison).
  *Mutation:* skip the lock check for the pair — observed: <filled at tick>
- AC-H2.1 (SEC-003, X10) — Given the org, When scripts/checks/org-security-check.sh runs, Then force-app/main/default/settings/Security.settings-meta.xml has enableMFADirectUILoginOptIn true, the org's retrieved Security settings and Health Check show MFA required for direct UI logins, and the script exits 0; it exits non-zero otherwise (also on a failed query or retrieve).
  *Mutation:* deploy the setting as false (script red), then deploy true again — observed: <filled at tick>
- AC-H3.1 (SEC-001, X14) — Given the repository with hooks enabled, When a commit stages a file containing a test value shaped like the EntregaYa key (built in the test from parts, never a real key), a PEM private-key header or an SFDX auth URL, Then the commit is refused naming the file, line and rule and never the value; and scripts/checks/secret-scan.sh over the tracked tree at HEAD reports 0 findings (pattern-definition files allow-listed by path).
  *Mutation:* remove the EntregaYa key pattern — the test commit is accepted — observed: <filled at tick>
- AC-H3.2 (CA-001) — Given the rcHeader tests, When `sf code-analyzer run` with the BestPractices and ErrorProne selectors targets force-app/main/default/lwc/rcHeader, Then no no-promise-executor-return violation, and Jest stays green.
  *Mutation:* restore the expression-bodied executor — the violation returns — observed: <filled at tick>
- AC-H3.3 (CA-002, X14) — Given CustomerShipmentAccessTest, When the analyzer runs, Then no ApexUnitTestShouldNotUseSeeAllDataTrue violation in force-app; and as Ana (System.runAs) Delivery_Instructions__c is not accessible by describe and a user-mode query that selects it fails; the gate (RunLocalTests) needs no history row (DEPLOY-ORDER.md step 5c removed).
  *Mutation:* grant read on Delivery_Instructions__c to RutaCargo_Customer (test red), revert with an explicit readable=false entry and compare the org's FieldPermissions with the file — observed: <filled at tick>

## Task analysis
| Task | Solves | Acceptance | Scope (files to touch) | Security | Executor | Skills | Reviewers |
|---|---|---|---|---|---|---|---|
| T1 | S1 | AC-H1.1, AC-H1.2, AC-H1.3 | force-app/main/default/classes/RecipientAccess.cls, force-app/main/default/classes/RecipientAccessTest.cls, force-app/main/default/classes/RecipientDeliveryControllerTest.cls, force-app/main/default/classes/TestDataFactory.cls, force-app/main/default/objects/Recipient_Access_Guard__c/fields/Shipment_Key__c.field-meta.xml (length only), odd/evidence/hardening-1/T1.md | yes | task-worker | salesforce-development:platform-apex-generate, salesforce-development:platform-apex-test-generate, salesforce-development:platform-apex-test-run, salesforce-development:platform-custom-field-generate, salesforce-development:platform-metadata-api-context-get, salesforce-development:platform-metadata-deploy, sf-security-code-review | task-reviewer, security-reviewer, access-auditor |
| T2 | S2 | AC-H2.1 | force-app/main/default/settings/Security.settings-meta.xml (new, only enableMFADirectUILoginOptIn), scripts/checks/org-security-check.sh (new), README.md (security settings section), odd/evidence/hardening-1/T2.md | yes | task-worker | salesforce-development:platform-metadata-api-context-get, salesforce-development:platform-metadata-deploy, salesforce-development:platform-metadata-retrieve, salesforce-development:platform-soql-query, sf-security-exposure-review | task-reviewer, security-reviewer, access-auditor |
| T3 | S3 | AC-H3.1, AC-H3.2, AC-H3.3 | scripts/checks/secret-scan.sh (new), .githooks/pre-commit (new), scripts/setup/enable-git-hooks.sh (new), README.md (repository hygiene section), force-app/main/default/lwc/rcHeader/__tests__/rcHeader.accessibility.test.js, force-app/main/default/lwc/rcHeader/__tests__/rcHeader.test.js, force-app/main/default/classes/CustomerShipmentAccessTest.cls, scripts/setup/DEPLOY-ORDER.md (step 5c), odd/evidence/hardening-1/T3.md | yes | task-worker | salesforce-code-quality:dx-code-analyzer-run, salesforce-development:platform-apex-test-generate, salesforce-development:platform-apex-test-run, salesforce-development:platform-permission-set-generate, salesforce-development:platform-metadata-deploy, experience-lwc:experience-lwc-generate, sf-security-exposure-review | task-reviewer, security-reviewer, access-auditor |

## Tasks
- [ ] T1 (S1): Guard keyed on (shipment, typed postal code); every failure counted; lock read FOR UPDATE — test first
- [ ] T2 (S2): MFA required for direct UI logins, versioned and checked — check first
- [ ] T3 (S3): Repository secret scan and pre-commit hook; CA-001; CA-002 without org data — test first

## Assumptions
- H1: SEC-001 stays open for the owner: rotate the EntregaYa key, decide on purging history (all branches, force-push), check the remote repository's visibility, and remove scripts/setup-entregaya-key.sh from the other branch. The re-audit will report it again until then.
- H2: Requiring MFA for direct UI logins in cargo-opus-t1 means both administrators register a verification method at their next UI login; CLI (OAuth) sessions are unaffected. Conservative choice under X10; recorded for the owner.
- H3: Residual of S1: an attacker who sweeps every postal code of the destination city 5 times each still locks the recipient's pair (cost: 5 × the city's postal codes, and no oracle tells them when they hit it); a site rate limit (CDN/WAF) is the owner's infrastructure item.
- H4: Medium and Low findings of audit 1 (SEC-004 to SEC-017) and the owner decisions (SEC-005, SEC-009, SEC-010, SEC-013, SEC-014) go to the final report, with no tasks.

## Close
Stage: pending
