# RutaCargo — Shipping and Tracking

Salesforce DX implementation of [`docs/functional-design.md`](docs/functional-design.md): an Experience Cloud
(LWR) site where customers sign up and request door-to-door shipments, anyone tracks shipments, recipients
manage their delivery, and the EntregaYa carrier updates statuses through an API. The site follows the brand
manual in [`docs/brand-manual.pdf`](docs/brand-manual.pdf) (see [Brand](#brand)).

Development org: alias `rutacargoaopus` — site `https://force-data-3264-dev-ed.scratch.my.site.com/rutacargo`.

## Setup

```bash
npm install
TEST_USER_PASSWORD='<10+ chars, letters and numbers>' \
ENTREGAYA_API_KEY='<EntregaYa test key>' \
scripts/setup-org.sh <org-alias>
```

`scripts/setup-org.sh` is idempotent and does everything that can be automated:

1. Enables Digital Experiences and creates the **RutaCargo** site (Build Your Own LWR, path `/rutacargo`).
2. Deploys all metadata (the Network goes twice the first time: self-registration can only point at a member profile).
3. Gives the running admin the _RutaCargo Operations_ role (account owners need a role to have site users),
   stores it as owner of self-registered accounts (`RutaCargo_Settings__c`) and assigns _RutaCargo Site Guest_
   to the site guest user.
4. Loads the test data (`scripts/apex/load-test-data.apex`): Abarrotes Acme and Globex Farma, 60 shipments each
   (RC000001001–RC000001060 and RC000001061–RC000001120), all statuses, 15 Delivered with proof id per customer.
   Then creates the site users Ana López (`ana.lopez@abarrotes-acme.example`) and Marta Ruiz
   (`marta.ruiz@globex-farma.example`). Customers log in with their **email**.
5. Creates the EntregaYa integration user, sets it as run-as user of the _EntregaYa_ External Client App and
   stores the API key in the _EntregaYa_ External Credential (`scripts/setup-entregaya-key.sh`).
6. Publishes the site.

Run the tests: `sf apex run test -o <alias> --test-level RunLocalTests --code-coverage` (72 Apex tests,
93% coverage, one class per requirement, methods named after the acceptance criteria) and `npm test` (Jest).

## Manual steps pending in the org

| #   | Step                                                                                                                                                                                                                                                                                                                                                                | Why it is manual                                                                                                                                                       |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | **EntregaYa base URL**: Setup › Named Credentials › _EntregaYa_ › URL. Replace `https://replace-with-your-entregaya-mock.example.com` with the EntregaYa test (or mock) base URL.                                                                                                                                                                                   | The provider's ticket gives no real URL ("REPLACE-WITH-YOUR-MOCK"). Until it is set, "Download proof of delivery" shows the AC-002.5 retry message.                    |
| 2   | **Send EntregaYa its credentials**: Setup › External Client App Manager › _EntregaYa_ › Settings › OAuth Settings › _Consumer Key and Secret_. Send key, secret, token URL `https://<my-domain>/services/oauth2/token` (grant `client_credentials`) and endpoint `POST https://<my-domain>/services/apexrest/entregaya/v1/status-updates` through a secure channel. | The consumer secret cannot be retrieved through the API.                                                                                                               |
| 3   | **Company currency → MXN**: Setup › Company Information › Currency Locale / Corporate currency.                                                                                                                                                                                                                                                                     | The scratch org was created in USD; amounts are MXN by design. The site always formats them as MXN; internal pages show the org currency symbol until this is changed. |
| 4   | **Email deliverability** (Setup › Deliverability › _All email_) and a verified **sender address** for the site (Administration › Emails; `noreply@rutacargo.example` is a placeholder).                                                                                                                                                                             | Needed for the password-reset email (AC-005.6).                                                                                                                        |
| 5   | **Password policy of the RutaCargo Customer profile**: minimum length 10, "letters and numbers".                                                                                                                                                                                                                                                                    | AC-005.4 is enforced at sign-up in Apex; this makes resets follow the same rule.                                                                                       |
| 6   | **Licenses**: the dev org has 5 _Customer Community Login_ licenses (2 used by test users, 1 by a sign-up test). Production needs enough for the expected customers.                                                                                                                                                                                                | Licensing.                                                                                                                                                             |
| 7   | **Rotate the EntregaYa API key** before production.                                                                                                                                                                                                                                                                                                                 | The test key is written in plain text in `docs/functional-design.md`.                                                                                                  |
| 8   | Optional: the **Daily Brew** display font (brand manual) as a static resource, and the official SVG/transparent logos.                                                                                                                                                                                                                                              | Not provided in the repo; see [Brand](#brand).                                                                                                                         |

## Architecture

| Area                  | Main pieces                                                                                                                                                                                                                                                                                                                                 |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Data model            | `Account` (+ `Customer_Type__c`, `Credit_Limit__c`, `Credit_Risk__c`), `Shipment__c` (fields of the design + `Original_Estimated_Delivery__c`, `Verification_Failures__c`, `Verification_Locked_Until__c`). `Name` is an auto number `RC{000000000}` (BR-05). History tracking on status, dates, instructions, reschedule count (AC-003.5). |
| REQ-001 tracking      | `PublicTrackingController`, LWC `rcTracking` (also opens with `?tracking=RC…` / `?reference=…`, for the QR code on the label).                                                                                                                                                                                                              |
| REQ-002/003 recipient | `RecipientDeliveryController` → `RecipientDeliveryService`, `EntregaYaProofClient` (Named Credential `EntregaYa`, 10 s timeout), LWC `rcDeliveryDetails`.                                                                                                                                                                                   |
| REQ-004 carrier       | `EntregaYaStatusResource` (Apex REST) → `ShipmentStatusUpdateService`. OAuth 2.0 client credentials through the _EntregaYa_ External Client App, run as the _EntregaYa Integration_ user. Simulate it with `scripts/entregaya/send-status-update.sh`.                                                                                       |
| REQ-005 sign-up/login | `CustomerAuthController` (`Site.createExternalUser`, `Site.login`, `Site.forgotPassword`), LWC `rcRegister`, `rcLogin`, `rcForgotPassword`. Profile _RutaCargo Customer_.                                                                                                                                                                   |
| REQ-006/007 customer  | `CustomerShipmentController`, `ShipmentRequestService`, `ShipmentPricing` (BR-08), `RutaCargoDates` (BR-06, business days), LWC `rcShipmentRequest`, `rcMyShipments`, `rcShipmentDetail`.                                                                                                                                                   |
| Site                  | DigitalExperienceBundle `RutaCargo1`: public Home/Login/SelfRegister/ForgotPassword pages; `request-shipment`, `my-shipments` and `shipment` require login. Header/footer: `rcHeader`, `rcFooter`.                                                                                                                                          |

### Security model

- **No object permissions for site users.** Guest and customer users get no access to `Shipment__c` and no field
  permissions on internal fields. Every read and write goes through Apex controllers that run in explicit
  `SYSTEM_MODE`, scope the data themselves and return DTOs with only the allowed fields: public fields of BR-01 for
  visitors, the recipient's data only after the postal code check (BR-02), the customer's own shipments only (BR-07),
  never cost, margin, notes or credit data (BR-03). Tests assert the DTOs contain none of those values.
- **API 67 runs Apex SOQL/DML in user mode by default** for these users. That is why the controllers say
  `WITH SYSTEM_MODE` / `AccessLevel.SYSTEM_MODE` explicitly: the controller _is_ the access control.
- **Recipient check.** Every recipient call re-verifies the destination postal code on the server. A 5-digit code is
  guessable, so 5 wrong codes lock the shipment's details for 15 minutes (`Verification_*` fields).
- **BR-04.** Only the _EntregaYa Integration_ permission set grants the REST class (a test asserts it).
- Login redirects only accept site-relative paths; password reset answers the same for any email.

## Decisions and assumptions

- **Original estimated date** (AC-003.2): stored on the first reschedule, so the window stays "next day … original
  estimate + 7 days" after a reschedule. Every saved reschedule counts toward the limit of 2.
- **Business days** are Monday–Friday; Mexican public holidays are not excluded (can be added with Business Hours/Holidays).
- **Price per kg** uses the exact weight (2.5 kg × 18 MXN), rounded to cents.
- **Order references** are not unique across customers; a reference search returns every match (BR-01 allows it),
  capped at 20 per reference.
- **Carrier updates**: statuses are matched case-insensitively; an update with the same timestamp as the last one is
  applied, an older one is ignored with HTTP 200 `IGNORED`; `proofId` is stored when the status is Delivered.
- **Request date** in "My shipments" is the record's creation date (all test shipments share the load date).

## Brand

The design asks to apply the _Coffee Blazers Summit_ Brand Manual to the RutaCargo site — that brand belongs to a
different (community event) identity, and its logo reads "Coffee Blazers Summit". It was applied as instructed;
confirm with the business that this is intended before going live.

- Colours: night blue `#0D1F5F` (text, footer), electric blue `#016BFA` (actions), cyan `#07E9F6` (Delivered,
  focus ring), enamel gray `#D6E0EA`; the tricolor yellow/red only as small details (footer stripe, exception dot),
  never as background. Shared tokens: `lwc/rcBrand/rcBrand.css`.
- Type: Montserrat (Google Fonts, allowed by CSP Trusted Sites). The display face _Daily Brew_ is not available as a
  web font, so short uppercase headlines use Montserrat Black.
- Logos (`docs/brand/*.png` as static resources) are used only on their own background colour, never stretched.
  The main logo is never shown below 360 px wide: mobile shows the isotype (Tinto) on electric blue in the header,
  the full colour logo appears in the home hero (≥ 900 px) and the negative logo in the footer (≥ 420 px).
