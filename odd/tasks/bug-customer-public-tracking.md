# bug-customer-public-tracking — Logged-in customers can track shipments and use the recipient flow
Tier: 2 · Reason: the fix grants Apex class access on the permission set RutaCargo_Customer (who can call what; BR-01 public tracking, REQ-002/003 recipient flow)
Mode: auto
Branch: ODD-Opus-Cargo-Test-1
Org: cargo-opus-t1
Approved: the owner, 2026-11-18 ("si, arreglalo", after the Problems and Solutions summary)
Base: b0d7e0c
Plan review: 

## Findings
- Owner report (manual test, 2026-11-18): logged in as a customer, tracking RC000001124 (a shipment the owner created as customer user, CspLitePortal) shows the generic error; logged out it works. The shipment exists and `PublicTrackingController.search('TRACKING_NUMBER', ['RC000001124'])` returns it (anonymous Apex, rolled back).
- The home view places c:rcHome and c:rcTracking (`force-app/main/default/digitalExperiences/site/RutaCargo1/sfdc_cms__view/home/content.json`); rcTracking calls PublicTrackingController and opens rcDeliveryDetails, which calls RecipientDeliveryController (3 imports) — both reachable only through Apex class access.
- Class access today: the guest profile `RutaCargo Profile` grants CustomerLoginController, CustomerSignUpController, PublicTrackingController, RecipientDeliveryController; `force-app/main/default/permissionsets/RutaCargo_Customer.permissionset-meta.xml:4,8` grants only MyShipmentsController and ShipmentRequestController; the profile `RutaCargo Customer` grants no class. So a logged-in customer's call to either public controller is refused by the platform and rcTracking shows GENERIC_ERROR (`force-app/main/default/lwc/rcTracking/rcTracking.js:139-141, 257-258`).
- `scripts/checks/customer-access-check.sh:143, 375-388` asserts the customer's class access is exactly `CUSTOMER_CLASSES='MyShipmentsController ShipmentRequestController'`.
- Neither public controller refuses a non-guest user type (no Guest/UserType check in `RecipientDeliveryController.cls` or `PublicTrackingController.cls`); `ShipmentTriggerHandler.beforeUpdate` (`ShipmentTriggerHandler.cls:110`) runs on a reschedule and the customer-insert guard keys on UserType (`:156`) — whether a reschedule by a CspLitePortal user passes beforeUpdate must be proven.
- RecipientAccess runs `without sharing` with system-mode DML (guard upsert, 3-field Shipment__c update); a guard row created by a logged-in customer would be owned by that customer user (Recipient_Access_Guard__c has no object or field permission for customers, so they cannot read it).

## Problems
- P1: A logged-in customer cannot track any shipment nor use the recipient flow, although tracking is public (BR-01) and any person holding the code may act as recipient (REQ-002/003) (evidence: owner report; class access above).
- P2: Granting class access widens what a logged-in customer can call; it must not give more than an anonymous visitor already gets (same server checks, same fields), and must not break the trigger guards or leave customer-readable guard data (evidence: X11, P1, G9).

## Solutions
- S1 → P1, P2: add class access to PublicTrackingController and RecipientDeliveryController on RutaCargo_Customer (the one customer permission set); update customer-access-check.sh's exact class list to the four classes (and keep "the guest cannot call the customer controllers"); add Apex tests that run as the seeded customer Ana (System.runAs) through tracking (her own and another customer's shipment: BR-01 fields only, like a guest) and the full recipient flow (details, reschedule, proof with the mocked callout) for a shipment of another account, proving the verification still demands tracking number + postal code + access code, that a reschedule by a CspLitePortal user passes the trigger, and that the customer still cannot read Recipient_Access_Guard__c. Discarded: class access on the profile (one permission set per actor); a separate "public site" permission set (one more grant to maintain for the same actor); hiding the tracking box when logged in (BR-01 says tracking is public).

## Acceptance
- AC-BUG.1 (BR-01) — Given a logged-in customer (Ana López, System.runAs), When PublicTrackingController.search runs with a tracking number of hers and one of Marta's, Then both return exactly the BR-01 fields a guest gets (same JSON as the same call as the site guest), and nothing else.
  *Mutation:* make search refuse non-guest users (or drop a returned field for customers) — observed: <filled at tick>
- AC-BUG.2 (REQ-002/003, X16) — Given a logged-in customer (Ana) holding the tracking number, destination postal code and access code of a shipment of another account, When she calls getDeliveryDetails, rescheduleDelivery (a valid date) and downloadProof (mocked callout), Then each succeeds exactly as for the guest; with a wrong code she gets NOT_MATCHED and the per-pair attempt limit applies; the reschedule passes ShipmentTriggerHandler.beforeUpdate; and Ana still cannot read any Recipient_Access_Guard__c row or field (user-mode query refused).
  *Mutation:* skip the verification for non-guest users (the wrong-code case turns red) — observed: <filled at tick>
- AC-BUG.3 (P2, X11) — Given scripts/checks/customer-access-check.sh, When it runs, Then RutaCargo_Customer's Apex class access is exactly {MyShipmentsController, PublicTrackingController, RecipientDeliveryController, ShipmentRequestController}, the guest still cannot call the two customer controllers, and every other existing assertion still passes; exits non-zero otherwise. guest-access-check.sh still passes unchanged.
  *Mutation:* remove PublicTrackingController from the permission set and deploy (script red), redeploy the file — observed: <filled at tick>

## Task analysis
| Task | Solves | Acceptance | Scope (files to touch) | Security | Executor | Skills | Reviewers |
|---|---|---|---|---|---|---|---|
| T1 | S1 | AC-BUG.1, AC-BUG.2, AC-BUG.3 | force-app/main/default/permissionsets/RutaCargo_Customer.permissionset-meta.xml (two classAccesses), scripts/checks/customer-access-check.sh (CUSTOMER_CLASSES and its comments), force-app/main/default/classes/CustomerPublicAccessTest.cls(+meta, new), force-app/main/default/classes/TestDataFactory.cls (only if a helper is needed), odd/evidence/bug-customer-public-tracking/T1.md | yes | task-worker | salesforce-development:platform-permission-set-generate, salesforce-development:platform-metadata-api-context-get, salesforce-development:platform-metadata-deploy, salesforce-development:platform-apex-test-generate, salesforce-development:platform-apex-test-run, salesforce-development:platform-soql-query, sf-security-access-review | task-reviewer, security-reviewer, access-auditor |

## Tasks
- [ ] T1 (S1): Customer class access to the two public controllers, check script, tests as a logged-in customer — test first

## Assumptions
- B1: Apex unit tests do not enforce Apex class access on direct static calls; the class grant itself is proven by customer-access-check.sh against the org (AC-BUG.3) and by the owner's manual retest while logged in; the Apex tests prove the behaviour as a CspLitePortal user.
- B2: A guard row created by a logged-in customer's failed attempt is owned by that customer user; customers have no object permission on Recipient_Access_Guard__c, so they still cannot read it (proved in AC-BUG.2); the daily purge (System Administrator) still sees and deletes it.

## Close
Stage: pending
