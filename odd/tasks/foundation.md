# foundation — Data model, internal access, site shell with brand, and reproducible test data
Tier: 2 · Reason: Shipment__c and Account external sharing model (BR-07), guest profile of the site (BR-01, policy X11/X16), support agent permission set with internal-only fields (BR-03)
Mode: auto
Branch: ODD-Opus-Cargo-Test-1
Org: cargo-opus-t1
Approved: unattended run, per the request, 2026-11-17
Base: 18a2aa5
Plan review: 

## Findings
- force-app is empty: no objects, classes, LWC, permission sets or site exist yet (`git ls-files force-app` returns nothing).
- The design's data model: Account fields Customer_Type__c, Credit_Limit__c, Credit_Risk__c and the custom object Shipment__c with 28 fields (`docs/functional-design.md:36-82`).
- Tracking number is the record Name, prefix RC + 9 digits, consecutive at creation (BR-05, `docs/functional-design.md:156`); test data uses RC000001001–RC000001120 (`docs/functional-design.md:229-232`).
- Margin__c is a percent formula; Carrier_Cost__c, Margin__c, Internal_Notes__c, Credit_Limit__c and Credit_Risk__c are internal-only (BR-03).
- Every requirement after this one needs an Experience Cloud site in English, mobile first, with the brand manual applied (`docs/functional-design.md:212-218`). The org has the Communities feature (scratch definition fd2ae95) and 5 Customer Community licenses, 3 Salesforce Platform licenses, 0 free Salesforce licenses (UserLicense query, 2026-11-17).
- Brand manual: palette night blue #0D1F5F, electric blue #016BFA, cyan #07E9F6, white #FFFFFF, enamel gray #D6E0EA, accents #FF3636 and #FFC91D; typography Daily Brew (display, logo letter, short uppercase headings only) and Montserrat (Google Fonts, everything else) (`docs/brand-manual.pdf` pages 6-7). Logo stand-ins in `docs/brand/`, each to be used only on the background it was cropped from (`docs/brand/README.txt`).
- Plugin skills cannot be loaded with the Skill tool in this session ("Unknown skill"); their SKILL.md files are readable under ~/.claude/plugins/cache/salesforce/ and ~/.claude/plugins/marketplaces/salesforce/skills/.

## Problems
- P1: Without the objects and fields, no requirement can be built or tested; a wrong picklist value would silently break the EntregaYa contract, which sends the status label as text (evidence: data model table, REQ-004 body example "Out for delivery").
- P2: Tracking numbers that are not consecutive or not in the RC + 9 digits format break BR-05 and make the test data in the design unreproducible (evidence: BR-05, test data table).
- P3: An external sharing model other than Private on Shipment__c or Account would let one customer or a guest read another customer's shipments, recipients' personal data or credit data (evidence: BR-02, BR-03, BR-07; policy "External access to objects is Private").
- P4: The recipient must not be authorized only by a guessable tracking number and a public postal code (policy X16); a secret per shipment must exist from creation, for every path that creates shipments (seed data, REQ-006 sign-up flow, agents) (evidence: owner decision D1 in .mem/memory.md).
- P5: Reschedules must be bounded by the first estimate, which is lost once Estimated_Delivery__c is changed (evidence: AC-003.2, owner decision D4).
- P6: Support agents need the internal fields; any wider grant (Delete, View All, Modify All, edit on system-computed fields) breaks least privilege and BR-09 (evidence: BR-03, BR-09, policy P-rules on minimal permission sets).
- P7: A site created by clicks is not versioned and cannot be rebuilt in the next scratch org; a guest profile with object permissions exposes data directly through the APIs (evidence: policy "The guest user receives no object permissions", X11).
- P8: Test data loaded by hand is not reproducible and the definition of done requires a script (evidence: DoD "test data loaded with a reproducible script").

## Solutions
- S1 → P1, P2, P3, P5: Account fields and Shipment__c with every design field, plus Original_Estimated_Delivery__c (Date) and Delivery_Access_Code__c (Text 10); Name is an Auto Number `RC{000000000}` starting at 1001; picklist API names equal the design labels; Shipment__c internal sharing Read/Write and external Private; Account external Private (internal stays as the org default); field history on Status__c, Estimated_Delivery__c and Delivery_Instructions__c. Discarded: a Text Name filled by a trigger from a counter record (row-lock contention at peak volume and a home-grown sequence; Auto Number is the platform's concurrency-safe sequence); master-detail to Account (would force sharing to follow Account and block reparenting by agents).
- S2 → P4, P5: one Shipment__c trigger with a handler that, before insert, generates Delivery_Access_Code__c with `Crypto.getRandomInteger` from an alphabet without ambiguous characters (overwriting any value the caller sent) and copies Estimated_Delivery__c into Original_Estimated_Delivery__c; never on update. Discarded: storing only a hash of the code (RutaCargo must print the code on the label and the customer must see it to share it with the recipient; FLS restricts it instead); generating the code in each controller (a path that forgets it leaves a shipment without a secret).
- S3 → P6: permission set RutaCargo_Support_Agent: Shipment__c Read, Create, Edit (no Delete, View All, Modify All); read on every Shipment__c field, edit on every field except Name, Margin__c, Delivery_Access_Code__c and Original_Estimated_Delivery__c; read and edit on the three Account fields; the Shipment tab and a RutaCargo Lightning app. Discarded: granting it through a cloned profile (profiles are being retired for permissions and cannot be reused for Salesforce Platform users); View All on Shipment__c (internal OWD Read/Write already gives the visibility).
- S4 → P7: an LWR Experience Cloud site "RutaCargo" (URL prefix `rutacargo`), created and retrieved into force-app so it is versioned; guest profile with no object permissions at all; brand theme (palette, Montserrat self-hosted in a static resource, logos in a static resource used on their own background), a header with the logo and a public home page placeholder. Discarded: Aura template (older runtime, slower on mobile); loading Montserrat from Google Fonts at runtime (needs a CSP trusted site to an external host; self-hosting the OFL font avoids it); Daily Brew (no font file in the repo: headings fall back to Montserrat Black in uppercase, recorded as an assumption).
- S5 → P8: an idempotent seed script under scripts/seed/ (anonymous Apex run by a shell wrapper) that loads the two customers with their contacts and 120 shipments exactly as the design's table, plus a verify script that asserts the counts, tracking numbers, statuses and Delivered data; the README gets the run steps and the run's assumptions. Site users for Ana López and Marta Ruiz are added by REQ-005, which creates the customer profile. Discarded: `sf data tree import` JSON files (cannot compute dates relative to the run date, and cannot assert).

## Acceptance
- AC-F.1 (data model) — Given the deployed schema, When Shipment__c and Account are described, Then Status__c has exactly Requested, Picked up, In transit, Out for delivery, Delivered, Exception (API name = label), Service_Type__c has Standard and Express, Customer_Type__c has Individual and Business, Credit_Risk__c has Low, Medium and High, and every field of the design table exists with its type.
  *Mutation:* remove the value "Exception" from Status__c — observed: <filled by the worker>
- AC-F.2 (BR-05) — Given two shipments inserted one after the other, When they are read back, Then each Name matches `^RC\d{9}$` and the second number is the first plus 1.
  *Mutation:* change the display format to `RC{00000000}` (8 digits) — observed: <filled by the worker>
- AC-F.3 (BR-03, data model) — Given Price__c 200 and Carrier_Cost__c 150, When Margin__c is read, Then it is 25%; given Price__c 400 and Carrier_Cost__c 100, Then it is 75%; given Price__c 0 or empty, Then it is empty.
  *Mutation:* remove the zero/empty guard from the formula, or use Carrier_Cost__c as the divisor — observed: <filled by the worker>
- AC-F.4 (D1, X16) — Given 251 new shipments inserted in one DML, one of them with a Delivery_Access_Code__c set by the caller, When they are read back, Then every shipment has a 10-character code from the alphabet `ABCDEFGHJKMNPQRSTUVWXYZ23456789`, all 251 codes are distinct, and the caller's value was replaced; an update of the shipment does not change its code.
  *Mutation:* make the generator return a constant code — observed: <filled by the worker>
- AC-F.5 (D4, AC-003.2) — Given a new shipment with Estimated_Delivery__c, When it is inserted, Then Original_Estimated_Delivery__c equals that date; When Estimated_Delivery__c is later updated, Then Original_Estimated_Delivery__c keeps the first date.
  *Mutation:* also copy the date on update — observed: <filled by the worker>
- AC-F.6 (AC-003.5 support) — Given the deployed Shipment__c, When FieldDefinition is queried, Then Status__c, Estimated_Delivery__c and Delivery_Instructions__c have IsFieldHistoryTracked = true, and Shipment__c has external sharing Private and Account external sharing Private.
  *Mutation:* set trackHistory false on Estimated_Delivery__c — observed: <filled by the worker>
- AC-F.7 (BR-03, S3) — Given a Standard Platform User with RutaCargo_Support_Agent, When they read, create and edit a shipment, Then it succeeds and they can read Carrier_Cost__c, Margin__c, Internal_Notes__c, Credit_Limit__c and Credit_Risk__c; and they cannot delete a shipment; Given the same kind of user without the permission set, Then Shipment__c is not accessible.
  *Mutation:* grant Delete on Shipment__c in the permission set — observed: <filled by the worker>
- AC-F.8 (BR-09, D1) — Given the same support agent, When the fields are described, Then Name, Margin__c, Delivery_Access_Code__c and Original_Estimated_Delivery__c are readable but not updateable.
  *Mutation:* grant edit on Delivery_Access_Code__c — observed: <filled by the worker>
- AC-F.9 (BR-01, policy guest) — Given the RutaCargo site, When the guest user's profile and any permission set assigned to the guest user are queried in ObjectPermissions, Then there are 0 rows; and an anonymous GET of the site's home URL returns 200 and a page that shows the RutaCargo logo.
  *Mutation:* grant Read on Shipment__c to the guest profile and deploy — observed: <filled by the worker>
- AC-F.10 (NFR visual identity) — Given the site theme and its static resources, When scripts/checks/brand-check.sh runs, Then it confirms the brand palette (#0D1F5F, #016BFA, #07E9F6, #D6E0EA), the Montserrat font face from the static resource, and the logo static resource are wired in the theme or the header component, and that no other external font or style host is referenced.
  *Mutation:* replace the primary brand color with the SLDS default blue — observed: <filled by the worker>
- AC-F.11 (DoD test data) — Given an org with the foundation metadata, When scripts/seed/seed.sh runs, Then there are the accounts Abarrotes Acme (Business, Low, 500,000) and Globex Farma (Business, High, 150,000), each with one contact (Ana López, Marta Ruiz), 60 shipments each with tracking numbers RC000001001–RC000001060 and RC000001061–RC000001120, all six statuses per customer, at least 10 Delivered per customer with Proof_Id__c and Delivered_At__c, and Price__c, Carrier_Cost__c and Internal_Notes__c on every shipment; When it runs a second time, Then nothing new is created; scripts/seed/verify.sh asserts all of it.
  *Mutation:* remove the idempotency check of the seed script and run it twice — observed: <filled by the worker>

## Task analysis
| Task | Solves | Acceptance | Scope (files to touch) | Security | Executor | Skills | Reviewers |
|---|---|---|---|---|---|---|---|
| T1 | S1 | AC-F.1, AC-F.2, AC-F.3, AC-F.6 | force-app/main/default/objects/Shipment__c/** (object, fields, list view All), force-app/main/default/objects/Account/fields/{Customer_Type__c,Credit_Limit__c,Credit_Risk__c}.field-meta.xml, force-app/main/default/objects/Account/Account.object-meta.xml (externalSharingModel only), force-app/main/default/settings/Apex.settings-meta.xml (only if needed for an independent test auto-number sequence), force-app/main/default/classes/ShipmentSchemaTest.cls(+meta), force-app/main/default/classes/TestDataFactory.cls(+meta) | yes | task-worker | salesforce-development:platform-custom-object-generate, salesforce-development:platform-custom-field-generate, salesforce-development:platform-value-set-generate, salesforce-development:platform-sharing-owd-configure, salesforce-development:platform-metadata-api-context-get, salesforce-development:platform-apex-test-generate, salesforce-development:platform-apex-test-run, salesforce-development:platform-metadata-deploy | task-reviewer, security-reviewer, access-auditor |
| T2 | S2 | AC-F.4, AC-F.5 | force-app/main/default/triggers/ShipmentTrigger.trigger(+meta), force-app/main/default/classes/ShipmentTriggerHandler.cls(+meta), force-app/main/default/classes/DeliveryAccessCode.cls(+meta), force-app/main/default/classes/ShipmentTriggerHandlerTest.cls(+meta), force-app/main/default/classes/TestDataFactory.cls | no | task-worker | salesforce-development:platform-apex-generate, salesforce-development:platform-apex-test-generate, salesforce-development:platform-apex-test-run, salesforce-development:platform-metadata-deploy, salesforce-code-quality:dx-code-analyzer-run | task-reviewer |
| T3 | S3 | AC-F.7, AC-F.8 | force-app/main/default/permissionsets/RutaCargo_Support_Agent.permissionset-meta.xml, force-app/main/default/tabs/Shipment__c.tab-meta.xml, force-app/main/default/applications/RutaCargo.app-meta.xml, force-app/main/default/classes/SupportAgentAccessTest.cls(+meta), force-app/main/default/classes/TestDataFactory.cls | yes | task-worker | salesforce-development:platform-permission-set-generate, salesforce-development:platform-custom-tab-generate, salesforce-development:platform-custom-application-generate, salesforce-development:platform-apex-test-generate, salesforce-development:platform-apex-test-run, salesforce-development:platform-metadata-deploy | task-reviewer, security-reviewer, access-auditor |
| T4 | S4 | AC-F.9, AC-F.10 | force-app/main/default/{networks,sites,digitalExperiences,digitalExperienceConfigs,navigationMenus,profiles (the site's guest profile only),staticresources,lwc/rcHeader,lwc/rcHome}/**, scripts/checks/brand-check.sh | yes | task-worker | experience-lwr-site-generate (marketplace), experience-lwc:experience-lwc-generate, experience-lwc:experience-lwc-security-validate, experience-lwc:experience-accessibility-validate, salesforce-development:platform-metadata-retrieve, salesforce-development:platform-metadata-deploy, salesforce-development:platform-soql-query | task-reviewer, security-reviewer, access-auditor |
| T5 | S5 | AC-F.11 | scripts/seed/** , README.md | no | task-worker | salesforce-development:platform-data-manage, salesforce-development:platform-apex-anonymous-run, salesforce-development:platform-soql-query | task-reviewer |

## Tasks
- [ ] T1 (S1): Account fields, Shipment__c object and fields, sharing models and field history — test first
- [ ] T2 (S2): Shipment trigger: delivery access code and original estimated delivery — test first
- [ ] T3 (S3): Support agent permission set, tab and app — test first
- [ ] T4 (S4): LWR site RutaCargo, locked-down guest profile, brand theme and header — test first
- [ ] T5 (S5): Idempotent seed and verify scripts, README run steps and assumptions — test first

## Assumptions
- A1 (D1): the delivery access code is stored in clear text with FLS restricted (support agents read it; the requesting customer will see it in REQ-006/007), because RutaCargo prints it on the label; no Shield encryption in a Developer org.
- A2: Account internal sharing stays as the org default; only its external model is set to Private.
- A3: Daily Brew is not in the repo; headings use Montserrat Black in uppercase. The logo PNGs are stand-ins, used only on their own background color.
- A4: Site users for the test customers are created by REQ-005 (it owns the customer profile and the account-owner role).

## Close
Stage: pending
