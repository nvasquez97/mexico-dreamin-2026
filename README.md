# RutaCargo — Shipping and Tracking on Salesforce

RutaCargo is a door-to-door parcel service. This Salesforce DX project builds
its Experience Cloud site (English, mobile first) and the internal data model
behind it:

- Public tracking by tracking number or customer order reference.
- Delivery details, proof of delivery and rescheduling for the recipient,
  protected by a per-shipment delivery access code.
- Status updates from the last-mile carrier EntregaYa.
- Sign-up, login, shipment requests and "my shipments" for customers.
- Internal management of customers and shipments by RutaCargo support agents.

The functional design is `docs/functional-design.md`. Work is planned and
tracked with ODD: one task document per requirement in `odd/tasks/` (the
foundation is `odd/tasks/foundation.md`), with the evidence of every task in
`odd/evidence/`.

## Prerequisites

- Salesforce CLI (`sf`) v2, `jq`, `bash` and `curl`.
- A Dev Hub to create scratch orgs.
- Node.js and npm for the LWC tooling (`npm install`).

## Setup from zero

Run every command on its own and replace `<alias>` with your org alias.
Development orgs only: the seed and check scripts refuse anything that is not a
sandbox or scratch org, and nothing here is meant for production.

1. Create the scratch org (it enables Communities and Experience Bundle
   metadata):

   ```bash
   sf org create scratch --definition-file config/project-scratch-def.json --alias <alias> --duration-days 30 --target-dev-hub <dev-hub-alias>
   ```

2. Deploy the metadata, publish the site and set the guest user's time zone,
   in the order given in `scripts/setup/DEPLOY-ORDER.md` (the site first, then
   everything else with `RunLocalTests`, then `sf community publish`, then
   `scripts/setup/site-guest-user.sh <alias>`).

3. Load the test data:

   ```bash
   scripts/seed/seed.sh <alias>
   ```

   It creates the customers Abarrotes Acme and Globex Farma, their contacts
   Ana López and Marta Ruiz, and 120 shipments RC000001001–RC000001120 across
   all statuses, with dates relative to the run date in Mexico City time. It
   needs a new org: the tracking numbers come from an Auto Number that never
   goes back, so it refuses an org where any shipment was ever created. A
   second run changes nothing. It assigns the `RutaCargo_Support_Agent`
   permission set to the running user (A12). The clear delivery access codes
   are written once to `.seed-output/access-codes.csv`, which is git-ignored:
   never commit or share it.

   If the data is loaded but `.seed-output/access-codes.csv` is not on this
   machine (the codes of the first load were lost), reissue them:

   ```bash
   scripts/seed/seed.sh --reissue-codes <alias>
   ```

   It gives the 120 seeded shipments new codes through
   `DeliveryAccessCode.reissueCodes` (the running user needs Edit on the
   shipments) and writes them to `.seed-output/access-codes.csv`. **The reissue
   invalidates the previous codes** of those shipments: any label or message
   that carries an old code stops working. It loads nothing, refuses unless all
   120 seeded shipments exist, and never overwrites an existing
   `.seed-output/access-codes.csv`.

4. Verify the test data (read-only on the data; exits non-zero on any failure):

   ```bash
   scripts/seed/verify.sh <alias>
   ```

   When `.seed-output/access-codes.csv` is on this machine it also checks every
   code in it against its shipment with `DeliveryAccessCode.verify` (it prints
   only counts and deletes the debug logs of that check); without the file
   that check is skipped.

5. Run the org checks (read-only; each exits non-zero on any failure):

   ```bash
   scripts/checks/shipment-access-check.sh <alias>
   scripts/checks/guest-access-check.sh <alias>
   scripts/checks/brand-check.sh <alias>
   scripts/checks/entregaya-access-check.sh <alias>
   scripts/entregaya/attack-check.sh <alias>
   ```

   `scripts/setup/DEPLOY-ORDER.md` includes the EntregaYa integration step
   (`scripts/setup/entregaya-integration.sh <alias>`) after the force-app
   deploy; see "EntregaYa integration" below.

## EntregaYa integration

EntregaYa (the carrier) sends every status change of a shipment to Salesforce
(REQ-004, decision D2).

- Endpoint: `POST https://<My Domain>/services/apexrest/entregaya/v1/status`
  with a JSON body `{"trackingNumber":"RC000001002","status":"Out for delivery","location":"Monterrey, NL","timestamp":"2026-11-20T10:00:00-06:00","proofId":null}`
  (`proofId` is required for `Delivered`). Answers: 200 `{"result":"updated"}`,
  200 `{"result":"ignored"}` for an update that is not newer than the last one,
  404 `TRACKING_NOT_FOUND`, 400 with a closed error code for an invalid body,
  403 `FORBIDDEN` for a caller without the EntregaYa permission, 503
  `TEMPORARILY_UNAVAILABLE` (retry) and 500 `INTERNAL_ERROR`.
- Authentication: OAuth 2.0 client credentials through the External Client App
  **EntregaYa Status** (`force-app/main/default/externalClientApps/`). Token
  endpoint: `https://<My Domain>/services/oauth2/token` with
  `grant_type=client_credentials` (the My Domain URL, not login.salesforce.com).
  Scope `api` only; only users of the permission set
  `RutaCargo_EntregaYa_Integration` are pre-authorized; IP restrictions are
  enforced. The token runs as the dedicated integration user
  `entregaya-integration@<org id>.rutacargo.dev` (profile "Minimum Access - API
  Only Integrations", Salesforce Integration license, "Salesforce API
  Integration" permission set license, permission set
  `RutaCargo_EntregaYa_Integration`, group `RutaCargo_EntregaYa_Integration`),
  created by `scripts/setup/entregaya-integration.sh <alias>`. Anonymous calls
  are refused on the My Domain and on the site domain
  (`scripts/entregaya/attack-check.sh <alias>`).
- No consumer key, consumer secret, token or org-specific username is in this
  repository: the platform generates the key and secret when the app is
  deployed, and the OAuth policies that name the integration user are rendered
  from `scripts/setup/templates/` at setup time.

### Hand the consumer key and secret to EntregaYa (owner, B4)

1. In Setup, open External Client App Manager, then **EntregaYa Status**,
   Settings, OAuth Settings, and click Consumer Key and Secret. Salesforce asks
   you to verify your identity.
2. Send the key and the secret to EntregaYa through a secure channel (for
   example a one-time secret link or a shared password-manager entry), never by
   email, chat, a ticket or this repository. Send the token URL and the endpoint
   above with them.
3. If the secret is ever exposed, generate a new one on the same page and send
   it again.

### Try it with `simulate-status.sh`

The script reads the key and secret only from the environment, never prints
them or the token, and prints the HTTP status and body of the answer. Type them
so they do not land in your shell history:

```bash
read -rs ENTREGAYA_CLIENT_ID && export ENTREGAYA_CLIENT_ID
read -rs ENTREGAYA_CLIENT_SECRET && export ENTREGAYA_CLIENT_SECRET
scripts/entregaya/simulate-status.sh <alias> updated <trackingNumber> "Out for delivery" "Monterrey, NL" <timestamp>
scripts/entregaya/simulate-status.sh <alias> ignored <trackingNumber> "Out for delivery" "Monterrey, NL" <timestamp>
unset ENTREGAYA_CLIENT_ID ENTREGAYA_CLIENT_SECRET
```

Use a seeded "In transit" shipment whose `Last_Update__c` is earlier than the
timestamp, and a timestamp of now in `-06:00` (for example
`2026-11-17T14:00:00-06:00`); a timestamp more than 10 minutes in the future is
refused. The second argument is the result you expect: the first post must
answer 200 `{"result":"updated"}` and move the shipment to the posted status,
location and timestamp; the same post again must answer 200
`{"result":"ignored"}` and leave the shipment as it was. The script reads the
shipment before and after each post and exits 1 on any difference. Then run `scripts/seed/verify.sh <alias>`:
every customer must still have all six statuses.

## Decisions of this run (D1–D5)

The design questions the owner delegated, decided on 2026-11-17. Details in
`odd/tasks/foundation.md` and `.mem/memory.md`.

- D1: the recipient is authorized by a random delivery access code (printed on
  the label/QR, stored only as a salted hash) plus the destination postal code,
  with a limit on failed attempts; never by the postal code alone.
- D2: EntregaYa sends status updates to Apex REST
  `POST /services/apexrest/entregaya/v1/status`, authenticated with OAuth client
  credentials (External Client App) as a dedicated integration user.
- D3: calls to EntregaYa use a Named Credential and an External Credential; the
  API key is entered by hand in the org, never in the repository.
- D4: the reschedule window is measured from the first estimated delivery date
  (`Original_Estimated_Delivery__c`); field history tracks the date and the
  delivery instructions.
- D5: every customer is a business Account with one Contact (no Person
  Accounts), with a Customer Community license; shipments are Private
  externally and shared to customers through their account.

## Assumptions (A1–A12)

One line each; the full text is in the Assumptions section of
`odd/tasks/foundation.md`.

- A1: the delivery access code exists in clear only in the creating
  transaction (shown once in REQ-006, written once by the seed); label printing
  and code reissue are out of scope.
- A2: Shipment__c and Account are Private internally; support agents get access
  through the RutaCargo_Support_Agents group and sharing rules, never View All
  or Modify All.
- A3: Daily Brew is not in the repository; headings use Montserrat Black in
  uppercase, and the logo PNGs are stand-ins used only on their own background.
- A4: the site users of the test customers are created by REQ-005.
- A5: every date and time on the site is formatted in America/Mexico_City; the
  org default time zone is left as is.
- A6: no Shipment__c is inserted in the org outside Apex tests, except by the
  seed, so the tracking numbers stay reproducible.
- A7: every `// SECURITY-JUSTIFICATION:` names its approver as "pending owner
  approval"; agents cannot approve.
- A8: the access code is 12 characters, hashed with 100 SHA-256 rounds and a
  128-bit salt; the site shows it as XXXX-XXXX-XXXX.
- A9: the platform keeps Read and View All on Shipment__c for the Analytics
  Cloud Integration User profile; accepted as a platform exception, guarded by
  `scripts/checks/shipment-access-check.sh`.
- A10: criteria-based sharing rules are not evaluated in Apex tests; the real
  rule shares are proven on the seeded data by `scripts/seed/verify.sh`.
- A11: the site's from-zero rebuild has not been proven in a second org;
  `scripts/setup/DEPLOY-ORDER.md` documents the order to verify.
- A12: the seed runs as the org administrator in user mode and assigns it the
  RutaCargo_Support_Agent permission set for the field permissions; it never
  uses system mode.

## EntregaYa proof of delivery

A verified recipient downloads the proof of delivery PDF from the delivery
details on the site (REQ-002, AC-002.4). `ProofOfDeliveryService` calls
`GET callout:EntregaYa_API/proofs/{proofId}` with a 10-second timeout, accepts
the answer only when it is a 200 of at most 2,500,000 characters whose
`trackingNumber` is the shipment's and whose `pdfBase64` is a PDF, and returns
the PDF to the browser. Nothing is stored in Salesforce. Any failure shows
"We could not get the proof of delivery, please try again later".

- Credential (E11): the Named Credential `EntregaYa_API`, password
  authentication, named principal. Apex sends
  `Authorization: Bearer {!$Credential.Password}`, a merge field the platform
  fills with the credential's password when it sends the request. The guest
  user needs no permission set for it. The API key is never in this
  repository, in Apex or in a log.
- The repository holds the credential with no password and the placeholder URL
  `https://entregaya.invalid`. The platform cannot create a password credential
  without a password, so `scripts/setup/guest-proof-access.sh <alias>` creates
  it once, before the force-app deploy, with the non-secret placeholder
  password `not-set-enter-the-key-in-setup`. It never touches an existing
  credential. It also removes the old `RutaCargo_Guest_Proof_Download`
  assignment from the guest if one exists (`scripts/setup/DEPLOY-ORDER.md`).
- `scripts/checks/guest-access-check.sh <alias>` checks that there is no key,
  token, password or Authorization value in the repository, that the guest has
  no permission set besides its profile's own, and that the credential has no
  password in source and keeps the placeholder URL.

### Enter the key and the URL (owner)

1. Rotate the EntregaYa API key first: the original key is in the git history.
2. In Setup, open Named Credentials, choose the **Legacy** list view (or "Named
   Credentials (Legacy)"), then **EntregaYa API**, and click Edit.
3. URL: the real EntregaYa base URL, in place of `https://entregaya.invalid`.
4. Password: the rotated API key, typed by hand. Leave the username as it is,
   "Generate Authorization Header" off and "Allow Merge Fields in HTTP Header"
   on. Save.
5. On the site, open a Delivered shipment's details and download its proof.
   The live download is pending until you do this (E6).
6. After a later force-app deploy, check the download again. The repository
   file has no password, and nobody has tested whether a deploy keeps the
   password you entered.

The now-unused External Credential `EntregaYa` and permission set
`RutaCargo_Guest_Proof_Download` of the discarded design stay deployed in
cargo-opus-t1 and are not in this repository. Removing them from the org is
your decision (a destructive deploy).

## Manual steps pending for the owner

- EntregaYa (B4): read the consumer key and secret of the External Client App
  EntregaYa Status in Setup and hand them to EntregaYa (see "EntregaYa
  integration"). Then run `scripts/entregaya/simulate-status.sh` with them in
  cargo-opus-t1 to prove the live update (200 updated, then 200 ignored) and
  run `scripts/seed/verify.sh`: the agents could not run it because the org
  does not let the API read consumer secrets (`enableClientSecretInRestApiAccess`
  is off, and stays off).
- EntregaYa (B6): the app enforces IP restrictions, but the integration user has
  no login IP ranges yet because EntregaYa has not sent its IP addresses. When
  it does, add them as login IP ranges of the "Minimum Access - API Only
  Integrations" profile and test again. Do not use the app's trusted IP ranges
  for this: they relax verification instead of restricting the caller.

- Rotate the EntregaYa API key. It was redacted from the design in commit
  18a2aa5, but it remains in the git history. Then enter the rotated key and
  the real base URL in the Named Credential EntregaYa API (see "EntregaYa proof
  of delivery") and try a live download (E6).
- Decide whether to remove the unused External Credential `EntregaYa` and
  permission set `RutaCargo_Guest_Proof_Download` from cargo-opus-t1 (E11).
- Approve or reject every `// SECURITY-JUSTIFICATION:` comment (find them with
  `grep -rn "SECURITY-JUSTIFICATION" force-app scripts`). Those marked "pending
  owner approval" wait for you; the one in `ShipmentSchemaTest.cls` names
  "task-reviewer T1" as approver and needs your approval too (A7).
- Review the accepted platform exception A9 (Analytics Cloud Integration User
  profile on Shipment__c) before production.
- Prove the site's from-zero rebuild (A11) in the next new org by following
  `scripts/setup/DEPLOY-ORDER.md`, and record the result.
- Set and verify a real sender email address for the site: the Network uses
  `noreply@example.com`, which stays unverified.
- The administrator user created at the owner's request in the development
  org is a justified exception to policy P7 (minimal admins); keep or remove
  it.
- In the development org cargo-opus-t1 the delivery access codes of the first
  seed load were lost (see `odd/evidence/foundation/T6.md`; only their hashes
  are stored, D1). They were replaced with `scripts/seed/seed.sh
  --reissue-codes` (T7); the new codes exist only in the local, git-ignored
  `.seed-output/access-codes.csv` of the machine that ran it.

## Project structure

- `force-app/main/default/` — metadata: objects, Apex, LWC, permission sets,
  sharing rules and the RutaCargo site.
- `scripts/setup/` — deploy order, the guest user setup and the EntregaYa
  integration setup (`entregaya-integration.sh`, its template in `templates/`).
- `scripts/entregaya/` — EntregaYa simulation (`simulate-status.sh`) and the
  anonymous attack check (`attack-check.sh`).
- `scripts/seed/` — test data load (`seed.sh`, `seed.apex`) and its check
  (`verify.sh`).
- `scripts/checks/` — read-only org checks for access, guest exposure and
  brand.
- `odd/` — task documents and evidence; `.mem/` — project memory.
- `docs/` — functional design and brand material.
