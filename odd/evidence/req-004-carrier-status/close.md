# Close of req-004-carrier-status - fix evidence

## Fix - ae77cb2

- Reviewed range: 642bc1b..727f777
- Fix commit: ae77cb2 (`close fix req-004-carrier-status: ...`)
- Org: cargo-opus-t1 (scratch, Org Id 00DEk00000qop2zMAA, `isScratch: true`,
  `Organization.IsSandbox = true`, Developer Edition). Never production.
- Files: scripts/entregaya/simulate-status.sh, scripts/entregaya/attack-check.sh,
  force-app/main/default/classes/EntregaYaStatusResourceTest.cls, README.md
  (simulate-status usage lines only).
- Skills used:
  - salesforce-development:platform-apex-test-generate - the new resource-level
    Delivered test (two inputs, Assert with messages, exact expected values).
  - salesforce-development:platform-apex-test-run - LOOP runs and the mutation runs.
  - salesforce-development:platform-metadata-deploy - test class deploys, mutation
    deploys of EntregaYaStatusResource and its restore.
  - salesforce-development:platform-soql-query - checking that the CLI user can read
    the shipment fields the new script checks, and the Organization.IsSandbox flag.
  - salesforce-code-quality:dx-code-analyzer-run - scan of the changed Apex file.

### Finding 1 - test-reviewer [Medium] simulate-status.sh exits 0 on any 2xx: FIXED

Before (727f777, line 101): `[[ "$status" =~ ^2[0-9][0-9]$ ]] || exit 1`.

Change: a new required second argument `<updated | ignored>`. The script reads the
shipment (`Id, Status__c, Last_Location__c, Last_Update__c, Delivered_At__c,
Proof_Id__c`) with `sf data query` before and after the POST, and `check_outcome`
exits 1 on any difference:
- the HTTP code must be 200 and the body's `result` the expected one;
- `updated`: the shipment must have changed (Status__c, Last_Location__c and
  Last_Update__c not all as before) and hold the posted status, location and the
  posted timestamp as an instant (both sides converted to epoch seconds, so
  `2026-11-20T10:00:00-06:00` equals Salesforce's `2026-11-20T16:00:00.000+0000`);
  on "Delivered", Delivered_At__c is that instant and Proof_Id__c the posted proofId;
  otherwise Delivered_At__c and Proof_Id__c are as before (AC-004.2);
- `ignored`: all five fields exactly as before.
Also: the first argument is now an org alias only (the before/after reads need
`sf data query`; the URL form could not be verified), the tracking number must
match `^RC[0-9]{9}$` before it goes into the SOQL literal, exit 4 = shipment not
readable or not exactly one. Sourcing the script defines the functions without
running main, so the comparison can be dry-run.

The live run needs the consumer secret, which the agents cannot read (owner items
B12/B13), so the proof is `bash -n`, the usage text and dry runs.

`bash -n`:
```
bash -n simulate-status.sh: ok
```

Dry run 1 - `check_outcome` called directly with fake answers and rows
(scratchpad harness `dry-run-simulate.sh`: `source simulate-status.sh`, then
`check_outcome <expected> <http> <body> <before> <after> <status> <location> <timestamp> <proofId>`):
```
=> updated expected, 200 updated, shipment moved                  exit 0 (want 0) OK
simulate-status: FAIL: result ignored, expected updated
simulate-status: FAIL: the shipment did not change: {"status":"In transit","location":"Celaya, GTO","lastUpdate":1794907599,"deliveredAt":null,"proofId":null}
simulate-status: FAIL: Status__c is In transit, expected Out for delivery
simulate-status: FAIL: Last_Location__c is Celaya, GTO, expected Monterrey, NL
simulate-status: FAIL: Last_Update__c is 2026-11-17T09:26:39.000+0000, expected the instant 2026-11-20T10:00:00-06:00
=> updated expected, 200 ignored (first POST ignored)             exit 1 (want 1) OK
simulate-status: FAIL: the shipment did not change: {"status":"In transit","location":"Celaya, GTO","lastUpdate":1794907599,"deliveredAt":null,"proofId":null}
simulate-status: FAIL: Status__c is In transit, expected Out for delivery
simulate-status: FAIL: Last_Location__c is Celaya, GTO, expected Monterrey, NL
simulate-status: FAIL: Last_Update__c is 2026-11-17T09:26:39.000+0000, expected the instant 2026-11-20T10:00:00-06:00
=> updated expected, 200 updated, shipment unchanged              exit 1 (want 1) OK
simulate-status: FAIL: Last_Update__c is 2026-11-20T10:00:00.000+0000, expected the instant 2026-11-20T10:00:00-06:00
=> updated expected, Last_Update__c not the posted instant        exit 1 (want 1) OK
simulate-status: FAIL: HTTP 401, expected 200
simulate-status: FAIL: result none, expected updated
...
=> updated expected, HTTP 401 empty body                          exit 1 (want 1) OK
=> ignored expected, 200 ignored, shipment unchanged              exit 0 (want 0) OK
simulate-status: FAIL: result updated, expected ignored
=> ignored expected, 200 updated                                  exit 1 (want 1) OK
simulate-status: FAIL: the shipment changed: before {"status":"In transit","location":"Celaya, GTO","lastUpdate":1794907599,"deliveredAt":null,"proofId":null}, after {"status":"Out for delivery","location":"Monterrey, NL","lastUpdate":1795190400,"deliveredAt":null,"proofId":null}
=> ignored expected, 200 ignored, shipment changed                exit 1 (want 1) OK
=> updated Delivered PRF-88231, saved                             exit 0 (want 0) OK
simulate-status: FAIL: Proof_Id__c is PRF-88231, expected PRF-90417
=> updated Delivered PRF-90417 expected, PRF-88231 saved          exit 1 (want 1) OK
simulate-status: FAIL: the outcome could not be compared: jq: error (at <unknown>): not an ISO-8601 instant: yesterday
=> unparsable posted timestamp                                    exit 1 (want 1) OK
```

Dry run 2 - `main` end to end with stub `sf` and `curl` shell functions (no org, no
network; the credential variables hold the word `placeholder`; the stub `sf data
query` answers the "before" row first and the case's "after" row second, the stub
`curl` answers a token and then the case's POST body with HTTP 200):
```
   HTTP 200
   simulate-status: passed: 200 updated, and the shipment matches
=> main: updated expected, answer updated, moved              exit 0 (want 0) OK
   HTTP 200
   simulate-status: FAIL: result ignored, expected updated
   simulate-status: FAIL: the shipment did not change: {"status":"In transit","location":"Celaya, GTO","lastUpdate":1794907599,"deliveredAt":null,"proofId":null}
   simulate-status: FAIL: Status__c is In transit, expected Out for delivery
   simulate-status: FAIL: Last_Location__c is Celaya, GTO, expected Monterrey, NL
   simulate-status: FAIL: Last_Update__c is 2026-11-17T09:26:39.000+0000, expected the instant 2026-11-20T10:00:00-06:00
=> main: updated expected, answer ignored                     exit 1 (want 1) OK
   HTTP 200
   simulate-status: FAIL: the shipment did not change: {"status":"In transit","location":"Celaya, GTO","lastUpdate":1794907599,"deliveredAt":null,"proofId":null}
   simulate-status: FAIL: Status__c is In transit, expected Out for delivery
   simulate-status: FAIL: Last_Location__c is Celaya, GTO, expected Monterrey, NL
   simulate-status: FAIL: Last_Update__c is 2026-11-17T09:26:39.000+0000, expected the instant 2026-11-20T10:00:00-06:00
=> main: updated expected, answer updated, unchanged          exit 1 (want 1) OK
   HTTP 200
   simulate-status: passed: 200 ignored, and the shipment matches
=> main: ignored expected, answer ignored, unchanged          exit 0 (want 0) OK
=> main: bad expected-result argument                         exit 2 (want 2) OK
```

The CLI user can read every field the check reads in cargo-opus-t1 (status 0):
`SELECT Id, Name, Status__c, Last_Location__c, Last_Update__c, Delivered_At__c,
Proof_Id__c, SystemModstamp FROM Shipment__c WHERE Status__c = 'In transit' ORDER
BY Name LIMIT 2` returned RC000001002 and RC000001008 with all fields.

### Finding 2 - test-reviewer [Low] no resource-level Delivered POST with a proofId: FIXED

New test `EntregaYaStatusResourceTest.post_answersUpdatedAndSavesDeliveredAtAndProofId_forTwoDeliveries`
(AC-004.2): two POSTs as the integration user, "Delivered" with PRF-88231 at
2026-11-20T15:30:00-06:00 and PRF-90417 at 2026-11-21T09:05:00-06:00; asserts both
answer `200|application/json|{result=updated}` and each row's Delivered_At__c /
Last_Update__c instant and Proof_Id__c.

First run: green (the mapping at EntregaYaStatusResource.cls:135 already exists),
so the mutations below are what prove the test.

Mutation A (handoff): `request.proofId = null;` in the resource, deployed - red:
```
EntregaYaStatusResourceTest.post_answersUpdatedAndSavesDeliveredAtAndProofId_forTwoDeliveries  Fail     System.AssertException: Assertion Failed: Both deliveries must answer 200 updated: Expected: (200|application/json|{result=updated}, 200|application/json|{result=updated}), Actual: (400|application/json|{error={code=PROOF_ID_REQUIRED, message=A proof id is required when the status is Delivered.}}, 400|application/json|{error={code=PROOF_ID_REQUIRED, message=A proof id is required when the status is Delivered.}})
    Class.EntregaYaStatusResourceTest.post_answersUpdatedAndSavesDeliveredAtAndProofId_forTwoDeliveries: line 263, column 1
```
Mutation A is caught by the service's PROOF_ID_REQUIRED check, not by the saved
value, so a stronger variant was added.

Mutation B (stronger, valid but wrong value): `request.proofId = 'PRF-88231';` in
the resource, deployed - red on the saved Proof_Id__c of the second input:
```
EntregaYaStatusResourceTest.post_answersUpdatedAndSavesDeliveredAtAndProofId_forTwoDeliveries  Fail     System.AssertException: Assertion Failed: The second delivery must save Delivered_At__c and Proof_Id__c: Expected: RC000101122|Delivered|Guadalajara, JAL|1795273500000|1795273500000|PRF-90417, Actual: RC000101122|Delivered|Guadalajara, JAL|1795273500000|1795273500000|PRF-88231
    Class.EntregaYaStatusResourceTest.post_answersUpdatedAndSavesDeliveredAtAndProofId_forTwoDeliveries: line 267, column 1
```

Reverted with `git checkout -- force-app/main/default/classes/EntregaYaStatusResource.cls`
(tree clean for that file), the original resource redeployed (Succeeded), and the
whole class green again:
```
EntregaYaStatusResourceTest.post_answersUpdatedAndSavesDeliveredAtAndProofId_forTwoDeliveries               Pass              135
Outcome              Passed
Tests Ran            25
Pass Rate            100%
Fail Rate            0%
```

### Finding 3 - security-reviewer [Low, X14] inline secrets in the usage text: FIXED

grep for the inline form, before (727f777):
```
15:#   ENTREGAYA_CLIENT_ID=... ENTREGAYA_CLIENT_SECRET=... \
29:    echo "Usage: ENTREGAYA_CLIENT_ID=... ENTREGAYA_CLIENT_SECRET=... $0 <org-alias | https://<my-domain>> <trackingNumber> <status> <location> <timestamp> [proofId]" >&2
```
After (`grep -rn 'ENTREGAYA_CLIENT_ID=\.\.\.\|ENTREGAYA_CLIENT_SECRET=\.\.\.' scripts/entregaya/simulate-status.sh README.md`): no match (exit 1).

Usage text now printed by the script:
```
Usage: scripts/entregaya/simulate-status.sh <org-alias> <updated | ignored> <trackingNumber> <status> <location> <timestamp> [proofId]
Set the key and the secret first, without putting them on a command line:
  read -rs ENTREGAYA_CLIENT_ID && export ENTREGAYA_CLIENT_ID
  read -rs ENTREGAYA_CLIENT_SECRET && export ENTREGAYA_CLIENT_SECRET
and run 'unset ENTREGAYA_CLIENT_ID ENTREGAYA_CLIENT_SECRET' when done.
```
The header comment (lines 26-34) shows the same `read -rs` / `unset` form, and the
README block now runs the script twice, with `updated` then `ignored`.

### Finding 4 - security-reviewer [Low] attack-check.sh has no sandbox check: FIXED

attack-check.sh now queries `SELECT IsSandbox FROM Organization` right after
`query()` is defined and before any host lookup or request, and exits 4 (`refused:
<alias> is not a sandbox or scratch org`) unless it is `true`, as
entregaya-integration.sh:50 does. `bash -n`: ok.

Refusal proof with PATH shims (a stub `sf` answering `IsSandbox: false`, a stub
`curl` that only logs its calls):
```
ERROR: refused: prod-like-stub is not a sandbox or scratch org
exit 4
calls:
sf data query --target-org prod-like-stub --json --query SELECT IsSandbox FROM Organization
```
No curl call was made.

Still green in cargo-opus-t1 (exit 0):
```
attack-check: target RC000001002 (In transit), timestamp 2026-11-17T15:00:08-06:00
ok:   POST https://data-energy-2854-dev-ed.scratch.my.salesforce.com/services/apexrest/entregaya/v1/status without a token is refused with 401
ok:   POST https://data-energy-2854-dev-ed.scratch.my.site.com/rutacargo/services/apexrest/entregaya/v1/status without a token is refused with 501 by the LWR site runtime (a resource that does not exist answers the same 501: not routed to Apex)
ok:   POST https://data-energy-2854-dev-ed.scratch.my.site.com/services/apexrest/entregaya/v1/status without a token is refused with 403
ok:   POST https://data-energy-2854-dev-ed.scratch.my.site.com/rutacargovforcesite/services/apexrest/entregaya/v1/status without a token is refused with 403
ok:   shipment RC000001002 did not change (status, location, last update, SystemModstamp)
attack-check: passed in cargo-opus-t1
```

### Not in this round (recorded by the handoff)

- test-reviewer [High] AC-004.6 live POST: owner item B12/B13 (the agents cannot
  read the consumer secret). The owner's run is now:
  `simulate-status.sh <alias> updated ...` then `simulate-status.sh <alias> ignored ...`.
- test-reviewer [Low] 251-row tests build data in the method: left as is.

### Mutations of the acceptance lines

- AC-004.2 (stop saving Proof_Id__c on Delivered, at the resource level): A red
  (400 PROOF_ID_REQUIRED), B red (PRF-88231 saved instead of PRF-90417); reverted.
- AC-004.6 (disable client credentials in the ECA): not re-applied. This fix did
  not change the ECA, its policies or the setup script, and the live POST stays
  an owner item.
- AC-004.8: attack-check.sh changed (sandbox guard only); re-run green above.

### Code analyzer

`sf code-analyzer run --rule-selector Recommended --target force-app/main/default/classes/EntregaYaStatusResourceTest.cls`:
59 violations, 0 Critical, 0 High, 36 Moderate, 23 Low (MethodNamingConventions 24,
ApexUnitTestClassShouldHaveRunAs 23, ApexUnitTestClassShouldHaveAsserts 10,
CyclomaticComplexity 1, ExcessiveParameterList 1). On the new method (line 248):
MethodNamingConventions (sev 3, the class's `subject_behavior_forInput` naming) and
ApexUnitTestClassShouldHaveRunAs (sev 4, a false positive: `System.runAs` is in the
`post()` helper). Both follow the existing pattern of the class; nothing to fix.
The shell scripts are outside Code Analyzer's engines; `bash -n` is their check.

Governor limits: the new test makes 2 POSTs (1 SOQL + 1 DML each in the service)
inside one startTest/stopTest; no risk.

### Commands

```
sf org display --target-org cargo-opus-t1 --json
sf org list --skip-connection-status --json
sf project deploy start --source-dir force-app/main/default/classes/EntregaYaStatusResourceTest.cls --target-org cargo-opus-t1
sf apex run test --class-names EntregaYaStatusResourceTest --result-format human --wait 10 --target-org cargo-opus-t1
sf project deploy start --source-dir force-app/main/default/classes/EntregaYaStatusResource.cls --target-org cargo-opus-t1   # mutation A, mutation B, restore
sf apex run test --tests EntregaYaStatusResourceTest.post_answersUpdatedAndSavesDeliveredAtAndProofId_forTwoDeliveries --result-format human --wait 10 --target-org cargo-opus-t1
sf data query --target-org cargo-opus-t1 --json --query "SELECT Id, Name, Status__c, Last_Location__c, Last_Update__c, Delivered_At__c, Proof_Id__c, SystemModstamp FROM Shipment__c WHERE Status__c = 'In transit' ORDER BY Name LIMIT 2"
sf data query --target-org cargo-opus-t1 --json --query "SELECT IsSandbox, OrganizationType FROM Organization"
bash -n scripts/entregaya/simulate-status.sh
bash -n scripts/entregaya/attack-check.sh
bash <scratchpad>/dry-run-simulate.sh
bash <scratchpad>/dry-run-main.sh
SHIM_LOG=... PATH="<scratchpad>/shim:$PATH" bash scripts/entregaya/attack-check.sh prod-like-stub
scripts/entregaya/attack-check.sh cargo-opus-t1
sf code-analyzer run --rule-selector Recommended --target force-app/main/default/classes/EntregaYaStatusResourceTest.cls --output-file <scratchpad>/code-analyzer-results-20261117-160259.json --include-fixes
```
