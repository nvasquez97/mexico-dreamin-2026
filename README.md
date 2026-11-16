# RutaCargo — Shipping and Tracking site

Experience Cloud (LWR) site where customers sign up and request door-to-door
shipments, anyone tracks shipments, recipients manage their delivery, and the
last-mile carrier EntregaYa updates statuses. Requirements:
[docs/functional-design.md](docs/functional-design.md). Brand:
[docs/brand-manual.pdf](docs/brand-manual.pdf) and [docs/brand/](docs/brand/).
Work tracking (specs, tasks, commits, decisions, reviewer verdicts):
[odd/tasks/rutacargo-shipping-tracking.md](odd/tasks/rutacargo-shipping-tracking.md).

## What is in the project

| Area | Metadata |
| --- | --- |
| Data model | `Shipment__c` (tracking number `RC` + 9 digits, auto-number), Account customer fields, `Shipping_Rate__mdt` (BR-08 rate), `RutaCargo_Settings__c` |
| Public tracking and recipient self-service | `PublicTrackingController`, `DeliveryController`, `DeliveryAccessService`, `EntregaYaClient` |
| Customers | `CustomerAuthController` (sign-up, login, reset), `ShipmentRequestController`, `MyShipmentsController` |
| Carrier updates | `EntregaYaStatusResource` — `POST /services/apexrest/entregaya/v1/shipment-status` |
| Site | `digitalExperiences/site/RutaCargo1`, LWC `rc*`, static resource `rcBrand` (Montserrat + logo files) |
| Access | Permission sets `RutaCargo_Guest`, `RutaCargo_Customer`, `RutaCargo_Support_Agent`, `EntregaYa_Integration`; profile `RutaCargo Customer`; sharing set `RutaCargo Customers`; external client app `EntregaYa_Status_Updates` |
| Outbound | Named Credential + External Credential `EntregaYa` (proof of delivery) |

## Deploy and load test data

The development org is the scratch org `rutacargo-b-opus` (see `.mem/memory.md`).

```bash
sf project deploy start --source-dir force-app --target-org rutacargo-b-opus
scripts/seed/seed.sh rutacargo-b-opus      # idempotent; PASSWORD_FILE=/path writes the site users' password to a file
sf apex run test --test-level RunLocalTests --code-coverage --target-org rutacargo-b-opus
sf community publish --name RutaCargo --target-org rutacargo-b-opus
```

Deploy order notes:

- On a new org, deploy the Network with `RutaCargo Customer` as a member **before** setting it as the
  self-registration profile (the platform rejects a self-registration profile that is not a member yet).
- Run the seed **after** deploying and **before** running the Apex tests on a fresh org, so the
  shipment auto-number starts at RC000001001 as in the test data (tests also consume auto-numbers).

Test site users (created by the seed): `ana.lopez@abarrotes-acme.example` (Abarrotes Acme) and
`marta.ruiz@globex-farma.example` (Globex Farma). Their password is generated on each seed run and is
never stored in the repository.

## Manual steps still pending in the org

1. **EntregaYa API key and URL (proof of delivery).** In Setup > Named Credentials:
   - Named Credential `EntregaYa`: replace the placeholder URL `https://replace-with-your-mock.invalid`
     with the EntregaYa base URL (or the test mock).
   - External Credential `EntregaYa` > principal `EntregaYaPrincipal`: add the authentication parameter
     `ApiKey` with the key. The header `Authorization: Bearer {ApiKey}` is built by the credential.
   - Until this is done, "Download proof of delivery" shows "We could not get the proof of delivery,
     please try again later" (AC-002.5).
2. **Rotate the EntregaYa test key.** The provider's key is written in plain text in
   `docs/functional-design.md`, which is committed to this repository. Ask EntregaYa for a new key and
   remove the old one from the document and the git history.
3. **EntregaYa OAuth credentials (status updates).** Setup > External Client App Manager >
   `EntregaYa Status Updates` > Settings > OAuth Settings > Consumer Key and Secret. Send them to
   EntregaYa through a secure channel together with the token URL (`https://<my-domain>/services/oauth2/token`,
   grant `client_credentials`) and the endpoint above. To simulate EntregaYa:
   `SF_MY_DOMAIN=... ENTREGAYA_CLIENT_ID=... ENTREGAYA_CLIENT_SECRET=... scripts/entregaya/send-status.sh RC000001042 "Out for delivery" "Monterrey, NL"`.
4. **Run-as user of the OAuth app is org-specific.** `extlClntAppOauthPolicies/EntregaYa_Status_Updates_defaultPolicy`
   names `entregaya.integration@<orgId>.rutacargo.example`, the user the seed creates. On another org,
   change it to that org's integration user before deploying.
5. **Org currency.** The org currency is USD; the design asks for MXN. In Setup > Company Information,
   set the currency locale to Spanish (Mexico) / MXN. The site already formats every amount as MXN.
6. **Site email sender.** The Network sender address is the scratch org admin's email. Set a
   RutaCargo address (Setup > Digital Experiences > RutaCargo > Administration > Emails) before going live.
7. **Remove the Chatter tab from the site.** Experience Workspaces > Administration > Tabs (or Pages):
   the org still lists the standard Chatter tab, which a metadata deploy does not remove. Member
   visibility and messages are already off.
8. **Official logo files.** `docs/brand/*.png` are stand-ins cropped from the manual. Replace them (and
   `staticresources/rcBrand/img`) with the official SVG or transparent PNG files. The display typeface
   Daily Brew is not available as a web font, so headlines use Montserrat Black, which the manual
   assigns to headlines.

## Known limits

- Tracking numbers are consecutive (BR-05), so anyone can enumerate the public status of shipments.
  This is what BR-01 allows: only the AC-001.2 fields are public.
- Recipient access is protected by the 5-digit destination postal code. From the 5th wrong code each
  further wrong code locks the shipment's delivery details for 15 minutes, and from the 10th for 24
  hours. While a lock is active even the right code is refused; after it expires, the right code clears
  the count. Anyone who knows a tracking number can keep a shipment locked, so a support agent can
  unlock it by clearing "Failed Verification Attempts" and "Verification Locked Until" on the shipment.
  Bot protection on the recipient form is recommended before going live.
- Sign-up has no bot protection or email verification, and each sign-up uses a Customer Community
  licence (5 in this org). Add CAPTCHA / email verification before going live and monitor licence use.
- The requesting customer sees the recipient data they entered on the shipment detail page
  (AC-007.3); only the recipient can open the recipient views and change the delivery (BR-02).
- Business days are Monday to Friday; public holidays are not considered.
- "My shipments" shows the 200 most recent shipments that match the filter.
