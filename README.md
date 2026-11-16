# RutaCargo Shipping and Tracking

Salesforce DX project: an Experience Cloud (LWR) site where visitors track shipments, recipients manage their delivery,
customers sign up and request door-to-door shipments, and the carrier EntregaYa posts status changes.
Design: `docs/functional-design.md`. Brand: `docs/brand-manual.pdf` (Coffee Blazers Summit). Work log: `odd/tasks/rutacargo-shipping-tracking.md`.

- Target org used: scratch org alias `rutacargobsonnet` (the prompt said `ALIAS`; see assumption A1).
- Site: https://flow-drive-2236-dev-ed.scratch.my.site.com/rutacargovforcesite (Live, published).

## What is built

| Area | Where |
| --- | --- |
| Data model: `Shipment__c`, `Delivery_Change__c` (reschedule audit trail), Account fields | `force-app/main/default/objects` |
| Business rules (price BR-08, business days, limits, passwords) | `ShipmentRules` |
| Public tracking, recipient details / proof / reschedule | `TrackingService`, `RecipientService`, `EntregaYaClient` |
| Inbound carrier status (REST) | `EntregaYaStatusRestResource`, `ShipmentStatusService` |
| Sign-up, shipment request, my shipments | `CustomerService`, `RutaCargoController` (single entry point for the LWCs) |
| Access | Profiles `RutaCargo Profile` (guest) and `RutaCargo Customer`; permission sets `RutaCargo_Support_Agent`, `RutaCargo_EntregaYa_Integration`; custom permission `EntregaYa_Status_Update` |
| Site and brand | `digitalExperiences`, `lwc/rc*`, static resource `RutaCargoBrand` (Montserrat + logos) |
| Test data | `scripts/setup-org.sh`, `scripts/apex/*.apex` |

## Set up an org

```bash
sf project deploy start --source-dir force-app --target-org <alias>
scripts/setup-org.sh <alias>                 # permission set + owner role for the running user, loads 2 customers and 120 shipments
sf apex run --file scripts/apex/create-site-users.apex --target-org <alias>      # Ana Lopez / Marta Ruiz site users; random passwords are printed once in the log
sf apex run --file scripts/apex/create-integration-user.apex --target-org <alias>
sf community publish --name RutaCargo --target-org <alias>
sf apex run test --test-level RunLocalTests --target-org <alias> --code-coverage --result-format human --wait 20
```

## Manual steps that remain pending in the org

1. **EntregaYa API key and base URL.** Setup > Named Credentials > `EntregaYa` (legacy): set the URL to the mock/real base URL
   (metadata holds the placeholder `https://REPLACE-WITH-YOUR-MOCK`) and enter the API key as the **password**
   (metadata holds the placeholder `REPLACE-IN-SETUP`). Until then the proof-of-delivery download answers "We could not get the proof of delivery, please try again later".
2. **Inbound OAuth.** Setup > External Client App Manager > `EntregaYa Status` > Policies: confirm the run-as user is
   `entregaya.integration@rutacargo.example.com`; copy the consumer key and secret and give them to EntregaYa through a secure channel.
   Token URL: `https://<my-domain>/services/oauth2/token`, grant type `client_credentials`; service URL: `/services/apexrest/entregaya/v1/status`.
3. **Sender address.** Setup > Digital Experiences > Settings / Emails: verify the sender address (the site was created with
   `jhony.atehortua@adaptus.com.invalid` as sender and `jhony.atehortua@adaptus.com` as the pending new sender). Password-reset emails need it.
4. **Rotate the provider test key.** `docs/functional-design.md` contains EntregaYa's test API key in clear text and is committed. Rotate it with the provider and remove it from the document.
5. **Daily Brew font.** Not supplied. Display headlines use Montserrat Black in capitals; add the font file to the `RutaCargoBrand` static resource and load it in `rcHeader`.
6. **Official logos.** `docs/brand/*.png` are stand-ins with solid backgrounds (see `docs/brand/README.txt`). Replace them with the official vector/transparent files.
7. **Old External Credential.** An earlier `EntregaYa` External Credential created while experimenting may still exist in the scratch org (not in the repo); delete it in Setup if it shows.
8. **Org time zone.** The scratch org runs in America/Los_Angeles; the code and the UI use America/Mexico_City explicitly (BR-06). Set the org default if reports should match.
9. **Salesforce metadata MCP servers** (`salesforce-metadata-experts`, `salesforce-metadata-grounding`) failed to connect during the build (HTTP 404), so site pages were written by hand from the retrieved default content instead of from `getSiteContentMetadata` schemas. Open the site in Experience Builder once and publish from there to confirm every page renders.

## Assumptions (most conservative option, recorded as the workflow requires)

- A1. `ALIAS` is an unfilled placeholder; `rutacargobsonnet` is the project's default target org.
- A2. Shipment__c is Private and shared with nobody external. Guest, recipient and customer flows run in system mode inside the services only,
  each method restricting rows itself (tracking number or reference, postal code, or the caller's account derived from the logged-in user). Every such class states its sharing mode and justifies it.
- A3. "Original estimated date" (AC-003.2) is the estimate at creation (`Original_Estimated_Delivery__c`).
- A4. Business day = Monday to Friday; no holiday calendar.
- A5. Postal-code verification locks a shipment for 15 minutes after 5 wrong attempts (5-digit codes are easy to brute force). A third party could use this to lock a recipient out for 15 minutes; accepted as the safer side.
- A6. EntregaYa may send Picked up, In transit, Out for delivery, Delivered, Exception. `Requested` is rejected as invalid (BR-09). A Delivered update without `proofId` is accepted and leaves the proof id empty.
- A7. Older-than-last updates (AC-004.4) are acknowledged with HTTP 200 and ignored, so the carrier does not retry them.
- A8. Login is by email: the username is `<email>.rutacargo`; the login form maps the email to the username on the server.
- A9. The guest cannot hold External Credential principal access, so the proof callout uses a legacy Named Credential (API key as its password).
- A10. Unknown tracking numbers and wrong postal codes return the same message, so the details endpoint does not confirm which one was wrong.
- A11. Test classes use API 66.0 so plain SOQL/DML in tests stays in system mode; production classes use API 67.0 with explicit `WITH SYSTEM_MODE` / `AccessLevel.SYSTEM_MODE`.

## Known residual risks (recorded because they are not resolved)

- **Postal-code spraying (High, accepted with reason).** The recipient is verified only by the 5-digit destination postal code (AC-002.1/BR-02) and tracking numbers are sequential (BR-05). The lock (5 failures, 15 minutes) is per shipment, so one caller can try one code across many shipments, and 10 postal codes can cover many shipments of a dense city. A control that closes this changes the design (a second factor such as the recipient phone's last 4 digits) or sits outside Apex (Experience Cloud guest rate limiting, a WAF, CAPTCHA). Decide with the business before go-live.
- **Sign-up is unthrottled and reveals which emails are registered.** The reveal is required by AC-005.3; add CAPTCHA or rate limiting and consider email verification.
- **Lock-out denial of service.** Anyone can keep a shipment locked by sending wrong codes (A5).
- **Hard-coded scratch-org users in metadata.** `sites/RutaCargo.site-meta.xml` (siteAdmin, siteGuestRecordDefaultOwner) and the ECA policy (`clientCredentialsFlowUser`) name users of this scratch org. Adjust them for any other org before deploying.
- **Internal visibility.** Support agents have view-all on Shipment (every agent serves every customer); internal OWD on Account/Contact is Public Read/Write, so credit fields are readable by other internal profiles. Tighten if more internal profiles are added.
- **Brand.** Branding set still carries platform tint slots outside the 7-color palette; Too Many Requests and Service Not Available pages keep Salesforce stock illustrations; the `@font-face` for Montserrat in `styles.css` was not verified in a browser.
- **No CI.** Tests and Code Analyzer run by hand. Code Analyzer reports High findings on the five intentional system-mode classes (ApexFlsViolation, DatabaseOperationsMustUseWithSharing); each class justifies its mode in its header.
- **Personal email address** is in the External Client App `contactEmail` and this README; replace with a team mailbox.

## Verification status

See `odd/tasks/rutacargo-shipping-tracking.md` (Log) for evidence and reviewer verdicts. Local tests: 90 of 90 pass, 91% org-wide coverage. Live checks done: the EntregaYa status endpoint answered 403/200/404/400/ignored-older as specified; test data counts match the design. Known gaps: no browser-driven end-to-end run of the site
(sign-up, login, request, proof download with the real EntregaYa) was possible from the CLI; LWC Jest tests were not written; the OAuth token exchange with the generated consumer key was not exercised.
