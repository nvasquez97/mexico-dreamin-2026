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

## 2026-11-17 22:40 — Plugin skills not loadable in this session
- Type: environment
- What: The Skill tool returns "Unknown skill" for salesforce-development:*, experience-lwc:*, integration:*, salesforce-code-quality:* although the plugins are installed. Workaround in every handoff: read SKILL.md from ~/.claude/plugins/cache/salesforce/<plugin>/<version>/skills/<name>/ (or marketplaces/salesforce/skills/ for experience-lwr-site-generate). Record under "Skills not available" in each Close.
- Why / evidence: Skill call failed 2026-11-17; tier 0 reviewer hit the same.

## 2026-11-17 22:40 — Tier 0 reviewed; foundation plan in review
- Type: review
- What: Tier 0 range ca754cc..18a2aa5 reviewed clean (task-reviewer). Foundation plan d0a2432 reviewed with 4 High / 7 Medium findings; fixed in d1603d7 (hashed code kept per D1, internal Private + sharing rules, independent auto-number, T4 split into T4/T5, seed is T6). Closing check pending with the same plan-reviewer.
- Why / evidence: odd/tasks/foundation.md
- Next: record Plan review line, launch T1.
- Open issue: the EntregaYa key stays in git history (commits 709c3cc..b85773a); owner must rotate it.

## 2026-11-17 23:30 — foundation T1 ticked, T2 running
- Type: status
- What: T1 7fa6794 ticked (task-reviewer Low x2, security-reviewer approved, access-auditor ACC-001 Medium moved to T3 as AC-F.14). AC-F.15 added to T2 (trigger forces Status Requested on insert; seed must insert then update statuses). A7: SECURITY-JUSTIFICATION approver is "pending owner approval". T2 worker launched.
- Why / evidence: odd/tasks/foundation.md task lines.
- Next: review T2 with task-reviewer + security lens, then T3.

## 2026-11-18 02:00 — foundation T2 ticked after one fix round
- Type: review
- What: T2 cd29570, fixed in 45b3eee: codes 12 chars, 100-round SHA-256 + 128-bit salt (v1$100$salt$hash, A8), DeliveryAccessCode.insertWithCodes(rows) returns Map<Id,String> in user mode (the only way to get clear codes). ~8 ms CPU per hash/check: >1,000 per sync transaction nears the CPU limit. Full GATE 65/65, 90.79%.
- Why / evidence: odd/tasks/foundation.md T2 line; closing checks closed by task-reviewer and security-reviewer.
- Next: T3 (support agent permset, group, sharing rules, ACC-001 profile fix). T6 seed must use insertWithCodes and needs FLS for the running admin (API 67 user mode).

## 2026-11-17 07:00 — Correction: earlier entry times were wrong
- Type: environment
- What: The run started about 01:00 local (-05:00) on 2026-11-17; entries above stamped 22:15-02:00 or 2026-11-18 are wrong. Take times from `date` from now on.
- Why / evidence: `date +%Y-%m-%d` = 2026-11-17; commit 41502ba at 06:51 -0500.

## 2026-11-17 07:00 — foundation T3 ticked after one fix round
- Type: review
- What: T3 16ad26a, fixed in 41502ba. A9: platform keeps Read/View All on Shipment__c for the Analytics Cloud Integration User profile (only its platform Integration User active, 0 FLS), guarded by scripts/checks/shipment-access-check.sh. A10: criteria sharing rules are not evaluated in Apex tests (mirrored with Manual shares; T6 verify must prove RowCause Rule shares). Open Low: justification date 2026-11-18 in SupportAgentAccessTest.cls:44. Notes for later plans: agents can edit Reschedule_Count__c, Proof_Id__c, Delivered_At__c, Last_Update__c, Customer_Type__c — REQ-002/003 code must not trust them blindly; Standard Platform User profile grants Delete on Account/Contact (pre-existing, Low).
- Why / evidence: odd/tasks/foundation.md T3 line.
- Next: T4 (LWR site, guest profile locked down, guest TZ).

## 2026-11-17 08:30 — foundation T4-T6 ticked, T7 in fix round
- Type: status
- What: T4 3da69bd (fixed 1cae575; site https://data-energy-2854-dev-ed.scratch.my.site.com/rutacargo/ Live; guest 0 object perms; 6 VF pages allowed; A11 from-zero rebuild unproven). T5 0482f05 clean (brand; font via loadStyle because the site's styles.css never publishes in this org). T6 738ff65 (seed loaded; first load lost clear codes; security mark corrected to yes). T7 29a6fa5 adds DeliveryAccessCode.reissueCodes/verify; 120 seeded codes reissued once into git-ignored .seed-output/access-codes.csv (never reissue again). T7 fix round running.
- Why / evidence: odd/tasks/foundation.md
- Next: tick T7, then foundation Close (GATE, test-reviewer, brand-reviewer, sf-security-auditor, access-auditor). REQ-004 plan is drafted (odd/tasks/req-004-carrier-status.md) — set Base and run plan review after foundation is archived.
- Notes for REQ-002: DeliveryAccessCode is `with sharing`, so a guest caller of verify gets false unless a narrowly justified without-sharing helper does the lookup; verify does 1 SOQL per call and ~8 ms CPU; the guest controller must rate-limit (X16) and must not trust agent-editable fields (Proof_Id__c, Reschedule_Count__c). Network enableApexCDNCaching is true: guest cacheable Apex must not return caller-specific data. Every site page is public unless set to require login.

## 2026-11-17 11:51 — foundation closed and archived
- Type: close
- What: Gate @ f2dedeb 98/98 and re-run @ 265a51d 101/101, org 90.79% (DeliveryAccessCode 98.42, ShipmentTriggerHandler 95.45). Reviews: test closed, security pass (Low), access approved, brand 2 open (logo ~303 px < 360 at desktop; platform #EFF0F2 wrapper around header/footer) → carried into REQ-001 as a task. Assumptions A1-A14 in the archived document.
- Why / evidence: odd/tasks/archive/2026-11-17-foundation.md, Close section.
- Next: REQ-004: set Base, commit plan, plan-reviewer. Then REQ-001 (include the two brand findings), REQ-002, REQ-003, REQ-005, REQ-006, REQ-007; Hardening; End of run.

## 2026-11-17 13:48 — REQ-004 in progress: T1, T2 ticked, T3 running
- Type: status
- What: odd/tasks/req-004-carrier-status.md (Base 642bc1b, plan review fixed). T1 87b84b4 (fixed d77dade): integration permset, custom permission RutaCargo_EntregaYa_Sender, group + sharing rule, entregaya-access-check.sh. T2 4c7096d (fixed 4298410): EntregaYaStatusService + trigger guard refusing direct updates by custom-permission holders (AC-004.9), INVALID_PROOF_ID (B9). T3 (REST resource) worker launched; T4 (External Client App, integration user, live simulation and attack check) next.
- Why / evidence: task lines in the document.
- Next: review T3, then T4 (must create the integration user and assign the Salesforce API Integration PSL in one step, B8; ECA OAuth policies from a template, not versioned).
