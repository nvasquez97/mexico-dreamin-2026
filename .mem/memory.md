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

## 2026-11-18 01:30 — REQ-002+003 closed and archived; REQ-005 T1 running
- Type: close
- What: Gate @ 3ae2ef1 296/296 and re-run @ 0d67085 303/303, org 95.86% (Recipient* 94-100%, ProofOfDeliveryService 95%), Jest 122/122. Reviews: test-reviewer (2 Medium + 6 Low fixed at 8e3db4f), brand approved, sf-security-auditor pass (SEC-001 Low + E1/C1 chain → Hardening), access-auditor approved. E11: password Named Credential (the guest's External Credential callout needs a forbidden object permission). Owner items in the Close section.
- Why / evidence: odd/tasks/archive/2026-11-18-req-002-003-recipient-delivery.md (or the date `date +%Y-%m-%d` gave).
- Next: REQ-005 T1 (customer profile, policy, permission set, owner role, network self-registration, seeded customer users) running; then T2, T3, Close; REQ-006+007; Hardening.

## 2026-11-18 04:00 — REQ-005: T1, T2 ticked; T3 running
- Type: status
- What: (Correction: REQ-002+003 is archived as odd/tasks/archive/2026-11-17-req-002-003-recipient-delivery.md.) REQ-005 T1 1938f82 fixed in 25b3df5 (customer profile revokes 709 license-default field permissions, 21 user permissions, all 287 tabs; allow-lists: 2 fields, EnableNotifications); T1 open item EXP-001 → T3 live negative self-registration test (F9). T2 d609edc ticked with batched Close items and F11 (sign-up does not prove email ownership: owner decision, Hardening). Customer Community licenses: 2/5 used (Ana, Marta).
- Why / evidence: odd/tasks/req-005-customer-signup.md task lines, F9-F11.
- Next: T3 review; REQ-005 Close (batched items: password passed to Site not asserted, one-input reset case, nickname from the email local part, inner-class sharing keywords); REQ-006+007.

## 2026-11-18 04:40 — Owner live sign-up works; owner asked for a session restart
- Type: verification
- What: The owner's "accountId parameter value is not valid" came from a cached old standard selfRegister page; on the published new page (/rutacargo/SelfRegister, rcSignUp) the owner's sign-up worked. T4's reproduction sign-up (t4-repro-…@example.com, Account "T4 Prueba SA", 03:26:52Z) also succeeded. Customer Community licenses about 4/5 used (Ana, Marta, t4-repro, the owner's test user): no more live sign-ups. T3 ticked (6482a72). Owner asked to stop after the running agents finish and restart with fresh context.
- Why / evidence: owner message in the session; org query of RutaCargo Customer users.
- Next: T4 worker wraps up (allow-list of known messages in rcSignUp, evidence); then a new session resumes at T4 review.

## 2026-11-18 05:00 — Session handoff: REQ-005 T4 committed, awaiting review
- Type: status
- What: Archived: foundation, REQ-004, REQ-001, REQ-002+003 (odd/tasks/archive/2026-11-17-*). Active: odd/tasks/req-005-customer-signup.md — T1 ticked (fixed in 25b3df5; EXP-001 closed by T3's live F9 test, security-reviewer agreed), T2 ticked (open F11 owner decision; batched Close items), T3 ticked clean (6482a72), T4 committed 9d27c05 + evidence 11570ff NOT yet reviewed or ticked (root cause = cached old standard selfRegister page; CustomerRegistration unchanged; rcSignUp allow-lists known server messages; 2 Apex + Jest tests; opt-in live sign-up mode of customer-pages-check.sh NOT built). Planned and plan-reviewed: odd/tasks/req-006-007-customer-shipments.md (order gate: after REQ-005 archived). Then Hardening (security findings collected in each Close) and End of run.
- Why / evidence: task lines in odd/tasks/req-005-customer-signup.md; F9-F13; T4.md.
- Next (new session): (1) launch task-reviewer, security-reviewer, access-auditor over 9d27c05 for T4 (AC-005.10; Security yes); tick T4 (batch test-quality findings to Close). (2) REQ-005 Close: GATE from a clean worktree (`git worktree add --detach <scratch>/wt-gate HEAD`, deploy with --ignore-conflicts); Jest; four Close reviewers (test, brand, sf-security-auditor, access-auditor); ONE Close fix round with all batched items (F10, F11 Lows, F13, T2 test-quality, customer-access-check site/tab notes); gate re-run; archive. (3) REQ-006+007: T1, T2, T3 per its plan. (4) Hardening, End of run.
- Run rules in force: Mode auto, unattended, whole run; owner decision "batch fix rounds" (test-quality/evidence findings → Close; security/wrong behavior → per-task fix); grouping REQ-002+003 and REQ-006+007 approved; workers run only their own tests/checks; gate at Close only; one committing worker at a time (reviewers may run in parallel with the next worker).
- Org facts: cargo-opus-t1 scratch; Customer Community licenses 4/5 used (Ana, Marta, t4-repro, the owner's test user) — NO more live sign-ups; the guest must never get Account access (the still-callable standard self-register action would then create users — Critical); network self-registration is on with no default account; EntregaYa Named Credential is the password kind (E11); deploys after parallel work need a retrieve check + --ignore-conflicts; the async Apex runner sometimes returns UNKNOWN_EXCEPTION (use --synchronous per class).

## 2026-11-17 22:56 — Session resumed at REQ-005 T4 review
- Type: status
- What: New session (local clock 2026-11-17 22:56; entries stamped 2026-11-18 above are clock errors). Org cargo-opus-t1 verified Active scratch, default target-org. Mode: auto, unattended, whole run. T4 reviews launched over 9d27c05: task-reviewer, security-reviewer, access-auditor (ids go on the T4 line if findings).
- Why / evidence: /work arguments of this session; sf org display.
- Update 23:10: T4 ticked clean (task-reviewer, security-reviewer, access-auditor; notes in F14). Close Stage gate.
- Update 23:30: REQ-005 gate @ df792b0 green 358/358, org 95.62%, Jest 232/232. Close reviews (ids on the Reviewers line): test-reviewer 2 Medium + 6 Low, brand 1 Low, sf-security-auditor pass (SEC-001 → Hardening, SEC-002 → fix), access-auditor approved. Close fix worker launched with 13 findings (Stage fix round, 29d6a48). Hardening items collected: SEC-001 reset flooding, F2, F11, guest default FieldPermissions, standard self-register while self-registration on, Health Check 67 (MFA, clickjack, HttpOnly), leftover RutaCargo_Guest_Proof_Download permset.
- Next: REQ-005 Close (gate from a clean worktree, test/brand/sf-security-auditor/access-auditor, one fix round with every batched item, gate re-run, archive), then REQ-006+007 T1-T3, Hardening, End of run.

## 2026-11-17 23:45 — REQ-005 closed and archived
- Type: close
- What: Gate @ df792b0 358/358 and re-run @ 7f2554d 373/373, org 95.64% (Customer* 88-100%), Jest 257/257. Reviews: test-reviewer (2 Medium + 6 Low fixed in 0bb3a33), brand (1 Low fixed), sf-security-auditor pass (SEC-002 fixed; SEC-001 → Hardening), access-auditor approved. Open: live sign-up mode not built, F11, justification approver. Hardening list and owner items in the Close section.
- Why / evidence: odd/tasks/archive/2026-11-17-req-005-customer-signup.md.
- Next: REQ-006+007 T1 (permission set Read + sharing set; CustomerShipmentAccessTest), then T2, T3, Close; Hardening; End of run.

## 2026-11-18 00:15 — REQ-006+007: T1 in review, T2 running
- Type: status
- What: T1 committed 3c2a0ee (evidence f39406a): sharing set works inside Apex tests (no A10 mirror); customers read 17 fields, not Account__c; M2 done by dropping the sharing set's profile (deletion forbidden). T1 reviewers (task, security, access) running in parallel with the T2 worker (only committing worker). T2 told: grant Account__c read FLS only if the user-mode filter needs it; G8 probe decides Account Read.
- Why / evidence: odd/evidence/req-006-007-customer-shipments/T1.md.
- Next: tick T1 (fix round waits for T2's commit if needed), review T2, then T3, Close.
- Update 00:40: T2 stopped once (scope: CustomerShipmentAccessTest asserts T1's exact grants) → scope widened (d385a0a), same worker resumed. T1 reviews: security approved (Low CODE-001), access approved, task-reviewer Medium (customer-access-check.sh omits PermissionsViewAllFields) → T1 fix round after T2 commits (same files); Lows batched to Close. Reviewer ids on the T1 line.

## 2026-11-18 01:40 — REQ-006+007: T2 committed and reviewed; org FLS residue from a mutation
- Type: environment
- What: T2 8a322bd (evidence 3698f0c). T2 reviews: security-reviewer adedd08cf3d4fae52 approved (Medium CODE-001 = G7 residual → Hardening; Low CODE-002 approver pending; Low CODE-003 direct create skips recipient-field checks → Close), task-reviewer a23e4911d3479ab40 2 Lows (evidence reds not assertions; tz test repeats logic → Close), access-auditor a1cd9ff33029a9062 pending. T1 fix worker aa4fc50d3c25417bc. LESSON: a viewAllFields=true mutation leaves read FieldPermissions on every field after it is turned off, and a source redeploy does not remove them; revert with explicit readable=false entries and compare org FieldPermissions with the file. Verified 01:40: the org had 29 rows vs 21 in the file (cost, margin, notes, hash, Proof_Id readable by customers) — T1 fix worker told to clean it.
- Why / evidence: FieldPermissions query on RutaCargo_Customer.
- Next: confirm cleanup (29 → 21 rows), T1 closing check (task-reviewer), tick T1 and T2, then T3.

## 2026-11-18 02:50 — REQ-006+007: T1 and T2 ticked; T3 running
- Type: status
- What: Org residue cleaned (21 rows, then 17 after the T2 fix). T1 ticked (fixed in 8d70377). T2 ticked (fixed in b8d954d): customers have no FLS on the 4 recipient fields; the controller stages them for the trigger (G9 in the task document); direct customer creates need valid recipient data; a SeeAllData history test needs reschedule-history-check.sh run once in a new org (DEPLOY-ORDER at Close). T3 worker af7bcda2fb03ad1fb running (LWCs, login-only routes).
- Why / evidence: task lines and G9 in odd/tasks/req-006-007-customer-shipments.md.
- Next: T3 review, then Close (gate, test, brand, sf-security-auditor, access-auditor; Close fix round with the batched Lows), archive, Hardening.
- Update 03:20: T3 83b5a2e ticked clean. Close gate @ ee969a9 green 486/486, org 95.6%, Jest 375/375. Four Close reviewers running (ids on the Reviewers line).
- Update 03:45: Close reviews in (Reviews line). Close fix worker a276c4e67bb591622 launched with 16 findings. Owner decision recorded, not fixed: SEC-001 Medium (sender is shown the recipient's access code → can use the guest recipient flow; follows D1/A1/G5 and AC-006.5). Hardening: SEC-002 no request cap.

## 2026-11-18 04:10 — REQ-006+007 closed and archived; Hardening next
- Type: close
- What: Gate @ ee969a9 486/486 and re-run @ 56bac29 509/509, org 96.15% (Shipment* 96-99%), Jest 375/375. Reviews: test-reviewer (3 Medium + Lows fixed in 0c90270), brand (2 Low fixed), sf-security-auditor pass (SEC-001 Medium owner decision: sender holds the recipient's access code; SEC-002 → Hardening), access-auditor approved. Every requirement is now archived.
- Why / evidence: odd/tasks/archive/2026-11-18-req-006-007-customer-shipments.md (date from `date`).
- Next: Hardening round 1 — sf-security-audit --org cargo-opus-t1 over the whole project plus dx-code-analyzer-run (non-security rules, sev 1-2 = High CA-###); triage Critical/High into odd/tasks/hardening-1.md (Tier 2); at most 3 audits. Then End of run.

## 2026-11-18 04:20 — Hardening round 1: audit 1 running
- Type: hardening
- What: Run dir .security-reports/20261118-035506-hardening-1 (org confirmed scratch). Scanner 0 Critical/15 High candidates; Code Analyzer Security+AppExchange 3 sev-3, sfge 2 sev-3; quality rules 137 sev-2 = 134 PMD GlobalVariable on LWC class fields (false positive: PMD's JS parser reads class fields as globals) + CA no-promise-executor-return ×2 (rcHeader tests) + CA SeeAllData=true (CustomerShipmentAccessTest:252). Org scan 1 Critical/424 High (mostly guest platform-default FLS). Three specialists running (code, access, exposure).
- Why / evidence: the run directory.
- Next: consolidate → security-audit.md, triage Critical/High (SEC and CA) into odd/tasks/hardening-1.md.

## 2026-11-18 04:50 — Hardening round 1: audit 1 counts and plan
- Type: hardening
- What: Audit 1 (report .security-reports/20261118-035506-hardening-1/security-audit.md): Critical 1 (SEC-001 key in git history, owner rotation), High 2 (SEC-002 guest lockout oracle; SEC-003 MFA not enforced), Medium 7, Low 7, Info 6; CA High 2 (CA-001 rcHeader tests promise executor; CA-002 SeeAllData), 134 CA GlobalVariable dismissed (false positive). Plan odd/tasks/hardening-1.md (Base 2230597): T1 guard per (shipment, postal) pair, T2 MFA settings + org-security-check.sh, T3 secret scan + pre-commit hook + CA fixes. Assumptions H1-H4 (SEC-001 rotation/purge owner; MFA affects admins' next UI login).
- Why / evidence: the report and the task document.
- Next: plan-reviewer on the plan commit, then T1-T3, Close, audit 2.
- Update 05:30: plan review fixed (4 High: normalized key, unbounded rows → T2 purge + malformed key > 10 chars, schema-check, Husky not core.hooksPath); plan now T1-T5 (f5c0161). T1 worker a64d0b6317ea49b5c launched (guard per pair).
- Update 07:10: T1 e89a7a6 ticked clean (Lows: Kelvin fold → T2; test Lows → Close; H7 unsalted hash). T3 d1481d8 committed: MFA setting deployed true (org left true); AC-H3.1 amended — "MFA Enabled" row meets standard, "Require MFA for all direct UI logins" stays Not Enforced (Salesforce-side, owner item); H2 decided in auto (customers unaffected; owner confirms with one customer login; revert = deploy false). T3 reviewers ab92794001eb23427 (task), a50b0a5e914796af3 (security), a44550d5af2cdb2c9 (access) running; T2 worker a608612858afeb08f running. Next: T4 secret scan, T5 CA fixes, Close, audit 2.
- Update 08:40: T3 ticked clean. T2 55524f5 reviewed: task-reviewer Medium (scheduled purge blocks any deploy of its class, gate included) → fix round adafce2d40a6a166c with versioned Deployment settings doesSkipAsyncApexValidation (decided over abort-and-reschedule) + CODE-001 Low (ß stored code → malformed bucket) + justification wording; NCSS split batched to Close. T4 3d6957d (secret scan; Husky NOT enabled in this clone — decided not to run npm install: lint-staged would reformat staged Markdown incl. odd/ and .mem/; owner item; the gate runs `secret-scan.sh --tree`). T4 reviewers aaa58e82638261d07 (task), aab98bd4c11bd4321 (security), ac03a3eac9dc3d592 (access) running.
- Update 11:00: T2 ticked (fixed f0b8fcd: Deployment settings doesSkipAsyncApexValidation + DEPLOY-ORDER 1c; ß bucket). T4 ticked (fixed 1e4548f: widened scan, SECRET-FILE, .gitignore, near-miss tests). T5 deaa163 committed (CA-001, CA-002 without SeeAllData; DEPLOY-ORDER 5c removed); reviewers afad0a2968ea48f99 (task), a845ea157d34914bf (security), ae375fb45532d9150 (access) running. Environment: two workers died on network errors (ENOTFOUND, ECONNRESET); the second had already committed — always check git log before resuming. Next: tick T5, hardening-1 Close (gate from a clean worktree + org-security-check.sh + secret-scan.sh --tree; 4 reviewers; Close fix round with batched Lows), archive, audit 2.

## 2026-11-18 21:30 — hardening-1 closed and archived; audit 2 next
- Type: hardening
- What: Round 1 closed. Audit 1 counts before: Critical 1 (SEC-001), High 2 (SEC-002, SEC-003), CA High 2. Fixed: SEC-002 (per-pair guard, malformed key, purge), SEC-003 config side (MFA setting; "Require MFA…" row Salesforce-side), SEC-001 repo side (secret scan + pre-commit; rotation owner), CA-001, CA-002. Gate re-run @ f81c86e 541/541, org 96.17%, Jest 375/375, all checks green. Owner items in the Close section.
- Why / evidence: odd/tasks/archive/<date>-hardening-1.md.
- Next: audit 2 (sf-security-audit --org cargo-opus-t1 + quality CA pass); SEC-001 will reappear (history, owner) — not taskable by an agent; stop check after audit 2 (max 3 audits).
- Update 21:50: audit 2 running in .security-reports/20261118-195136-hardening-audit-2; automated: quality sev-2 only GlobalVariable ×134 (dismissed false positive) → CA High 0; security CA/sfge 8 sev-2 on the justified recipient system-mode reads (specialists triage). Specialists: code ac3517d3bfaa31c19, access a34aa34ae0fc40335, exposure acccc326e2a247ebf.

## 2026-11-18 22:30 — Hardening done after audit 2
- Type: hardening
- What: Audit 2 (report .security-reports/20261118-195136-hardening-audit-2/security-audit.md): Critical 1 (SEC-001 key in history — owner rotation only), High 0, Medium 9 (incl. SEC-026 guard rows per distinct short postal code, regression of hardening-1; SEC-002/SEC-003 residuals lowered from High; SEC-024 no login IP ranges), Low 9, Info 8; CA High 0. Before → after: Critical 1→1 (owner), High 2→0; CA High 2→0.
- Why / evidence: decision (Mode auto): Hardening stops after audit 2 — the only Critical left cannot be fixed by an agent (rotation at EntregaYa; history purge needs force-push, owner), so a hardening-2 round would have no task; a third audit would find the same. Medium/Low go to the final report.
- Next: End of run — salesforce-code-quality:architecture-review, then odd/final-report.md, commit "end of run". Warn the owner: do not push ODD-Opus-Cargo-Test-1 before deciding on SEC-001 (it carries the key in history).

## 2026-11-18 23:00 — End of run
- Type: status
- What: Architecture review (salesforce-code-quality:architecture-review): Trusted FAIL (SEC-001 only; code controls strong), Easy WARN, Adaptable WARN (no CI, hard-coded rules, Queueable without Finalizer, controller-trigger static staging). odd/final-report.md written: requirements, gates, hardening counts (SEC Critical 1→1 owner, High 2→0; CA High 2→0), open findings, owner list.
- Why / evidence: odd/final-report.md.
- Next: owner — rotate the EntregaYa key before pushing this branch; human test; AC-004.6 live POST; approvals; delivery. The run is finished.

## 2026-11-18 20:55 — Owner bug: logged-in customers cannot track
- Type: status
- What: Owner's manual test: logged in as a customer, public tracking (and the recipient flow) fails with the generic error — RutaCargo_Customer lacks class access to PublicTrackingController and RecipientDeliveryController (guest-only today). Owner approved the fix (Tier 2, Mode auto). Plan odd/tasks/bug-customer-public-tracking.md (Base b0d7e0c, plan af939c3), plan-reviewer a4e5ffac6c792d365 running. Owner was also given manual test data (tracking numbers, postal codes, access codes from .seed-output) and the steps to run simulate-status.sh (not run yet).
- Why / evidence: anonymous Apex search returned RC000001124; permission set file lines 4, 8.
- Next: plan review, T1 worker, reviews, Close (gate + reviewers), archive; ask the owner to retest logged in.
- Update 22:10: fixed and archived (task 3609e85, gate 554/554 @ 181bce2, all reviews clean, no fix round). Final report updated. Owner gave Nicolas Murcia a temporary password (generated by CLI on request; not stored). Pending: owner retest logged in.
- Update 2026-11-19: owner retested logged in — tracking and recipient flow work (B5 recorded in the archived document and the final report).

## 2026-11-19 — Org cleanup done (owner request)
- Type: status
- What: Deleted from cargo-opus-t1 by destructive deploy 0AfEk00000hA2z3KAC (validated first, 554/554): PermissionSet RutaCargo_Guest_Proof_Download, ExternalCredential EntregaYa (SEC-014), RemoteSiteSetting ApexDevNet (SEC-015). guest-access-check and customer-access-check pass. README and final report updated. Manifests kept in the scratchpad (not committed).
- Why / evidence: owner "borra lo que necesites y haz los commits y pushea a origin".
- Next: push to origin only after the owner confirms the SEC-001 key situation (the branch history carries the old EntregaYa key).
