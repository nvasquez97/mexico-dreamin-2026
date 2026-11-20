# Functional Design — RutaCargo Shipping and Tracking

## Context and goal

RutaCargo (a fictional parcel company in Mexico) will publish a Salesforce site where anyone can sign up and request door-to-door shipments, track a shipment with its tracking number and, if they are the recipient, manage their delivery without calling the contact center.

Today shipments are requested by phone or at a branch. The contact center receives about 1,200 calls a day: most ask where a package is or want to change the delivery date, and the rest request a pickup. In addition, status changes from the last-mile carrier are entered into Salesforce by hand, hours late.

Goals for this release:

- Customers sign up and request door-to-door shipments online.
- Self-service tracking, without creating an account.
- Recipients view their delivery details and reschedule on their own.
- Statuses updated automatically by the carrier.

## Scope

**In scope for this release:**

- An Experience Cloud site with a public area and an area for registered customers.
- Customer sign-up and login.
- Door-to-door shipment requests and a "my shipments" view.
- Public shipment tracking by tracking number or by order reference.
- Delivery details and download of the proof of delivery.
- Delivery rescheduling by the recipient.
- Receiving the status changes sent by the last-mile carrier (EntregaYa).

**Out of scope:** online payments (the shipment is paid at pickup), cancelling or modifying a shipment already requested, accounts with several users per company, invoicing, email or SMS notifications, and reports.

## Actors

| Actor         | Type                                                      | What they do                                                                         |
| ------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Customer      | Individual or business registered on the site, with login | Requests door-to-door shipments and views the ones they requested                    |
| Visitor       | Anyone, without login                                     | Checks the status of one or more shipments                                           |
| Recipient     | The person receiving the shipment, without login          | Views their delivery details, downloads the proof of delivery and reschedules        |
| Support agent | Internal RutaCargo user                                   | Manages customers and shipments from Salesforce                                      |
| EntregaYa     | Last-mile carrier (external system)                       | Sends status changes to Salesforce and provides the proof of delivery through an API |

## Data model

Each customer is an account (Account) with one contact (Contact), who is the person that signed up. Shipments live in a custom object. API names are a proposal; the development team may adjust them.

**Account (customer)** — additional fields:

| Field               | Type           | Description                                         |
| ------------------- | -------------- | --------------------------------------------------- |
| Customer\_Type\_\_c | Picklist       | Individual, Business                                |
| Credit\_Limit\_\_c  | Currency (MXN) | Authorized credit limit                             |
| Credit\_Risk\_\_c   | Picklist       | Low, Medium, High (internal collections assessment) |

**Contact (registered person)** — uses the standard first name, last name, email and phone fields.

**Shipment\_\_c (Shipment)**

| Field                                      | Type              | Description                                                              |
| ------------------------------------------ | ----------------- | ------------------------------------------------------------------------ |
| Name                                       | Text              | Tracking number                                                          |
| Account\_\_c                               | Lookup to Account | Customer who requested the shipment                                      |
| Customer\_Reference\_\_c                   | Text              | Order reference assigned by the customer (optional)                      |
| Status\_\_c                                | Picklist          | Requested, Picked up, In transit, Out for delivery, Delivered, Exception |
| Service\_Type\_\_c                         | Picklist          | Standard, Express                                                        |
| Pickup\_Address\_\_c                       | Long text         | Pickup address                                                           |
| Pickup\_Postal\_Code\_\_c                  | Text              | Pickup postal code                                                       |
| Pickup\_Date\_\_c                          | Date              | Requested pickup date                                                    |
| Origin\_City\_\_c / Destination\_City\_\_c | Text              | Origin and destination cities                                            |
| Recipient\_Name\_\_c                       | Text              | Recipient name                                                           |
| Recipient\_Address\_\_c                    | Long text         | Delivery address                                                         |
| Destination\_Postal\_Code\_\_c             | Text              | Destination postal code                                                  |
| Recipient\_Phone\_\_c                      | Phone             | Recipient contact phone                                                  |
| Recipient\_Email\_\_c                      | Email             | Recipient email                                                          |
| Delivery\_Instructions\_\_c                | Long text         | Delivery instructions                                                    |
| Package\_Description\_\_c                  | Text              | Description of the contents                                              |
| Weight\_Kg\_\_c                            | Number            | Weight in kg                                                             |
| Declared\_Value\_\_c                       | Currency (MXN)    | Declared value of the contents                                           |
| Price\_\_c                                 | Currency (MXN)    | Shipment price for the customer                                          |
| Estimated\_Delivery\_\_c                   | Date              | Estimated delivery date                                                  |
| Reschedule\_Count\_\_c                     | Number            | Number of times it has been rescheduled                                  |
| Last\_Location\_\_c                        | Text              | Last reported location                                                   |
| Last\_Update\_\_c                          | Date/Time         | Date of the last status update                                           |
| Delivered\_At\_\_c                         | Date/Time         | Moment of delivery                                                       |
| Proof\_Id\_\_c                             | Text              | Identifier of the proof of delivery in EntregaYa                         |
| Carrier\_Cost\_\_c                         | Currency (MXN)    | Transport cost for RutaCargo                                             |
| Margin\_\_c                                | Formula (%)       | Shipment margin                                                          |
| Internal\_Notes\_\_c                       | Long text         | Notes from the operations team                                           |

## Requirements

Seven requirements, each with its user story and numbered acceptance criteria so that code and tests can be traced back to their origin.

### REQ-001 — Public tracking

As a visitor, I want to check the status of my shipments with the tracking number or with my order reference, so that I know where my package is.

- **AC-001.1** The visitor chooses to search by tracking number or by order reference, and can enter up to 10 values separated by commas or line breaks.
- **AC-001.2** For each shipment found, the site shows: tracking number, status, origin city, destination city, last location, date of the last update and estimated delivery date.
- **AC-001.3** Values that do not match any shipment are listed as "Not found".
- **AC-001.4** Results can be sorted by status or by estimated delivery date.
- **AC-001.5** The search ignores case and leading or trailing spaces.

### REQ-002 — Delivery details and proof of delivery

As a recipient, I want to see my delivery details and download the proof of delivery, so that I can confirm where and when my package arrives and who received it.

- **AC-002.1** From a tracking result, the recipient enters the destination postal code to open the delivery details.
- **AC-002.2** The details show: recipient name, delivery address, contact phone, estimated date and delivery instructions.
- **AC-002.3** If the postal code does not match, the site shows "The details do not match this shipment".
- **AC-002.4** When the shipment is Delivered, "Download proof of delivery" fetches from EntregaYa the PDF with the signature of the person who received it. The PDF is not stored in Salesforce.
- **AC-002.5** If EntregaYa does not respond, the site shows "We could not get the proof of delivery, please try again later".

### REQ-003 — Reschedule the delivery

As a recipient, I want to change the date and the instructions of my delivery, so that I receive the package when someone is home.

- **AC-003.1** From the delivery details, the recipient can choose a new date and edit the delivery instructions.
- **AC-003.2** The new date must be between the next day and 7 calendar days after the original estimated date.
- **AC-003.3** Only a shipment in Picked up or In transit status can be rescheduled.
- **AC-003.4** A shipment can be rescheduled at most 2 times.
- **AC-003.5** On save, the new date is shown, and the support agent can see in Salesforce when each change was made.

### REQ-004 — Carrier status updates

As a support agent, I want EntregaYa to update shipment statuses directly in Salesforce, so that we stop entering them by hand.

- **AC-004.1** EntregaYa sends Salesforce every status change: tracking number, new status, location, and date and time.
- **AC-004.2** Salesforce updates the status, the last location and the last update date of the shipment. With the Delivered status, the moment of delivery and the proof of delivery identifier are also saved.
- **AC-004.3** A nonexistent tracking number or an invalid status is rejected with a clear error message for EntregaYa.
- **AC-004.4** If an update arrives that is older than the last one recorded, it is ignored.

### REQ-005 — Customer sign-up and login

As a customer, I want to create my account with my email and a password, so that I can request shipments and check them later.

- **AC-005.1** The sign-up form asks for: customer type (individual or business), name or legal name, first and last name of the contact person, email, phone and password.
- **AC-005.2** Signing up creates the customer in Salesforce: an account with its contact.
- **AC-005.3** An email can have only one account. If it is already registered, a message is shown and login is offered.
- **AC-005.4** The password must have at least 10 characters, with letters and numbers.
- **AC-005.5** The customer logs in with their email and password, and can log out.
- **AC-005.6** If they forget their password, they can reset it with a link they receive by email.

### REQ-006 — Request a door-to-door shipment

As a registered customer, I want to request that a package be picked up at my address and delivered to another one, so that I do not have to go to a branch.

- **AC-006.1** The form asks for: pickup address, city and postal code; pickup date; recipient name, address, city, postal code, phone and email; service type (Standard or Express); weight in kg; description of the contents; declared value; and, optionally, an order reference and delivery instructions.
- **AC-006.2** Before confirming, the customer sees the shipment price according to the current rate (BR-08).
- **AC-006.3** The pickup date must be a business day between the next day and 15 days later.
- **AC-006.4** The maximum weight is 30 kg and the maximum declared value is 50,000 MXN.
- **AC-006.5** On confirmation, the shipment is created under the customer, in Requested status and with its tracking number, which is shown on screen.
- **AC-006.6** The estimated delivery date is the pickup date plus 5 business days for Standard and plus 2 for Express.

### REQ-007 — My shipments

As a registered customer, I want to see the shipments I have requested, so that I can follow up on them.

- **AC-007.1** The list shows the customer's shipments: tracking number, request date, recipient, destination city, status, service type and price, most recent first.
- **AC-007.2** The list can be filtered by status and searched by tracking number, recipient or reference.
- **AC-007.3** Each shipment has a detail page with the data the customer entered, the price and the current status.

## Business rules

These rules apply to all requirements; if an acceptance criterion and a rule seem to contradict each other, the rule wins.

| ID    | Rule                                                                                                                                                                                                                                           |
| ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| BR-01 | The public information of a shipment is what AC-001.2 lists. Any visitor with the tracking number or the reference can see it, and nothing else.                                                                                               |
| BR-02 | The recipient's personal data, the proof of delivery and changes to the delivery are exclusive to the recipient of the shipment.                                                                                                               |
| BR-03 | The transport cost, the margin, the internal notes and the customer's credit limit and credit risk are internal RutaCargo information and are not shown on the site. The price of a shipment is visible only to the customer who requested it. |
| BR-04 | Only EntregaYa can send status updates.                                                                                                                                                                                                        |
| BR-05 | The tracking number has the prefix RC followed by 9 digits, and is assigned consecutively when the shipment is created.                                                                                                                        |
| BR-06 | Dates are shown in Mexico City time.                                                                                                                                                                                                           |
| BR-07 | Each customer sees and manages only their own shipments and their own data.                                                                                                                                                                    |
| BR-08 | Current rate: Standard, 120 MXN plus 18 MXN per kg; Express, 220 MXN plus 30 MXN per kg. In both cases, 1.5% of the declared value is added as insurance. RutaCargo determines the price with this rate.                                       |
| BR-09 | A new shipment starts in Requested status. Only RutaCargo and EntregaYa change the status of a shipment.                                                                                                                                       |

## Integration with EntregaYa

There are two exchanges with EntregaYa: Salesforce asks it for the proof of delivery, and EntregaYa sends Salesforce the status changes.

**Note from the provider's ticket (copied as is):**

> Hi, your access to the test environment is now active. Base URL: https://REPLACE-WITH-YOUR-MOCK — API key: ey_sk_test_4Qw8Zr2LmX9vTn6Kp3Hd. It goes in the Authorization header as Bearer. To send you the status changes we need you to tell us the URL of your service and how we authenticate; on our side we support OAuth 2.0 (client credentials). Regards, EntregaYa support.

**Proof of delivery (Salesforce calls EntregaYa):**

- **Method and path:** GET {base URL}/proofs/{proofId}
- **Headers:** Authorization: Bearer {API key}
- **Successful response:** 200 with `{"proofId": "PRF-88231", "trackingNumber": "RC000001042", "signedBy": "Ana López", "fileName": "proof-of-delivery.pdf", "pdfBase64": "JVBERi0xLjQK..."}`
- **Errors:** 401 if the key is wrong, 404 if the proof does not exist, 5xx if the service is unavailable. The provider recommends a 10-second timeout.

**Status changes (EntregaYa calls Salesforce):**

- EntregaYa makes a POST to the service RutaCargo defines, one call per status change.
- **Body:**

```json
{
  "trackingNumber": "RC000001042",
  "status": "Out for delivery",
  "location": "Monterrey, NL",
  "timestamp": "2026-11-20T10:00:00-06:00",
  "proofId": null
}
```

- **Expected volume:** about 5,000 updates per day.

## Non-functional requirements

The site will be announced with a QR code printed on the label of each package, so most visits will come from mobile phones.

- **Platform:** Experience Cloud site in English, with public pages (tracking and delivery) and pages for registered customers (request a shipment and my shipments). Components in LWC and logic in Apex.
- **Devices:** mobile as the primary experience; it must also work on desktop.
- **Volume:** about 200,000 shipments per year, with peaks in November and December.
- **Response time:** tracking, lists and price calculation in under 2 seconds; proof of delivery download in under 10 seconds.
- **Visual identity:** the site applies the Coffee Blazers Summit Brand Manual (`docs/brand-manual.pdf`) and uses the logo files in `docs/brand/`: colors, typography, logo versions and usage rules.

## Test data and definition of done

The development org is loaded with two customers, each with its contact and its site user, and 120 shipments; all names, addresses and phone numbers are fictional.

| Customer       | Type     | Test user  | Credit risk | Credit limit (MXN) | Shipments | Tracking numbers           |
| -------------- | -------- | ---------- | ----------- | ------------------ | --------- | -------------------------- |
| Abarrotes Acme | Business | Ana López  | Low         | 500,000            | 60        | RC000001001 to RC000001060 |
| Globex Farma   | Business | Marta Ruiz | High        | 150,000            | 60        | RC000001061 to RC000001120 |

Shipments are spread across all statuses, with realistic recipients, addresses and postal codes, and with price, transport cost and internal notes. At least 10 shipments per customer are Delivered and have a proof of delivery identifier.

**Definition of done:**

- [ ] Metadata deployed to the development org and test data loaded with a reproducible script.
- [ ] A new customer can sign up, log in, request a shipment and see it in "my shipments".
- [ ] The public site supports the full flow without logging in: track, open the details, download the proof of delivery and reschedule.
- [ ] EntregaYa (simulated) can send a status update and the change is reflected in the shipment.
- [ ] Automated Apex tests for each acceptance criterion, with coverage above 75%.
- [ ] A README with the manual steps that remain pending in the org.
