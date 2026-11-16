# Feature: RutaCargo Shipping and Tracking

- **Objective:** Implement docs/functional-design.md in the scratch org `rutacargobsonnet`, following docs/brand-manual.pdf.
- **Branch:** Sonnet-skills
- **Test runner:** Apex, `sf apex run test` against rutacargobsonnet (Jest only for LWC).

## Specs

- S1 (AC-001.1) The visitor chooses to search by tracking number or by order reference, and can enter up to 10 values separated by commas or line breaks.
- S2 (AC-001.2) For each shipment found, the site shows: tracking number, status, origin city, destination city, last location, date of the last update and estimated delivery date.
- S3 (AC-001.3) Values that do not match any shipment are listed as "Not found".
- S4 (AC-001.4) Results can be sorted by status or by estimated delivery date.
- S5 (AC-001.5) The search ignores case and leading or trailing spaces.
- S6 (AC-002.1) From a tracking result, the recipient enters the destination postal code to open the delivery details.
- S7 (AC-002.2) The details show: recipient name, delivery address, contact phone, estimated date and delivery instructions.
- S8 (AC-002.3) If the postal code does not match, the site shows "The details do not match this shipment".
- S9 (AC-002.4) When the shipment is Delivered, "Download proof of delivery" fetches from EntregaYa the PDF with the signature of the person who received it. The PDF is not stored in Salesforce.
- S10 (AC-002.5) If EntregaYa does not respond, the site shows "We could not get the proof of delivery, please try again later".
- S11 (AC-003.1) From the delivery details, the recipient can choose a new date and edit the delivery instructions.
- S12 (AC-003.2) The new date must be between the next day and 7 calendar days after the original estimated date.
- S13 (AC-003.3) Only a shipment in Picked up or In transit status can be rescheduled.
- S14 (AC-003.4) A shipment can be rescheduled at most 2 times.
- S15 (AC-003.5) On save, the new date is shown, and the support agent can see in Salesforce when each change was made.
- S16 (AC-004.1) EntregaYa sends Salesforce every status change: tracking number, new status, location, and date and time.
- S17 (AC-004.2) Salesforce updates the status, the last location and the last update date of the shipment. With the Delivered status, the moment of delivery and the proof of delivery identifier are also saved.
- S18 (AC-004.3) A nonexistent tracking number or an invalid status is rejected with a clear error message for EntregaYa.
- S19 (AC-004.4) If an update arrives that is older than the last one recorded, it is ignored.
- S20 (AC-005.1) The sign-up form asks for: customer type (individual or business), name or legal name, first and last name of the contact person, email, phone and password.
- S21 (AC-005.2) Signing up creates the customer in Salesforce: an account with its contact.
- S22 (AC-005.3) An email can have only one account. If it is already registered, a message is shown and login is offered.
- S23 (AC-005.4) The password must have at least 10 characters, with letters and numbers.
- S24 (AC-005.5) The customer logs in with their email and password, and can log out.
- S25 (AC-005.6) If they forget their password, they can reset it with a link they receive by email.
- S26 (AC-006.1) The form asks for: pickup address, city and postal code; pickup date; recipient name, address, city, postal code, phone and email; service type (Standard or Express); weight in kg; description of the contents; declared value; and, optionally, an order reference and delivery instructions.
- S27 (AC-006.2) Before confirming, the customer sees the shipment price according to the current rate (BR-08).
- S28 (AC-006.3) The pickup date must be a business day between the next day and 15 days later.
- S29 (AC-006.4) The maximum weight is 30 kg and the maximum declared value is 50,000 MXN.
- S30 (AC-006.5) On confirmation, the shipment is created under the customer, in Requested status and with its tracking number, which is shown on screen.
- S31 (AC-006.6) The estimated delivery date is the pickup date plus 5 business days for Standard and plus 2 for Express.
- S32 (AC-007.1) The list shows the customer's shipments: tracking number, request date, recipient, destination city, status, service type and price, most recent first.
- S33 (AC-007.2) The list can be filtered by status and searched by tracking number, recipient or reference.
- S34 (AC-007.3) Each shipment has a detail page with the data the customer entered, the price and the current status.
- S35 (BR-01..BR-09) Business rules apply to every requirement and win over any AC (visibility, internal data, EntregaYa-only status updates, tracking number format, Mexico City time, own-data only, rate, initial status).
- S36 (NFR) Brand: site applies the Coffee Blazers Summit brand manual (colors, Montserrat/Daily Brew, logo versions and usage); mobile first.

## Tasks

- T1 | S35 | Data model: Account fields, Shipment__c, Delivery_Change__c | done (deployed 41 components, 0 errors) | see git log
- T2 | S35 | Permission sets, custom permission, guest/external access config | done (Permission sets, profile, role, custom permission deployed) | see git log
- T3 | S27,S28,S29,S31 | Pricing + date services (Apex, tests) | done (9 tests pass) | see git log
- T4 | S1-S5 | Public tracking Apex + tests | done (tests pass) | see git log
- T5 | S6-S10 | Delivery details + proof (Named Credential, callout, tests) | done (tests pass (callout mocked)) | see git log
- T6 | S11-S15 | Reschedule Apex + tests | done (tests pass) | see git log
- T7 | S16-S19 | Inbound EntregaYa REST service + OAuth External Client App + tests | done (tests pass; OAuth External Client App pending (T13/README)) | see git log
- T8 | S20-S25 | Sign-up / login / reset Apex + tests | done (tests pass; sign-up setPassword needs verified sender (manual)) | see git log
- T9 | S26-S34 | Request shipment + my shipments Apex + tests | done (tests pass) | see git log
- T10 | S36 | Brand assets, theme, LWCs | done (LWCs, brand CSS, static resource deployed; Jest not written) | see git log
- T11 | S36 | Experience Cloud LWR site | done (site Live, published; public home 301, login 200) | see git log
- T12 | S35 | Test data script (120 shipments) | todo | -
- T13 | all | Reviewers, README, close | todo | -

## Log

- L1: Implement the functional design in docs/functional-design.md in the org ALIAS, following the brand manual in docs/brand-manual.pdf
- L2 (assumption): "ALIAS" is an unfilled placeholder. Used `rutacargobsonnet`, the project default target org (memory + sf config).
- L3 (assumption): Customer-facing and public Apex runs in system mode (Shipment__c stays Private and is not shared with guest/external users); each method derives the caller's account from the running user, never from client input, and returns DTOs with only the permitted fields.
- L4 (assumption): "original estimated date" in AC-003.2 is the estimate at creation (stored in Original_Estimated_Delivery__c), the narrower interpretation.
- L5 (assumption): Business day = Monday to Friday; no holiday calendar.
- L6 (assumption): Postal-code verification is limited to 5 failed attempts, then locked 15 minutes, to stop brute force of the 5-digit code.
- L7 (assumption): EntregaYa may send Picked up, In transit, Out for delivery, Delivered, Exception; "Requested" is rejected as invalid (BR-09).
- L8 (note): docs/functional-design.md contains a provider test API key in clear text. It must not be copied to code or metadata; it goes in the External Credential secret by hand. Recommend rotating it and removing it from the doc.
- L9 (note): Daily Brew font file was not provided; display headlines fall back to Montserrat Black uppercase until the font file is supplied.
- L10: Backend (T2-T9) deployed; full local test run: 73/73 pass, org-wide coverage 87%.
- L11 (decision): guest cannot hold External Credential principal access (it exists only on permission sets), so EntregaYa uses a legacy Named Credential; its password field (placeholder REPLACE-IN-SETUP in metadata) holds the API key, entered by hand.
- L12 (finding): the unfiled `sf community create` site has an unverified sender address (jhony...@adaptus.com.invalid); System.setPassword fails until the sender is verified in Setup. Sign-up tests bypass setPassword via a @TestVisible flag.
- L13 (finding): the salesforce-metadata-experts MCP server failed to connect (HTTP 404), so site pages/views are written by hand from the retrieved default content instead of getSiteContentMetadata schemas.
- L14 (finding): anonymous Apex cannot use SYSTEM_MODE, so the test-data script uses plain DML with the Support Agent permission set.
- L15: Site URL https://flow-drive-2236-dev-ed.scratch.my.site.com/rutacargovforcesite (prefix rutacargovforcesite is assigned by the org; DigitalExperienceConfig prefix is rutacargo). Custom route ids need the __c suffix.
