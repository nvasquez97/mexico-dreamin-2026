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

## 2026-11-17 15:05 — Session handoff: REQ-004 T4 committed, awaiting review; plugins installed
- Type: status
- What: REQ-004 T3 ticked (62342c7, fixed 4d8c04f; B10 16 KB cap, B11 depth ≤ 20). T4 committed 55bb487, evidence d7da664 (odd/evidence/req-004-carrier-status/T4.md): External Client App "EntregaYa Status", integration user via scripts/setup/entregaya-integration.sh (ran, idempotent), attack-check.sh, simulate-status.sh; gate 166/166, 94.6%. Live simulation NOT run (consumer secret not readable via API; owner step, B12). T4 is NOT ticked yet: its review has not run.
- Why / evidence: odd/tasks/req-004-carrier-status.md (B12), T4 evidence.
- Next (new session): launch task-reviewer, security-reviewer and access-auditor over 55bb487 with Review handoffs for T4 (AC-004.6, AC-004.8; Security yes); fix round if needed; tick T4; then REQ-004 Close (gate, test-reviewer, sf-security-auditor, access-auditor; no brand: no interface); archive; then REQ-001.
- Speed-ups decided (apply from the next requirement): workers run only their own test classes and scripts (no full GATE per task; the gate stays at Close); fewer, larger tasks (2–3 per requirement); draft and plan-review the next requirement while workers run. Grouping requirements (REQ-002+003, REQ-006+007, REQ-005 alone) is proposed to the owner but NOT approved: keep one task document per requirement unless the owner says yes.

## 2026-11-17 15:05 — Environment: Salesforce plugins installed at project scope
- Type: environment
- What: The four Salesforce plugins were disabled in ~/.claude/settings.json and only installed for other project folders, so the Skill tool returned "Unknown skill" and every agent read SKILL.md by hand (main cause of slow agents). Installed salesforce-development, salesforce-code-quality, experience-lwc and integration with `claude plugin install <p>@salesforce --scope project` on 2026-11-17; they load after a session restart. In the new session, check that the Skill tool lists salesforce-development:* skills; if it does, drop the "read SKILL.md from the cache" note from handoffs.
- Why / evidence: measured: deploys 1–3 s, test runs 5–40 s, gate ~2.5 min; the gaps are agent turns.

## 2026-11-17 16:00 — Session resumed; skills load; grouping approved
- Type: decision
- What: Resumed REQ-004 at the T4 review (org cargo-opus-t1, active scratch, default target-org; Mode: auto, unattended, whole run). The Skill tool now lists salesforce-development:*, salesforce-code-quality:*, experience-lwc:*, integration:* — handoffs no longer tell agents to read SKILL.md from the cache. Owner approved grouping: REQ-002+REQ-003 in one task document, REQ-006+REQ-007 in another; REQ-001 and REQ-005 alone (approved exception to "one task document per requirement"). Speed-ups in force: workers run only their own test classes and checks; 2–3 larger tasks per requirement; draft and plan-review the next requirement while workers run.
- Why / evidence: /work arguments of this session.
- Next: T4 reviews (task-reviewer, security-reviewer, access-auditor running), then REQ-004 Close; draft REQ-001 meanwhile.

## 2026-11-17 16:20 — REQ-004 T4 ticked with open owner items; Close gate; REQ-001 plan in review
- Type: review
- What: T4 55bb487 ticked: security-reviewer and access-auditor APPROVED; task-reviewer High (AC-004.6 live POST not run) and EXP-001 Medium (no login IP ranges) recorded open, pending owner (B12, B6, B13); no worker fix round. REQ-004 Close Stage gate. REQ-001 plan committed 1e25e74 (odd/tasks/req-001-public-tracking.md, Base d0c2143), plan-reviewer running.
- Why / evidence: T4 task line and B13 in odd/tasks/req-004-carrier-status.md.
- Next: GATE @ HEAD, then test-reviewer, sf-security-auditor, access-auditor (tier 2, no interface); archive; REQ-001 T1.

## 2026-11-17 17:10 — Pipeline status: REQ-004 Close fix round pending; REQ-001 T1 running; REQ-002+003 and REQ-005 planned
- Type: status
- What: REQ-004 gate @ 139ffb7 green (166/166, 94.6%); Close reviews: test-reviewer changes required (Medium simulate-status.sh exits 0 on any 2xx; Lows), sf-security-auditor pass, access-auditor approved; Stage fix round — the fix worker launches after REQ-001 T1 commits (one committing worker). REQ-001 T1 worker running (PublicTracking*). REQ-002+003 plan reviewed and fixed (3c64ca7; new object Recipient_Access_Guard__c, guest permset RutaCargo_Guest_Proof_Download; starts after REQ-001 archive). REQ-005 plan b59ead7 in plan review.
- Why / evidence: the three task documents; reviewer ids on their lines.
- Next: REQ-001 T1 review (task-reviewer, security-reviewer, access-auditor) + REQ-004 Close fix worker; then REQ-001 T2, T3.

## 2026-11-17 18:30 — REQ-004 closed and archived
- Type: close
- What: Gate @ 139ffb7 166/166 and re-run @ a096821 192/192, org 95.26% (EntregaYa* 100%). Reviews: test-reviewer (Medium + Low fixed in ae77cb2; High AC-004.6 live POST open, owner), sf-security-auditor pass, access-auditor approved. Open: AC-004.6 live POST (B12/B13), EXP-001 IP ranges (B6), one Low.
- Why / evidence: odd/tasks/archive/2026-11-17-req-004-carrier-status.md, Close section.
- Next: REQ-001 T1 fix round (worker running), then T2, T3, Close. REQ-002+003, REQ-005, REQ-006+007 plans are reviewed and committed.

## 2026-11-17 18:30 — Environment: gate from a clean worktree
- Type: environment
- What: To run the GATE while a worker edits the main checkout, deploy from `git worktree add --detach <scratch>/wt-gate HEAD`; a fresh worktree has no source-tracking state, so the deploy needs `--ignore-conflicts` (156 "conflicts" otherwise).
- Why / evidence: gate 0AfEk00000h4y85KAA.

## 2026-11-17 19:40 — REQ-001: T1, T2 ticked; T3 in review
- Type: status
- What: T1 04ed8f0 (fixed 093aab3: 520-char entry bound, 100-entry test, inner sharing keywords), T2 00532b9 clean (rcTracking on the home page, published). T3 6f82b47 (logo 440 px box from 40em → 369 px visible; gray wrapper removed by zero branding-set row paddings — side effect: page sections edge to edge) under task-reviewer.
- Why / evidence: odd/tasks/req-001-public-tracking.md task lines.
- Next: tick T3, REQ-001 Close (gate from a clean worktree; test-reviewer, brand-reviewer, sf-security-auditor, access-auditor), archive; then REQ-002+003 T1.
- Environment: source tracking reports stale conflicts after deploys from other worktrees; workers verify with a retrieve and use --ignore-conflicts.

## 2026-11-17 21:00 — REQ-001 closed and archived; REQ-002+003 starts
- Type: close
- What: Gate @ d55cd2c 196/196 and re-run @ a6e305b 205/205, org 95.48% (PublicTracking* 100%), Jest 63/63. Reviews: test-reviewer (2 Medium + 5 Low fixed at 2dcff81), brand approved (C11 live region fixed), sf-security-auditor pass (SEC-001 fixed by guest-access-check 5c), access-auditor approved. No open blocking findings; Hardening items in the Close section (C1 rate limit, etc.).
- Why / evidence: odd/tasks/archive/2026-11-17-req-001-public-tracking.md.
- Next: REQ-002+003 T1 (recipient access with lockout, details, reschedule); REQ-005 and REQ-006+007 plans are reviewed and wait their order gates.

## 2026-11-17 22:30 — REQ-002+003: T1 in fix round, T2 resumed with credential decision E11
- Type: decision
- What: T1 1d02283 reviewed (access approved, security approved with 2 Lows, task-reviewer Medium: 3 clauses never seen red on their own assertion) — fix round after T2 commits. T2 stopped: the guest's External Credential callout needs Read on UserExternalCredential (object permission forbidden for the guest). E11: use a password-authenticated (legacy) Named Credential, key in the org only; fallback = one guest Read on UserExternalCredential as an exception pending owner approval. T2 worker resumed (same agent) with E11.
- Why / evidence: odd/tasks/req-002-003-recipient-delivery.md E11; T2 stop report.
- Next: T2 commit and review; T1 fix round; T3 (LWC, layout history list, live history check); Close.

## 2026-11-17 23:40 — Owner decision: batch fix rounds
- Type: decision
- What: From REQ-002+003 T3 onward, per-task reviews still run, but Medium/Low findings that are test-quality or evidence issues (not security, not wrong behavior) do not start a per-task fix round: the task is ticked with `review: batched to Close — <finding>` and the finding goes to the requirement's Close fix round. Security findings and wrong-behavior findings keep the per-task fix round. Other speed-ups offered (lighter security lens, fewer tasks) were NOT chosen.
- Why / evidence: owner answer in the session ("Batch fix rounds"), tasks were taking about 1 hour each.
- Next: apply to T3 of REQ-002+003, REQ-005, REQ-006+007 and Hardening.
