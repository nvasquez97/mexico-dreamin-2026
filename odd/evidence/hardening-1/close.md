# hardening-1 Close fix round

## Fix - 994b51b

- Reviewed range: 2230597..2967cb3 (HEAD at start 8ca18f2, bookkeeping only since)
- Fix commit: 994b51b `close fix hardening-1: password-variable rule, *.der, purge VAD refusal, guard test split and asserts`
- Org: cargo-opus-t1 (scratch, Org Id 00DEk00000qop2zMAA, `isScratch: true`, verified with `sf org display` and `sf org list --skip-connection-status`)
- Skills used:
  - salesforce-development:platform-apex-test-generate (split class, size assertions, purge tests per condition)
  - salesforce-development:platform-apex-test-run (per-class synchronous runs, mutation reds)
  - salesforce-development:platform-metadata-deploy (LOOP deploys, mutation deploys)
  - salesforce-development:platform-permission-set-generate (temporary MFA probe permission set, finding 7)
  - salesforce-development:platform-soql-query (PermissionSetAssignment / CronTrigger / User queries)
  - salesforce-development:platform-data-manage (probe permission set and assignment create + delete)
  - salesforce-code-quality:dx-code-analyzer-run (Recommended over the changed Apex; NcssCount before/after)
- Production Apex (RecipientAccess.cls, RecipientAccessGuardPurge.cls) was changed only for the mutations below and restored (`git checkout`) and redeployed before the commit; the commit holds no production Apex.

### Finding 1 - test-reviewer Medium (AC-H4.1) + access-auditor: guest-access-check.sh reported a `$`-variable password as a literal (secret-scan-selftest.sh:301)

Fixed in the rule, not the fixture, no allow-list. The password values found by the grep are re-checked with perl: a value that is exactly `$UPPER_CASE_VAR`, or starts with `${` or `$(`, is a reference (the same test as `placeholder()` in secret-scan.sh); any other value, including one starting with `$` followed by lower case, is still reported.

Red before (`bash scripts/checks/guest-access-check.sh cargo-opus-t1`, rc=1):
```
FAIL: password literal in the repository at: scripts/checks/tests/secret-scan-selftest.sh:301
guest-access-check: 1 violation(s) in cargo-opus-t1
```
Offline check of the new filter (six lines built at runtime: 1 `$DB_PASSWORD`, 2 `${DB_PW}`, 3 a 10-character literal, 4 `$` + lower-case literal, 5 an XML password element with a literal, 6 a `$VAR` and a literal on one line) -> reported `a:3 a:4 a:5 a:6`, not 1 and 2.

A real literal is still caught (untracked probe file `pw-probe.tmp.txt`, line 1 a `$DB_PASSWORD` assignment, line 2 a 10-character literal assignment built at runtime; deleted right after; rc=1):
```
FAIL: password literal in the repository at: pw-probe.tmp.txt:2
guest-access-check: 1 violation(s) in cargo-opus-t1
```
Green after (rc=0):
```
ok:   no password literal in the repository besides the placeholder
guest-access-check: passed in cargo-opus-t1
```

### Finding 2 - test-reviewer Low (AC-H1.3): the step name "pairReadForUpdate" claims a lock the test never sees

The step name is written by RecipientAccess.cls:329 (production); renaming it is outside this round's Touch list (production Apex only for a temporary mutation). Fixed in the tests instead, so the claim is now proven:
- New `RecipientAccessPairGuardTest.shouldReadThePairRowFromSourceForUpdate_WhenRecipientAccessIsDeployed`: reads the deployed RecipientAccess body, takes the text of `lockPairGuard` up to the `note(... 'pairReadForUpdate:none' : 'pairReadForUpdate:row')` call, and asserts its SELECT ends in `WITH SYSTEM_MODE LIMIT 1 FOR UPDATE ];`.
- The two trace tests were renamed (`shouldReadThePairBeforeTheCodeAndMakeNoDml_...`, `shouldReadThePairBeforeTheCode_WhenTheCodeIsWrong`) and their messages now say "read before the code comparison"; they prove the order only.

Mutation: `FOR UPDATE` removed from `lockPairGuard` (RecipientAccess.cls:327), deploy 0AfEk00000h87zdKAA -> RecipientAccessPairGuardTest 23 run, 1 fail:
```
RecipientAccessPairGuardTest.shouldReadThePairRowFromSourceForUpdate_WhenRecipientAccessIsDeployed  Fail  System.AssertException: Assertion Failed: The SELECT of the pair row that notes "pairReadForUpdate" ends in FOR UPDATE: List<Recipient_Access_Guard__c> guards = [ SELECT Id, Failed_Attempts__c, Locked_Until__c FROM Recipient_Access_Guard__c WHERE Shipment_Key__c = :pairKey WITH SYSTEM_MODE LIMIT 1 ];
```
Restored, redeployed (0AfEk00000h87gIKAQ) -> 23/23 Pass.

### Finding 3 - test-reviewer Low: rows read with [0] and no count assertion

New helpers assert `size() == 1` before reading: `onlyGuardOf` (RecipientAccessPairGuardTest) and `onlyGuardOfPair` (RecipientDeliveryControllerTest), message `Exactly one guard row for the pair of "<typed postal code>"`.
Before (HEAD): RecipientAccessTest.cls:618, :619 (`guardsOf(...)[0]`), :638, :721, :745, :766; RecipientDeliveryControllerTest.cls:1042, :1076 (`guardOfPair(...).`).
After: those reads are `onlyGuardOf(...)` in RecipientAccessPairGuardTest and `onlyGuardOfPair(...)` at RecipientDeliveryControllerTest.cls:1053, :1087. `grep -nE "guardsOf\([^)]*\)\[0\]" RecipientAccessPairGuardTest.cls` -> no match.
Not changed (not named by the finding): the same pattern on older AC-002.1b tests, RecipientAccessTest.cls:315, :331, :337, :459, :509.

### Finding 4 - test-reviewer Low: RecipientAccessTest NCSS above 500

The hardening-1 sections (AC-H1.1, AC-H1.2, AC-H1.3, AC-H2.1, CODE-001 Kelvin, former lines 563-986) moved to the new class RecipientAccessPairGuardTest with the helpers they use; constants and helpers used only there were removed from RecipientAccessTest. Every test kept: 45 before -> 23 (RecipientAccessTest) + 22 moved + 1 new (finding 2) = 46.
Code Analyzer `pmd:NcssCount`:
- before (HEAD copy of RecipientAccessTest.cls): `The class 'RecipientAccessTest' has a NCSS line count of 560 (limit: 500, highest: 20).`
- after: 0 NcssCount on RecipientAccessTest.cls and 0 on RecipientAccessPairGuardTest.cls.
Green: RecipientAccessTest 23/23, RecipientAccessPairGuardTest 23/23.

### Finding 5 - test-reviewer Low (AC-H5.2): CustomerShipmentAccessTest:258 message claims field history

Before: `'Ana must not have read access to Delivery_Instructions__c, so its field history stays hidden from her'`.
After: `'As Ana, the describe must report Delivery_Instructions__c as not accessible (no read FLS)'`; the test comment says the history itself is not read there. CustomerShipmentAccessTest 11/11.

### Finding 6 - test-reviewer Low (AC-H2.1): the purge re-read test did not isolate its two conditions

Split into:
- (a) `shouldNotDelete_WhenScopeRowIsUnlockedButTouchedAfterTheBatchStarted`: 2 unlocked rows touched now, `new RecipientAccessGuardPurge().execute(null, rows)` on the real clock; only the date condition keeps them.
- (b) `shouldNotDelete_WhenScopeRowIsLockedAfterTheBatchStartedButOld`: 2 rows locked until asOf+10m, `new RecipientAccessGuardPurge(now+2d).execute(null, rows)`; only the lock condition keeps them.

Mutation (a): `AND LastModifiedDate < :cutoff` removed from execute's re-read (RecipientAccessGuardPurge.cls:106), deploy 0AfEk00000h87zdKAA -> 8 run, 1 fail:
```
RecipientAccessGuardPurgeTest.shouldNotDelete_WhenScopeRowIsUnlockedButTouchedAfterTheBatchStarted  Fail  System.AssertException: Assertion Failed: An unlocked row touched after the batch started is not deleted: Expected: 2, Actual: 0
```
Mutation (b): `AND (Locked_Until__c = null OR Locked_Until__c <= :now)` removed (RecipientAccessGuardPurge.cls:105), deploy 0AfEk00000h80TWKAY -> 8 run, 1 fail:
```
RecipientAccessGuardPurgeTest.shouldNotDelete_WhenScopeRowIsLockedAfterTheBatchStartedButOld  Fail  System.AssertException: Assertion Failed: A row locked after the batch started is never deleted: Expected: 2, Actual: 0
```
Restored, redeployed (0AfEk00000h87gIKAQ) -> 8/8 Pass. Classes deployed while the purge stays scheduled (Deployment setting).

### Finding 7 - test-reviewer Low (AC-H3.1): the "no customer holds MFA-for-UI-logins" clause never seen red

org-security-check.sh not changed (its existing clause turned red). Baseline rc=0. Then, in cargo-opus-t1 (times UTC):
- 01:41:01 created PermissionSet `Tmp_H31_MFA_Probe` (0PSEk00000EsvR3OAJ, `PermissionsForceTwoFactor=true`, a data record, never in the repository).
- 01:41:14 assigned it (PermissionSetAssignment 0PaEk00000miO6IKAU) to the test customer user t4-repro (005Ek00000vuVbPIAU, CspLitePortal). RutaCargo_Customer and the RutaCargo Customer profile were not touched.
- `bash scripts/checks/org-security-check.sh cargo-opus-t1` -> rc=1:
```
FAIL: active users with a UserType other than Standard hold Multi-Factor Authentication for User Interface Logins: Tmp_H31_MFA_Probe -> CspLitePortal
org-security-check: 1 violation(s) in cargo-opus-t1
```
- 01:41:37 deleted the assignment, then the permission set (23 seconds live; no login happened). Verified: `SELECT COUNT() FROM PermissionSet WHERE Name = 'Tmp_H31_MFA_Probe'` -> 0; ForceTwoFactor assignments of 005Ek00000vuVbPIAU -> 0.
- Re-run -> rc=0, `org-security-check: passed in cargo-opus-t1`.

### Finding 8 - sf-security-auditor note 2 (P7/H3): schedule-guard-purge.sh does not require View All Data

The script now refuses (exit 1, nothing scheduled) unless the user it runs as holds `PermissionsViewAllData` (read-only `SELECT COUNT() FROM PermissionSetAssignment WHERE Assignee.Username = ... AND Assignee.IsActive = true AND PermissionSet.PermissionsViewAllData = true`, which counts profile and permission-set grants), and, when the job exists, unless the job's owner (CronTrigger.OwnerId) holds it too. Seam `GUARD_PURGE_ALSO_CHECK_USERNAME=<username>` checks one more user; it can only add a refusal. Usernames are checked against `^[A-Za-z0-9._%+@-]+$` before they go into the query.

Red (seam pointed at the site guest user, no user changed), rc=1:
```
schedule-guard-purge: the user this script runs as (<admin>) holds View All Data
schedule-guard-purge: refused: the user to check (<site guest user>) has no View All Data in cargo-opus-t1; the purge is with sharing and would not see every guard row. Run it as an admin with View All Data.
```
Injection-shaped seam value -> rc=1 `schedule-guard-purge: not a username: refusing to query it`.
Green (normal run, idempotent), rc=0:
```
schedule-guard-purge: the user this script runs as (<admin>) holds View All Data
schedule-guard-purge: the owner of the scheduled job (005Ek00000voo5hIAA) holds View All Data
schedule-guard-purge: already scheduled in cargo-opus-t1; nothing changed
schedule-guard-purge: 0 0 3 * * ? state WAITING, next run 2026-11-19T11:00:00.000+0000
```
CronTrigger count for "RecipientAccessGuardPurge daily": 1 (08eEk00000zFXVCIA4, WAITING).

### Finding 9 - access-auditor T4 residual (X14, Low): SECRET-FILE does not match *.der

`der` added to the SECRET-FILE extension list (and its header comment) and `*.der` to .gitignore. Self-test cases: a binary `certs/client.der` is refused by the pre-commit with `certs/client.der:0 SECRET-FILE` and no value; the repository .gitignore ignores `certs/client.der` (`git check-ignore --no-index`).
Red before the rule (`bash scripts/checks/tests/secret-scan-selftest.sh`, rc=1):
```
FAIL  DER-encoded key or certificate (.der): the pre-commit refuses the commit (rc=0, the test commit was accepted)
FAIL  DER-encoded key or certificate (.der): output names certs/client.der:0 SECRET-FILE
FAIL  the repository .gitignore ignores *.der files
selftest: 3 failure(s)
```
Green after: 119 PASS, `selftest: all checks passed`; `bash scripts/checks/secret-scan.sh --tree` -> `secret-scan: 0 findings in tracked files at HEAD`.

### All task test classes (LOOP, after the fix, production restored)
- RecipientAccessPairGuardTest: Passed, 23 run, 100%
- RecipientAccessTest: Passed, 23 run, 100%
- RecipientDeliveryControllerTest: Passed, 48 run, 100%
- RecipientAccessGuardPurgeTest: Passed, 8 run, 100%
- CustomerShipmentAccessTest: Passed, 11 run, 100%

The AC Mutations M1-M4 and the T2 mutations were not re-applied: no production code changed in this round, and the moved tests are unchanged copies (finding 3 only added a size assertion before the same reads).

### Code Analyzer
`sf code-analyzer run --rule-selector Recommended` over the five changed test classes: 218 violations, 0 severity 1, 0 severity 2; 122 sev 3, 95 sev 4, 1 sev 5. Top rules: MethodNamingConventions 102, ApexUnitTestClassShouldHaveRunAs 91, ApexUnitTestClassShouldHaveAsserts 12 (methods that assert through helpers), CyclomaticComplexity 3, AvoidNonRestrictiveQueries 3. Noted, not fixed (not named by a finding): NcssCount 662 on RecipientDeliveryControllerTest (existed before); CPD sev 5 in RecipientAccessPairGuardTest (the Fixture/insertShipment/guardsOf helpers duplicate RecipientAccessTest's, the cost of the split). Bash scripts are not covered by the analyzer.

### Governor limits
No change to production code. The source check reads one ApexClass row. The purge tests use 2 rows each; the 251-row purge tests are unchanged.

### Commands
- `sf org display --target-org cargo-opus-t1 --json`; `sf org list --skip-connection-status --json`
- `sf project deploy start --source-dir force-app/main/default/classes --target-org cargo-opus-t1` (green, 2 mutation deploys, restore deploy)
- `sf apex run test --class-names <class> --synchronous --result-format human --target-org cargo-opus-t1` for the five classes
- `bash scripts/checks/guest-access-check.sh cargo-opus-t1` (before, probe, after)
- `bash scripts/checks/org-security-check.sh cargo-opus-t1` (baseline, probe, after)
- `sf data create record` / `sf data delete record` for PermissionSet and PermissionSetAssignment (finding 7)
- `bash scripts/setup/schedule-guard-purge.sh cargo-opus-t1` (seam red, injection red, green)
- `bash scripts/checks/tests/secret-scan-selftest.sh`; `bash scripts/checks/secret-scan.sh --tree`; `bash scripts/checks/secret-scan.sh --staged` before each commit
- `sf code-analyzer run --rule-selector Recommended --target <5 classes>`; `sf code-analyzer run --rule-selector pmd:NcssCount` over the HEAD copy of RecipientAccessTest.cls
