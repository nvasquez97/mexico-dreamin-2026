# req-004-carrier-status — EntregaYa sends status changes that update shipments in Salesforce
Tier: 2 · Reason: AC-004.1 is an inbound contract with an external system (EntregaYa) and BR-04 restricts who may send updates (authentication with OAuth client credentials, integration user access)
Mode: auto
Branch: ODD-Opus-Cargo-Test-1
Org: cargo-opus-t1
Approved: standing choice of the owner (unattended run), 2026-11-17
Base: 642bc1b
Plan review: 

## Findings
- The contract: one POST per status change with trackingNumber, status, location, timestamp (ISO-8601 with offset) and proofId (null unless delivered); about 5,000 updates a day (`docs/functional-design.md`, "Status changes (EntregaYa calls Salesforce)").
- Owner decision D2 (.mem/memory.md): Apex REST `POST /services/apexrest/entregaya/v1/status`, OAuth 2.0 client credentials through an External Client App, a dedicated integration user (Salesforce Integration license, 1 free) with a minimal permission set; responses 200 `{"result":"updated"}`, 200 `{"result":"ignored"}` for stale updates, 404 for an unknown tracking number, 400 for an invalid status or body.
- Shipment__c is Private internally (foundation S1); the integration user needs record access through sharing, like the support agents (`force-app/main/default/sharingRules/Shipment__c.sharingRules-meta.xml`).
- Status picklist API names equal the labels EntregaYa sends ("Out for delivery") (`force-app/main/default/objects/Shipment__c/fields/Status__c.field-meta.xml`).
- Tracking numbers are the record Name, `^RC\d{9}$`, indexed (foundation AC-F.2).
- At API 67 Apex DML/SOQL default to user mode, so the integration user's FLS and sharing apply (foundation T1 evidence).
- The site's guest and customers must never reach this endpoint (BR-04); Apex REST is reachable only by authenticated users with class access.
- Foundation lessons (odd/tasks/archive/2026-11-17-foundation.md): criteria-based sharing rules are not evaluated in Apex tests (A10: mirror them with Manual group shares in tests, prove the real rule shares with a script); every check script must fail on a failed query; agents can edit Status__c, Last_Location__c, Last_Update__c, Delivered_At__c and Proof_Id__c (BR-09 allows RutaCargo to correct statuses); licenses: Salesforce Integration 0/1 used, Salesforce Platform 0/3 (tests create users without consuming real licenses but must use profiles whose license exists).
- Only 120 seeded shipments exist; A6 forbids stray Shipment__c inserts outside tests; the live check of AC-004.6 updates one seeded "In transit" shipment, which keeps every status present per customer (scripts/seed/verify.sh must stay green).

## Problems
- P1: Without an inbound service, statuses keep being typed by hand hours late (evidence: REQ-004 story).
- P2: Status changes can arrive out of order or be retried; applying an older one would move a shipment backwards (evidence: AC-004.4).
- P3: A malformed body, an unknown tracking number or a status outside the picklist could corrupt data or leak internals (stack traces, field names) to the caller (evidence: AC-004.3, policy X7, X6 mass assignment if the body were deserialized into an SObject).
- P4: Anyone other than EntregaYa able to call the service, or the integration user having more access than the status fields, breaks BR-04 and least privilege (evidence: BR-04, policy P-rules on minimal permission sets, "Inbound services authenticate with OAuth").
- P5: The OAuth client secret is a secret: it must never be in the repository (evidence: policy "No secrets in the repository").
- P6: Two concurrent updates for the same shipment could interleave and keep the older one (evidence: AC-004.4, 5,000 updates a day).

## Solutions
- S1 → P2, P3, P6: a `with sharing` service class EntregaYaStatusService that receives individual fields (a typed request DTO, never an SObject), validates them (tracking number format, status in the closed list of the six picklist values, location length, ISO-8601 timestamp with offset, proofId required for Delivered), locks the shipment with `FOR UPDATE`, ignores the update when its timestamp is not newer than Last_Update__c, and otherwise updates Status__c, Last_Location__c, Last_Update__c and, for Delivered, Delivered_At__c and Proof_Id__c — all in user mode. Discarded: a Flow or Platform Event subscriber (harder to return synchronous 404/400 to EntregaYa); last-write-wins without a timestamp check (breaks AC-004.4).
- S2 → P1, P3: a thin Apex REST resource EntregaYaStatusResource (`/entregaya/v1/status`, POST only) that parses the JSON body into the DTO, calls the service and maps results to 200 updated / 200 ignored / 404 / 400 with a JSON body `{"result":...}` or `{"error":{"code":...,"message":...}}`; no stack traces, no field API names in messages. Discarded: returning 409 for stale updates (D2 chose 200 ignored so EntregaYa does not retry).
- S3 → P4: permission set RutaCargo_EntregaYa_Integration: Apex class access to EntregaYaStatusResource only; Shipment__c Read and Edit; FLS read on Name, Status__c, Last_Location__c, Last_Update__c, Delivered_At__c, Proof_Id__c and edit on the last five; nothing else. A public group RutaCargo_EntregaYa_Integration and a criteria-based sharing rule giving it Read/Write on all shipments. Discarded: `without sharing` in the service (the sharing rule gives the same reach with a narrower, versioned grant); View All on Shipment__c (policy flags it).
- S4 → P4, P5: an External Client App "EntregaYa Status" with the OAuth client credentials flow enabled, scope `api` only, run as the dedicated integration user (profile "Minimum Access - API Only Integrations", Salesforce Integration license), created by a versioned setup script (the user is data; its username is org-specific); the consumer secret stays in the org and is handed to EntregaYa by the owner (README). A simulation script posts status changes with a token obtained from client credentials read from environment variables, never from files. Discarded: a Connected App (External Client Apps are the current, packageable model); a named user password flow (needs a password).

## Acceptance
- AC-004.1 — Given an integration user with RutaCargo_EntregaYa_Integration, When EntregaYa POSTs `{"trackingNumber":"RC…","status":"Out for delivery","location":"Monterrey, NL","timestamp":"2026-11-20T10:00:00-06:00","proofId":null}` for an existing shipment, Then the response is 200 `{"result":"updated"}`; the same holds for a second input with status "Picked up" and another location.
  *Mutation:* make the resource return 200 without calling the service — observed: <filled by the worker>
- AC-004.2 — Given that update, When the shipment is read, Then Status__c, Last_Location__c and Last_Update__c (the timestamp converted to an instant) are saved; Given a "Delivered" update with proofId "PRF-88231", Then Delivered_At__c equals the timestamp and Proof_Id__c is "PRF-88231"; Given a non-Delivered update, Then Delivered_At__c and Proof_Id__c are unchanged.
  *Mutation:* stop saving Proof_Id__c on Delivered — observed: <filled by the worker>
- AC-004.3 — Given a POST with an unknown tracking number, Then 404 `{"error":{"code":"TRACKING_NOT_FOUND",…}}` and nothing changes; Given a status outside the six values (e.g. "Lost", "delivered" in another case), Then 400 `{"error":{"code":"INVALID_STATUS",…}}`; Given a malformed JSON body, a missing field, a bad timestamp, a tracking number not matching `^RC\d{9}$`, or "Delivered" without proofId, Then 400 with a clear code and message and no stack trace or field API name in the body.
  *Mutation:* accept any status string — observed: <filled by the worker>
- AC-004.4 — Given a shipment whose Last_Update__c is 2026-11-20T10:00:00-06:00, When an update with timestamp 2026-11-20T09:00:00-06:00 arrives, Then 200 `{"result":"ignored"}` and nothing changes; When one with exactly the same timestamp arrives, Then it is also ignored; When one with 2026-11-20T11:00:00-06:00 arrives, Then it is applied.
  *Mutation:* compare with `<` instead of `<=` (equal timestamps applied) — observed: <filled by the worker>
- AC-004.5 (BR-04, P4) — Given the deployed metadata, When scripts/checks/entregaya-access-check.sh runs, Then EntregaYaStatusResource is accessible only through RutaCargo_EntregaYa_Integration (and System Administrator), the permission set grants Shipment__c only Read and Edit with edit FLS only on the five status fields and no read on Delivery_Access_Code_Hash__c, Recipient_* or Price/cost fields, and an Apex test shows a support agent (without the integration permission set) gets no access to the class; the script exits non-zero otherwise.
  *Mutation:* grant the class to RutaCargo_Support_Agent — observed: <filled by the worker>
- AC-004.6 (D2, P4, P5) — Given the External Client App and the integration user created by scripts/setup/entregaya-integration.sh, When the configuration is queried, Then the client credentials flow is enabled with scope api only and runs as the integration user (profile Minimum Access - API Only Integrations, only RutaCargo_EntregaYa_Integration assigned, member of RutaCargo_EntregaYa_Integration group), no consumer secret or token is in the repository (grep), and a live POST to /services/apexrest/entregaya/v1/status (scripts/entregaya/simulate-status.sh) moves one seeded "In transit" shipment to "Out for delivery" and returns 200 updated, and posting the same body again returns 200 ignored.
  *Mutation:* disable the client credentials flow in the External Client App and deploy — observed: <filled by the worker>

## Task analysis
| Task | Solves | Acceptance | Scope (files to touch) | Security | Executor | Skills | Reviewers |
|---|---|---|---|---|---|---|---|
| T1 | S3 | AC-004.5 | force-app/main/default/permissionsets/RutaCargo_EntregaYa_Integration.permissionset-meta.xml, force-app/main/default/groups/RutaCargo_EntregaYa_Integration.group-meta.xml, force-app/main/default/sharingRules/Shipment__c.sharingRules-meta.xml (add one rule), force-app/main/default/classes/EntregaYaStatusResource.cls(+meta) (stub that returns 501 only, so class access can be granted), force-app/main/default/classes/EntregaYaAccessTest.cls(+meta), force-app/main/default/classes/TestDataFactory.cls, scripts/checks/entregaya-access-check.sh | yes | task-worker | salesforce-development:platform-permission-set-generate, salesforce-development:platform-sharing-rules-generate, salesforce-development:platform-apex-test-generate, salesforce-development:platform-apex-test-run, salesforce-development:platform-metadata-deploy, salesforce-development:platform-soql-query | task-reviewer, security-reviewer, access-auditor |
| T2 | S1, S2 | AC-004.1, AC-004.2, AC-004.3, AC-004.4 | force-app/main/default/classes/EntregaYaStatusResource.cls, force-app/main/default/classes/EntregaYaStatusService.cls(+meta), force-app/main/default/classes/EntregaYaStatusRequest.cls(+meta), force-app/main/default/classes/EntregaYaStatusResourceTest.cls(+meta), force-app/main/default/classes/EntregaYaStatusServiceTest.cls(+meta), force-app/main/default/classes/TestDataFactory.cls | yes | task-worker | salesforce-development:platform-apex-generate, salesforce-development:platform-apex-test-generate, salesforce-development:platform-apex-test-run, salesforce-development:platform-metadata-deploy, salesforce-code-quality:dx-code-analyzer-run | task-reviewer, security-reviewer, access-auditor |
| T3 | S4 | AC-004.6 | force-app/main/default/externalClientApps/**, force-app/main/default/extlClntAppOauthSettings/**, force-app/main/default/extlClntAppGlobalOauthSets/**, force-app/main/default/extlClntAppOauthPolicies/** (or the names the platform uses for the EntregaYa Status app), scripts/setup/entregaya-integration.sh, scripts/setup/entregaya-integration.apex, scripts/entregaya/simulate-status.sh, scripts/checks/entregaya-access-check.sh, README.md (EntregaYa section) | yes | task-worker | integration:integration-connectivity-connected-app-configure, salesforce-development:platform-metadata-deploy, salesforce-development:platform-metadata-retrieve, salesforce-development:platform-soql-query, salesforce-development:platform-apex-anonymous-run | task-reviewer, security-reviewer, access-auditor |

## Tasks
- [ ] T1 (S3): Integration permission set, group, sharing rule and access check — test first
- [ ] T2 (S1, S2): Status service and REST resource with validation, stale-update guard and error contract — test first
- [ ] T3 (S4): External Client App with client credentials, integration user setup, live simulation — test first

## Assumptions
- B1: a "Delivered" update without proofId is rejected with 400 (AC-004.2 needs the proof id; the conservative choice is not to record a delivery without it).
- B2: equal timestamps are ignored (idempotent retries); only strictly newer updates apply.
- B3: status transitions are not otherwise validated (the design only orders updates by time; RutaCargo agents can correct statuses by hand, BR-09).
- B4: the consumer secret is read by the owner in Setup and handed to EntregaYa; the simulation script reads ENTREGAYA_CLIENT_ID / ENTREGAYA_CLIENT_SECRET from the environment.

## Close
Stage: pending
