# RutaCargo: shipping and tracking

Implementation of `docs/functional-design.md` as a Salesforce DX project: an Experience Cloud (LWR) site with a public
area (track, delivery details, proof of delivery, reschedule) and a customer area (sign up, log in, request a shipment,
my shipments), plus the EntregaYa integration. Visual identity follows `docs/brand-manual.pdf`.

Deployed and verified in the scratch org alias `rutacargoasonnet`.
Site: `https://flow-momentum-5385-dev-ed.scratch.my.site.com/rutacargo`

## What is where

| Area | Source |
| --- | --- |
| Data model (Account fields, `Shipment__c`, `Shipment_Change__c`) | `force-app/main/default/objects` |
| Public pages Apex (guest) | `PublicTrackingController`, `AuthController` |
| Customer pages Apex | `CustomerPortalController` |
| EntregaYa inbound (REST) / outbound (callout) | `EntregaYaStatusResource`, `EntregaYaClient` + Named/External Credential `EntregaYa` |
| Rules shared by all | `ShipmentRules` (Mexico City dates, business days, validators), `ShipmentPricing` (BR-08) |
| LWC | `lwc/rc*` (`rcTheme` = brand tokens, `rcUtils` = helpers) |
| Site | `digitalExperiences/site/RutaCargo1`, `digitalExperienceConfigs`, `networks`, `sites`, `cspTrustedSites` |
| Security | permission sets `RutaCargo_Support`, `RutaCargo_Public_Site`, `RutaCargo_EntregaYa_Integration`; profile `RutaCargo Customer`; custom permission `EntregaYa_Integration` |
| Tests / data | Apex tests (`*Test`), `scripts/load-test-data.sh` |

Public URLs for the QR code on labels: `/track?tn=RC000001042` (searches immediately) and `/delivery?tn=RC000001042`.

## Deploy to a new org

```bash
sf org create scratch -f config/project-scratch-def.json -a rutacargo   # country MX, Communities enabled
sf project deploy start -o rutacargo -d force-app
sf community publish -o rutacargo -n RutaCargo
scripts/load-test-data.sh rutacargo      # permission sets, owner role, 2 customers + users, 120 shipments
```

**Load the test data before running Apex tests.** Tracking numbers are an auto-number (`RC` + 9 digits, starting at 1001);
numbers are never reused, so tests that insert shipments would shift the loaded data off `RC000001001..RC000001120`.
The script prints the (random) password of the two test users in a `TESTUSER` line: `ana.lopez@example.com`,
`marta.ruiz@example.com`.

## Pending manual steps (not possible from source)

1. **EntregaYa base URL.** The provider's URL in the ticket is still a placeholder (`REPLACE-WITH-YOUR-MOCK`). Edit
   Setup > Named Credentials > EntregaYa > URL. Until then, "Download proof of delivery" shows the AC-002.5 message
   (it is covered by tests with a mock).
2. **EntregaYa API key.** Setup > Named Credentials > External Credentials > EntregaYa > principal `EntregaYaKey` >
   add an authentication parameter named `ApiKey` with the key from the provider ticket. Secrets are not deployable and
   the key is deliberately **not** in this repo. (The Named Credential sends `Authorization: Bearer {ApiKey}`.)
3. **EntregaYa to Salesforce authentication.** The provider supports OAuth 2.0 client credentials. Create an External
   Client App / Connected App with the client-credentials flow, run as a dedicated integration user holding the
   permission set `RutaCargo EntregaYa Integration`, and send EntregaYa the endpoint
   `POST https://<my-domain>/services/apexrest/entregaya/v1/status` and the token URL. Only users with that permission
   set can post (BR-04); anyone else gets 403.
4. **Password-reset email** (AC-005.6) needs working email deliverability and the site's sender address verified.
5. **Production sizing/licensing.** The scratch org has 5 Customer Community licenses; production needs one per
   expected customer login (or Login-based licenses). Sign-up accounts are owned by the site's default record owner,
   which must hold a role (`scripts/apex/setup-owner-role.apex` does it for the admin in a dev org); use a dedicated user.
6. **Brand assets.** `docs/brand/*.png` are stand-ins with solid backgrounds (see `docs/brand/README.txt`); each is
   used only on the background it was cropped from. Replace with the official SVG files when available. The
   display typeface *Daily Brew* has no font file in the repo, so headlines fall back to Montserrat Black (uppercase)
   until it is added as a static resource. Montserrat loads from Google Fonts (CSP-trusted sites are deployed).
7. **Org currency / time zone.** The scratch org was created in USD and Los Angeles time (the definition now sets
   `country: MX` for new orgs). The site always shows MXN and Mexico City time (BR-06) regardless.
8. **Page layouts.** Support agents get the new fields through the permission set; add `Customer Type`, `Credit
   Limit` and `Credit Risk` to the Account page layout and the `Delivery Changes` related list to the Shipment layout.

## Decisions and deviations worth knowing

- **Guest Apex is explicit system mode.** Guest users ignore `without sharing`, so public queries/DML use
  `WITH SYSTEM_MODE` / `AccessLevel.SYSTEM_MODE`. Guests have no record sharing, so nothing is readable except through
  `PublicTrackingController`, whose DTOs only contain the BR-01 fields (search) or require the postal code (BR-02).
- **Postal code is a weak secret (5 digits).** Added throttling: 5 wrong guesses lock the shipment's delivery details
  for 15 minutes (`Failed_Verifications__c`, `Verification_Locked_Until__c`). Consider a stronger check than the
  postal code. Order references are also not unique, so a reused reference returns every matching shipment's public data.
- **`Original_Estimated_Delivery__c`** was added so the 7-day reschedule window is measured from the *original* date
  (AC-003.2) and cannot be chained. A reschedule must change the date.
- **`Shipment_Change__c`** (one row per reschedule, with old/new date and instructions; created date = when) satisfies
  AC-003.5 for support agents.
- Wrong postal codes and reschedule rule violations are returned as an `error` field instead of thrown: a thrown error
  would roll back the throttle counter, and the Experience runtime replaced some thrown messages with a generic one.
- Typed Apex wrapper parameters were not bound by the LWR Apex endpoint, so `signUp` and `createShipment` take a
  `Map<String, Object>`.
- Business days are Monday to Friday; Mexican public holidays are not modelled.
- Usernames are `<email>.rutacargo` (usernames are unique across all Salesforce orgs); customers log in with their email.
- `Daily Brew` and logo minimum size: the main logo is rendered at 360 px wide, shrinking only on screens narrower than that.

## Verification done

- Apex: 5 test classes, all passing; 91% org-wide coverage, at least 82% for each RutaCargo class. Tests are traced to
  AC/BR ids in comments.
- Guest flows against the live site: tracking (case/space tolerant, not-found list, 10-value limit), delivery details,
  postal-code mismatch and lockout, reschedule rules, proof-of-delivery error path, sign-up (account + contact + user),
  duplicate email, bad login.
- Headless Chrome at phone width: home, tracking via QR link, log in as a test customer, my shipments (25 per page),
  request a shipment (price shown before confirming, tracking number returned).
- EntregaYa endpoint with curl: update, ignore older, delivered + proof, unknown tracking (404), invalid status (400),
  invalid JSON (400), caller without the permission (403, in tests).
- **Not verified:** the real EntregaYa proof download (no mock URL yet), password-reset email delivery, LWC Jest tests
  (none written; `npm test` has nothing to run), and ESLint/Prettier (dependencies not installed here).
