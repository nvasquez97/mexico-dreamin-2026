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
T3 | S1–S5, S35, S40 | Public tracking Apex + tests (guest) | done | fcb5ebb, 6df454c, d75d73d
T4 | S6–S8, S36 | Delivery details with postal-code verification and attempt throttle + tests | done | dedae45, 6df454c, d75d73d
T5 | S9, S10, S36 | Proof of delivery callout through Named Credential + tests | done | 1a7c12a, 13b72b0
T6 | S11–S15, S36 | Reschedule + tests | done | f6e55ea, d75d73d
T7 | S16–S19, S38, S43 | EntregaYa status REST endpoint + integration access + tests | done | 08da7ab, 6df454c, d75d73d
T8 | S20–S25 | Sign-up, login, logout, forgot password Apex + tests | done | b7faada, d75d73d
T9 | S26–S31, S43 | Request shipment Apex + tests | done | 98b26a8, 6df454c, d75d73d
T10 | S32–S34, S37, S41 | My shipments Apex + tests | done | 9fba4fb, d75d73d
T11 | S35–S38, S41 | Permission sets per actor, guest access, sharing set | done | 83065bb, 41712d1, 512b5d0, 7adff0f
T12 | S44, S45, S1–S34 UI | LWR site, theme layout, LWC components with brand | done | b8f5205, 845e34d, 13b72b0, 23dc48a, 2f123b6, d75d73d
T13 | S46 | Reproducible seed script: 2 customers, 2 site users, 120 shipments | done | 4665bc7
T15 | S24, S21 | Fix: login/sign-up landed on a classic "URL No Longer Exists" page | done, security re-check pending | f7b28e5
T14 | S47 | README with pending manual steps; closing reviews | done | 41712d1, c44119c, ff58312, 4979843

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
- L35 Review security-reviewer (S1–S43): CHANGES REQUIRED. High H-1 (throttle counter race on the proof path). Medium M-1 (postal code guessable, city public), M-2 (sign-up abuse, licences), M-3 (customer profile default access), M-4 (EntregaYa key committed), M-5 (data: URL under LWS). Low L-1 (anyone can lock a recipient), L-2 (500 leaks details), L-3 (integration direct edit), L-4 (rounding), L-5 (seed password in anonymous Apex), L-6 (network chatter). Injection probes: 0 extra rows; Code Analyzer: 0 SOQL injection / CRUD / sharing violations.
- L36 Review access-auditor: CHANGES REQUIRED. High #1 (customer profile default object/field/user access, unversioned). Medium #2 guest profile FLS, #3 integration direct edit, #4 ECA policy/PKCE drift, #5 Account/Contact OWD unversioned, #6 customer sees recipient data, #7 weak postal-code factor. Low #8 agent fields, #9 chatter. Info #10 secure guest access.
- L37 Review brand-reviewer: CHANGES REQUIRED (S44 FAIL, S45 PASS). Medium #1 platform gray #EFF0F2 around header/footer, #2 logo 1X clear space. Low #3 yellow warning fill, #4 check-email page unbranded, #5 service pages unbranded. Questions recorded: licensed Daily Brew, isotype minimum, label weights, interface colour roles, Coffee Blazers logo on a RutaCargo site, favicon.
- L38 Fixes (6df454c, 512b5d0, 13b72b0): H-1, M-1/L-1 (escalating lock), L-2, L-3, L-4, M-3/access #1 (profile: 0 object permissions, 21 user permissions off; EnableNotifications required by the licence), access #2, #3, #4 (PKCE aligned; policy versioned in 41712d1), #5, #8 (agent read-only fields), #9/L-6, M-5, brand #1–#5. Customers additionally get Account Read (no custom fields) because a lookup field is hidden in user mode without read on its target object. RunLocalTests 156/156, 92% (707Ec00002j31CV). Site republished.
- L39 Decisions on findings not changed in code:
  - access #6 / BR-02 vs AC-007.3: the customer who requested the shipment sees the recipient data they entered (AC-007.3 "data the customer entered"); the estimated date is public by BR-01. BR-02 is read as: only the recipient can open the recipient views and change the delivery. Residual: the customer can see instructions the recipient edited.
  - M-2 (sign-up abuse, no CAPTCHA): out of the design's scope; recorded in README as pending (bot protection / email verification), licence use to be monitored.
  - L-5 (seed password visible in debug logs when logging is on): scratch org only; accepted.
  - M-4: README step 2 asks to rotate the key and clean history (the reviewer read README before 41712d1).
  - Access #8 seeded agent user: not created, the org has one free Salesforce licence and Apex tests need it.
  - Access #10 secure guest record access: guest has 0 object permissions and UserRecordAccess None (auditor), so no exposure either way.
- L40 Live evidence after fixes: guest downloadProof with the row lock reaches the callout (AC-002.5 message, placeholder URL). Guest sign-up through the site runtime created Account "Smoke Test Logistics" (Business, configured owner), one Contact with phone, User sara.prueba@smoke-test.example.rutacargo on "RutaCargo Customer", and CustomerAccessQueueable (Completed) assigned RutaCargo_Customer. Duplicate email -> "This email is already registered. Log in instead."; wrong login -> "Invalid email or password."; right login -> redirect URL; forgot password -> neutral message. S20–S25 verified live.
- L41 Review security-reviewer re-verification: APPROVED (no Critical/High). H-1, M-3, M-5, L-2, L-3, L-4, L-6 closed; M-1 mitigated (residual Low). Raised L-1 lockout to Medium (agents could not clear the lock; README inaccurate) -> fixed in 7adff0f: agents can edit the two throttle fields, README corrected, bot protection recommended. Open by decision: M-2 (README Known limits), M-4 (key rotation, README step 2), L-5 (accepted). Per S#: S6, S9, S36, S38, S43 PASS.
- L42 Review access-auditor re-verification: APPROVED (no Critical/High/Medium). #1–#7 closed (#6, #7 by recorded decision), #8 fields closed (agents later regained edit on the two throttle fields on purpose, 7adff0f, to clear locks). Remaining Low: Chatter tab still in the org network (README manual step 7), leftover platform field rows (ContactPointTypeConsent, IsOptedOut, Event.LocationId) that grant nothing. S36, S38, S41, S43 PASS.
- L43 Review brand-reviewer re-verification: CHANGES REQUIRED. #2, #3, #5 fixed; #1 still live (site styles.css not served after deploy: its CMS media record keeps the old file; and the rule was weaker than the platform's 0,2,0); #4 check-email button font Low. Fix 23dc48a: overrides moved to rcBrand/brand.css (served, verified with curl) with 0,2,2 selectors. Lesson: sfdc_cms__styles content is not updated by metadata deploy; edit it in Experience Builder > Theme > CSS if needed.
- L44 Review test-reviewer: CHANGES REQUIRED (0 Critical/High; Medium #1–#8). Fixed in d75d73d: #1 empty-record insert, #2 profile grants on the endpoint, #3 guest negatives + customer-class grants, #4 sign-up/login negatives, #5/#6 Jest (rcHeader logout link AC-005.5, rcFormat BR-06), #7 field-history regression test (AC-003.5), #8 key-set assertions. Evidence: RunLocalTests 164/164, 93% (707Ec00002j3GBi): 146 project test methods + 10 site-generated; Jest 11/11 in UTC and America/Los_Angeles; ESLint clean. Low #9–#22 kept as follow-ups. Re-verification requested.
- L45 Review architecture-review (Well-Architected): PASS WITH FINDINGS; Trusted, Easy, Adaptable all WARN; 0 Critical/High. Medium M1 committed EntregaYa key (open until rotated), M2 no CI, M3 failures not logged / queueable without Finalizer. Low: leading-wildcard search, row lock across the 10 s callout, history on Status and Last Location (volume), owner skew, duplicated constants, no Custom Labels, org-specific ids in source, rollback comment (fixed). Recorded as go-live conditions in README "Before going live".
- L46 Review brand-reviewer re-verification 3: APPROVED (S44 PASS, S45 PASS). #1 gray frame gone on all 6 views, #2 clear space met. Low check-email button font fixed afterwards in 2f123b6 (custom property through the shadow root). Brand-owner questions stay in L37.
- L47 Decision: Account internal OWD stays Read/Write (support agents work all customers; external is Private) and the custom Shipment__c object is used instead of the standard Field Service Shipment because the design defines its own fields and the standard object needs Field Service; both recorded after the architecture review (L7, L9).
- L48 Review test-reviewer re-verification: APPROVED. #1–#8 fixed; S15, S20, S22, S24, S38, S40, S41 PASS. The reviewer ran Jest itself (11/11 in UTC and America/Los_Angeles) but could not run Apex tests (hook); RunLocalTests 707Ec00002j3GBi (164/164, 93%) is the implementer's evidence, not reproduced by the reviewer. Follow-ups (Low): test review #9–#22, S39 "assigned consecutively" PARTIAL.
- L49 Close: all closing reviewers recorded (security APPROVED L41, access APPROVED L42, brand APPROVED L46, test APPROVED L48, architecture PASS WITH FINDINGS L45). No Critical or High finding open. Open Mediums by decision, listed in README: EntregaYa key rotation and history clean-up (M-4/M1), no CI (M2), failures not logged and queueable without retry (M3), sign-up abuse (M-2), lockout availability risk (mitigated: agents can unlock). Pending manual steps: README "Manual steps still pending in the org" 1–8. Test customer "Smoke Test Logistics" (sara.prueba@smoke-test.example) left in the org from the live sign-up check (L40).
- L50 Bug reported by the user after close: logging in as Ana showed the classic "URL No Longer Exists" page. Cause: Site.login got the relative start page "/my-shipments", resolved against the classic prefix /rutacargovforcesite. Earlier evidence (L40) only checked that a redirect URL came back, not where it led. Fix f7b28e5 (T15): LWC sends {basePath}/my-shipments, server accepts only ^(/site)?/my-shipments$. RED 3/24 -> GREEN 24/24; RunLocalTests 167/167, 93% (707Ec00002j3QVl). Live: frontdoor retURL = /rutacargo/my-shipments. Risk: item 2 -> security-reviewer and access-auditor requested for S24.

- L51 Review security-reviewer on T15 (f7b28e5): APPROVED, S24 PASS. 23 crafted start paths probed with the deployed pattern (schemes, //host, backslash, %2F, line breaks incl. , fragment, query, look-alike letters): all rejected except same-domain single-segment paths. Low: any single segment is accepted (e.g. /secur/my-shipments), harmless; could be pinned to the site prefix. Info: add a trailing-newline test case.
