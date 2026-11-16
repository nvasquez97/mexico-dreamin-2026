# RutaCargo Shipping and Tracking

- Objective: implement docs/functional-design.md (REQ-001..REQ-007, BR-01..BR-09)
  as an Experience Cloud LWR site with LWC + Apex in the project org, applying
  the brand manual docs/brand-manual.pdf and the logo files in docs/brand/.
- Branch: feature/rutacargo-shipping-tracking
- Org: rutacargo-b-opus (scratch, expires 2026-12-15)
- Test runner: Apex, `sf apex run test --target-org rutacargo-b-opus`

## Specs

Literal text from docs/functional-design.md.

### REQ-001 — Public tracking

- S1 (AC-001.1) The visitor chooses to search by tracking number or by order reference, and can enter up to 10 values separated by commas or line breaks.
- S2 (AC-001.2) For each shipment found, the site shows: tracking number, status, origin city, destination city, last location, date of the last update and estimated delivery date.
- S3 (AC-001.3) Values that do not match any shipment are listed as "Not found".
- S4 (AC-001.4) Results can be sorted by status or by estimated delivery date.
- S5 (AC-001.5) The search ignores case and leading or trailing spaces.

### REQ-002 — Delivery details and proof of delivery

- S6 (AC-002.1) From a tracking result, the recipient enters the destination postal code to open the delivery details.
- S7 (AC-002.2) The details show: recipient name, delivery address, contact phone, estimated date and delivery instructions.
- S8 (AC-002.3) If the postal code does not match, the site shows "The details do not match this shipment".
- S9 (AC-002.4) When the shipment is Delivered, "Download proof of delivery" fetches from EntregaYa the PDF with the signature of the person who received it. The PDF is not stored in Salesforce.
- S10 (AC-002.5) If EntregaYa does not respond, the site shows "We could not get the proof of delivery, please try again later".

### REQ-003 — Reschedule the delivery

- S11 (AC-003.1) From the delivery details, the recipient can choose a new date and edit the delivery instructions.
- S12 (AC-003.2) The new date must be between the next day and 7 calendar days after the original estimated date.
- S13 (AC-003.3) Only a shipment in Picked up or In transit status can be rescheduled.
- S14 (AC-003.4) A shipment can be rescheduled at most 2 times.
- S15 (AC-003.5) On save, the new date is shown, and the support agent can see in Salesforce when each change was made.

### REQ-004 — Carrier status updates

- S16 (AC-004.1) EntregaYa sends Salesforce every status change: tracking number, new status, location, and date and time.
- S17 (AC-004.2) Salesforce updates the status, the last location and the last update date of the shipment. With the Delivered status, the moment of delivery and the proof of delivery identifier are also saved.
- S18 (AC-004.3) A nonexistent tracking number or an invalid status is rejected with a clear error message for EntregaYa.
- S19 (AC-004.4) If an update arrives that is older than the last one recorded, it is ignored.

### REQ-005 — Customer sign-up and login

- S20 (AC-005.1) The sign-up form asks for: customer type (individual or business), name or legal name, first and last name of the contact person, email, phone and password.
- S21 (AC-005.2) Signing up creates the customer in Salesforce: an account with its contact.
- S22 (AC-005.3) An email can have only one account. If it is already registered, a message is shown and login is offered.
- S23 (AC-005.4) The password must have at least 10 characters, with letters and numbers.
- S24 (AC-005.5) The customer logs in with their email and password, and can log out.
- S25 (AC-005.6) If they forget their password, they can reset it with a link they receive by email.

### REQ-006 — Request a door-to-door shipment

- S26 (AC-006.1) The form asks for: pickup address, city and postal code; pickup date; recipient name, address, city, postal code, phone and email; service type (Standard or Express); weight in kg; description of the contents; declared value; and, optionally, an order reference and delivery instructions.
- S27 (AC-006.2) Before confirming, the customer sees the shipment price according to the current rate (BR-08).
- S28 (AC-006.3) The pickup date must be a business day between the next day and 15 days later.
- S29 (AC-006.4) The maximum weight is 30 kg and the maximum declared value is 50,000 MXN.
- S30 (AC-006.5) On confirmation, the shipment is created under the customer, in Requested status and with its tracking number, which is shown on screen.
- S31 (AC-006.6) The estimated delivery date is the pickup date plus 5 business days for Standard and plus 2 for Express.

### REQ-007 — My shipments

- S32 (AC-007.1) The list shows the customer's shipments: tracking number, request date, recipient, destination city, status, service type and price, most recent first.
- S33 (AC-007.2) The list can be filtered by status and searched by tracking number, recipient or reference.
- S34 (AC-007.3) Each shipment has a detail page with the data the customer entered, the price and the current status.

### Business rules (they win over acceptance criteria)

- S35 (BR-01) The public information of a shipment is what AC-001.2 lists. Any visitor with the tracking number or the reference can see it, and nothing else.
- S36 (BR-02) The recipient's personal data, the proof of delivery and changes to the delivery are exclusive to the recipient of the shipment.
- S37 (BR-03) The transport cost, the margin, the internal notes and the customer's credit limit and credit risk are internal RutaCargo information and are not shown on the site. The price of a shipment is visible only to the customer who requested it.
- S38 (BR-04) Only EntregaYa can send status updates.
- S39 (BR-05) The tracking number has the prefix RC followed by 9 digits, and is assigned consecutively when the shipment is created.
- S40 (BR-06) Dates are shown in Mexico City time.
- S41 (BR-07) Each customer sees and manages only their own shipments and their own data.
- S42 (BR-08) Current rate: Standard, 120 MXN plus 18 MXN per kg; Express, 220 MXN plus 30 MXN per kg. In both cases, 1.5% of the declared value is added as insurance. RutaCargo determines the price with this rate.
- S43 (BR-09) A new shipment starts in Requested status. Only RutaCargo and EntregaYa change the status of a shipment.

### Non-functional and definition of done

- S44 (NFR-Brand) Visual identity: the site applies the Coffee Blazers Summit Brand Manual (`docs/brand-manual.pdf`) and uses the logo files in `docs/brand/`: colors, typography, logo versions and usage rules.
- S45 (NFR-Platform) Experience Cloud site in English, with public pages (tracking and delivery) and pages for registered customers (request a shipment and my shipments). Components in LWC and logic in Apex.
- S46 (DoD-Data) Metadata deployed to the development org and test data loaded with a reproducible script.
- S47 (DoD-README) A README with the manual steps that remain pending in the org.

## Tasks

ID | S# covered | Task | Status | Commit
--- | --- | --- | --- | ---
T1 | S39, S37, S15 (history), S42 (rate config) | Data model: Account fields, Shipment__c, Shipping_Rate__mdt, settings, OWD, field history | done | 6f09a51
T2 | S27, S28, S29, S31, S42, S40 | Pricing and Mexico City business calendar services + tests | done | cfa6b13
T3 | S1–S5, S35, S40 | Public tracking Apex + tests (guest) | implemented, security review pending | fcb5ebb
T4 | S6–S8, S36 | Delivery details with postal-code verification and attempt throttle + tests | implemented, security review pending | dedae45
T5 | S9, S10, S36 | Proof of delivery callout through Named Credential + tests | implemented, security review pending | 1a7c12a
T6 | S11–S15, S36 | Reschedule + tests | implemented, security review pending; AC-003.5 history to verify in org | f6e55ea
T7 | S16–S19, S38, S43 | EntregaYa status REST endpoint + integration access + tests | implemented, security review pending; OAuth app in T11 | 08da7ab
T8 | S20–S25 | Sign-up, login, logout, forgot password Apex + tests | implemented, security review pending; live sign-up to verify on the site | b7faada
T9 | S26–S31, S43 | Request shipment Apex + tests | implemented, security review pending | 98b26a8
T10 | S32–S34, S37, S41 | My shipments Apex + tests | implemented, security review pending | 9fba4fb
T11 | S35–S38, S41 | Permission sets per actor, guest access, sharing set | implemented, security review pending; assignments in T13 | 83065bb
T12 | S44, S45, S1–S34 UI | LWR site, theme layout, LWC components with brand | implemented, security and brand review pending | b8f5205, 845e34d
T13 | S46 | Reproducible seed script: 2 customers, 2 site users, 120 shipments | done | 4665bc7
T14 | S47 | README with pending manual steps; closing reviews | in progress (README done) | 41712d1

## Log

- L1 Original request: "Implement the functional design in docs/functional-design.md in the org ALIAS, following the brand manual in docs/brand-manual.pdf"
- L2 Assumption: "the org ALIAS" is read as `rutacargo-b-opus`, the deploy target recorded in .mem/memory.md (2026-11-15 18:58) and set as target-org in .sf/config.json.
- L3 Decision: the EntregaYa API key in docs/functional-design.md is not copied anywhere. The callout uses a Named Credential + External Credential; the key and the base URL are entered manually in the org (README). The key is already committed in docs/functional-design.md; README recommends rotating it.
- L4 Assumption: the logo files in docs/brand/ (Coffee Blazers Summit) are used as the site logo, as S44 states, each on the background it was cropped from.
- L5 Assumption: Daily Brew (display face) is not available as a web font; headlines use Montserrat Black, which the manual assigns to "titulares". Montserrat is self-hosted in a static resource.
- L6 Assumption: the 7-day reschedule window (S12) is anchored to the original estimated date, stored in Original_Estimated_Delivery__c, so it does not slide with each reschedule.
- L7 Assumption: business days (S28, S31) are Monday to Friday; public holidays are not considered.
- L8 Assumption: a Delivered update without proofId is rejected (400), because S17 requires saving the proof identifier.
- L9 Decision: postal-code verification (S6) is throttled per shipment (5 failed attempts lock it for 15 minutes) to limit brute force on recipient data (S36).
- L10 Decision: shipment price uses the actual weight (2 decimals), rounded half-up to 2 decimals; rates live in Shipping_Rate__mdt.
- L11 Decision: OWD Shipment__c internal Read/Write (support agents), external Private; customers see their account's shipments via a sharing set; guest and EntregaYa access only through Apex with explicit field lists.
- L12 Evidence T1: dry-run and deploy succeeded (0AfEc00000pyRBFKA2, 45 components). Tooling query: Shipment__c, Account, Contact internal ReadWrite / external Private. Risk: item 6.
- L13 Evidence T2 (cfa6b13): RED 20/21 failing on stubs (test run 707Ec00002j3IVz); GREEN 21/21 (707Ec00002j3Pi8), coverage PricingService 100%, BusinessCalendar 93%. Risk: none.
- L14 Decision: Apex classes use API 67.0, where user mode is the default; guest and integration paths that need system mode declare it explicitly (WITH SYSTEM_MODE / AccessLevel.SYSTEM_MODE) with a justification comment. Async work uses Queueable, not @future.
- L15 Evidence T12 (part): site RutaCargo created (job 08PEc00000eB19xMAC, Network 0DBEc000000g9ZxOAI, guest profile "RutaCargo Profile"); metadata retrieved, commit b8f5205.
- L16 Environment: with API 67.0, Apex DML/SOQL in tests also runs in user mode; the admin profile has no FLS on new fields, so test data setup uses AccessLevel.SYSTEM_MODE / WITH SYSTEM_MODE. Code under test still runs as the real user (guest, customer, integration).
- L17 Evidence T3 (fcb5ebb): RED 14/16 failing (707Ec00002j3NTU); GREEN 16/16 (707Ec00002j3OMS), PublicTrackingController 96%. Risk: item 2.
- L18 Decision: the item-2 tasks that share the guest/customer/integration access surface (T3–T8, T11) get one security-reviewer + access-auditor pass with all their S#, run once T11 grants the permissions (the access auditor needs the real permission sets). Each of those tasks stays "security review pending" and is not closed until Critical and High findings are fixed.
- L19 Evidence T4 (dedae45): RED 11/12 failing (707Ec00002j3BPf); GREEN 12/12 (707Ec00002j31vP), DeliveryController and DeliveryAccessService 100%. Risk: item 2.
- L20 Evidence T5 (1a7c12a): credentials deployed (0AfEc00000pySP3KAM); RED 9/11 failing (707Ec00002j3ST5); GREEN 23/23 with T4 (707Ec00002j3QWU), EntregaYaClient 90%. Pending manual: base URL + ApiKey in Setup (README). Risk: item 2.
- L21 Evidence T6 (f6e55ea): RED 12/13 failing (707Ec00002j3TIo); GREEN 36/36 with T4/T5 (707Ec00002j2tl9). Field history rows are not created in Apex tests, so AC-003.5 is verified in the org after seeding (T13). Risk: item 2.
- L22 Evidence T7 (08da7ab): RED 12/14 failing (707Ec00002j3PnY); GREEN 14/14 (707Ec00002j3Jdg), EntregaYaStatusResource 93%. Contract: POST /services/apexrest/entregaya/v1/shipment-status; 200 updated|ignored, 400/404 rejected with code. Risk: items 2, 3.
- L23 Evidence T8 (b7faada): RED 16/20 failing (707Ec00002j3I3B); GREEN 20/20 (707Ec00002j3XxT); SiteGatewayTest 3/3 (707Ec00002j3IhL). Site.* calls can only be proven on the live site (T12 smoke test). Risk: item 2.
- L24 Decision: site customers use the custom profile "RutaCargo Customer" (Customer Community license, no object permissions) because the org blocks standard external profiles for user creation; access comes from the RutaCargo_Customer permission set, assigned by CustomerAccessQueueable after sign-up. Site username = email + ".rutacargo".
- L25 Evidence T9 (98b26a8): RED 15/16 failing (707Ec00002j2fUy); GREEN 37/37 with T8 tests (707Ec00002j3Rqr), ShipmentRequestController 96%. Lesson: System.runAs does not apply object permissions to describe calls; prove permissions with USER_MODE DML. Risk: item 2.
- L26 Evidence T10 (9fba4fb): sharing set deployed (0AfEc00000pyU97KAE); RED 13/14 failing (707Ec00002j3Ump); GREEN 14/14 (707Ec00002j3Kkl), MyShipmentsController 100%. Risk: item 2.
- L27 Evidence T11 (83065bb): ECA deployed (0AfEc00000pyUPFKA2); tab, layout, guest and agent permission sets (0AfEc00000pyUaXKAU); network membership then self-registration profile (0AfEc00000pyUgzKAE, 0AfEc00000pyUibKAE). The network only accepts a self-registration profile that is already a member: deploy membership first.
- L28 Decision (updates L18): the batched security-reviewer + access-auditor pass runs after T12 (LWC) and T13 (seeded assignments), so it covers the Apex, the LWC and the real org access in one pass. T3–T11 stay "security review pending" until then.
- L29 Evidence T13 (4665bc7): seed run 1 created 3 assignments + 120 shipments + 2 site users; run 2 skipped everything (idempotent). SOQL: RC000001001..RC000001120, 60 per customer across 6 statuses, 14 Delivered with Proof_Id per customer. Password for the seeded site users kept outside the repo (scratchpad file, not committed).
- L30 Evidence T12 (845e34d): site deployed (0AfEc00000pyVRlKAM) and published (job 08PEc00000eBJYAMA4 Complete). Anonymous HTTP checks: /, /login, /SelfRegister, /ForgotPassword return 200; /my-shipments redirects to login. Guest Apex through /webruntime/api/apex/execute: track returns only AC-001.2 fields and lists RC999999999 as not found; wrong postal code returns the AC-002.3 message; right code returns details; reschedule of RC000001003 saved; downloadProof returns the AC-002.5 message (EntregaYa URL and key still placeholders).
- L31 Evidence S15 (AC-003.5) in the org: Shipment__History for RC000001003 shows Estimated_Delivery__c 2026-11-17 -> 2026-11-20, Reschedule_Count__c 0 -> 1 and Delivery_Instructions__c, created by the site guest at 2026-11-16T01:03:42Z; the Shipment layout shows the history related list.
- L32 Evidence S16-S19 over HTTP (admin session): RC000001003 updated to Out for delivery, an older update ignored, RC999999999 rejected 404 UNKNOWN_TRACKING_NUMBER, "Lost" rejected 400 INVALID_STATUS. OAuth client credentials as the integration user is configured (policy 0AfEc00000pyVl7KAE) but not exercised: the consumer secret can only be read in Setup (README step 3).
- L33 Evidence: RunLocalTests 151/151 pass, org-wide coverage 93% (707Ec00002j3Jlc).
- L34 Assumption: the org currency stays USD (README step 5); the site formats amounts as MXN. Branding-set fonts accept only a family name, so the platform styles use "Montserrat" without fallbacks; LWC CSS keeps fallbacks.
