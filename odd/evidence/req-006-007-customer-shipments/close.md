# Close of req-006-007-customer-shipments - fix round

- Fix sha: 0c90270 (`close fix req-006-007-customer-shipments: ...`)
- Reviewed range: 0ce038b..96a30db (HEAD at start: be29c62, bookkeeping only since)
- Org: cargo-opus-t1 (scratch: instance `*.scratch.my.salesforce.com`, Organization.IsSandbox = true, trial expires 2026-12-18). Never production.
- Mode: no live sign-ups, no shipment requests through the site, no `--probe-standard-selfreg`. All shipment writes happened inside Apex tests (rolled back).

## Skills used

- salesforce-development:platform-apex-test-generate - the new and split test methods (one behavior each, Assert class, factory data).
- salesforce-development:platform-apex-test-run - the per-class runs, the mutation runs and the final green.
- salesforce-development:platform-apex-generate - loaded for the temporary production-code mutations (all reverted; no production class changed in the commit).
- salesforce-development:platform-metadata-deploy - the LOOP runner deploys and the temporary permission set deploys.
- salesforce-development:platform-metadata-retrieve - the retrieve that proved the LWC source-tracking conflicts stale.
- salesforce-development:platform-soql-query - the ObjectPermissions / FieldPermissions comparisons, the publish job status and the history-row count.
- experience-lwc:experience-lwc-generate - the three CSS changes and the Jest run.
- salesforce-code-quality:dx-code-analyzer-run - Code Analyzer before and after.

## Conflict check before `--ignore-conflicts`

The first LOOP deploy reported conflicts on the three LWC bundles. They were retrieved in metadata format to a temporary folder (`sf project retrieve start --metadata LightningComponentBundle:rcMyShipments --metadata LightningComponentBundle:rcRequestShipment --metadata LightningComponentBundle:rcShipmentDetail --target-metadata-dir .retrieve-tmp --unzip`) and compared with `git show HEAD:<file>`. Every file was equal to HEAD except for a missing final newline (`\ No newline at end of file`). That proved the conflicts stale, so the LOOP runner used `--ignore-conflicts` from then on. The temporary folder was deleted.

## Per finding

### F1 [Medium] (test-reviewer, AC-006.1): fixed

There are now 14 one-field tests in ShipmentRequestControllerTest, one per required field. Each leaves its field blank and asserts `Check these fields: <name>` and 0 created. The recipientEmail test already existed. The other 13 are new: pickupAddress (null), pickupCity (''), pickupPostalCode, pickupDate, recipientName, recipientAddress, recipientCity, recipientPostalCode, recipientPhone, serviceType, weightKg, packageDescription and declaredValue.

Mutation (handoff): the required flag was dropped for pickupPostalCode, and also for packageDescription (the second field the finding names), at ShipmentRequestController.cls:154 and :165 (`true` -> `false`). Red, verbatim:

```
ShipmentRequestControllerTest.submitRequest_refusesAndCreatesNothing_whenThePickupPostalCodeIsMissing Fail System.AssertException: Assertion Failed: Assertion failed: submitRequest must refuse this request
ShipmentRequestControllerTest.submitRequest_refusesAndCreatesNothing_whenThePackageDescriptionIsMissing Fail System.AssertException: Assertion Failed: Assertion failed: submitRequest must refuse this request
```

(Run: Tests Ran 44, Pass Rate 91%. The two other reds of that run belong to the F12 mutation below.) The mutation was reverted with `git checkout`, and the final run is green: 44/44.

### F2 [Medium] (test-reviewer, AC-007.3): fixed

`getShipment_returnsTheShipmentsValuesInMexicoCityTime` now asserts all 19 values of Ana's shipment, in the DETAIL_FIELDS order. The new `getShipment_returnsMartasOwnShipmentsValues` is a second input: Marta's own shipment, read by Marta. The setup gives it other values: pickup Calle 60 No. 500, Centro / Cancun / 77500 / 2026-12-02, destination postal code 97000, Lab samples, 4.25 kg, 2,500.00 declared, price 230.00, estimate 2026-12-09, last update 2026-11-17 20:45 GMT -> 14:45 Mexico City, Merida hub.

Mutation (handoff): `detail.pickupCity = shipment.Destination_City__c` (MyShipmentsController.cls:227). Red, verbatim:

```
MyShipmentsControllerTest.getShipment_returnsMartasOwnShipmentsValues Fail System.AssertException: Assertion Failed: The detail must carry all 19 values of Marta's shipment: Expected: RC000101127|2026-11-16 09:00|In transit|Standard|230.00|2026-12-09|2026-11-17 14:45|Merida hub|Calle 60 No. 500, Centro|Cancun|77500|2026-12-02|Carlos Méndez|Merida|97000|4.25|Lab samples|2500.00|ORD-7, Actual: RC000101127|2026-11-16 09:00|In transit|Standard|230.00|2026-12-09|2026-11-17 14:45|Merida hub|Calle 60 No. 500, Centro|Merida|77500|2026-12-02|Carlos Méndez|Merida|97000|4.25|Lab samples|2500.00|ORD-7
MyShipmentsControllerTest.getShipment_returnsTheShipmentsValuesInMexicoCityTime Fail System.AssertException: Assertion Failed: The detail must carry all 19 values of Ana's shipment: Expected: RC000101126|2026-11-15 12:30|In transit|Standard|165.00|2026-12-08|2026-11-15 19:05|Puebla hub|Av. Reforma 100, Col. Juarez|Ciudad de Mexico|06600|2026-12-01|Diana O'Neil|Puebla|44160|1.50|Test package|1000.00|ABC-3, Actual: RC000101126|2026-11-15 12:30|In transit|Standard|165.00|2026-12-08|2026-11-15 19:05|Puebla hub|Av. Reforma 100, Col. Juarez|Puebla|06600|2026-12-01|Diana O'Neil|Puebla|44160|1.50|Test ...
```

Reverted. The final run is green: 27/27.

### F3 [Medium] (test-reviewer, BR-07, P2): fixed

The new `listShipments_refusesASignedInUserWithoutACustomerAccount` and `getShipment_refusesASignedInUserWithoutACustomerAccount` run as `new User(Id = UserInfo.getUserId())`, which has no User.AccountId, and assert NOT_AVAILABLE_MESSAGE. ShipmentRequestController already had this test (`submitRequest_refusesAnInternalUserWithoutACustomerAccount`, SRCT:494 at HEAD), so nothing was added there.

Mutation (handoff): the no-account refusal was removed (MyShipmentsController.cls:153-155). Red, verbatim:

```
MyShipmentsControllerTest.listShipments_refusesASignedInUserWithoutACustomerAccount Fail System.AssertException: Assertion Failed: Assertion failed: listShipments must refuse this call
MyShipmentsControllerTest.getShipment_refusesASignedInUserWithoutACustomerAccount Fail System.AssertException: Assertion Failed: A user without a customer account must get the generic refusal: Expected: This service is available only to signed-in customers., Actual: Shipment not found.
```

Reverted. The final run is green.

### F4 [batched T1, evidence] and F5 [batched T1, test quality]: fixed (one mutation)

The mutation ran on the committed CustomerShipmentAccessTest (current layout; the only change in this round is the F6 comments). It over-grants: `<viewAllRecords>true</viewAllRecords>` on Shipment__c in RutaCargo_Customer.permissionset-meta.xml (viewAllFields was not touched), deployed on its own. Both negative tests turned red on their assertion, verbatim:

```
CustomerShipmentAccessTest.anaReadsNoneOfMartasShipments Fail System.AssertException: Assertion Failed: Ana must read none of Marta's shipments: Expected: 0, Actual: 251
CustomerShipmentAccessTest.martaReadsNoneOfAnasShipments Fail System.AssertException: Assertion Failed: Marta must read none of Ana's shipments: Expected: 0, Actual: 251
```

(Run: Tests Ran 11, Pass Rate 82%.)

To revert, the file was restored from HEAD with `git checkout`. Its Shipment__c entry states every flag explicitly, `viewAllRecords` false included. The file was then deployed again on its own. The org's ObjectPermissions and FieldPermissions for `Parent.Name = 'RutaCargo_Customer'` were then compared row by row, both with the file and with a snapshot taken before the mutation:

```
ObjectPermissions org==file: True | org==before: True
  OP Shipment__c org (Read True, Create True, Edit False, Delete False, ViewAll False, ModifyAll False, ViewAllFields False) file (same) OK
FieldPermissions org==file: True | org==before: True | rows 17
  17 rows OK (Customer_Reference__c, Declared_Value__c, Destination_City__c, Destination_Postal_Code__c, Origin_City__c,
  Package_Description__c, Pickup_Address__c, Pickup_Date__c, Pickup_Postal_Code__c, Recipient_Name__c, Service_Type__c,
  Weight_Kg__c read+edit; Estimated_Delivery__c, Last_Location__c, Last_Update__c, Price__c, Status__c read only)
file all-false entries (no org row expected): Delivery_Instructions__c, Recipient_Address__c, Recipient_Email__c, Recipient_Phone__c; present in org: []
```

No row was left behind. The committed permission set equals HEAD (`git diff --quiet HEAD -- force-app/main/default/permissionsets` returned 0). `scripts/checks/customer-access-check.sh cargo-opus-t1` passed afterwards (exit 0, below).

### F6 [Low CODE-001 + test-reviewer]: fixed (structural)

Each `WITH SYSTEM_MODE` the finding names now has a `// SECURITY-JUSTIFICATION: <why, scope, compensating control> (pending owner approval, 2026-11-18)` above it. The two new expected-row queries in MyShipmentsControllerTest have one too. The proof is a grep for `WITH SYSTEM_MODE` with no SECURITY-JUSTIFICATION in the 8 lines above it.

Before (HEAD):
```
CSAT: unjustified WITH SYSTEM_MODE at lines [288, 294, 327]
SRCT: unjustified WITH SYSTEM_MODE at lines [57]
MSCT: unjustified WITH SYSTEM_MODE at lines [88, 225]
```
After:
```
CSAT: unjustified WITH SYSTEM_MODE at lines []
SRCT: unjustified WITH SYSTEM_MODE at lines []
MSCT: unjustified WITH SYSTEM_MODE at lines []
```

The new ShipmentTriggerHandlerTest methods add no SYSTEM_MODE query: they rely on `refusalsAs`, which already asserts that the insert is refused.

### F7 [batched T2, evidence]: recorded (no code change)

The deviation is recorded here. The reds before the code for T2 (T2.md:48-77) were compile errors and a QueryException, not assertion failures. The assertion reds for the T2 behaviors are in this round's mutations (F1, F2, F3, F9, F11, F12, F13) and in T2.md's mutation section.

### F8 [batched T2, test quality]: fixed

`today_isTheMexicoCityDate_withoutTheSeam` used to compute its expected value with the same `Datetime.format(..., 'America/Mexico_City')` expression as the rules. It now computes it independently: `now.addSeconds(TimeZone.getTimeZone('America/Mexico_City').getOffset(now) / 1000).dateGmt()`.

Mutation: `ShipmentRequestRules.today()` formatted in another zone. Pacific/Kiritimati (UTC+14) was tried first, but at 02:34 Mexico City time it was on the same date, so the mutation would have been equivalent at that moment. It was replaced with Pacific/Honolulu, which was then on 2026-11-17. Red, verbatim:

```
ShipmentRequestRulesTest.today_isTheMexicoCityDate_withoutTheSeam Fail System.AssertException: Assertion Failed: Today must be the Mexico City date (GMT + the zone offset): Expected: 2026-11-18 00:00:00, Actual: 2026-11-17 00:00:00
```

Reverted. The final run is green: 36/36. Note: this mutation turns red only during the hours when the two zones are on different dates.

### F9 [Low]: fixed

New `listShipments_filtersByTheRequestedStatus` (status "Requested" -> only Ana's Requested shipment). Mutation: the status bind hard-coded to `'In transit'`. Red, verbatim:

```
MyShipmentsControllerTest.listShipments_filtersByTheRequestedStatus Fail System.AssertException: Assertion Failed: Only Ana's Requested shipment must return: Expected: (RC000101124), Actual: (RC000101125, RC000101126)
```

Reverted. Green.

### F10 [Low]: fixed

The combined methods were split:
- SRCT `submitRequest_acceptsARequestWithoutTheOptionalFields` -> `..._acceptsARequestWithoutTheReference_whenItIsNull` and `..._acceptsARequestWithoutTheInstructions_whenTheyAreBlank`.
- SRCT `..._whenThePickupAddressAndCityAreMissing` -> `..._whenThePickupAddressIsMissing` (null) and `..._whenThePickupCityIsMissing` ('').
- SRRT `weight_isRejected_whenZeroOrNegative` -> `weight_isRejected_whenZero` and `weight_isRejected_whenNegative`.

All are green.

### F11 [Low]: fixed

New ShipmentTriggerHandlerTest methods: `customerInsert_isRefusedWithAFieldError_whenTheServiceTypeIsMissing` (null; a value outside the list would be refused first by the restricted picklist) and `..._whenTheDeclaredValueIsNegative` (-1). Both assert exactly one generic field error on the field.

Mutation: the guard's service-type and declared-value checks (ShipmentTriggerHandler.cls:234-236, :242-244) were removed. Red, verbatim:

```
ShipmentTriggerHandlerTest.customerInsert_isRefusedWithAFieldError_whenTheDeclaredValueIsNegative Fail System.AssertException: Assertion Failed: A direct create with a negative declared value must be refused on Declared_Value__c only: Expected: Declared_Value__c=Check this field., Actual: =ShipmentTrigger: execution of BeforeInsert
ShipmentTriggerHandlerTest.customerInsert_isRefusedWithAFieldError_whenTheServiceTypeIsMissing Fail System.AssertException: Assertion Failed: A direct create without a service type must be refused on Service_Type__c only: Expected: Service_Type__c=Check this field., Actual: =ShipmentTrigger: execution of BeforeInsert
```

Reverted. The final run is green: 39/39.

### F12 [Low]: fixed (no seam needed)

- DmlException path (SAVE_FAILED_MESSAGE): `submitRequest_givesTheGenericSaveError_whenThePlatformRefusesTheInsert` uses the recipient email `.laura@example.com`. The AC-006.1 rule accepts it, but the platform's Email field refuses it. The candidate was found with a temporary probe method, removed before the commit. Probe output, verbatim: `.laura@example.com rule=true platform=false`, `laura@-example.com rule=true platform=false`, `laura@example-.com rule=true platform=false`. The first candidate, `laura..gomez@example.com`, was accepted by the platform, so its test failed with `Assertion failed: submitRequest must refuse this request` and was replaced.
- SecurityException path (NOT_AVAILABLE_MESSAGE): `submitRequest_givesTheGenericRefusal_whenTheCustomerCannotCreateShipments` removes Ana's RutaCargo_Customer assignment inside the test (TestDataFactory.removePermissionSetAssignment, rolled back).
- QueryException path (the read-back after a successful insert): not covered. It needs a user who has Create but no Read on Name, Price__c and Estimated_Delivery__c. One permission set grants both, so reaching that state needs a production seam. Not added.

Mutation: the two catch messages were swapped (DmlException -> NOT_AVAILABLE, SecurityException -> SAVE_FAILED). Red, verbatim:

```
ShipmentRequestControllerTest.submitRequest_givesTheGenericRefusal_whenTheCustomerCannotCreateShipments Fail System.AssertException: Assertion Failed: A customer without Create must get the generic refusal: Expected: This service is available only to signed-in customers., Actual: Your request could not be saved. Check the fields and try again.
ShipmentRequestControllerTest.submitRequest_givesTheGenericSaveError_whenThePlatformRefusesTheInsert Fail System.AssertException: Assertion Failed: A refused insert must get the generic save error: Expected: Your request could not be saved. Check the fields and try again., Actual: This service is available only to signed-in customers.
```

Reverted. Green.

### F13 [Low]: fixed

`listShipments_returnsAtMost200Shipments` still checks the count. The new `listShipments_returnsAnasNewest200_andNoneOfMartas` inserts 251 more shipments for Ana and 251 for Marta, and gives Marta's recipient the name `MARTA_BULK`. It asserts that no row has that recipient, and that the tracking numbers equal Ana's 200 newest in the list order (an admin-side query with a SECURITY-JUSTIFICATION). Marta's rows are identified by recipient, not by tracking number, because inside a test method the Name auto-number restarts below the @TestSetup rows. In the set-B red below, `RC000101124` appears twice in one list.

Reds, verbatim:
- Order assertion. Mutation: `ORDER BY CreatedDate ASC, Name ASC`.
  ```
  MyShipmentsControllerTest.listShipments_returnsAnasNewest200_andNoneOfMartas Fail System.AssertException: Assertion Failed: Ana must get exactly her 200 newest shipments, newest first: Expected: (RC000101374, RC000101373, RC000101372, RC000101371, RC000101370, RC000101369, RC000101368, RC000101367, RC000101366, RC000101365, ...), Actual: (RC000101124, RC000101125, RC000101126, RC000101124, RC000101125, RC000101126, RC000101127, RC000101128, RC000101129, RC000101130, ...)
  ```
- "None of Marta's" assertion, placed first in the method. Mutation: View All on Shipment__c (the F5 mutation) plus `own.contains(shipment.Id) || true` in listShipments.
  ```
  MyShipmentsControllerTest.listShipments_returnsAnasNewest200_andNoneOfMartas Fail System.AssertException: Assertion Failed: None of Marta's shipments may be in Ana's list
  ```

Both reverted (permission set as in F4/F5). Green.

### F14 [Low] (brand-reviewer): fixed

rcRequestShipment.css `.rc-request__price` and `.rc-request__code-value`: `font-weight: 900` -> `700`.

Before (HEAD) -> after, verbatim from `git diff`:

```
 .rc-request__price {
   font-size: var(--slds-g-font-scale-4, 1.5rem);
-  font-weight: 900;
+  font-weight: 700;
 .rc-request__code-value {
...
-  font-weight: 900;
+  font-weight: 700;
```

### F15 [Low] (brand-reviewer): fixed

`.rc-shipments__fields dd` (rcMyShipments.css:196-199) and `.rc-detail__fields dd` (rcShipmentDetail.css:116-119): `font-weight: 700` -> `400`, as decided, like rcTracking and rcDeliveryDetails. The card's tracking-number link (`.rc-shipments__card-link`, in the card title, not a `dd`) stays 700.

After the CSS deploy and `sf community publish --name RutaCargo` (job 08PEk00000qTzzrMAC, BackgroundOperation Status Complete), `scripts/checks/brand-check.sh cargo-opus-t1` passed (exit 0, `brand-check: passed in cargo-opus-t1`, 51 ok lines). brand-check does not check font weights, so the proof for F14 and F15 is the diff above. Jest: 6 suites, 114 tests passed.

### F16 (access-auditor / G9): fixed

scripts/setup/DEPLOY-ORDER.md changes:
- New step 5c: run `scripts/checks/reschedule-history-check.sh <alias>` after the seed and the customer site users (README steps 3 and 3b, with `.seed-output/access-codes.csv`) and before any RunLocalTests run. It explains why the SeeAllData test needs that row and the message it fails with. It gives a count query that confirms an Abarrotes Acme row exists: the script takes the first qualifying seeded shipment of either account, so the row can land on Globex Farma, in which case you run it again.
- New step 5d: run the local tests.
- A note in step 2: in a brand-new org, the tests that need the seed or the history row cannot pass at step 2. In a scratch org or sandbox only, deploy step 2 with `--test-level NoTestRun` and run the tests at 5d.

The 5c query in cargo-opus-t1 returns 4 rows. This note changes the documented procedure for a new org; the main session should confirm it.

## Final green (after all reverts)

| Class | Result |
|---|---|
| ShipmentRequestControllerTest | Passed, 44/44 (100%) |
| MyShipmentsControllerTest | Passed, 27/27 (100%) |
| ShipmentRequestRulesTest | Passed, 36/36 (100%) |
| ShipmentTriggerHandlerTest | Passed, 39/39 (100%) |
| CustomerShipmentAccessTest | Passed, 11/11 (100%) |

- Jest (rcRequestShipment, rcMyShipments, rcShipmentDetail): 6 suites, 114 tests passed.
- `scripts/checks/customer-access-check.sh cargo-opus-t1`: exit 0, `customer-access-check: passed in cargo-opus-t1`. Live: each seeded customer reads their own shipment and not the other customer's.
- `scripts/checks/brand-check.sh cargo-opus-t1`: exit 0.
- The production classes (ShipmentRequestController, MyShipmentsController, ShipmentTriggerHandler, ShipmentRequestRules) and the permission set equal HEAD, both in the commit and in the org (redeployed after the last revert).

## Code Analyzer (Recommended; the 5 test classes and 3 CSS files)

- After: Sev1 0, Sev2 1, Sev3 155, Sev4 243.
- HEAD baseline (same files): Sev1 0, Sev2 1, Sev3 130, Sev4 219.
- The only Sev2 is the accepted, pre-existing `ApexUnitTestShouldNotUseSeeAllDataTrue` (CustomerShipmentAccessTest:252, the history test; justification in the class).
- The first scan reported 13 `ApexUnitTestClassShouldHaveAsserts` on the new F1 methods (the asserts were in a helper). They were fixed by inlining the two asserts in each method; 0 remain.
- The deltas are the project's existing test conventions on the new methods: MethodNamingConventions +23 (underscored names), ApexUnitTestClassShouldHaveRunAs +24 (runAs inside the helpers), and class-level CyclomaticComplexity +2.
- Left as they were: OperationWithLimitsInLoop (CSAT field-query helper, a fixed list of field names), ExcessiveParameterList (the MSCT setup helper), FieldDeclarationsShouldBeAtStart and NcssCount (STHT). All pre-existing.

## Governor limits

The F13 test inserts 502 shipments in the test method (the trigger and code issue run in 200-row batches) and reads at most 253 rows with the admin-side queries. Its run passed with no limit warning. No SOQL or DML inside loops was added.

## Noticed, out of scope

1. The AC-006.1 email rule (ShipmentRequestRules.EMAIL_FORMAT) accepts addresses that the platform's Email field refuses (`.laura@example.com`, `laura@-example.com`, `laura@example-.com`). A customer who types one gets the generic "could not be saved" message instead of `Check these fields: recipientEmail`. Fixing it means changing ShipmentRequestRules, which is outside this scope.
2. ShipmentRequestControllerTest is now about 715 lines, over the skill's 500-line guideline. Splitting it means a new class, which is outside this scope.
3. Step 2 of DEPLOY-ORDER.md uses RunLocalTests even in a brand-new org, where the tests that use the seeded customer users fail until the seed exists. The note above documents this; the procedure itself is the main session's decision.

## Commands

```
sf org display --target-org cargo-opus-t1 --json
sf data query --target-org cargo-opus-t1 --query "SELECT IsSandbox, OrganizationType, TrialExpirationDate FROM Organization" --json
sf project deploy start --source-dir force-app/main/default/classes --source-dir force-app/main/default/lwc/rcRequestShipment --source-dir force-app/main/default/lwc/rcMyShipments --source-dir force-app/main/default/lwc/rcShipmentDetail --target-org cargo-opus-t1 [--ignore-conflicts after the retrieve proof]
sf project retrieve start --metadata LightningComponentBundle:rcMyShipments --metadata LightningComponentBundle:rcRequestShipment --metadata LightningComponentBundle:rcShipmentDetail --target-metadata-dir .retrieve-tmp --unzip --target-org cargo-opus-t1 --json
sf project deploy start --source-dir force-app/main/default/permissionsets/RutaCargo_Customer.permissionset-meta.xml --target-org cargo-opus-t1 --ignore-conflicts   (mutation, then HEAD)
sf apex run test --class-names <Class> --synchronous --result-format human --target-org cargo-opus-t1   (the five classes)
sf apex run test --tests MyShipmentsControllerTest.listShipments_returnsAnasNewest200_andNoneOfMartas --synchronous --result-format human --target-org cargo-opus-t1
sf data query --target-org cargo-opus-t1 --json --query "SELECT SobjectType, PermissionsRead, PermissionsCreate, PermissionsEdit, PermissionsDelete, PermissionsViewAllRecords, PermissionsModifyAllRecords, PermissionsViewAllFields FROM ObjectPermissions WHERE Parent.Name = 'RutaCargo_Customer' ORDER BY SobjectType"
sf data query --target-org cargo-opus-t1 --json --query "SELECT SobjectType, Field, PermissionsRead, PermissionsEdit FROM FieldPermissions WHERE Parent.Name = 'RutaCargo_Customer' ORDER BY Field"
npx jest force-app/main/default/lwc/rcRequestShipment force-app/main/default/lwc/rcMyShipments force-app/main/default/lwc/rcShipmentDetail
sf community publish --name RutaCargo --target-org cargo-opus-t1
sf data query --target-org cargo-opus-t1 --json --query "SELECT Status FROM BackgroundOperation WHERE Id = '08PEk00000qTzzrMAC'"
scripts/checks/customer-access-check.sh cargo-opus-t1
scripts/checks/brand-check.sh cargo-opus-t1
sf data query --target-org cargo-opus-t1 --query "SELECT COUNT() FROM Shipment__History WHERE Field = 'Delivery_Instructions__c' AND Parent.Account__r.Name = 'Abarrotes Acme'"
sf code-analyzer run --rule-selector Recommended --target <the 5 test classes and 3 CSS files> --output-file <scratchpad>/code-analyzer-results-20261118-fix2.json --include-fixes
```
