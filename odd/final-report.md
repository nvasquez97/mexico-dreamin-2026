# Final report — RutaCargo (mexico-dreamin-2026), ODD run

Branch: ODD-Opus-Cargo-Test-1 · Org: cargo-opus-t1 (scratch, never production) · Mode: auto, unattended, whole run · Run: 2026-11-17 to 2026-11-18

Every requirement of docs/functional-design.md is built, reviewed and archived; Hardening ran one round and a re-audit. Nothing was merged, pushed or deployed outside the dev org. **Before anything else: do not push this branch until the EntregaYa key is rotated (SEC-001) — its history carries the key.**

## 1. Requirements

| Document | Final gate (RunLocalTests, clean worktree) | Coverage | Open findings |
|---|---|---|---|
| foundation (objects, site, access code, sharing, seed) | 98/98 @ f2dedeb → 101/101 @ 265a51d after the fix round | org 90.79% | brand logo width and header wrapper → carried to and closed in REQ-001; Lows (agents can edit Customer_Type__c; reissueCodes without a custom-permission gate) |
| REQ-004 carrier status (EntregaYa inbound REST) | 166/166 @ 139ffb7 → 192/192 @ a096821 | 95.26%; EntregaYa* 100% | **AC-004.6 live POST never run** (needs the ECA key/secret, owner); no login IP ranges behind the ECA (now SEC-024) |
| REQ-001 public tracking | 196/196 @ d55cd2c → 205/205 @ a6e305b; Jest 63/63 | 95.48%; PublicTracking* 100% | none blocking; rate limit / sequential numbers → SEC-004 |
| REQ-002+003 recipient delivery and reschedule | 296/296 @ 3ae2ef1 → 303/303 @ 0d67085; Jest 122/122 | 95.86%; Recipient* 94-100% | none blocking; lockout oracle → fixed in Hardening (SEC-002); legacy Named Credential (E11) |
| REQ-005 customer sign-up, login, reset | 358/358 @ df792b0 → 373/373 @ 7f2554d; Jest 257/257 | 95.64%; Customer* 88-100% | opt-in live sign-up check not built (no licenses); email ownership not proven at sign-up (owner, SEC-010) |
| REQ-006+007 customer requests and My shipments | 486/486 @ ee969a9 → 509/509 @ 56bac29; Jest 375/375 | 96.15%; Shipment* 96-99% | sender is shown the recipient's access code (SEC-009, owner decision vs AC-006.5) |
| hardening-1 | 539/539 @ cc92228 → 541/541 @ f81c86e; Jest 375/375; guest/customer/org-security checks and secret scan green | 96.17% | key rotation (owner); "Require MFA for all direct UI logins" Health Check row (Salesforce-side) |

Every Close ran test-reviewer, sf-security-auditor and access-auditor (tier 2), plus brand-reviewer where there was interface, and one fix round; every task was reviewed after its commit, with the security lens on every security task.

**After the run — owner bug (2026-11-18):** logged-in customers could not use public tracking or the recipient flow (RutaCargo_Customer lacked class access to PublicTrackingController and RecipientDeliveryController). Fixed in odd/tasks/archive/2026-11-18-bug-customer-public-tracking.md: class access granted, check script updated, 13 tests as a logged-in customer; gate 554/554 @ 181bce2, org 96.17%; reviews clean. The owner retested while logged in on 2026-11-19: tracking and the recipient flow work.

## 2. Hardening

| | Audit 1 (before) | Audit 2 (after) |
|---|---|---|
| SEC Critical | 1 (SEC-001) | 1 (SEC-001, owner-only) |
| SEC High | 2 (SEC-002, SEC-003) | 0 |
| SEC Medium | 7 | 9 |
| SEC Low | 7 | 9 |
| SEC Info | 6 | 8 |
| CA High (sev 1-2) | 2 (CA-001, CA-002) + 134 dismissed | 0 + 134 dismissed |

Reports (git-ignored, local only): .security-reports/20261118-035506-hardening-1/security-audit.md, .security-reports/20261118-195136-hardening-audit-2/security-audit.md. The 134 dismissed CA hits are PMD GlobalVariable on LWC class fields (false positive: PMD's JavaScript parser reads `rcHeader.js:47 isGuest = IS_GUEST;` as a global).

Round 1 (odd/tasks/archive/2026-11-18-hardening-1.md) fixed:
- SEC-002 lockout oracle → guard per (shipment, normalized typed postal code) pair, every failure counted, pair row read FOR UPDATE, over-long values share one key, daily RecipientAccessGuardPurge (force-app/main/default/classes/RecipientAccess.cls:178-204, :308-315; RecipientAccessGuardPurge.cls).
- SEC-003 MFA → force-app/main/default/settings/Security.settings-meta.xml (enableMFADirectUILoginOptIn) + scripts/checks/org-security-check.sh.
- SEC-001 repository side → scripts/checks/secret-scan.sh in .husky/pre-commit, self-test, .gitignore globs.
- CA-001 (rcHeader tests), CA-002 (SeeAllData test replaced).

Hardening stopped after audit 2 (decision in .mem/memory.md, 2026-11-18): the only Critical left can be closed only by the owner (rotation at EntregaYa; history purge needs a force-push), so a second round would have had no task.

## 3. Security findings still open

**Critical**
- SEC-001 (P2, X14): the EntregaYa API key is in the git history of docs/functional-design.md (commits b85773a, 709c3cc, d975db7, 0a2ff71, f1ce31d) on five remote branches and on this branch. HEAD is clean. Owner: rotate with EntregaYa, enter the new key by hand in Named Credential EntregaYa_API, then decide on purging history.

**Medium**
- SEC-026 (X16): guest attempts create one guard row per distinct short postal code, bounded only by request rate × the one-day purge window (RecipientAccess.cls:199-202, :308-315). Fix: own row only for a well-formed postal code, row cap, alert.
- SEC-002 residual (X16): sweeping every postal code of the destination city still locks the recipient's pair (availability only).
- SEC-003 residual (X10): Health Check "Require MFA for all direct UI logins" stays Not Enforced (not settable by metadata); admin MFA registration not verifiable by API.
- SEC-024 (X10, P9): no login IP ranges on the integration and admin profiles; the ECA's IP enforcement restricts nothing.
- SEC-004 (P1, X16): bulk harvest of public tracking data; cross-customer reference search (PublicTrackingController.cls:60-89).
- SEC-005 (X16): sign-up reveals registered emails (AC-005.3, owner).
- SEC-006 (X9, X10): HttpOnly, session kill on admin reset, email-change verification, IP lock off.
- SEC-007 (X4): untrusted redirects always allowed.
- SEC-008 (P1): "Secure guest user record access" reported off in retrieved settings (confirm in Setup).
- SEC-009 (X16): the sender is shown the recipient's access code (ShipmentRequestController.cls:135; owner decision).
- SEC-010 (X16): sign-up does not prove email ownership (owner decision).

**Low**
- SEC-027 (X16): a locked pair stays locked with one failure per 15 minutes (RecipientAccess.cls:399-408).
- SEC-025 (X10): Health Check password-lifetime, secret-answer, lookup-name items.
- SEC-011 (parallel bursts on a brand-new pair), SEC-012 (sharing keyword on some inner classes), SEC-013 (support agents can edit credit, price, reschedule count), SEC-014 (leftover permission set RutaCargo_Guest_Proof_Download and orphan External Credential EntregaYa in the org), SEC-015 (http Remote Site ApexDevNet), SEC-016 (VF site pages without anti-framing headers), SEC-017 (no rate limits on sign-up, reset, shipment requests).

**Info**: SEC-018 justified system-mode elevations (approvers pending), SEC-019 two admins (40%), SEC-020 Analytics Cloud Integration User View All (platform), SEC-021 guest platform-default FLS (inert), SEC-022 no non-admin agent provisioned, SEC-023 drift, SEC-028 purge job runs as a personal admin + Deployment setting doesSkipAsyncApexValidation needs sign-off before production, SEC-029 temporary MFA-probe permission set (removed).

## 4. Pre-existing weaknesses recorded in the Closes
Guest profile platform-default field permissions (inert, 0 object permissions); Analytics Cloud Integration User with ViewAllData and View All on custom objects; Standard Platform User profile grants Delete on Account and Contact; Health Check 67-71 items; tests depend on the seeded customer users (licenses); RecipientDeliveryControllerTest and PublicTrackingControllerTest are large (NCSS); stand-in logo PNGs, Daily Brew font unused, off-palette success/offline branding roles; network sender email in the org differs from the repository.

## 5. Architecture (salesforce-code-quality:architecture-review)

| Pillar | Verdict | Main reasons |
|---|---|---|
| Trusted — Secure | FAIL | SEC-001 open (owner); otherwise strong: every class declares sharing, 4 justified `without sharing` helpers, user-mode/bound SOQL, Named Credential callouts, Private OWD |
| Trusted — Compliant | WARN | labels and sa11y tests in place; no Custom Labels (Spanish needs a code change) |
| Trusted — Reliable | WARN | no SOQL/DML in loops; Queueable CustomerPermissionAssigner without a Finalizer (CustomerPermissionAssigner.cls:43); FOR UPDATE contention untested under load |
| Easy — Intentional | PASS | API 67, no legacy automation, ApexDoc headers |
| Easy — Automated | WARN | complexity hotspots: EntregaYaStatusService.cls:151, :191; DeliveryAccessCode.cls:17; MyShipmentsController.cls:83 |
| Adaptable — Resilient | WARN | no CI; manual post-deploy steps (scripts/setup/DEPLOY-ORDER.md); AC-004.6 never run live |
| Adaptable — Composable | WARN | controller-to-trigger static staging (ShipmentRequestController.cls:112, :129 → ShipmentTriggerHandler.cls:78, :179); rules and thresholds hard-coded instead of Custom Metadata; Legacy Named Credential |

## 6. Skills not available
None at the end of the run. At the start (foundation), the Salesforce plugin skills were not loadable through the Skill tool and workers read each SKILL.md from the plugin cache; this was fixed by installing the plugins at project scope (2026-11-17). Shell-only tasks (secret scan) had no plugin skill.

## 7. Pending for the owner
1. **SEC-001**: rotate the EntregaYa key; do not push ODD-Opus-Cargo-Test-1 before deciding on the history; check the remote repository's visibility.
2. **Human test**: guest tracking; recipient details/reschedule/proof (enter the new key and the real EntregaYa base URL first); customer sign-up, login (confirm no MFA prompt for customers — if prompted, deploy Security settings with the MFA flag false), password reset, request a shipment, My shipments, detail, anonymous deep link.
3. **AC-004.6**: run scripts/entregaya/simulate-status.sh live with the ECA key and secret from Setup; hand the consumer key and secret to EntregaYa; add EntregaYa's login IP ranges (SEC-024).
4. **MFA**: each admin registers a verification method at the next UI login.
5. **Approvals and decisions**: sign every SECURITY-JUSTIFICATION marked "pending owner approval"; decide SEC-009 (who receives the access code), SEC-010/SEC-005 (email ownership and enumeration), SEC-013 (agent edit rights, Reschedule_Count__c); sign off the Deployment setting doesSkipAsyncApexValidation before production; brand questions (state colors, data weights).
6. **Org cleanup**: delete RutaCargo_Guest_Proof_Download and the External Credential EntregaYa (SEC-014); delete Remote Site ApexDevNet (SEC-015); deactivate the two non-seeded customer test users (4 of 5 Customer Community licenses used); confirm secure guest record access and guest API access in Setup.
7. **Repository**: enable Husky (`npm install`) in every clone; add a CI pipeline (tests, Jest, Code Analyzer, `secret-scan.sh --tree`).
8. **Delivery**: pull request, merge and any deploy beyond the dev org belong to the owner.
