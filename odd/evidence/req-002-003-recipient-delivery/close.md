# Close of req-002-003-recipient-delivery — fix evidence

- Reviewed range: bfc2dc3..59167d0 (test-reviewer and sf-security-auditor findings)
- Fix sha: 8e3db4f (`close fix req-002-003-recipient-delivery: tests prove the locked reschedule ...`)
- Org: cargo-opus-t1 (scratch, org id 00DEk00000qop2zMAA, instance `*.scratch.my.salesforce.com`, `isDevHub: false`; verified with `sf org display` and `sf org list --skip-connection-status`)
- Files changed: force-app/main/default/classes/RecipientAccessTest.cls, force-app/main/default/classes/RecipientDeliveryControllerTest.cls, force-app/main/default/objects/Recipient_Access_Guard__c/fields/Failed_Attempts__c.field-meta.xml (description only). No production Apex changed: no new test showed a defect.
- No access code, key or token appears in this file or in any command output below.

## Skills used

| Skill | For |
|---|---|
| salesforce-development:platform-apex-test-generate | the new and changed test methods (one behavior per method, null and empty apart, Assert class with messages, two inputs for a positive result) |
| salesforce-development:platform-apex-test-run | the LOOP runs, the focused runs under each mutation, coverage |
| salesforce-development:platform-metadata-deploy | the LOOP deploys and the temporary mutation deploys |
| salesforce-development:platform-custom-field-generate | the Failed_Attempts__c description edit (checklist: description and help text present, Number precision 2 scale 0, no comment before the root) |
| salesforce-code-quality:dx-code-analyzer-run | Code Analyzer (Recommended) over the two changed test classes, against a HEAD baseline |

No skill conflicted with the handoff or CLAUDE.md.

## Findings

| # | Reviewer, severity | Result |
|---|---|---|
| 1 | test-reviewer Medium: the locked sixth attempt never sent through rescheduleDelivery | fixed: RecipientAccessTest.shouldRefuseRescheduleWithoutVerifyingOrWriting_WhenSixthAttemptHasRightValues |
| 2 | test-reviewer Medium: no wrong-record (IDOR, X16) test with another shipment's valid code | fixed: RecipientDeliveryControllerTest.shouldRefuseEveryMethod_WhenGuestSendsAnotherShipmentsCodeWithSamePostalCode |
| 3 | test-reviewer Low: the SystemModstamp assertion in assertRejectedUnchanged cannot fail | fixed: a per-call DML delta of 0 replaces it (finding confirmed first, see M3-before) |
| 4 | test-reviewer Low: guest reschedule asserts only the date | fixed: also Delivery_Instructions__c == DOORMAN and Reschedule_Count__c == 1 |
| 5 | test-reviewer Low: ProofOfDeliveryService missing from the sharing test | fixed: added to the query and asserted `public with sharing class ProofOfDeliveryService` |
| 6 | test-reviewer Low: null, empty and malformed dates in one method | fixed: shouldReject_WhenNewDateIsNull, shouldReject_WhenNewDateIsEmpty, shouldReject_WhenNewDateIsMalformed |
| 7 | test-reviewer Low: rescheduleDelivery:142-143 (generic AuraHandledException) uncovered | fixed: shouldThrowGenericAuraHandledException_WhenRescheduleFailsUnexpectedly; line 143 now covered (controller 99%, only line 138 uncovered) |
| 8 | test-reviewer Low: findShipment:226 uncovered (blank, over-80 tracking number); positive tests assert only non-null | fixed: shouldReturnNotMatchedWithOneHash_WhenTrackingNumberIsBlank and _WhenTrackingNumberIsOver80Characters (NOT_MATCHED, shared message, exactly 1 hash); both positive tests assert recipientName, and the second fixture now has its own recipient name ("Maria Lopez") so a fixed value cannot pass both |
| 9 | sf-security-auditor note: Failed_Attempts__c description says the counter is reset when locked | fixed (description only): "Consecutive failed verifications with the right postal code and a wrong access code; reset by a success; the fifth failure locks the shipment and the counter stays at 5 while it is locked." |

### What each new or changed test does

- Finding 1: shipment In transit, todayOverride 2026-12-05, 5 failures through rescheduleDelivery, then rescheduleDelivery with the right values and 2026-12-12 (inside the window). Asserts LOCKED, `RecipientAccess.LOCKED_MESSAGE`, details null, `DeliveryAccessCode.hashesComputed` delta 0, and Estimated_Delivery__c, Delivery_Instructions__c, Reschedule_Count__c unchanged.
- Finding 2: shipments A and B, both postal code 64000 and In transit; as `TestDataFactory.siteGuestUser()` the test calls getDeliveryDetails, rescheduleDelivery (a valid date) and downloadProof with A's tracking number and B's code. Asserts each answer is NOT_MATCHED with the shared message, no details and no pdfBase64; no callout (ProofMock endpoints empty); the date, instructions and count of A and of B unchanged; A's guard Failed_Attempts__c == 3; B has no guard row.
- Finding 3: the `reschedule` helper records `Limits.getDmlStatements()` before and after each call per shipment; `assertRejectedUnchanged` asserts that the last call on the shipment made 0 DML statements (a rejection never writes: verification with a zero counter, the rules and FOR UPDATE make no DML). SystemModstamp is removed from `reload`.

## M3-before: the finding 3 confirmation at HEAD

Mutation M3 (below) deployed with the HEAD test classes. With the SystemModstamp assertion, 8 of the 9 rejection tests stayed GREEN although every verification wrote the shipment; the only red came because that test crossed a second boundary:

```
RecipientDeliveryControllerTest.shouldMeasureFromOriginal_WhenEstimateWasMovedLater                        Pass
RecipientDeliveryControllerTest.shouldMeasureSecondRescheduleFromOriginal_WhenFirstMovedTheDate            Pass
RecipientDeliveryControllerTest.shouldNotOfferAndReject_WhenOriginalEstimateIsEmpty                        Pass
RecipientDeliveryControllerTest.shouldRejectWithLimitMessage_WhenRescheduledTwice                          Pass
RecipientDeliveryControllerTest.shouldRejectWithStatusMessage_WhenStatusIsNotPickedUpOrInTransit           Fail     System.AssertException: Assertion Failed: The shipment must not be written: Expected: 2026-11-18 00:48:15, Actual: 2026-11-18 00:48:16
RecipientDeliveryControllerTest.shouldReject_WhenInstructionsExceed1000Characters                          Pass
RecipientDeliveryControllerTest.shouldReject_WhenNewDateIsOriginalPlusEight                                Pass
RecipientDeliveryControllerTest.shouldReject_WhenNewDateIsToday                                            Pass
RecipientDeliveryControllerTest.shouldReject_WhenNewDateIsUnparsable                                       Pass
Outcome              Failed
Tests Ran            42
Pass Rate            98%
```

## First green (new tests, HEAD production code)

The new and changed tests passed on their first run (Test Run Id 707Ek00003V21q5: 98 run, 100%). Since they were never red before the code, each was then proven by a mutation of the production code.

## Mutations (each applied alone, deployed with RecipientAccess.cls and RecipientDeliveryController.cls, run, reverted)

Mutations were deployed temporarily; M5 also deployed ProofOfDeliveryService.cls temporarily. All mutations are global to the shared code path (for M1, RecipientAccess bundles the lock check for every method, so "rescheduleDelivery skips the lock check" was applied as the shared check skipped).

- M1 (finding 1), RecipientAccess.verifyBeforeCallout:124 `if (isLocked(guard))` -> `if (false && isLocked(guard))`. Run 707Ek00003V28uO:
  ```
  RecipientAccessTest.shouldRefuseRescheduleWithoutVerifyingOrWriting_WhenSixthAttemptHasRightValues  Fail  System.AssertException: Assertion Failed: A locked shipment must refuse the reschedule: Expected: LOCKED, Actual: SUCCESS
    Class.RecipientAccessTest.shouldRefuseRescheduleWithoutVerifyingOrWriting_WhenSixthAttemptHasRightValues: line 386, column 1
  ```
- M2 (finding 2), RecipientAccess.verifyBeforeCallout after the hash: when the postal code matches and the code is well formed but does not match, compare it against every other shipment with that postal code (`SELECT Delivery_Access_Code_Hash__c FROM Shipment__c WHERE Destination_Postal_Code__c = :row.Destination_Postal_Code__c AND Id != :row.Id`) and verify A on a match. Run 707Ek00003V1tzq:
  ```
  RecipientDeliveryControllerTest.shouldRefuseEveryMethod_WhenGuestSendsAnotherShipmentsCodeWithSamePostalCode  Fail  System.AssertException: Assertion Failed: Another shipment's code is refused: Expected: NOT_MATCHED, Actual: SUCCESS
    Class.RecipientDeliveryControllerTest.shouldRefuseEveryMethod_WhenGuestSendsAnotherShipmentsCodeWithSamePostalCode: line 1113, column 1
  ```
- M3 (finding 3), RecipientAccess.verify: after a successful verification, `Database.update(new Shipment__c(Id = result.shipmentId), AccessLevel.SYSTEM_MODE)` (a write that keeps date, instructions and count). Run 707Ek00003V1p1I: all 11 rejection tests red (8 of 9 were green at HEAD, above):
  ```
  RecipientDeliveryControllerTest.shouldRejectWithLimitMessage_WhenRescheduledTwice  Fail  System.AssertException: Assertion Failed: A rejection makes no DML: the shipment must not be written: Expected: 0, Actual: 1
  RecipientDeliveryControllerTest.shouldReject_WhenNewDateIsNull  Fail  System.AssertException: Assertion Failed: A rejection makes no DML: the shipment must not be written: Expected: 0, Actual: 1
  RecipientDeliveryControllerTest.shouldReject_WhenNewDateIsMalformed  Fail  System.AssertException: Assertion Failed: A rejection makes no DML: the shipment must not be written: Expected: 0, Actual: 1
  RecipientDeliveryControllerTest.shouldMeasureSecondRescheduleFromOriginal_WhenFirstMovedTheDate  Fail  System.AssertException: Assertion Failed: A rejection makes no DML: the shipment must not be written: Expected: 0, Actual: 1
  RecipientDeliveryControllerTest.shouldNotOfferAndReject_WhenOriginalEstimateIsEmpty  Fail  System.AssertException: Assertion Failed: A rejection makes no DML: the shipment must not be written: Expected: 0, Actual: 1
  RecipientDeliveryControllerTest.shouldRejectWithStatusMessage_WhenStatusIsNotPickedUpOrInTransit  Fail  System.AssertException: Assertion Failed: A rejection makes no DML: the shipment must not be written: Expected: 0, Actual: 1
  RecipientDeliveryControllerTest.shouldReject_WhenNewDateIsToday  Fail  System.AssertException: Assertion Failed: A rejection makes no DML: the shipment must not be written: Expected: 0, Actual: 1
  RecipientDeliveryControllerTest.shouldReject_WhenNewDateIsEmpty  Fail  System.AssertException: Assertion Failed: A rejection makes no DML: the shipment must not be written: Expected: 0, Actual: 1
  RecipientDeliveryControllerTest.shouldReject_WhenNewDateIsOriginalPlusEight  Fail  System.AssertException: Assertion Failed: A rejection makes no DML: the shipment must not be written: Expected: 0, Actual: 1
  RecipientDeliveryControllerTest.shouldMeasureFromOriginal_WhenEstimateWasMovedLater  Fail  System.AssertException: Assertion Failed: A rejection makes no DML: the shipment must not be written: Expected: 0, Actual: 1
  RecipientDeliveryControllerTest.shouldReject_WhenInstructionsExceed1000Characters  Fail  System.AssertException: Assertion Failed: A rejection makes no DML: the shipment must not be written: Expected: 0, Actual: 1
  Outcome  Failed
  Tests Ran  11
  Pass Rate  0%
  ```
- M4 (finding 4), RecipientAccess.saveReschedule:210 `Delivery_Instructions__c = instructions` -> `Delivery_Instructions__c = verification.lockedRow.Delivery_Instructions__c`. Run 707Ek00003V1eR5:
  ```
  RecipientDeliveryControllerTest.shouldReschedule_WhenGuestSendsValidValues  Fail  System.AssertException: Assertion Failed: The guest's instructions are saved: Expected: Leave with the doorman, Actual: null
    Class.RecipientDeliveryControllerTest.shouldReschedule_WhenGuestSendsValidValues: line 292, column 1
  ```
- M5 (finding 5), ProofOfDeliveryService.cls:25 `public with sharing class` -> `public inherited sharing class`. Run 707Ek00003V1iOL:
  ```
  RecipientAccessTest.shouldDeclareSharingAndJustification_WhenClassesAreDeployed  Fail  System.AssertException: Assertion Failed: ProofOfDeliveryService must be with sharing
    Class.RecipientAccessTest.shouldDeclareSharingAndJustification_WhenClassesAreDeployed: line 568, column 1
  ```
- M6 (finding 6), RecipientDeliveryController.parseIsoDate: a blank value returns `today().addDays(2)` (a date inside the window). Run 707Ek00003V1mGZ (the malformed test stays green, so each input has its own red):
  ```
  RecipientDeliveryControllerTest.shouldReject_WhenNewDateIsNull  Fail  System.AssertException: Assertion Failed: The reschedule must be rejected: Expected: REJECTED, Actual: SUCCESS
  RecipientDeliveryControllerTest.shouldReject_WhenNewDateIsMalformed  Pass  198
  RecipientDeliveryControllerTest.shouldReject_WhenNewDateIsEmpty  Fail  System.AssertException: Assertion Failed: The reschedule must be rejected: Expected: REJECTED, Actual: SUCCESS
  ```
- M7 (finding 7), RecipientDeliveryController.rescheduleDelivery:143 `throw genericError();` -> `throw unexpected;`. Run 707Ek00003V1zTA:
  ```
  RecipientDeliveryControllerTest.shouldThrowGenericAuraHandledException_WhenRescheduleFailsUnexpectedly  Fail  RecipientAccess.RecipientAccessException: Simulated unexpected failure.
    Class.RecipientDeliveryController.failIfSimulated: line 326, column 1
    Class.RecipientDeliveryController.rescheduleDelivery: line 122, column 1
  ```
- M8a (finding 8), RecipientAccess.verifyBeforeCallout: `if (row == null) { return new Verification(Outcome.NOT_MATCHED, NOT_MATCHED_MESSAGE); }` right after findShipment (no decoy hash). Run 707Ek00003V1mi6:
  ```
  RecipientAccessTest.shouldReturnNotMatchedWithOneHash_WhenTrackingNumberIsBlank  Fail  System.AssertException: Assertion Failed: A blank tracking number costs the same hash work as a success: Expected: 1, Actual: 0
  RecipientAccessTest.shouldReturnNotMatchedWithOneHash_WhenTrackingNumberIsOver80Characters  Fail  System.AssertException: Assertion Failed: An over-long tracking number costs the same hash work as a success: Expected: 1, Actual: 0
  ```
  Equivalent mutations noted: removing the blank check or the 80-character check in findShipment is equivalent (the query by Name finds no row either way, and the decoy hash still runs), so the stronger variant M8a was used.
- M8b (finding 8, second part), RecipientDeliveryController.detailsOf `details.recipientName = shipment.Recipient_Name__c` -> `'Test Recipient'`. Run 707Ek00003V2CLB (the first input passes; the second input, added for this reason, is red):
  ```
  RecipientAccessTest.shouldOpenDetails_WhenPostalCodeHasSpacesAndCodeIsHyphenatedLowerCase  Pass  289
  RecipientAccessTest.shouldOpenDetails_WhenCodeHasSpacesAndPostalCodeHasInnerSpaceAndOtherCase  Fail  System.AssertException: Assertion Failed: The details are the verified shipment's: Expected: Maria Lopez, Actual: Test Recipient
  ```
- Finding 9 is a description; no mutation applies.

After each mutation the file was reverted with `git checkout --`; the next deploy shipped both production classes at HEAD. After M5: `grep -rn MUTATION force-app/` found nothing, `git status` showed only the three task files, and RecipientAccess.cls, RecipientDeliveryController.cls and ProofOfDeliveryService.cls were redeployed at HEAD (Succeeded 10/10).

## Green

LOOP deploy (Succeeded 7/7, 0AfEk00000h59EqKAI), then the three classes. Run 707Ek00003V29Ia:

```
Outcome              Passed
Tests Ran            98
Pass Rate            100%
Fail Rate            0%
```

Coverage (run 707Ek00003V1zNl, same code): RecipientDeliveryController 99% (uncovered 138: the rejection on the re-check of the locked row, which only a concurrent reschedule reaches), RecipientAccess 94% (uncovered 204, 320-324: misuse guard and the duplicate-key retry), ProofOfDeliveryService 95%. The lines named in the findings (controller 142-143 and RecipientAccess 226) are covered.

## Code Analyzer

`sf code-analyzer run --rule-selector Recommended` over the two test classes, and the same over the HEAD versions of both files as a baseline:

- 0 Critical (1), 0 High (2). After the fix: 158 (89 moderate, 69 low). HEAD baseline: 141.
- New: MethodNamingConventions +7 (the project's `should..._When...` convention, the same as every existing test), ApexUnitTestClassShouldHaveRunAs +6 (the same pattern as the existing tests; the guest tests use System.runAs), ApexUnitTestClassShouldHaveAsserts +2 (the null and empty date tests assert in the `assertRejectedUnchanged` helper, a false positive), CyclomaticComplexity +1 (class-level total of RecipientAccessTest 45, highest method 2).
- FieldDeclarationsShouldBeAtStart for the new `RESCHEDULE_DML_BY_SHIPMENT` was fixed (moved to the field block); the 2 that remain (PROOF_UNAVAILABLE, PDF_BASE64) exist at HEAD.

## Governor-limit note

No risk: test code only. The DML-delta helper reads `Limits.getDmlStatements()` and makes no query or DML. The new tests use at most 6 controller calls each.

## Commands

```
sf org display --target-org cargo-opus-t1 --json
sf org list --skip-connection-status --json
sf project deploy start --source-dir force-app/main/default/classes/RecipientAccessTest.cls --source-dir force-app/main/default/classes/RecipientDeliveryControllerTest.cls --source-dir force-app/main/default/objects/Recipient_Access_Guard__c --target-org cargo-opus-t1
sf project deploy start --source-dir force-app/main/default/classes/RecipientAccess.cls --source-dir force-app/main/default/classes/RecipientDeliveryController.cls [--source-dir force-app/main/default/classes/ProofOfDeliveryService.cls] --target-org cargo-opus-t1 --wait 10 --json   (each mutation, and the HEAD restore)
sf apex run test --class-names RecipientAccessTest --class-names RecipientDeliveryControllerTest --class-names ProofOfDeliveryServiceTest --result-format human --wait 10 --target-org cargo-opus-t1 [--code-coverage]
sf apex run test --tests <Class.method> ... --result-format human --wait 10 --target-org cargo-opus-t1   (focused runs under each mutation)
sf code-analyzer run --rule-selector Recommended --target <the two test classes> --output-file <scratchpad>/code-analyzer-results-20261117-close2.json --include-fixes
sf code-analyzer run --rule-selector Recommended --workspace <scratchpad>/head --target <scratchpad>/head/classes --output-file <scratchpad>/code-analyzer-results-20261117-head.json
```

## Out of scope noticed

- Failed_Attempts__c `inlineHelpText` still reads "Consecutive failed access attempts since the last success or lock." The handoff allowed the description only; the help text also implies a reset at the lock.
