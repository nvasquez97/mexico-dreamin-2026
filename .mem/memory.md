# Project memory

## 2026-11-17 22:15 — Run started: full functional design, new scratch
- Type: status
- What: Branch ODD-Opus-Cargo-Test-1 (from Opus-ODD-Skills). Org cargo-opus-t1 (scratch from Dev_Hub, Developer Edition, expires 2026-12-17), set as local default target-org. Mode: auto, unattended, for the whole run (owner answered the up-front questions on 2026-11-17).
- Why / evidence: sf org display --target-org cargo-opus-t1 → Active; Organization.IsSandbox=true (scratch), not production.
- Next: tier 0 review, then the foundation task document.

## 2026-11-17 22:15 — Owner answers to the up-front questions
- Type: decision
- What: Dev Hub = Dev_Hub (JhonyMexD is full, 3/3). Alias cargo-opus-t1, 30 days. Scratch def adds Communities + communitiesSettings + experienceBundleSettings (fd2ae95). Create the admin user now. Design ambiguities Q5-Q9: owner delegated to the model ("decide the best"); the recommended options apply.
- Why / evidence: owner reply in the session.
- Next: apply decisions D1-D5 below.

## 2026-11-17 22:15 — Design decisions delegated by the owner
- Type: decision
- What: D1 recipient access = random delivery access code (stored hashed, on the label/QR) + destination postal code + rate limit of failed attempts (policy forbids postal code alone; BR-05 numbers are sequential). D2 inbound = Apex REST POST /services/apexrest/entregaya/v1/status, OAuth client credentials via External Client App, dedicated integration user (Salesforce Integration license), 200 updated / 200 ignored (stale) / 404 unknown / 400 invalid. D3 outbound = Named Credential + External Credential, key entered by hand (README); no mock URL: tests use HttpCalloutMock, live proof download pending for owner. D4 reschedule window measured from Original_Estimated_Delivery__c (first estimate); field history on date and instructions. D5 business Account + Contact for both customer types (no Person Accounts); Customer Community license; Shipment__c external OWD Private; sharing set on Account__c.
- Why / evidence: owner delegated; conservative options per security policy.
- Next: record D1-D5 as assumptions in task documents and README.

## 2026-11-17 22:15 — Setup done
- Type: verification
- What: Admin user Nicolas Murcia (nicolas.murcia@cargo-opus-t1.rutacargo.dev, System Administrator, email nicolas.murcia@adaptus.com) created, System.resetPassword(id, true) sent. Justified exception to policy P7, requested by the owner. EntregaYa key redacted in docs (18a2aa5); owner must rotate it (it stays in git history).
- Why / evidence: SOQL on User; anonymous Apex RESET_OK.
- Next: licenses left: Salesforce 2/2 used (none free), Salesforce Platform 0/3, Salesforce Integration 0/1, Customer Community 0/5. Tests needing internal users use Salesforce Platform profiles.

## 2026-11-17 22:15 — Environment lesson
- Type: environment
- What: `sf ... --json | python` fails when the CLI prints its update warning first; read status with sf org list instead, or strip non-JSON lines.
- Why / evidence: scratch create succeeded although the parse failed.
