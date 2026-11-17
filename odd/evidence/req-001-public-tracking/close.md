# Close of req-001-public-tracking - evidence

## Fix - 2dcff81

- Task document: odd/tasks/req-001-public-tracking.md · reviewed range d0c2143..bb1d1c7
- Fix commit: 2dcff81 (`close fix req-001-public-tracking: ...`), files: PublicTrackingControllerTest.cls, lwc/rcTracking/{rcTracking.js, rcTracking.css, __tests__/rcTracking.test.js}, scripts/checks/guest-access-check.sh, scripts/checks/brand-check.sh. PublicTrackingController.cls, PublicTrackingSelector.cls and PublicTrackingResult.cls are unchanged; no test showed a defect in them. They were changed only for the mutations below, and each mutation was reverted and redeployed.
- Org: cargo-opus-t1 (`sf org display`: scratch, https://data-energy-2854-dev-ed.scratch.my.salesforce.com, `isScratch: true`, expires 2026-12-17)
- Skills used:
  - salesforce-development:platform-apex-test-generate: the new and split Apex tests.
  - salesforce-development:platform-apex-test-run: the LOOP runs and the mutation runs.
  - salesforce-development:platform-metadata-deploy: deploying the test class, the LWC and the mutants.
  - salesforce-development:platform-metadata-retrieve: retrieving rcTracking to prove the org matched HEAD before `--ignore-conflicts`.
  - experience-lwc:experience-lwc-generate: the rcTracking JS/CSS and the Jest tests.
  - experience-lwc:experience-lwc-accessibility-jest-run: the Sa11y suite inside `npx jest`.
  - experience-lwc:experience-accessibility-validate: finding 3, WCAG 4.1.3. The live region now stays in the accessibility tree.
  - salesforce-code-quality:dx-code-analyzer-run: the analyzer run over the changed files.
- Conflicts with skill guidance:
  - platform-apex-test-generate advises splitting a test class over 500 lines. PublicTrackingControllerTest is now 574 lines, but the handoff's scope is that single file, so it was not split.
  - The handoff names the platform-apex-test-generate skill, so test names keep the project's existing `subject_scenario_result` style. PMD MethodNamingConventions flags that style; see the analyzer section.

### Final green (after the fix, org redeployed with HEAD production classes)
```
sf apex run test --class-names PublicTrackingControllerTest --result-format human --wait 10 --target-org cargo-opus-t1
Outcome              Passed
Tests Ran            39
Pass Rate            100%
Fail Rate            0%
Test Run Id          707Ek00003V0roD

npx jest force-app/main/default/lwc/rcTracking
Test Suites: 2 passed, 2 total
Tests:       46 passed, 46 total
```
Deploy (LOOP): `sf project deploy start --source-dir force-app/main/default/classes/PublicTrackingControllerTest.cls --source-dir force-app/main/default/lwc/rcTracking --target-org cargo-opus-t1` first answered 4 Conflicts on rcTracking. Then `sf project retrieve start --metadata LightningComponentBundle:rcTracking --target-metadata-dir .retrieve-check-rcTracking --unzip` was compared with `git show HEAD:` for each of the 4 files. The only difference was the final newline, which the platform strips (`\ No newline at end of file`), so the org matched HEAD. The temporary folder was removed, and the deploy was rerun with `--ignore-conflicts`: Deploy ID 0AfEk00000h51acKAA, rcTracking Changed. `sf community publish --name RutaCargo --target-org cargo-opus-t1` returned status 0, "We're publishing your changes now."

---

### Finding 1 - test-reviewer [Medium] vacuous `search_response_containsNoPrivateValueAndNoId` (C10) - fixed
The guard `serialized.contains(searched[0]) && serialized.contains(searched[1])` is replaced. The test now keeps the PublicTrackingResult and asserts `trackingNumbersOf(result) == searched` and `notFound` empty, and only then serializes it. The private-value set moved to a helper, `privateValuesOf`, which the guest test also uses.

Before: under MF3 the old test stayed green (T1.md:490).
After: MF3 (the selector is never called), applied to PublicTrackingController.selectRows:
```
-        if (queryable.isEmpty()) {
+        if (queryable.isEmpty() || queryable != null) {
```
Red, verbatim:
```
PublicTrackingControllerTest.search_response_containsNoPrivateValueAndNoId               Fail     System.AssertException: Assertion Failed: Both shipments must be results before the response is inspected: Expected: (RC000101121, RC000101122), Actual: ()
PublicTrackingControllerTest.siteGuest_search_eachResultHasExactlyTheBr01Keys            Fail     System.AssertException: Assertion Failed: The guest must get both shipments before their keys are checked: Expected: (RC000101121, RC000101122), Actual: ()
PublicTrackingControllerTest.siteGuest_search_responseContainsNoPrivateValueAndNoId      Fail     System.AssertException: Assertion Failed: The guest must get both shipments before the response is inspected: Expected: (RC000101121, RC000101122), Actual: ()
PublicTrackingControllerTest.search_trackingValuesSplitOnLineBreaks_returnsThreeResults  Fail     System.AssertException: Assertion Failed: One entry "A\nB\r\nC" must be split on LF and CRLF into three tracking numbers: Expected: (RC000101128, RC000101129, RC000101130), Actual: ()
PublicTrackingControllerTest.search_lastLocation_isEachShipmentsOwn                      Fail     System.AssertException: Assertion Failed: Both shipments must be returned before their locations are checked: Expected: 2, Actual: 0
Outcome              Failed
```
The mutation was reverted, and the test was green again in the final run.

### Finding 2 - test-reviewer [Medium] guest refusal and guest BR-01 keys untested - fixed
New tests, all running as the real site guest user (`System.runAs(TestDataFactory.siteGuestUser())`):
- `siteGuest_search_eachResultHasExactlyTheBr01Keys` asserts both shipments and then exactly BR01_KEYS for each result.
- `siteGuest_search_responseContainsNoPrivateValueAndNoId` asserts both shipments, an empty notFound, and none of the private values or Ids.
- `siteGuest_modePriceField_isRejectedWithoutQuery` expects mode 'Price__c' to give the generic message and run no query.

Mutation B (M4-style: Price__c in the DTO, the query and the mapping), in PublicTrackingResult.TrackedShipment, PublicTrackingSelector.selectByTrackingNumbers and PublicTrackingController.toTrackedShipment:
```
+        shipment.price = row.Price__c;
+        @AuraEnabled
+        public Decimal price;
-                Last_Location__c, Last_Update__c, Estimated_Delivery__c
+                Last_Location__c, Last_Update__c, Estimated_Delivery__c, Price__c
```
Red, verbatim:
```
PublicTrackingControllerTest.siteGuest_search_eachResultHasExactlyTheBr01Keys        Fail     System.AssertException: Assertion Failed: A guest result must have exactly the seven BR-01 keys: Expected: {destinationCity, estimatedDelivery, lastLocation, lastUpdate, originCity, status, trackingNumber}, Actual: {destinationCity, estimatedDelivery, lastLocation, lastUpdate, originCity, price, status, trackingNumber}
PublicTrackingControllerTest.siteGuest_search_responseContainsNoPrivateValueAndNoId  Fail     System.AssertException: Assertion Failed: The guest response must not contain 4321.87
PublicTrackingControllerTest.search_response_containsNoPrivateValueAndNoId           Fail     System.AssertException: Assertion Failed: The response must not contain 4321.87
Outcome              Failed
```
Mutation C (the closed mode list is removed, so a mode is accepted as a field name):
```
-        if (mode == null || !MODES.contains(mode)) {
+        if (mode == null) {
```
Red, verbatim:
```
PublicTrackingControllerTest.siteGuest_modePriceField_isRejectedWithoutQuery  Fail     System.AssertException: Assertion Failed: Assertion failed: search must throw an AuraHandledException
```
All three classes were reverted (`git checkout`) and redeployed. The final run is green.

### Finding 3 - brand-reviewer (C11, WCAG 4.1.3) live region hidden with `display: none` - fixed
In rcTracking.css, `.rc-tracking__summary:empty { display: none; }` became a visually-hidden rule: `position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap`. The empty region stays in the accessibility tree, and because it is out of the grid flow it adds no gap. New Jest tests:
- "the live region stays in the accessibility tree while empty (visually hidden, never display: none)" checks the CSS source.
- "a new search keeps the live region rendered while it is cleared" checks that the region is the same DOM node across two searches.

Red before the CSS change, verbatim:
```
  ● c-rc-tracking › AC-001.7: result cards, generic errors, text-only rendering › AC-001.7: the live region stays in the accessibility tree while empty (visually hidden, never display: none)
    expect(received).not.toMatch(expected)
    Expected pattern: not /display:\s*none|visibility:\s*hidden/
    Received string:      "
      display: none;
    "
```
Mutations on the final code:
- J6 adds `display: none;` back to the visually-hidden rule. Red: `● ... AC-001.7: the live region stays in the accessibility tree while empty (visually hidden, never display: none)` (1 failed, 45 passed).
- J7 wraps the summary `<p>` in `<template lwc:if={summary}>`. Red: `● ... AC-001.7: a new search keeps the live region rendered while it is cleared` (1 failed, 45 passed). This test passed on its first run because the region was never conditional in the DOM, so this mutation is what gives it meaning.

The Sa11y suite (rcTracking.accessibility.test.js, 3 tests) is green after the change. The rendered 375/1366 px look is left to brand-reviewer at re-review; Jest does not apply LWC CSS.

### Finding 4 - sf-security-auditor [Low] SEC-001 (P11) "only caller" not enforced - fixed
New section 5c in scripts/checks/guest-access-check.sh. It runs `grep -rliw` (whole word, any case, as Apex) over the .cls and .trigger files in force-app/main/default/classes and, when that folder exists, force-app/main/default/triggers. Only PublicTrackingSelector.cls, PublicTrackingController.cls and PublicTrackingControllerTest.cls may name `PublicTrackingSelector`. A grep error (exit 2) or a missing classes folder also fails the check.

The mutation is a scratch class, force-app/main/default/classes/ZzSelectorProbe.cls, that calls `publictrackingselector.selectByReferences(...)` in lower case. It was never deployed or committed and was removed afterwards.
- HEAD script with the probe: exit 0, `guest-access-check: passed in cargo-opus-t1`. This proves the gap.
- Fixed script with the probe: exit 1, verbatim:
```
FAIL: Apex source outside the allow-list names the without-sharing PublicTrackingSelector: ZzSelectorProbe.cls
guest-access-check: 1 violation(s) in cargo-opus-t1
```
- Fixed script after removing the probe: exit 0. Every section passed, including `ok:   only PublicTrackingSelector.cls PublicTrackingController.cls PublicTrackingControllerTest.cls name PublicTrackingSelector in the Apex source`, and the run ended with `guest-access-check: passed in cargo-opus-t1`.

### Finding 5 - test-reviewer [Low] split and missing server tests - fixed
- `search_blankValues_returnEmptyWithoutQuery` is split into `search_spaceOnlyValue_...`, `search_emptyValue_...` and `search_nullEntry_returnsEmptyWithoutQuery`. They share the helper `assertEmptyWithoutQuery`, which checks no query, no results and an empty notFound.
- Added `search_nullMode_isRejectedWithoutQuery` and `search_nullValues_returnsEmptyWithoutQuery`. The second covers normalize:108.
- Added `search_trackingValuesSplitOnLineBreaks_returnsThreeResults`, with one entry `A\nB\r\nC`.
- lastLocation moved out of `search_estimatedDelivery_isTheIsoDate` into `search_lastLocation_isEachShipmentsOwn`. The second shipment now has its own location ('Saltillo hub'), so the assertion covers two different values.

Each test red under its mutation (applied, deployed, run, reverted):
- D (empty values kept): `if (trimmed.length() == 0 || spellingByKey.containsKey(key))` became `if (spellingByKey.containsKey(key))`.
```
PublicTrackingControllerTest.search_spaceOnlyValue_returnsEmptyWithoutQuery  Fail     System.AssertException: Assertion Failed: Blank values must not be queried: Expected: 0, Actual: 1
PublicTrackingControllerTest.search_emptyValue_returnsEmptyWithoutQuery      Fail     System.AssertException: Assertion Failed: Blank values must not be queried: Expected: 0, Actual: 1
```
- E (the null-entry skip `if (entry == null) { continue; }` removed):
```
PublicTrackingControllerTest.search_nullEntry_returnsEmptyWithoutQuery  Fail     System.AuraHandledException: We could not complete the search. Please try again.
```
- G (the null-list guard in normalize removed):
```
PublicTrackingControllerTest.search_nullValues_returnsEmptyWithoutQuery  Fail     System.AuraHandledException: We could not complete the search. Please try again.
```
- F (null mode): the direct mutation, dropping `mode == null ||`, is equivalent. `Set.contains(null)` is false, so a null mode is still rejected. A stronger variant was proved red instead: a null mode defaults to the reference search (`if (mode != null && !MODES.contains(mode))` and `Boolean byTrackingNumber = MODE_TRACKING_NUMBER.equals(mode);`). Under mutation C the null-mode test stayed green, which is correct.
```
PublicTrackingControllerTest.search_nullMode_isRejectedWithoutQuery  Fail     System.AssertException: Assertion Failed: Assertion failed: search must throw an AuraHandledException
```
- H (separators limited to commas): `VALUE_SEPARATORS = '[,\\r\\n]'` became `'[,]'`.
```
PublicTrackingControllerTest.search_trackingValuesSplitOnLineBreaks_returnsThreeResults  Fail     System.AssertException: Assertion Failed: One entry "A\nB\r\nC" must be split on LF and CRLF into three tracking numbers: Expected: (RC000101128, RC000101129, RC000101130), Actual: ()
```
  A variant splitting on LF only is equivalent for CRLF, because `trim()` removes the trailing `\r`.
- I (lastLocation hard-coded to 'Queretaro hub'):
```
PublicTrackingControllerTest.search_lastLocation_isEachShipmentsOwn  Fail     System.AssertException: Assertion Failed: Second shipment last location (BR-01): Expected: Saltillo hub, Actual: Queretaro hub
```

### Finding 6 - test-reviewer [Low] values over 50 characters sent to the server - fixed
rcTracking now:
- counts all distinct values against the 10 cap, as the server does;
- sends only the values of 50 characters or fewer, and makes no Apex call when none is left;
- lists the longer values under "Not found", merged with the server's notFound in input order. A server value that matches no typed value is kept and listed after them;
- lists no value under "Not found" when the answer is truncated, the same rule as the server.

New Jest tests in "AC-001.3 client: values longer than 50 characters" (7 tests):
- 51 characters: not sent and listed;
- only long values (600 and 51 characters): no call, both listed, "0 shipments found.";
- exactly 50 characters: sent;
- merge in input order, with the long value first and with it last;
- a truncated answer lists no value as Not found;
- a long value counts toward the cap.

Red before the code, verbatim (excerpt):
```
  ● ... AC-001.3: a 51-character value is not sent and is listed as Not found
    expect(jest.fn()).toHaveBeenCalledWith(...expected)
        "values": Array [
          "RC000000001",
    +     "PO-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX",
  ● ... AC-001.3: only values longer than 50 characters make no Apex call and are all Not found
    Expected number of calls: 0
    Received number of calls: 1
  ● ... AC-001.3: long values merge with the server's Not found in input order (long value first)
  ● ... AC-001.3: long values merge with the server's Not found in input order (long value last)
Tests:       5 failed, 41 passed, 46 total   (the 5th red is finding 3's CSS test)
```
Mutations on the final code (each run, then reverted from a copy):
- J1 sends the long values anyway (`const sendable = values;`): 4 red (51-character, only-long, both merge-order tests).
- J2 sets the bound to 49 (`> MAX_VALUE_LENGTH - 1`): 1 red, "a value of exactly 50 characters is sent to the server".
- J3 lists long values even when truncated (`return !truncated;` became `return true;`): 1 red, "a truncated answer lists no value as Not found ...".
- J4 leaves long values out of the cap count: 1 red, "a long value still counts toward the 10-value cap".
- J5 appends long values after the server's misses instead of in input order: 1 red, "... in input order (long value first)".
- AC-001.3's own M2 (the client shows no Not found list, `this.notFound = [] || mergeNotFound(`) is re-applied because the fix changed that path: 8 red. A first attempt with `[] && ...` was a no-op (`[]` is truthy) and was redone.

Sa11y is green with the merge; its truncated fixture still lists the server's notFound.

### Finding 7 - task-reviewer T2 [Low] unused `titleId` - fixed
Structural proof by grep (`grep -n titleId lwc/rcTracking/*.js *.html`):
```
before: force-app/main/default/lwc/rcTracking/rcTracking.js:94:    titleId: `rc-tracking-card-${index}`
after:  (no match, grep exit 1)
```

### Finding 8 - task-reviewer T3 [Low] brand-check treats an empty or missing row padding as zero - fixed
- Source check (:418-421): ZERO is now `(0+(\.0*)?|\.0+)(px|rem|em|%)?`, which needs at least one digit. A missing key is reported as `<key> missing` instead of `.get(k, '')`.
- Published check (:526): the pattern is now `': *(0+(\.0*)?|\.0+)(px|rem|em|%)? *$'`.

Mutations on the branding set's VerticalRowPaddingDesktop (Build_Your_Own_LWR/content.json, reverted with `git checkout` after each run):
- HEAD script, value `""`: exit 0, `ok:   scopedHeaderAndFooter header band: no padding, ...` (the gap).
- HEAD script, key removed: exit 0 (the gap).
- Fixed script, value `""`: exit 1, verbatim:
```
FAIL: scopedHeaderAndFooter header band: the branding set's row paddings are not zero (VerticalRowPaddingDesktop=''): the platform gray shows in the section padding (an overlay without a background image is not painted)
FAIL: scopedHeaderAndFooter footer band: the branding set's row paddings are not zero (VerticalRowPaddingDesktop=''): the platform gray shows in the section padding (an overlay without a background image is not painted)
brand-check: 2 violation(s) in cargo-opus-t1
```
- Fixed script, key removed: exit 1, `... row paddings are not zero (VerticalRowPaddingDesktop missing) ...` for both bands, `brand-check: 2 violation(s) in cargo-opus-t1`.
- Fixed script, clean source: exit 0, `brand-check: passed in cargo-opus-t1` (44 ok lines, including `the published home page carries zero section paddings (8 hooks)`).

The published-page pattern was probed on sample hook lines (old vs new; lines reported as NOT zero):
```
old: --dxp-s-section-content-spacing-y: 1rem
new: --dxp-s-section-content-spacing-inline-end:
     --dxp-s-section-content-spacing-x: rem
     --dxp-s-section-content-spacing-y: 1rem
```

### Code analyzer
`sf code-analyzer run --rule-selector Recommended --target <the 5 changed Apex/LWC files> --include-fixes` (results in the session scratchpad, not committed): 112 violations, 0 Critical, 0 High, 51 Moderate, 61 Low.
- Moderate:
  - MethodNamingConventions ×38: the project's test naming style, already flagged at HEAD.
  - ApexUnitTestClassShouldHaveAsserts ×11: false positive; the asserts are in the shared helpers `assertRejectedWithoutQuery` and `assertEmptyWithoutQuery`.
  - CyclomaticComplexity ×1: class total 61, highest method 2.
  - ExcessiveParameterList ×1: `setPrivateAndPublicFields`, unchanged from HEAD.
- Low:
  - ApexUnitTestClassShouldHaveRunAs ×33;
  - @salesforce-ux/slds/no-hardcoded-values-slds2 ×27: the brand palette hex values, already at HEAD;
  - AvoidNonRestrictiveQueries ×1: test fixture read-back.
- ESLint (`npx eslint lwc/rcTracking`): clean, after replacing a no-confusing-arrow in mergeNotFound with a block. Prettier is clean on the JS, CSS and Jest files. The Apex test class was already not prettier-formatted at HEAD and was not reformatted.

Governor limits: no new risk. The tests add no SOQL or DML in loops. `privateValuesOf` loops over 2 records in memory.

### Out of scope / noticed
- PublicTrackingControllerTest is now 574 lines, over the skill's 500-line guidance. Splitting it, for example into a guest test class, needs a new file outside this handoff's scope.
- Code-analyzer naming and RunAs notes are project-wide conventions, not addressed here.

### Commands
- `sf org display --target-org cargo-opus-t1 --json`; `sf org list --skip-connection-status --json`
- `sf project deploy start --source-dir <file> --target-org cargo-opus-t1 --json`, once per mutant and once per revert, each as its own command.
- `sf apex run test --tests <Class.method,...> --result-format human --wait 10 --target-org cargo-opus-t1` for the mutation runs.
- `sf apex run test --class-names PublicTrackingControllerTest --result-format human --wait 10 --target-org cargo-opus-t1`
- `sf project retrieve start --metadata LightningComponentBundle:rcTracking --target-metadata-dir .retrieve-check-rcTracking --unzip --target-org cargo-opus-t1 --json`
- `sf project deploy start --source-dir force-app/main/default/classes/PublicTrackingControllerTest.cls --source-dir force-app/main/default/lwc/rcTracking --target-org cargo-opus-t1 --ignore-conflicts`
- `sf community publish --name RutaCargo --target-org cargo-opus-t1 --json`
- `npx jest force-app/main/default/lwc/rcTracking`; `npx eslint force-app/main/default/lwc/rcTracking`; `npx prettier --check ...`
- `scripts/checks/guest-access-check.sh cargo-opus-t1`; `scripts/checks/brand-check.sh cargo-opus-t1`
- `sf code-analyzer run --rule-selector Recommended --target ... --output-file <scratchpad>/code-analyzer-results-20261117-172008.json --include-fixes`
